# Phase 1 Checkpoint 6: Unified Speech Service

Status: Complete; manual audio and autopilot review passed

## Added

- One game-facing `SpeechService` autoload.
- A `KokoroSpeechProvider` adapter for the current local TTS server.
- Stable voice-profile resolution for Kaelen, faction agents, minor NPCs, and
  Jenna Kross.
- Provider-neutral speech metadata in NPC chatter and mission handoff state.
- Focused automated tests and a source-level architecture guard.

## Game Contract

Gameplay and UI code now use:

- `SpeechService.play`
- `SpeechService.cache`
- `SpeechService.stop`
- `SpeechService.start_interaction`
- speech readiness and cache-completion signals

Callers pass stable references such as:

- `voice.kaelen.v1`
- `voice.jenna_kross.v1`
- `faction.zenith`
- `npc.cassen_vane`

They no longer pass Kokoro voice names.

## Provider Boundary

`KokoroSpeechProvider` resolves a stable voice profile through
`voice_provider_kokoro.json`, including its speed setting and fallback profile.
It then delegates synthesis to the existing local TTS transport.

Changing a Kokoro voice now requires editing only the provider mapping.
Replacing Kokoro later requires a new provider adapter and configuration,
without changing dialogue or UI callers.

`TTSInterface` remains temporarily as the proven HTTP, WAV decoding, cache,
playback, cancellation, and audio-ducking backend. It is no longer a gameplay
API.

## Speaker Rules

Text is prepared once at the `SpeechService` boundary:

- dialogue metadata and stage directions are removed
- Kaelen's `voice.kaelen.v1` profile preserves `Shiny`
- every other stable voice profile rewrites accidental `Shiny` usage to `Indy`
- cached and immediate playback use the same prepared text

This fixes the old ambiguity where Kaelen and a generic neutral voice could
share one provider voice name.

## Migrated Callers

The migration includes:

- Kaelen introductions, reactions, completion, abandonment, and partial
  deliveries
- all faction-agent briefings and responses
- outpost NPC gossip and pickup handoffs
- Jenna's mechanic dialogue
- loading-screen readiness and cache completion
- speech stopping when dialogue panels close

## Compatibility

Legacy `neutral` calls resolve to Kaelen because that is how the existing
broker paths used the value. Existing provider-name resolution remains inside
the service only as a temporary compatibility fallback.

The current in-memory audio cache, request interruption, WAV decoder, local
server discovery, and audio ducking behavior remain unchanged.

## Verification

The focused speech tests verify:

- Kaelen, faction, and NPC profile resolution
- Kaelen's `Shiny` rule
- every other speaker's `Indy` rule
- identical cleanup before cache and playback
- Kaelen and Jenna's current Kokoro mappings
- absence of direct `TTSInterface` and provider-voice references in gameplay
  and UI callers

The complete baseline suite passes all 11 steps, including startup, two-way
gate travel, save restoration, docking, and dock autosave.

Manual approval confirmed the audible voices, interruption behavior, and music
ducking during normal Godot play.

## Manual Test Follow-Up

The first manual pass confirmed:

- Kaelen speaks and preserves `Shiny`
- faction agents speak and use `Indy`
- Jenna's voice is preserved
- outpost NPC voices are preserved
- music ducks and restores correctly

One non-repeating Voss/Kaelen presentation mismatch led to a stronger identity
rule: named agents now resolve their portrait and voice through the same NPC
definition.

Dock submenu transitions now stop speech explicitly, including Services,
Maintenance, agent-panel close, dock-menu close, and undock.

During the same test pass, a planet-avoidance regression was found. Planets now
declare navigation-circle radii outside their asteroid rings. Autopilot joins
that circle, follows a locked direction, and releases each celestial
independently instead of allowing a later planet to keep an earlier orbit
locked forever.

Clockwise and counterclockwise entries are scored before committing to a
celestial route. Each celestial navigation circle has six evenly spaced hard
exits. The ship travels between those exits in one committed direction and,
on reaching each exit, tests only whether that celestial still obstructs the
destination. Once clear, it releases the circle and recalculates the fastest
remaining route.

The exits use a circumscribed-hexagon radius so straight travel between
adjacent exits never cuts inside the protected circle. Reaching all six exits
forces a direction and route reassessment instead of silently starting another
identical lap.

Orbital stations and ring asteroids inside a broad navigation circle receive a
target-facing final approach corridor that retains the planet's physical
safety buffer.

Every target change invalidates the complete previous route: staged gate,
celestial lock, hard-exit index, avoidance waypoint, docking progress, and
target position. Changing away from a staged gate converts travel to a normal
approach instead of allowing the old gate route to survive.

The system chat explains deliberate celestial detours:

- `NAVIGATION: Direct route obstructed by <body>. Plotting a safe orbital bypass.`
- `NAVIGATION: Obstruction cleared. Resuming direct course.`

Each message is emitted once per obstruction. Internal hard-exit recalculation
does not repeat it, and changing targets cancels the old notification state.

The automated regression now includes the real Kova-to-Iron-Reach route. It
requires the ship to release Rocky Planet, handle the gas giant separately,
avoid reacquiring either body, preserve both clearances, and arrive at Iron
Reach.

## Generated-System Navigation Contract

Production autopilot does not recognize planet, station, or system names.
Routes are derived from runtime positions, collision geometry, and groups.

Every generated celestial must provide:

- membership in the `celestial` group
- a collision shape representing its physical body
- optional `navigation_clearance_radius` metadata

The system builder calculates `navigation_clearance_radius` as the greatest of:

- physical planet radius plus its safety buffer
- outer asteroid-ring radius plus its safety buffer
- any authored orbital hazard radius plus its safety buffer

When metadata is absent, autopilot derives a conservative clearance from the
physical radius. Stations may exist inside a celestial's broad navigation
circle; their final approach corridor is calculated from station and planet
geometry at runtime.

Named Kova and Iron Reach references exist only in the regression scenario
that reproduces the original failure.
