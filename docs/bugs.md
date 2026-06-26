# Known Bugs
_Confirmed issues spotted during playtesting. Move to todo.md or close with a commit reference when fixed._

---

## Active

### Autopilot object avoidance regressed
**Spotted:** ~2026-06-21  
**Severity:** Medium  
**Description:** Autopilot no longer avoids obstacles. Was working before, regressed around 2026-06-21.  
**Where to look:** `scripts/PlayerShip.gd` autopilot logic; any recent changes to navigation or physics layers that could have broken obstacle detection.

---

### Agent accept reply uses Kaelen voice
**Spotted:** 2026-06-23  
**Severity:** Medium — breaks immersion every time a quest is accepted  
**Description:** After the player accepts a quest from an agent (Liaison Ryn, Director Voss, etc.), the agent's spoken reply uses Kaelen's voice instead of the agent's own voice blend.  
**Where to look:** `UIManager.gd` or `SpeechService` — wherever the post-accept dialogue TTS call is made. Check that the agent's voice blend is passed, not defaulting to the Kaelen blend.

---

### Quest tracker panel blue box reappears on second quest
**Spotted:** 2026-06-25  
**Severity:** Low — cosmetic  
**Description:** When the player accepts a second quest, the oversized empty blue box (quest tracker panel) reappears. The `call_deferred("reset_size")` fix only fires when the panel first becomes visible; it doesn't re-fire when a new quest loads into an already-visible panel.  
**Where to look:** `scripts/UIManager.gd` → `_update_quest_tracker()`. The `reset_size()` call needs to fire every time quest content changes. Also check if `user://ui_layout.json` is persisting a saved `w`/`h` for the quest panel and re-applying it on each update.

---

### Mechanic pickup prompt persists after quest delivery
**Spotted:** 2026-06-25  
**Severity:** Low  
**Description:** After the player delivers a special cargo item to the mechanic NPC and receives credits, the "I'll Grab It / Not Now" buttons still show on subsequent visits. They should disappear permanently once the pickup quest is complete.  
**Where to look:** `scripts/UIManager.gd` — wherever the mechanic dock panel is built/refreshed. The prompt visibility is likely gated on a quest state flag that isn't being cleared after completion. Check `QuestManager` or `GlobalState` for the relevant completion flag.

---

## Fixed

| Date | Bug | Fix |
|---|---|---|
| 2026-06-25 | Combat flee taunt used Kaelen voice | Added `_play_npc_flee_taunt()` in `CombatManager._exec_flee()` |
