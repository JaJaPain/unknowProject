# Known Harmless Warnings

Warnings and errors that appear during normal operation and can be safely
ignored. If you see a message NOT on this list, investigate it.

## Headless / Test Runs

These appear on every `--headless --script` test invocation:

- **`WARNING: ObjectDB instances leaked at exit`** — Godot's autoload singletons
  (GlobalState, LLMInterface, etc.) are not freed before the SceneTree exits in
  headless mode. Not a real leak; the OS reclaims the memory.

- **`ERROR: 1 resources still in use at exit`** — Same root cause as above.
  The autoload nodes hold references to preloaded resources that outlive the
  tree teardown.

## Editor Script Reload

These appear in the Errors tab when scripts reload and do not affect gameplay:

- **`The parameter "headers" is never used in "<anonymous lambda>()"`** —
  HTTPRequest callback signatures include unused parameters. Harmless.

- **`The "for" iterator variable "seed" has the same name as a built-in function`** —
  Local variable shadowing in procedural generation code. Does not affect
  behavior since the built-in `seed()` is not called in those scopes.

- **`The local variable "example_faction_key" is declared but never used`** —
  Placeholder in template/example code. Will be cleaned up when the template
  is finalized.

## Runtime (In-Game)

- **`[LLMInterface] Connection to Ollama failed (attempt N)`** — Normal when
  Ollama is not running. The game falls back to procedural quest generation
  after a few retries. Not an error unless you expected LLM quests.

- **`[TTSInterface] TTS server not connected`** / **`Queueing cache request (TTS not connected)`** —
  Normal when the TTS Python server is not running. Voice lines are skipped
  gracefully.
