# Playtest 2026-10-04 (b): findings

Abe is playtesting today's changes: playtest 2026-10-04 fixes, the new outposts,
Scan Composition with its bubble, ping and countdown, the tutorial receiver
gate, and Kaelen's route gating. Rule: **record and research only; no code
changes until Abe says the playtest has finished.**

## Findings

### 1. Music waits far too long to come back after a stinger — FIXED

**Abe:** after a stinger the music waits an ungodly long time before it ramps
back up. It's not the fade, which he can hear; the fade starts really, really
late. Is there dead air at the end of the stinger?

**Measured (ffmpeg, loudness per half second):**

| Stinger | File length | Audible until (about -35 dB) | Quiet tail |
|---|---|---|---|
| Danger | 8.40 s | ~7.0 s | ~1.4 s |
| Jump | 10.28 s | ~9.0 s | ~1.3 s |
| Mission (contract paid) | 8.56 s | ~6.0 s | **~2.5 s** |
| Victory | 8.68 s | ~8.0 s | ~0.7 s |

Each file ends in a long, very quiet reverb tail plus true silence: 0.5 to
1.6 s below -50 dB.

**Cause (code), three parts that add up:**
1. **The hold is the whole file.** `AudioManager.play_stinger` ducks the bed
   for `stream.get_length()` (`AudioManager.gd:~503`). The music stays down
   through the inaudible tail: up to 2.5 s of nothing after Mission.
2. **The fade starts invisibly.** The restore is a 2.5 s sine ease-in-out
   from -12 dB to 0 dB (`_duck_bed_for`, `STINGER_RESTORE_S`). An ease-in
   barely moves in its first second, and a few dB at the bottom of a dB ramp
   isn't heard. So the audible rise begins about 1 s after the fade does.
   Together with part 1, that is roughly 2-3.5 s of "nothing happening" after
   the stinger sounds finished.
3. **Back-to-back stingers restart the hold.** A kill that completes a
   contract plays Victory, then Mission. Each new stinger restarts the hold
   for its full length, so the music can stay ducked for ~15 s or more.

**Proposed fix (after the playtest):**
- Hold only until the stinger is *audibly* done. Either store each stinger's
  audible length (measured above, as a constant table), or trim the files'
  tails with ffmpeg (fade out over the last 0.4 s at the -35 dB point, keep
  originals). Trimming the files fixes it everywhere.
- Start the fade-in a little before the stinger ends (overlap ~0.5 s), so
  the music swells under the last note instead of after it.
- Restore curve: ease-out (or linear in perceived loudness), so the rise is
  heard at once and settles gently. Keep the 2.5 s length Abe liked.
- For back-to-back stingers, extend the hold only to the later stinger's
  audible end, never longer.
- Test: the music test checks that the bed starts rising within 0.3 s of
  each stinger's audible end.

### 2. New game stuck at 35% ("Writing campaign story") for ~10 minutes — FIXED

**Abe:** it feels like way too much time at 35%; is something hanging new
game generation?

**What 35% is:** the loader waits for the campaign bible, written by the
large story model (qwen3:8b on Ollama), before it lets the game start
(`UIManager._check_both_services_ready` → `_wait_for_campaign_story_before_gameplay`).
Its request timeout is **600 s** (`LocalModelGateway.REQUEST_TIMEOUTS["campaign_bible"]`).

**This session (game started 15:34:40), from the game log, Ollama's
server.log, `ollama ps` and netstat:**
- At startup the game said "Ollama not responding — attempting to start it
  automatically" and launched a second Ollama. The real one (running since
  9/15) answered, so the second exited. The previous session had just quit
  at 15:33:49 with five generations in flight (Ollama aborted them).
- The game evicted both models (`vram_cleared_for_generation`), then sent the
  bible request (`request_started`). Godot has held that connection open
  ever since.
- **Ollama never started on it:** no qwen3:8b load in server.log, and
  `ollama ps` shows only qwen3:4b (its runner dates from 15:19, an earlier
  session). From 15:36:27 to 15:44+ Ollama got nothing but health polls.
- Meanwhile the small-model warm-up ran (in the previous session it was
  correctly *deferred* during the bible). It timed out after 90 s, then a
  4b probe passed at 15:36. So the warm-up and the bible raced for the GPU,
  and the 8b request has sat queued or stalled inside Ollama.
- Result: the loading screen says "Writing campaign story" for the full
  10-minute timeout, with no sign of progress or trouble.

**Likely cause:** the "Ollama not responding → launch it" startup path skips
the rule that defers the small-model warm-up while the bible is generating.
The eviction, then the warm-up reloading the 4b, then the 8b request left
Ollama's scheduler stuck (seen before: 2026-09-30 server.log "client
connection closed before llama-server finished loading"). The previous
session quitting mid-generation two minutes earlier probably caused the
"not responding" at startup.

**Proposed fix (after the playtest):**
- Never warm the small model while the bible is pending, on every startup
  path (including after launching or recovering Ollama).
- A watchdog instead of a blind 10-minute wait: poll `/api/ps`. If the large
  model hasn't started loading within ~45 s, or hasn't finished within ~3
  min, cancel and retry the bible once. If that also stalls, start the
  campaign on the procedural bible that's already built
  (`procedural_bootstrap`) and upgrade the story in the background when the
  model is back.
- The loading screen shows real progress: "Loading the story model...",
  "Writing... (1:20)", and after a stall "The story model isn't answering;
  starting with a simpler story."
- Check the outcome in this session's log after 15:45 (timeout).

## Fix log (Abe ended the playtest to patch 1 and 2)

- **1:** each stinger holds the music only while it's heard (measured
  audible lengths); the fade starts 0.5 s before its end and eases out;
  back-to-back stingers extend the hold only to the later end.
- **2:** the game owns Ollama (Abe): restarts are allowed by default. The
  bible cancels the small model's warm-up and probe before clearing the
  GPU. A watchdog polls /api/ps: if the story model isn't in memory within
  90 s, the request is cancelled, Ollama is restarted (taskkill ollama.exe and
  llama-server.exe, relaunch, wait until it answers) and the bible is asked
  again; a second stall reports a timeout and the loading screen retries.
  The loading screen shows the real stage with a clock: "Loading the story
  model... (0:12)", "Writing your campaign's story... (1:05)", "The story
  model got stuck. Restarting it...". Not yet tested against a live stall.
