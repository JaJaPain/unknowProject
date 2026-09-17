"""Run with python -m unittest discover -s tests/speech -p test_tts_device.py."""
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from tts_device import AdaptiveDevice, Capacity, GIB, cuda_capacity


class DeviceTests(unittest.TestCase):
    def setUp(self):
        self.now = 0
        self.samples = [Capacity("cuda:0", 7 * GIB, 12 * GIB, 10)]
        self.cpu, self.gpu = object(), object()
        self.factory, self.release = Mock(return_value=self.gpu), Mock()
        self.router = AdaptiveDevice(self.cpu, self.factory, lambda: self.samples,
                                     self.release, clock=lambda: self.now)

    def enable_gpu(self):
        self.assertIs(self.router.select(), self.cpu)
        self.now += 6
        self.assertIs(self.router.select(), self.gpu)

    def test_no_gpu_and_missing_monitor(self):
        self.samples = []
        self.assertIs(self.router.select(), self.cpu)
        self.router.probe = Mock(side_effect=RuntimeError("driver unavailable"))
        self.now = 6
        self.assertIs(self.router.select(), self.cpu)
        self.factory.assert_not_called()

    def test_cpu_only_torch_does_not_touch_gpu(self):
        torch = SimpleNamespace(cuda=Mock())
        torch.cuda.is_available.return_value = False
        self.assertEqual(cuda_capacity(torch), [])
        torch.cuda.device_count.assert_not_called()

    def test_low_memory_small_gpu_stays_cpu(self):
        self.samples = [Capacity("cuda:0", int(1.5 * GIB), 2 * GIB, 0)]
        self.router.select()
        self.now = 6
        self.assertIs(self.router.select(), self.cpu)

    def test_pressure_evicts_then_recovers_after_cooldown(self):
        self.enable_gpu()
        self.samples = [Capacity("cuda:0", 7 * GIB, 12 * GIB, 95)]
        self.now = 9
        self.assertIs(self.router.select(), self.cpu)
        self.release.assert_called_once_with("cuda:0")
        self.samples = [Capacity("cuda:0", 7 * GIB, 12 * GIB, 10)]
        self.now = 20
        self.assertIs(self.router.select(), self.cpu)
        self.now = 40
        self.assertIs(self.router.select(), self.cpu)
        self.now = 46
        self.assertIs(self.router.select(), self.gpu)

    def test_memory_pressure_and_lost_telemetry_evict(self):
        for samples in [[], [Capacity("cuda:0", GIB, 12 * GIB, 10)]]:
            self.setUp()
            self.enable_gpu()
            self.samples = samples
            self.now = 9
            self.assertIs(self.router.select(), self.cpu)

    def test_multiple_gpus_select_available_adapter(self):
        self.samples = [Capacity("cuda:0", 7 * GIB, 12 * GIB, 95),
                        Capacity("cuda:1", 5 * GIB, 8 * GIB, 5)]
        self.enable_gpu()
        self.factory.assert_called_once_with("cuda:1")

    def test_initialization_failure_is_backed_off(self):
        self.factory.side_effect = RuntimeError("unsupported CUDA architecture")
        self.router.select()
        self.now = 6
        self.assertIs(self.router.select(), self.cpu)
        self.now = 15
        self.assertIs(self.router.select(), self.cpu)
        self.assertEqual(self.factory.call_count, 1)

    def test_failed_render_retries_whole_line_on_cpu(self):
        self.enable_gpu()
        render = Mock(side_effect=[RuntimeError("CUDA out of memory"), b"complete wav"])
        self.assertEqual(self.router.render(render), b"complete wav")
        self.assertEqual([c.args[0] for c in render.call_args_list], [self.gpu, self.cpu])
        self.assertEqual(self.router.device, "cpu")
        self.release.assert_called_once()

    def test_cpu_failure_is_not_retried(self):
        render = Mock(side_effect=RuntimeError("invalid input"))
        with self.assertRaises(RuntimeError):
            self.router.render(render)
        self.assertEqual(render.call_count, 1)

    def test_cpu_override_never_probes(self):
        self.router.mode = "cpu"
        self.router.probe = Mock()
        self.assertIs(self.router.select(), self.cpu)
        self.router.probe.assert_not_called()


if __name__ == "__main__":
    unittest.main()
