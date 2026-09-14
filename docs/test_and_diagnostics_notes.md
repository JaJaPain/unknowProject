# Test & Diagnostics Notes
_Audit date: 2026-06-21_

---

## 1. Headless Godot Startup Crash Investigation

### Symptom
Godot 4.6.3 crashes during startup log rotation before any GDScript output appears:
```
ERROR: Failed to open 'user://logs/godot....log'.
CrashHandlerException: Program crashed with signal 11
```

### Root cause (confirmed)
The crash is a **Godot 4.6.3 bug**: when a previous timestamped log file exists
and the engine tries to rotate/rename it on startup, it can crash if the log
directory has a stale lock or the filename conflicts. This is not related to
any game code.

### Workaround (in use)
Always pass a workspace-local `--log-file` to bypass the default user:// log path:
```powershell
$logPath = Join-Path (Get-Location) ".tmp_godot_user\test_logs\my_test.log"
.\Godot\Godot_v4.6.3-stable_win64_console.exe --headless --path . `
  --script res://tests/my_test.gd --log-file $logPath
```

### No-op script test
To isolate: if the crash happens with the simplest possible script:
```gdscript
# res://tests/noop.gd
extends SceneTree
func _initialize():
    print("noop ok")
    quit()
```
…then it is definitively the log rotation bug, not a script error.

### Status
Documented in `CLAUDE.md`. No fix available until Godot patches the log rotation
bug. Workaround is stable.

---

## 2. Tests Safe to Run After Visual-Only Changes

**Definition of visual-only:** Changes confined to shaders, particle systems,
`JumpTransitionFX.gd`, `ImpactEffect.gd`, `AsteroidModels.gd`, or any `.gdshader`
file. No changes to `QuestManager`, `MissionContract`, `GlobalState`, `GameRoot`,
or `CampaignSlotStore`.

### Safe to run (fast, no side effects)
These tests have no dependency on visual nodes or shaders:

| Test file | What it covers | Approx time |
|---|---|---|
| `tests/domain/run_mission_contract_tests.gd` | Mission validation | ~5s |
| `tests/domain/run_timed_mission_tests.gd` | Timed contract expiry | ~5s |
| `tests/domain/run_mission_collection_tests.gd` | Quest collection | ~5s |
| `tests/registry/run_system_registry_tests.gd` | System/gate registry | ~3s |
| `tests/registry/run_game_content_registry_tests.gd` | Factions, portraits | ~3s |
| `tests/economy/run_store_tests.gd` | Economy/store logic | ~3s |
| `tests/economy/run_inventory_tests.gd` | Inventory | ~3s |

### Skip for visual-only changes
These tests exercise systems that could break if visual nodes are accidentally
removed or renamed, but they're also slow:

| Test file | Reason to skip | Note |
|---|---|---|
| `tests/speech/run_speech_service_tests.gd` | Touches TTS paths | Only run if `SpeechService.gd` changed |
| `tests/ai/run_narrative_director_tests.gd` | LLM interface | Only run if `LLMInterface.gd` changed |
| `tests/generation/run_system_factory_tests.gd` | Spawns scene nodes | Run if `JumpTransitionFX.gd` or scene structure changed |

### Recommended fast smoke test after any visual change
```powershell
$log = Join-Path (Get-Location) ".tmp_godot_user\test_logs\smoke.log"
.\Godot\Godot_v4.6.3-stable_win64_console.exe --headless --path . `
  --script res://tests/domain/run_mission_contract_tests.gd --log-file $log
```

---

## 3. Tests With Hard-Coded Agent Names — Audit Results

Searched for hard-coded agent names in `tests/` that might break if generated
system NPC names change.

### Found: Named NPCs in tests (intentional, not a concern)

| File | Hard-coded name | Context |
|---|---|---|
| `tests/domain/run_mission_instance_tests.gd:288` | `"Director Voss"` | Named test fixture — not a generated NPC |
| `tests/domain/run_timed_mission_tests.gd:266` | `"Director Voss"` | Same fixture |
| `tests/domain/run_timed_mission_tests.gd:281` | `"Jenna Kross"` | Named NPC fixture — defined in GlobalState |
| `tests/domain/run_timed_mission_tests.gd:300` | `"Public Board"` | Special board source, not an NPC name |
| `tests/domain/run_mission_collection_tests.gd:57` | `"Test Agent"` | Generic placeholder, not a real NPC |

**Verdict:** No tests depend on generated system NPC names. "Director Voss" and
"Jenna Kross" are fixed named NPCs defined in `GlobalState.NAMED_NPCS` — they
are not the same as generated contact names which are procedural. No cleanup needed.

---

## 4. Diagnostics: Noisy Messages That Can Hide Real Failures

### High-volume trace messages (normal, not failures)

These print on every frame or every quest generation cycle. Do not alarm:

| Message pattern | Source | Normal? |
|---|---|---|
| `[TRACE] [LLMInterface] HTTP response received...` | `LLMInterface.gd` | Yes — every quest gen |
| `[TRACE] [TTSInterface] WAV decoding completed...` | `TTSInterface.gd` | Yes — every TTS line |
| `[TRACE] [UIManager] No opening contract for this station` | `UIManager.gd` | Yes — generated stations |
| `[LLMInterface] Connection to Ollama failed (attempt N)` | `LLMInterface.gd` | Yes — if Ollama is off |
| `[TTSInterface] TTS server not connected` | `TTSInterface.gd` | Yes — if TTS is off |

### Messages that indicate real failures (investigate)

| Message pattern | Meaning | Action |
|---|---|---|
| `[LLMInterface] ⚠ VALIDATE: Final objective changed` | Ore amount substitution fired on unexpected "25" | Check dialogue for false-positive number replacement |
| `[LLMInterface] ⚠ SUBSTITUTE: Regex caught leftover slither-variant` | LLM leaked dummy faction name into dialogue | Retry logic should handle; if persistent, improve prompt |
| `[LLMInterface] Dialogue retry HTTP failed` | Network error during dialogue retry | Check Ollama connection |
| `[LLMInterface] Dialogue retry parse failed — using safe fallback` | LLM returned invalid JSON on retry | Check model quality; "not going to put my name on it" fallback fires |
| `[LLMInterface] Failed to parse inner generated JSON dialogue` | Bad LLM JSON | May resolve on next generation; persistent = model issue |
| `[GameRoot] No faction contact for generated station` | Station has no NPC contact | See §3 in `tts_hygiene_notes.md` — design question for Codex |
| `ERROR: ... is null` with stack in any system script | Null reference | Always investigate |
| `SCRIPT ERROR:` | GDScript runtime error | Always investigate |

### Known false-positive error patterns

| Pattern | Why it's false | Reference |
|---|---|---|
| `ObjectDB instances leaked` | Autoload cleanup in headless mode | `known_harmless_warnings.md` |
| `1 resources still in use at exit` | Same autoload cause | `known_harmless_warnings.md` |
| `Identifier not found: GlobalState` (check-only) | Autoloads not loaded in check-only | `known_harmless_warnings.md` |
| LF/CRLF warnings on `git commit` | Windows line-ending normalization | `known_harmless_warnings.md` |
