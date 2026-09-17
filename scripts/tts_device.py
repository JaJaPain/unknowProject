"""Conservative per-request CUDA routing; CPU is always the baseline.

No GPU or monitoring dependency is required to import this module.
The server serializes render calls, so model eviction cannot race synthesis.
"""
import gc
import logging
import time
from dataclasses import dataclass

log = logging.getLogger(__name__)
GIB = 1024 ** 3


@dataclass(frozen=True)
class Capacity:
    device: str
    free: int
    total: int
    utilization: float


def cuda_capacity(torch):
    """Unknown telemetry is not evidence of spare capacity. Fail closed to CPU."""
    if not torch.cuda.is_available() or torch.version.hip:
        return []
    result = []
    for index in range(torch.cuda.device_count()):
        try:
            free, total = torch.cuda.mem_get_info(index)
            busy = float(torch.cuda.utilization(index))
            if 0 <= busy <= 100 and 0 <= free <= total and total > 0:
                result.append(Capacity(f"cuda:{index}", free, total, busy))
        except Exception:
            # Missing NVML, unsupported driver/telemetry, or a lost adapter.
            continue
    return result


class AdaptiveDevice:
    def __init__(self, cpu_model, gpu_factory, probe, release, mode="auto", clock=time.monotonic):
        if mode not in ("auto", "cpu"):
            raise ValueError("SPACEGAME_TTS_DEVICE must be auto or cpu")
        self.cpu_model = cpu_model
        self.gpu_factory = gpu_factory
        self.probe = probe
        self.release = release
        self.mode = mode
        self.clock = clock
        self.gpu_model = None
        self.device = "cpu"
        self.reason = "cpu_baseline"
        self.retry_at = 0.0
        self.candidate = None
        self.candidate_since = 0.0
        self.last_probe = float("-inf")
        self.samples = []

    @staticmethod
    def reserve(sample):
        # Leave room for the renderer/other models on both small and large GPUs.
        return max(GIB, int(sample.total * 0.20))

    def _cpu(self, reason, cooldown=0):
        old_device = self.device
        self.gpu_model = None
        self.device = "cpu"
        self.reason = reason
        self.candidate = None
        self.retry_at = max(self.retry_at, self.clock() + cooldown)
        if old_device != "cpu":
            gc.collect()
            try:
                self.release(old_device)
            except Exception:
                pass
            log.info("TTS switched to CPU: %s", reason)

    def select(self):
        now = self.clock()
        if self.mode == "cpu":
            self._cpu("cpu_requested")
            return self.cpu_model
        if now - self.last_probe >= 2.0:
            try:
                self.samples = self.probe()
            except Exception:
                self.samples = []
            self.last_probe = now
        if self.gpu_model is not None:
            current = next((s for s in self.samples if s.device == self.device), None)
            if current is None or current.free < self.reserve(current) or current.utilization >= 85:
                self._cpu("gpu_pressure_or_telemetry_unavailable", cooldown=30)
            else:
                return self.gpu_model
        if now < self.retry_at:
            return self.cpu_model
        # Additional 1 GiB admission allowance for weights and synthesis scratch.
        eligible = [s for s in self.samples
                    if s.free >= self.reserve(s) + GIB and s.utilization <= 55]
        if not eligible:
            self.candidate = None
            self.reason = "no_supported_gpu_with_headroom"
            return self.cpu_model
        best = max(eligible, key=lambda s: s.free - self.reserve(s))
        if self.candidate != best.device:
            self.candidate = best.device
            self.candidate_since = now
        if now - self.candidate_since < 5:
            self.reason = "waiting_for_stable_gpu_headroom"
            return self.cpu_model
        self.device = best.device
        try:
            self.gpu_model = self.gpu_factory(best.device)
        except Exception:
            log.exception("GPU TTS initialization failed; using CPU")
        if self.gpu_model is None:
            # The exception traceback must be released before empty_cache.
            self._cpu("gpu_initialization_failed", cooldown=120)
            return self.cpu_model
        self.reason = "gpu_headroom_available"
        log.info("TTS switched to %s", self.device)
        return self.gpu_model

    def render(self, generate):
        # Fully consume a render before returning: failed GPU output is discarded.
        model = self.select()
        if model is self.cpu_model:
            return generate(model)
        try:
            return generate(model)
        except RuntimeError:
            log.exception("GPU TTS render failed; retrying complete line on CPU")
        # Leave the exception scope and drop the model reference before eviction.
        del model
        self._cpu("gpu_render_failed", cooldown=120)
        return generate(self.cpu_model)

    def status(self):
        return {"device_mode": self.mode, "device": self.device, "device_reason": self.reason}
