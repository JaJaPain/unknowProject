"""Validate premise cards against the Gemini writing brief.

Usage:
    python tools/premise_cards/validate_premise_cards.py [PATH ...] [--quiet]

PATH may be a .json file (one card or an array of cards) or a directory, which is
searched for *.json. With no PATH, checks data/content/premise_cards/incoming/.

Checks what a script can: structure, controlled vocabularies, references, story
routing and reachability, scale limits, ore types, reserved topics, and a few
batch-level variety signals. It does NOT judge whether a story is good or
playable -- that is the human/Claude review, which should only see cards that
pass here.

ERROR   = the card cannot be used as written (exit code 1 if any).
WARN    = probably wrong, or against the brief's variety rules; review it.
INFO    = worth knowing (for example `new:` tags waiting to be normalised).

The vocabularies below mirror Section 4 of docs/gemini_prompts/premise_card_prompt.md.
Update both together.
"""
import io
import json
import os
import re
import sys
from collections import Counter

DEFAULT_PATH = "data/content/premise_cards/incoming"
# Approved cards are not re-validated, but incoming cards are compared against them
# (duplicate ids, near-duplicate novelty tags, copied voice lines).
APPROVED_PATH = "data/content/premise_cards/approved"


def words(text):
    return set(text.split())


VOCAB = {
    "scale": words("personal local regional"),
    "tone": words("noir heist tragic farce paranoid political survival melancholy tense hopeful bleak absurd"),
    "themes": words(
        "debt_and_obligation safety_vs_freedom truth_vs_comfort loyalty_vs_survival progress_vs_tradition "
        "price_of_profit who_owns_the_past chosen_family justice_vs_mercy helpers_corrupted reinvention "
        "scarcity_breeds_cruelty faith_and_doubt cost_of_neutrality legacy labour_and_exploitation"),
    "function": words("setup pressure reversal crisis climax aftermath"),
    "kind": words("faction person place object ship"),
    "archetype": words(
        "broker dockmaster pilot official inspector mechanic preacher heir smuggler scientist soldier merchant "
        "refugee journalist doctor labourer crime_boss union_organiser bureaucrat veteran "
        "child_of_someone_important retired_legend con_artist bounty_hunter engineer archivist negotiator "
        "gambler debt_collector station_manager"),
    "reuse": words("prefer_existing new_ok must_be_new"),
    "quirk": words(
        "pulsar nebula ion_storm dense_debris dying_star black_hole_proximity dead_system gravity_tides "
        "relay_dark_zone"),
    "state": words(
        "blockade quarantine shortage boom evacuation curfew martial_law price_spike price_crash "
        "refugee_influx lane_closed lane_opened power_vacuum festival strike crackdown election mourning"),
    "law": words(
        "weapons_cold_zone mining_charter_required tariff_on_goods docking_bribes curfew scanning_banned "
        "salvage_registry contraband_list quarantine_orders cargo_inspection"),
    "good": words("ore fuel medical parts food luxury contraband data"),
    "ore": words("silicate ferrite water_ice cuprite thorium"),
    "surface": words("dialogue cargo scan wreck radio ship_marking station_notice price_board"),
    "method": words(
        "debt_leverage sabotage forged_records cornering_a_market blackmail impersonation manufactured_crisis "
        "proxy_violence slow_infiltration information_control bribery false_flag"),
    "motive": words("revenge fear faith control greed protecting_someone ideology survival legacy guilt"),
    "fate": words("alive_grateful alive_grudge owes_debt ruined promoted fled dead imprisoned exposed disappeared"),
    "seed": words(
        "power_vacuum grudge_against_player debt_owed_to_player refugees_moving evidence_loose "
        "rival_humiliated market_disrupted law_tightened law_loosened faction_weakened faction_emboldened "
        "secret_half_exposed wreck_left_behind martyr_made alliance_formed alliance_broken route_opened "
        "route_closed witness_at_large stolen_goods_circulating leader_discredited new_leader_untested "
        "public_outrage quiet_cover_up"),
    "verb": words(
        "kill_ships comms_reversal recover_combat_drop deliver_ore delivery_courier purchase_delivery "
        "pickup_special investigate_signal"),
    "location": words("same_system neighbouring_system any_system"),
}

COMBAT_VERBS = {"kill_ships", "comms_reversal", "recover_combat_drop"}
# What a mission's `target` role must be. Deliveries dock somewhere, so they need a place.
TARGET_KINDS = {
    "kill_ships": {"ship", "faction"},
    "comms_reversal": {"ship"},
    "recover_combat_drop": {"ship", "faction"},
    "deliver_ore": {"place"},
    "delivery_courier": {"place"},
    "purchase_delivery": {"place"},
    "pickup_special": {"place"},
    "investigate_signal": {"place", "object", "ship"},
}

# beats (min, max), missions (min, max)
SCALE_LIMITS = {
    "personal": ((3, 3), (3, 4)),
    "local": ((3, 5), (3, 6)),
    "regional": ((4, 5), (5, 8)),
}

# Reserved topics (brief Section 3, rule 3). Keep in step with the plan's secret-leak test.
RESERVED = re.compile(
    r"\b(dimensions?|parallel (universe|world|reality)|other universe|android|robot|synthetic (body|bodies|human)"
    r"|proxy (body|bodies)|remote (body|bodies)|upload(ed|ing)? (mind|consciousness)|consciousness transfer"
    r"|time[- ]travel|time[- ]loop|resurrect\w*|back from the dead|brought back to life|nova|n\.o\.v\.a|kaelen|clon(e|es|ed|ing)|spirits? of the dead|speaks? from beyond)\b",
    re.I)
# Text-to-speech cannot perform these (brief: voice_direction describes words, not sounds).
NONVERBAL = re.compile(
    r"\b(cough\w*|wheez\w*|whisper\w*|sob\w*|cr(y|ies|ying)|sigh\w*|laugh\w*|chuckl\w*|stutter\w*|slurr?\w*"
    r"|mumbl\w*|eat(s|ing)?|chew\w*|drink(s|ing)?|fad(e|es|ing) out|bleeding out|breath(e|es|ing)|gasp\w*|hum(s|ming)?|chatter\w*|clear(s|ing)? (their |his |her )?throat|blink\w*|scream\w*|shout\w*)\b",
    re.I)
# Thinking machines are reserved too (brief Section 3, rule 3); plain automation is fine, so these are
# errors only for the explicit words and a warning for a bare "AI".
MACHINE_MIND = re.compile(r"\b(self[- ]aware\w*|sentien\w*|conscious machine|machine mind|artificial intelligence|thinking machine)\b", re.I)
BARE_AI = re.compile(r"\bAIs?\b")
# A private fact that narrates the pilot instead of stating a hidden truth.
NARRATED_FACT = re.compile(r"^\s*the (pilot|player)\b|\bthe pilot (must|discovers?|realizes?|realises?|finds|learns|chooses|sees|notices|will)\b|\b(you|your)\b", re.I)

# Overused or universe-history ideas the brief asks to avoid.
BIG_HISTORY = re.compile(r"\b(alien\w*|precursor\w*|predates human\w*|ancient civili[sz]ation\w*|lost empire|galactic collapse|pre-collapse|dreadnoughts?|ancient (tech\w*|machine\w*|terraformer\w*|weapon\w*|war\w*|fleet\w*|defen[cs]e\w*)|pre-war|imperial|empire|the last war|old war|century ago|centuries ago|infinite energy|perpetual motion)\b", re.I)
# Threads that all point at the same kind of culprit make the hidden mystery predictable.
MILITARY_THREAD = re.compile(r"\b(naval|navy|military|admiral|imperial|intelligence (officer|agency|service)|black site)\b", re.I)
# pickup_special is a hand-over at a dock; stealing or sneaking is not possible.
STEALTH = re.compile(r"\b(steal\w*|stole|sneak\w*|infiltrat\w*|board(s|ing)?|break in\w*)\b", re.I)
# The pilot can never carry a person.
CARRY_PERSON = re.compile(r"\b(extract (them|him|her|the (doctor|merchant|prisoner|heir|witness))|escort (them|him|her) out|fly (them|him|her) (out|to safety)|smuggle (them|him|her|a family|refugees|the \w+) (out|off|past|through)|sneak (them|him|her) (out|off|past)|recover the escape pod|carry (them|him|her))\b", re.I)
# A person stood in for by a hologram, puppet or remote-controlled body/ship is reserved; so is the dead
# talking to the living. Warnings, because the words also have innocent uses.
STAND_IN = re.compile(r"\b(hologram of (a|the|their|her|his) \w+|interactive hologram|by remote control|remote[- ]controlled (ship|body|pilot)|dead \w+ (is )?(speaking|talking|calling)|voice of the dead|haunt(ed|ing)? (station|ship|beacon|ruin|colony|wreck)|ghosts? (speak|talk|walk|of the dead|return))\b", re.I)
MASTERMIND = re.compile(r"\b(architect|mastermind|puppet ?master|the one behind|behind it all|shadow council)\b", re.I)
KILLING_OUTCOME = re.compile(r"destroy|kill|dead|wreck|sunk|eliminat", re.I)


# Stock phrases: an 8-word run shared by 3+ cards is filler, not writing (padding was
# detected on 2026-09-24: "they specifically need an independent pilot with no local ties...").
GRAM_WORDS = 12
TITLE_STOP = set("""the stolen lost last broken false forged hidden secret final great little old new
dead dying black silent empty missing golden heavy iron red""".split())


def card_grams(card):
    parts = [m.get("reason", "") + " " + m.get("private_fact", "") for b in card.get("beats", []) for m in b.get("missions", [])]
    parts += [r.get("summary", "") for r in card.get("resolutions", [])]
    grams = set()
    for text in parts:
        w = re.findall(r"[a-z']+", text.lower())
        grams |= {" ".join(w[i:i + GRAM_WORDS]) for i in range(len(w) - GRAM_WORDS + 1)}
    return grams


def title_words(card):
    return {w for w in str(card.get("id", "")).replace("premise.", "").split("_") if len(w) >= 5 and w not in TITLE_STOP}


class Report:
    def __init__(self):
        self.items = []

    def add(self, level, card_id, message):
        self.items.append((level, card_id, message))

    def count(self, level):
        return sum(1 for item in self.items if item[0] == level)


def check_vocab(report, card_id, value, vocab, where):
    if isinstance(value, str) and value.startswith("new:"):
        report.add("INFO", card_id, "new tag %s: %s" % (where, value))
    elif value not in VOCAB[vocab]:
        report.add("ERROR", card_id, "%s: %r is not in the %s vocabulary" % (where, value, vocab))


def check_count(report, card_id, items, low, high, where, level="WARN"):
    n = len(items) if isinstance(items, (list, dict)) else 0
    if not low <= n <= high:
        report.add(level, card_id, "%s: has %d, expected %d-%d" % (where, n, low, high))


def require(report, card_id, card, field, kind):
    if field not in card:
        report.add("ERROR", card_id, "missing field %r" % field)
        return False
    if not isinstance(card[field], kind):
        report.add("ERROR", card_id, "field %r should be %s" % (field, kind.__name__))
        return False
    return True


def parse_target(value):
    """'next' | 'beat:3' | 'resolution:x' -> (kind, key) or None."""
    if value == "next":
        return ("next", None)
    kind, _, key = str(value).partition(":")
    if kind == "beat" and key.isdigit():
        return ("beat", int(key))
    if kind == "resolution" and key:
        return ("resolution", key)
    return None


def validate_card(card, report):
    card_id = card.get("id", "<no id>")
    if not re.fullmatch(r"premise\.[a-z0-9_]+", str(card_id)):
        report.add("ERROR", card_id, "id must be premise.<snake_case>")
    if card.get("schema_version") != 1:
        report.add("ERROR", card_id, "schema_version must be 1")

    fields = [
        ("title", str), ("logline", str), ("scale", str), ("tone", list), ("themes", list), ("roles", list),
        ("requirements", dict), ("accepts_seeds", list), ("public_situation", str), ("private_truth", str),
        ("beats", list), ("resolutions", list), ("default_resolution", str), ("loose_threads", list),
        ("hidden_hand_compat", dict), ("law_hooks", list), ("radio_hooks", list), ("voice_direction", dict),
        ("novelty_tags", list),
    ]
    if not all([require(report, card_id, card, f, k) for f, k in fields]):
        return None

    check_vocab(report, card_id, card["scale"], "scale", "scale")
    for x in card["tone"]:
        check_vocab(report, card_id, x, "tone", "tone")
    for x in card["themes"]:
        check_vocab(report, card_id, x, "themes", "themes")
    check_count(report, card_id, card["tone"], 1, 2, "tone")
    check_count(report, card_id, card["themes"], 1, 2, "themes")

    # Roles
    roles = {}
    for role in card["roles"]:
        rid = role.get("id")
        if rid in roles:
            report.add("ERROR", card_id, "duplicate role id %r" % rid)
        roles[rid] = role
        check_vocab(report, card_id, role.get("kind"), "kind", "role %s kind" % rid)
        check_vocab(report, card_id, role.get("reuse"), "reuse", "role %s reuse" % rid)
        if role.get("kind") == "person":
            check_vocab(report, card_id, role.get("archetype"), "archetype", "role %s archetype" % rid)
        elif "archetype" in role:
            report.add("WARN", card_id, "role %s has an archetype but is not a person" % rid)
    check_count(report, card_id, card["roles"], 3, 8, "roles")
    kinds = Counter(r.get("kind") for r in card["roles"])
    if not any(r.get("reuse") == "prefer_existing" for r in card["roles"]):
        report.add("WARN", card_id, "no role is prefer_existing (the game can't cast someone the player knows)")

    req = card["requirements"]
    min_factions = req.get("min_factions")
    if not isinstance(min_factions, int) or not 1 <= min_factions <= 4:
        report.add("ERROR", card_id, "requirements.min_factions must be an int 1-4")
    for key, vocab in (("quirks_required", "quirk"), ("quirks_preferred", "quirk"), ("quirks_forbidden", "quirk"),
                       ("states_required", "state"), ("states_forbidden", "state")):
        for x in req.get(key, []):
            check_vocab(report, card_id, x, vocab, "requirements.%s" % key)
    clash = set(req.get("quirks_preferred", []) + req.get("quirks_required", [])) & set(req.get("quirks_forbidden", []))
    if clash:
        report.add("ERROR", card_id, "quirks both preferred and forbidden: %s" % sorted(clash))
    for x in card["accepts_seeds"]:
        check_vocab(report, card_id, x, "seed", "accepts_seeds")
    check_count(report, card_id, card["accepts_seeds"], 1, 4, "accepts_seeds")

    # Beats and missions
    beats = card["beats"]
    beat_numbers = [b.get("n") for b in beats]
    if beat_numbers != list(range(1, len(beats) + 1)):
        report.add("ERROR", card_id, "beats must be numbered 1..N in order, got %s" % beat_numbers)
    resolution_ids = [r.get("id") for r in card["resolutions"]]
    if len(set(resolution_ids)) != len(resolution_ids):
        report.add("ERROR", card_id, "duplicate resolution ids")
    resolution_set = set(resolution_ids)

    def valid_target(value, where, beat_n, has_choice=False):
        parsed = parse_target(value)
        if parsed is None:
            report.add("ERROR", card_id, "%s: %r is not next / beat:<n> / resolution:<id>" % (where, value))
            return None
        kind, key = parsed
        if kind == "beat" and key not in beat_numbers:
            report.add("ERROR", card_id, "%s: beat %s does not exist" % (where, key))
            return None
        if kind == "beat" and key <= beat_n:
            report.add("WARN", card_id, "%s: routes backwards to beat %s" % (where, key))
        if kind == "resolution" and key not in resolution_set:
            report.add("ERROR", card_id, "%s: resolution %r does not exist" % (where, key))
            return None
        if kind == "next" and beat_n == len(beats) and not has_choice:
            report.add("ERROR", card_id, "%s: 'next' from the last beat goes nowhere (no player_choice follows)" % where)
            return None
        return parsed

    mission_count = 0
    has_decision = False
    edges = {}  # beat n -> set of targets
    verbs = []
    for beat in beats:
        n = beat.get("n")
        where_beat = "beat %s" % n
        check_vocab(report, card_id, beat.get("function"), "function", where_beat + " function")
        if "location" in beat:
            check_vocab(report, card_id, beat["location"], "location", where_beat + " location")
        missions = beat.get("missions", [])
        mode = beat.get("missions_mode", "all")
        if mode not in ("all", "one_of"):
            report.add("ERROR", card_id, "%s: missions_mode must be all or one_of" % where_beat)
        if mode == "one_of" and len(missions) < 2:
            report.add("ERROR", card_id, "%s: one_of needs 2 competing missions" % where_beat)
        if mode == "one_of":
            has_decision = True
        check_count(report, card_id, missions, 1, 2, where_beat + " missions")
        targets = set()
        choice = beat.get("player_choice")
        for m_index, mission in enumerate(missions, start=1):
            mission_count += 1
            where = "%s mission %d" % (where_beat, m_index)
            verb = mission.get("verb")
            verbs.append(verb)
            check_vocab(report, card_id, verb, "verb", where + " verb")
            for ref in ("requester", "target"):
                value = mission.get(ref)
                if value is None and ref == "target":
                    continue
                if value not in roles:
                    report.add("ERROR", card_id, "%s: %s %r is not a role" % (where, ref, value))
            allowed = TARGET_KINDS.get(verb)
            target_kind = roles.get(mission.get("target"), {}).get("kind")
            if allowed and mission.get("target") is None:
                report.add("ERROR", card_id, "%s: %s needs a target (%s role)" % (where, verb, " or ".join(sorted(allowed))))
            elif allowed and target_kind and target_kind not in allowed:
                level = "WARN" if target_kind == "person" and "place" in allowed else "ERROR"
                report.add(level, card_id, "%s: %s target %r is a %s; expected %s"
                           % (where, verb, mission["target"], target_kind, " or ".join(sorted(allowed))))
            if verb == "deliver_ore":
                if "ore" not in mission:
                    report.add("ERROR", card_id, "%s: deliver_ore needs an 'ore' type" % where)
                else:
                    check_vocab(report, card_id, mission["ore"], "ore", where + " ore")
            if verb == "comms_reversal":
                has_decision = True
            carry = CARRY_PERSON.search(mission.get("reason", ""))  # only what the pilot is asked to do
            if carry:
                report.add("ERROR", card_id, "%s: the pilot can't carry a person (%r)" % (where, carry.group(0)))
            if verb == "pickup_special" and STEALTH.search(mission.get("reason", "")):
                report.add("WARN", card_id, "%s: pickup_special is a hand-over at a dock, not %r"
                           % (where, STEALTH.search(mission["reason"]).group(0)))
            tags = mission.get("outcome_tags", [])
            check_count(report, card_id, tags, 1, 4, where + " outcome_tags", level="ERROR")
            if verb == "investigate_signal" and choice:
                repeated = set(tags) & {o.get("id") for o in choice.get("options", [])}
                if repeated:
                    report.add("WARN", card_id, "%s: player_choice repeats the investigate_signal findings %s; "
                               "route the findings directly" % (where, sorted(repeated)))
            routes = mission.get("routes")
            if not isinstance(routes, dict):
                report.add("ERROR", card_id, "%s: missing 'routes' for outcome tags %s" % (where, tags))
                continue
            if set(routes) != set(tags):
                report.add("ERROR", card_id, "%s: routes %s must match outcome_tags %s" % (where, sorted(routes), sorted(tags)))
            if len({str(v) for v in routes.values()}) > 1:
                has_decision = True
            for tag, value in routes.items():
                parsed = valid_target(value, "%s route %s" % (where, tag), n, bool(choice))
                if parsed is None:
                    continue
                if parsed[0] == "next":
                    targets.add(("choice", n) if choice else ("beat", n + 1))
                else:
                    targets.add(parsed)
                # Continuity: a destroyed/killed target should not be needed later on that route.
                target_role = mission.get("target")
                if target_role and KILLING_OUTCOME.search(tag) and parsed[0] != "resolution":
                    start = n if parsed[0] == "next" else parsed[1] - 1
                    for later in beats:
                        if later.get("n", 0) > start and any(
                                target_role in (lm.get("requester"), lm.get("target"))
                                for lm in later.get("missions", [])):
                            report.add("WARN", card_id, "%s: outcome %r removes %r but beat %s still uses it"
                                       % (where, tag, target_role, later.get("n")))
                            break
        if choice:
            has_decision = True
            options = choice.get("options", [])
            check_count(report, card_id, options, 2, 4, where_beat + " choice options", level="ERROR")
            for option in options:
                parsed = valid_target(option.get("leads_to"), "%s option %s" % (where_beat, option.get("id")), n)
                if parsed:
                    targets.add(("beat", n + 1) if parsed[0] == "next" else parsed)
        if not targets and n != len(beats):
            targets.add(("beat", n + 1))
        edges[n] = targets

    if not has_decision:
        report.add("ERROR", card_id, "no decision: needs a player_choice, a comms_reversal or a branching route")
    if beats:
        if beats[0].get("function") != "setup":
            report.add("WARN", card_id, "first beat should be setup")
        if beats[-1].get("function") not in ("climax", "aftermath"):
            report.add("WARN", card_id, "last beat should be climax or aftermath")

    # Reachability from beat 1
    reached_beats, reached_res, stack = set(), set(), [1] if beats else []
    while stack:
        n = stack.pop()
        if n in reached_beats or n not in edges:
            continue
        reached_beats.add(n)
        for kind, key in edges[n]:
            if kind == "beat":
                stack.append(key)
            elif kind == "resolution":
                reached_res.add(key)
    for n in beat_numbers:
        if n not in reached_beats:
            report.add("ERROR", card_id, "beat %s can never be reached" % n)
    default = card["default_resolution"]
    if default not in resolution_set:
        report.add("ERROR", card_id, "default_resolution %r does not exist" % default)
    for rid in resolution_ids:
        if rid not in reached_res and rid != default:
            report.add("ERROR", card_id, "resolution %r is never routed to" % rid)
    if edges and not reached_res:
        report.add("ERROR", card_id, "no route ever reaches a resolution")

    # Scale limits
    limits = SCALE_LIMITS.get(card["scale"])
    if limits:
        (b_lo, b_hi), (m_lo, m_hi) = limits
        if not b_lo <= len(beats) <= b_hi:
            report.add("ERROR", card_id, "%s card has %d beats, expected %d-%d" % (card["scale"], len(beats), b_lo, b_hi))
        if not m_lo <= mission_count <= m_hi:
            report.add("ERROR", card_id, "%s card has %d missions, expected %d-%d" % (card["scale"], mission_count, m_lo, m_hi))
        cast = len(roles) - kinds.get("place", 0) - kinds.get("object", 0)
        if card["scale"] == "personal" and (cast > 4 or kinds.get("faction", 0) > 1):
            report.add("ERROR", card_id, "personal card has %d people/ships/factions and %d factions (max 4 / 1; places and objects don't count)"
                       % (cast, kinds.get("faction", 0)))
        if card["scale"] == "regional":
            moved = sum(1 for b in beats if b.get("location", "same_system") != "same_system")
            if moved < 2:
                report.add("ERROR", card_id, "regional card moves only %d beats out of the starting system (need 2)" % moved)

    # Resolutions
    check_count(report, card_id, card["resolutions"], 3, 5, "resolutions", level="ERROR")
    for res in card["resolutions"]:
        rid = res.get("id")
        consequences = res.get("consequences", [])
        check_count(report, card_id, consequences, 2, 6, "resolution %s consequences" % rid)
        check_count(report, card_id, res.get("seeds", []), 1, 3, "resolution %s seeds" % rid)
        for s in res.get("seeds", []):
            check_vocab(report, card_id, s, "seed", "resolution %s seeds" % rid)
        for q in consequences:
            kind = q.get("type")
            where = "resolution %s %s" % (rid, kind)
            if kind == "standing":
                if roles.get(q.get("target"), {}).get("kind") != "faction":
                    report.add("ERROR", card_id, "%s: target %r is not a faction role" % (where, q.get("target")))
                if not isinstance(q.get("delta"), int) or not -3 <= q["delta"] <= 3:
                    report.add("ERROR", card_id, "%s: delta must be an int -3..3" % where)
            elif kind == "cast_fate":
                if roles.get(q.get("target"), {}).get("kind") != "person":
                    report.add("ERROR", card_id, "%s: target %r is not a person role" % (where, q.get("target")))
                check_vocab(report, card_id, q.get("fate"), "fate", where)
            elif kind == "system_state":
                for x in q.get("add", []) + q.get("remove", []):
                    check_vocab(report, card_id, x, "state", where)
            elif kind == "law_change":
                check_vocab(report, card_id, q.get("law"), "law", where)
                if q.get("change") not in ("enacted", "repealed"):
                    report.add("ERROR", card_id, "%s: change must be enacted or repealed" % where)
            elif kind == "economy":
                check_vocab(report, card_id, q.get("good"), "good", where)
                if q.get("price") not in ("spike", "crash"):
                    report.add("ERROR", card_id, "%s: price must be spike or crash" % where)
                if q.get("good") == "ore":
                    if "ore" not in q:
                        report.add("ERROR", card_id, "%s: ore economy needs an 'ore' type" % where)
                    else:
                        check_vocab(report, card_id, q["ore"], "ore", where)
            elif kind == "deed":
                if not re.fullmatch(r"[a-z0-9_]+", str(q.get("tag", ""))) or not q.get("public_summary"):
                    report.add("ERROR", card_id, "%s: needs a snake_case tag and a public_summary" % where)
            else:
                report.add("ERROR", card_id, "%s: unknown consequence type" % where)

    # Threads, hidden hand, laws, radio
    check_count(report, card_id, card["loose_threads"], 2, 4, "loose_threads")
    for thread in card["loose_threads"]:
        tid = thread.get("id")
        check_vocab(report, card_id, thread.get("surface"), "surface", "thread %s surface" % tid)
        for m in thread.get("can_carry_methods", []):
            check_vocab(report, card_id, m, "method", "thread %s methods" % tid)
        if MASTERMIND.search(thread.get("detail", "")):
            report.add("ERROR", card_id, "thread %s names a mastermind: %r" % (tid, MASTERMIND.search(thread["detail"]).group(0)))
    hh = card["hidden_hand_compat"]
    for m in hh.get("methods", []):
        check_vocab(report, card_id, m, "method", "hidden_hand_compat.methods")
    for m in hh.get("motives", []):
        check_vocab(report, card_id, m, "motive", "hidden_hand_compat.motives")
    check_count(report, card_id, hh.get("methods", []), 1, 4, "hidden_hand_compat.methods")
    check_count(report, card_id, hh.get("motives", []), 1, 4, "hidden_hand_compat.motives")
    for x in card["law_hooks"]:
        check_vocab(report, card_id, x, "law", "law_hooks")
    check_count(report, card_id, card["law_hooks"], 0, 3, "law_hooks")
    check_count(report, card_id, card["radio_hooks"], 2, 4, "radio_hooks")
    check_count(report, card_id, card["novelty_tags"], 3, 6, "novelty_tags")

    # Voice direction
    for rid, note in card["voice_direction"].items():
        if roles.get(rid, {}).get("kind") != "person":
            report.add("ERROR", card_id, "voice_direction for %r, which is not a person role" % rid)
        hit = NONVERBAL.search(str(note))
        if hit:
            report.add("WARN", card_id, "voice_direction %s asks TTS for a sound or action: %r" % (rid, hit.group(0)))

    # Placeholders and reserved topics, across the whole card
    text = json.dumps(card, ensure_ascii=False)
    for ph in sorted(set(re.findall(r"\{role:([^}]*)\}", text))):
        if ph not in roles:
            report.add("ERROR", card_id, "placeholder {role:%s} is not a role" % ph)
    for ph in sorted(set(re.findall(r"\{([a-z_]+)\}", text))):
        if ph not in ("system", "player"):
            report.add("ERROR", card_id, "unknown placeholder {%s}" % ph)
    if "\ufffd" in text:
        report.add("ERROR", card_id, "contains a broken character (\\ufffd); retype the word")
    for res in card["resolutions"]:
        if res.get("id") == default and re.search(r"\bpilot\b", res.get("summary", ""), re.I):
            report.add("WARN", card_id, "default_resolution %r mentions the pilot; the default is what happens if the pilot never gets involved" % default)
    for hit in sorted({m.group(0).lower() for m in RESERVED.finditer(text)}):
        report.add("ERROR", card_id, "reserved topic or fixed-cast term: %r" % hit)
    for hit in sorted({m.group(0).lower() for m in STAND_IN.finditer(text)}):
        report.add("WARN", card_id, "reserved area (stand-ins for people, or the dead speaking): %r" % hit)
    for hit in sorted({m.group(0).lower() for m in MACHINE_MIND.finditer(text)}):
        report.add("ERROR", card_id, "reserved topic (thinking machines): %r" % hit)
    if BARE_AI.search(text):
        report.add("WARN", card_id, "mentions an AI; fine only if it is plain automation, never a mind or a character")
    for hit in sorted({m.group(0).lower() for m in BIG_HISTORY.finditer(text)}):
        report.add("WARN", card_id, "overused or universe-scale idea: %r" % hit)
    for role in card["roles"]:
        if re.search(r"(^|_)ai(_|$)", role.get("id", "")):
            report.add("ERROR", card_id, "role %r is an AI; generated AIs can't be characters" % role["id"])

    quirk_words = {q: q.replace("_proximity", "").replace("_", " ") for q in VOCAB["quirk"]}
    story = (card["logline"] + " " + card["public_situation"]).lower().replace("_", " ")
    for q, word in quirk_words.items():
        if word in story and q not in req.get("quirks_required", []):
            report.add("WARN", card_id, "the story depends on %r; put it in requirements.quirks_required" % q)
    military_threads = sum(1 for th in card["loose_threads"] if MILITARY_THREAD.search(th.get("detail", "")))
    # Depth floor. Measured on the approved deck (2026-09-24): reasons average ~105 characters,
    # private facts ~80, resolution summaries ~120, ~3.2 consequences per ending. Thin cards
    # validate structurally but play flat, so these are warnings Gemini must clear.
    all_missions = [m for bt in beats for m in bt.get("missions", [])]
    thin_reasons = [m for m in all_missions if len(m.get("reason", "")) < 60]
    thin_private = [m for m in all_missions if len(m.get("private_fact", "")) < 45]
    if thin_reasons:
        report.add("WARN", card_id, "%d mission reason(s) under 60 characters; say what the requester needs, why now, and why this pilot" % len(thin_reasons))
    if thin_private:
        report.add("WARN", card_id, "%d private fact(s) under 45 characters; give the actor something real to hide" % len(thin_private))
    # A private fact is a hidden truth about a person, and the game may have the
    # companion read it aloud mid-job, so it must never narrate the pilot.
    for m in all_missions:
        fact = m.get("private_fact", "")
        if m.get("verb") != "comms_reversal" and NARRATED_FACT.search(fact):
            report.add("WARN", card_id, "private_fact narrates the pilot; state what the person hides, in the present tense: %r" % fact[:90])
    kinds = {r.get("id"): r.get("kind") for r in card["roles"]}
    for m in all_missions:
        culprit = m.get("culprit")
        if culprit is None:
            continue
        if m.get("verb") != "investigate_signal":
            report.add("WARN", card_id, "culprit only means something on an investigate_signal mission")
        elif culprit not in kinds or kinds[culprit] not in ("person", "faction"):
            report.add("ERROR", card_id, "culprit %r must be the id of a person or faction role" % culprit)
    thin_summaries = [r for r in card["resolutions"] if len(r.get("summary", "")) < 70]
    if thin_summaries:
        report.add("WARN", card_id, "%d resolution summary(ies) under 70 characters; say who wins, who pays and what changes" % len(thin_summaries))
    avg_conseq = sum(len(r.get("consequences", [])) for r in card["resolutions"]) / max(1, len(card["resolutions"]))
    if avg_conseq < 2.5:
        report.add("WARN", card_id, "endings average %.1f consequences; aim for 3 or more so outcomes change the world" % avg_conseq)
    for r in card["resolutions"]:
        if re.fullmatch(r"(default|res|resolution|ending)(_?\w{0,4})?|default_res\w*", str(r.get("id", ""))):
            report.add("WARN", card_id, "resolution id %r is a placeholder; name what happens" % r.get("id"))
    why = card.get("core_why")
    if not isinstance(why, dict):
        report.add("ERROR", card_id, "missing core_why {motive, secret}: the specific reason this story exists")
    else:
        check_vocab(report, card_id, why.get("motive"), "motive", "core_why.motive")
        secret = str(why.get("secret", ""))
        if not re.fullmatch(r"[a-z0-9]+(_[a-z0-9]+){1,6}", secret):
            report.add("ERROR", card_id, "core_why.secret must be a specific snake_case label of 2-7 words, got %r" % secret)
    default_kills = any(
        q.get("type") == "cast_fate" and q.get("fate") == "dead"
        for r in card["resolutions"] if r.get("id") == default for q in r.get("consequences", []))
    return {
        "id": card_id, "scale": card["scale"], "beats": len(beats), "missions": mission_count,
        "shape": tuple(b.get("function") for b in beats), "combat": bool(COMBAT_VERBS & set(verbs)),
        "default_kills": default_kills, "novelty": set(card["novelty_tags"]), "military_threads": military_threads,
        "voices": {v.strip().lower(): k for k, v in card["voice_direction"].items()},
        "threads": {th.get("detail", "").strip().lower() for th in card["loose_threads"]},
        "grams": card_grams(card), "title_words": title_words(card),
        "secret": str((card.get("core_why") or {}).get("secret", "")),
    }


def batch_checks(summaries, report, label):
    if len(summaries) < 2:
        return
    kills = sum(1 for s in summaries if s["default_kills"])
    if kills > 1:
        report.add("WARN", label, "%d default resolutions kill someone (brief allows 1 per batch)" % kills)
    military = sum(s["military_threads"] for s in summaries)
    if military > 1:
        report.add("WARN", label, "%d loose threads point at the military/navy; vary who the oddities point at (max 1 per batch)" % military)
    combat_free = sum(1 for s in summaries if not s["combat"])
    if len(summaries) >= 5 and combat_free < 2:
        report.add("WARN", label, "only %d card(s) without combat (brief wants at least 2 per batch)" % combat_free)
    shapes = Counter(s["shape"] for s in summaries)
    shape, count = shapes.most_common(1)[0]
    if count >= 3:
        report.add("WARN", label, "%d cards share the same beat shape %s" % (count, " > ".join(shape)))
    scales = Counter(s["scale"] for s in summaries)
    if len(summaries) >= 5 and len(scales) < 3:
        report.add("WARN", label, "scale mix is %s (aim for personal, local and regional)" % dict(scales))


def load(path, report):
    try:
        data = json.load(io.open(path, encoding="utf-8"))
    except json.JSONDecodeError as exc:
        report.add("ERROR", path, "invalid JSON: %s" % exc)
        return []
    return data if isinstance(data, list) else [data]


def main(argv):
    quiet = "--quiet" in argv
    paths = [a for a in argv if a != "--quiet"] or [DEFAULT_PATH]
    files = []
    for path in paths:
        if os.path.isdir(path):
            files += sorted(os.path.join(path, f) for f in os.listdir(path) if f.endswith(".json"))
        elif os.path.isfile(path):
            files.append(path)
        else:
            sys.exit("no such file or directory: %s" % path)

    report = Report()
    seen_ids, all_summaries = {}, []
    for path in files:
        summaries = []
        for card in load(path, report):
            if not isinstance(card, dict):
                report.add("ERROR", path, "array item is not an object")
                continue
            cid = card.get("id")
            if cid in seen_ids:
                report.add("ERROR", cid, "duplicate id (also in %s)" % seen_ids[cid])
            seen_ids[cid] = path
            summary = validate_card(card, report)
            if summary:
                summaries.append(summary)
        batch_checks(summaries, report, os.path.basename(path))
        all_summaries += summaries

    # Compare against the approved deck without re-validating it.
    approved = []
    if os.path.isdir(APPROVED_PATH):
        for name in sorted(os.listdir(APPROVED_PATH)):
            if name.endswith(".json"):
                for card in load(os.path.join(APPROVED_PATH, name), report):
                    if card.get("id") in seen_ids:
                        report.add("ERROR", card.get("id"), "id is already approved; pick a new id")
                    approved.append({
                        "id": card.get("id"), "novelty": set(card.get("novelty_tags", [])),
                        "voices": {str(v).strip().lower(): k for k, v in card.get("voice_direction", {}).items()},
                        "threads": {str(th.get("detail", "")).strip().lower() for th in card.get("loose_threads", [])},
                        "grams": card_grams(card), "title_words": title_words(card),
                        "secret": str((card.get("core_why") or {}).get("secret", "")),
                    })

    # Near-duplicates across everything checked, and against the approved deck
    for i, a in enumerate(all_summaries):
        for b in all_summaries[i + 1:] + approved:
            shared = a["novelty"] & b["novelty"]
            if len(shared) >= 3:
                report.add("WARN", a["id"], "shares novelty tags %s with %s" % (sorted(shared), b["id"]))
            for detail in a["threads"] & b.get("threads", set()):
                report.add("WARN", a["id"], "loose thread copied word-for-word from %s: %r" % (b["id"], detail[:60]))
            for note in set(a["voices"]) & set(b["voices"]):
                report.add("WARN", a["id"], "voice_direction for %s is copied word-for-word in %s (%s)"
                           % (a["voices"][note], b["id"], b["voices"][note]))

    # Stock phrases shared by 3+ cards (checked + approved), and title words echoing approved cards
    from collections import Counter as _Counter
    gram_count = _Counter()
    for s in all_summaries + approved:
        gram_count.update(s.get("grams", set()))
    for s in all_summaries:
        shared = sorted(g for g in s["grams"] if gram_count[g] >= 3)
        if shared:
            report.add("ERROR", s["id"], "stock phrase used in 3+ cards (write it fresh): %r" % shared[0])
        if s.get("secret"):
            twins = [o["id"] for o in all_summaries + approved if o is not s and o["id"] != s["id"] and o.get("secret") == s["secret"]]
            if twins:
                report.add("WARN", s["id"], "core_why.secret %r repeats %s; a similar shape is fine, but the reason should be new "
                           "(if it truly differs, keep it and explain in your report)" % (s["secret"], ", ".join(twins[:3])))
        for word in sorted(s["title_words"]):
            echoes = [a["id"] for a in approved if word in a.get("title_words", set())]
            if echoes:
                report.add("INFO", s["id"], "title word %r echoes approved %s; fine if the core_why is different "
                           "" % (word, ", ".join(echoes[:3])))

    print("Checked %d cards in %d file(s)\n" % (len(all_summaries), len(files)))
    for s in all_summaries:
        errors = sum(1 for lvl, cid, _ in report.items if cid == s["id"] and lvl == "ERROR")
        warns = sum(1 for lvl, cid, _ in report.items if cid == s["id"] and lvl == "WARN")
        status = "FAIL" if errors else ("check" if warns else "pass")
        print("  %-5s %-40s %-8s beats %d  missions %d  errors %d  warnings %d"
              % (status, s["id"], s["scale"], s["beats"], s["missions"], errors, warns))
    if not quiet:
        print()
        for level in ("ERROR", "WARN", "INFO"):
            for lvl, cid, message in report.items:
                if lvl == level:
                    print("%-5s %s: %s" % (lvl, cid, message))
    print("\n%d errors, %d warnings, %d info" % (report.count("ERROR"), report.count("WARN"), report.count("INFO")))
    return 1 if report.count("ERROR") else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
