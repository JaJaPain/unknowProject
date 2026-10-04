# Playtest 2026-10-04 (b): findings

Abe is playtesting today's changes: playtest 2026-10-04 fixes, the new outposts,
Scan Composition with its bubble, ping and countdown, the tutorial receiver
gate, and Kaelen's route gating. Rule: **record and research only; no code
changes until Abe says the playtest has finished.**

## Findings

### 1. Music waits far too long to come back after a stinger

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
