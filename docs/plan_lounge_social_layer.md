# Lounge Social Layer — Implementation Plan (2026-07-05)

Goal (user's words): the lounge should feel like sitting down at a bar next to
these people, not a rumor vending machine. Two-way conversations, a rare
"someone wants a word with you" approach, buy-them-a-drink, occasional
off-faction side offers, and a rare shady stranger.

Rollback tag: `pre-lounge-social-layer`. Phases are independent commits —
ANY phase can be picked up standalone by a future session/model. Each phase
lists exact files, functions, and tests. House rules that apply to all:
- Small models get FLAT few-key JSON only (never nested; see memory
  project_labeled_field_generation + AmbientChatGenerator.build_prompt note).
- Prompts use ONLY player-safe context (get_ambient_flavor_block / story
  context block). Director-only fields never appear.
- Failure = logged GenerationDiagnostics event + graceful absence, no canned
  spam. (Canned is allowed ONLY as an explicit last-resort reply row so the
  UI never dead-ends — log it when used.)
- Code owns ALL consequences (rep deltas, credits, cooldowns). The model only
  writes dialogue text. Never parse numbers/outcomes out of model text.

## Existing seams (verified 2026-07-05)

- `UIManager.show_dock_message(text, npc_name, color, portrait, choices)` —
  choices is `[{text: String, callback: Callable}]`, rendered as a button row
  (`_set_dock_message_choices`, UIManager.gd ~8556). THE conversation UI.
- `UIManager._on_lounge_card_pressed(card_data)` (~4429) → builds context via
  `_lounge_card_context` → `LLMInterface.request_lounge_chatter(context,
  fallback, cb)` (one-liner). This is the entry point L1 replaces.
- `LLMInterface.request_ambient_chat(prompt, cb)` — generic small-model
  transport returning `{ok, inner_text}`; reuse the same pattern.
- `GlobalState.spend_credits / add_credits / adjust_reputation(faction, amt)`.
- `StoryManager.story_state` persists per campaign (StoryStateStore); add new
  keys to BOTH default dicts in StoryManager AND StoryStateStore._default_state.
- `StoryManager.get_lounge_rumor()/record_lounge_rumor_heard()` — rumor path
  stays, but becomes ONE of several conversation flavors, not the whole show.
- Lounge cards: `_lounge_npc_card/_lounge_kaelen_card/...` (~4098-4190) build
  card_data dicts; `_add_lounge_contact_card` (~4190) renders them.

## Phase L1 — Two-way conversations (core) — STATUS: see todo.md

New file `scripts/story/LoungeConversation.gd` (RefCounted, class_name
LoungeConversation) — pure/testable protocol layer, mirroring
AmbientChatGenerator's structure:

- `const MAX_TURNS := 3` (opener + 2 player replies max, then it winds down).
- `static build_opener_prompt(npc, context, flavor_block) -> String`
  Output spec (FLAT): `{"line": "...", "r1": "...", "r2": "...", "r3": "..."}`
  where r1-r3 are SHORT player reply options (under 8 words each) written in
  the player's plain voice. r3 may be "" (2 options ok). Rules: PG-13 dry
  humor, no player-name, no lore inventions, replies must be tonally distinct
  (one friendly/curious, one dry/pushback, optional third odd/funny).
- `static build_reply_prompt(npc, context, flavor_block, transcript, player_reply, turns_left) -> String`
  Same flat shape. When turns_left == 0, instruct: line wraps the chat up
  naturally, r1-r3 must all be "".
- `static parse_turn(inner_text) -> {ok, line, replies: Array[String], reason}`
  Flat-key parse + length caps (line 4..220, replies 2..60), drop empty
  replies, strip self-tags via AmbientChatGenerator._strip_speaker_prefix.
- `static transcript_block(turns: Array) -> String` — "NPC: .../You: ..."
  lines for the reply prompt, capped at last 6 entries.

UIManager wiring (replace body of `_on_lounge_card_pressed`):
- Keep instant "Listening..." feedback; call
  `LLMInterface.request_lounge_conversation_turn(prompt, cb)` (thin transport,
  clone of request_ambient_chat; capability "lounge_chat" small/12s — add to
  LocalModelGateway CAPABILITY_PROFILES + REQUEST_TIMEOUTS).
- On ok: `show_dock_message(line, npc_name, color, portrait, choices)` where
  each choice = reply text + callback → appends to a `_lounge_convo` state
  dict {card, turns: [], turns_left} held in UIManager, fires the reply
  prompt, shows next turn. Last turn shows no choices.
- Always append a code-owned "(nod and leave)" choice that ends the convo —
  the player can always bail; no LLM call on bail.
- On failure: fall back to the OLD single-line request_lounge_chatter path
  (still logged), so the lounge never goes mute.
- Consequences (code-owned, small): completing a full conversation (reached
  wind-down) with a FACTION-affiliated contact → +1.0 rep to that faction,
  at most once per contact per dock (track in `_lounge_convo_done` session
  dict, no persistence needed). Rude bail (leaving on turn 1 via nod-and-
  leave) → nothing. Keep it gentle; todo line "Faction lounge social checks"
  covers bigger swings later.

Tests `tests/story/run_lounge_conversation_tests.gd` (runtime-load harness —
see run_ambient_chat_tests header for WHY preload breaks): parse_turn shapes
(good/2-reply/wind-down/junk/over-cap), prompt content (flat spec present,
flavor block, no director fields), transcript capping.

## Phase L2 — Buy them a drink

- Card button "Buy a drink" (UIManager `_add_lounge_card_buttons` area) for
  kind=="npc"/"bartender" cards. Cost: 20 credits flat (const). Disabled +
  tooltip when broke or already bought this dock.
- Effect: `StoryManager.adjust_lounge_warmth(npc_key, +1)` — new story_state
  dict `lounge_warmth: {npc_key: int}` clamped 0..3, persisted (add to both
  default dicts + StoryStateStore). npc_key = lowercase npc name slug.
- Warmth is injected into conversation context ("This contact remembers the
  player bought them a drink; warmth N of 3") → warmer openers, and it raises
  Phase L3 approach odds. Warmth 0 = stranger-polite.
- One drink per contact per dock (session dict), costs spent via
  GlobalState.spend_credits, small chatter confirmation line (code template,
  not LLM — instant feedback matters more than variety here).

## Phase L3 — "Wants a word" approaches (rare, NPC-initiated)

- On lounge open (`_render_station_contacts`), roll ONCE per dock (session
  dict `_lounge_approach_rolled`): base 12% + 4% per point of that contact's
  warmth, pick ONE eligible npc card → card_data["approach"] = true.
- Render: small pulsing dot + "wants a word" sublabel on that card only
  (reuse card styling; keep it subtle — this is a glance-across-the-bar cue,
  not a quest marker).
- Clicking an approach card: the OPENER prompt gets an extra instruction —
  the NPC initiates with something they wanted to tell the player. Content
  priority (code picks, model phrases): 1) if a pending_hook exists and not
  yet hinted → deliver as personal tip (mark via record_lounge_rumor_heard,
  same dedup as rumors); 2) else if warmth >= 2 → personal/backstory beat;
  3) else → small world observation. Approach conversations use the same
  L1 turn machinery afterward.
- Frequency guard: never two docks in a row with an approach (persist last
  dock flag in story_state `lounge_last_approach_dock` int; compare to
  dock count or campaign minutes).

## Phase L4 — The stranger (rare black-market passerby)

- Todo anchor: "Lounge black-market passerby" (docs/todo.md ~line 112).
- Roll on lounge open AFTER approach roll, mutually exclusive with it:
  6% chance, never at the tutorial station, never twice in a row
  (story_state `lounge_last_stranger_dock`). Adds a TEMPORARY extra card
  "A Stranger" (no portrait match needed — use neutral/hooded styling,
  kind=="stranger"), gone next dock.
- Conversation: L1 machinery with a stranger-specific opener instruction:
  they have a deal — deliberately shady, PG-13, could be real or a scam.
- The DEAL is code-owned (model only phrases it). Generate offer struct:
  `{ask_credits: 150-600 by rep/chapter, kind: intel|goods|job}` and a
  hidden `is_scam` roll (35%). Reply row on final turn becomes code-owned:
  "[Pay N] / [Haggle] / [Walk away]".
  - Walk away: nothing, tiny chance (10%) stranger sweetens once (ask * 0.7).
  - Haggle: one reroll, 50% ask drops 20%, 50% stranger gets cold (deal off).
  - Pay + honest: payout by kind — intel: unlock a rumor lead (append a
    pending_hook from the bible's unused rumor clue_templates if any, else
    +rep tease), goods: cargo credits value ~1.4x ask via add_credits framing
    ("fenceable goods"), job: a timed bonus payout (ask * 1.8 after 10-20
    min via CampaignClock deferred beat — reuse StoryManager
    schedule_beat_after_delay_min pattern or simple await timer + validity
    checks).
  - Pay + scam: credits gone, dry one-liner, `record_player_choice` logs it;
    NO rep hit (nobody saw you get fleeced) — the sting is the lesson.
  - Every resolution → `StoryManager.record_player_choice("stranger_deal_*", ...)`
    so the campaign remembers, and GenerationDiagnostics content_source log.
- SAFETY: stranger never references Kaelen/N.O.V.A. secrets; prompt gets the
  same player-safe flavor block only. Plot-armor rules apply (no kill offers
  naming protected cast — quest_violates_plot_armor if this ever becomes a
  real spawned job).

## Phase L5 — LATER (explicitly out of scope this pass)

- Off-faction side jobs as REAL QuestManager quests (needs lane/board work).
- Relationship heat bar UI + contact moods/last-seen (todo "Station lounge
  UI / social layer", docs/design_parking_lot.md section1).
- Bigger rep swings from conversation tone analysis.

## Hand-off checklist per phase (for whichever model continues)

1. Read this doc + the Existing seams section. Verify seams still match
   (grep, don't trust line numbers).
2. Implement ONE phase. Small edits, save incrementally (CLAUDE.md rule).
3. Run headless per CLAUDE.md: unique --log-file, serial, one at a time:
   parse_check, run_lounge_conversation_tests (L1+), seed, hooks.
   Watch for the vacuous-pass signature: "Compile Error: Identifier not
   found" followed by [PASS] means the suite did NOT run (use runtime load()).
4. Update docs/todo.md + docs/whileYouWasSleeping.md, commit with a clear
   message. Tag stays `pre-lounge-social-layer` for full rollback.

## Phase L5a — Faction lounge social checks (IMPLEMENTED 2026-07-05)

Todo anchor: "Faction lounge social checks" (~line 64). Agents in the lounge
react to standing; conversations move standing; walking out on an officer has
a cost. Numbers stay gentle — this is social texture, not a rep farm.

- `LoungeConversation.agent_disposition(rep) -> Dictionary` (pure, tested):
  tier via GlobalState.reputation_tier; returns {tier, refuses, context_line,
  completion_rep, bail_rep, lead_chance}. sworn enemy (<= -75) REFUSES to
  talk (template brush-off, no LLM call, no rep change). hostile/unfriendly:
  completion +2.0 (hard-won), bail -0.5, lead 5%. wary..cordial: +1.5 /
  -0.5 / 15%. friendly+: +1.0 / -0.25 / 30% (friends tip friends).
- Agent cards gain `rep_key` (faction_key minus "faction." prefix) so rep
  lookups don't depend on display names.
- `_start_lounge_conversation`: agent + refuses -> template line, done;
  cold contacts (walked out on earlier this dock) -> template line, no LLM.
  Otherwise disposition.context_line joins npc.extra so the model plays the
  actual relationship.
- Completion: agents use disposition.completion_rep instead of the flat
  +1.0; on completion, roll lead_chance -> agent slips an unhinted pending
  hook as "something extra" (marked heard via the rumor dedup, same as L3).
- Bail on the OPENER (nod-and-leave with <=1 turn heard) with an agent:
  bail_rep penalty + contact goes cold for this dock
  (`_lounge_cold_contacts` session dict, cleared on fresh dock).
