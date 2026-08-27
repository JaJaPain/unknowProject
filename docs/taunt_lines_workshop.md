# Enemy taunt lines — authoring session

Working file for the guided pass. Abe writes 2-3 anchor lines per cause; those
anchors set the register and I fill out the rest toward them. Every line here is
checked against the real runtime validator
(`LLMInterface.validate_taunt_line`) before it is accepted, so nothing lands in
the game that the speech path would mangle.

**Status legend:** ⬜ not started · 🟡 in progress · ✅ anchors done

| Cause | When it fires | Status |
|---|---|---|
| `pirate_predation` | Pirates jumped you for your cargo | 🟡 |
| `contract_hit` | You shot them to collect a bounty | 🟡 |
| `unprovoked` | You shot a neutral going about their business | ✅ |
| `preemptive_strike` | You shot first at someone already coming for you | ⬜ |
| `code_enforcement` | Patrol collecting your unpaid mining fine | ⬜ |
| `reputation_grudge` | A faction acting on your bad standing | ⬜ |
| `reinforcement` | Backup, after you fought their people earlier | ⬜ |
| `opportunist` | They started it and won't say why | ⬜ |

**Standing decisions from Abe (2026-08-18):**
- Fix grammar and typos silently; post the corrected line so he can read it.
- Apply suggested changes without waiting; he pauses if he dislikes one.
- **PG-13, mild profanity expected and encouraged.** These are people trying to
  kill the player and being killed by them; they are not expected to be sweet.
  My authored fill-in lines should lean into this rather than staying polite.

Rules a line has to satisfy (enforced, not advisory):
- One line, spoken aloud mid-fight. No line breaks.
- 8–170 characters. Under ~18 words reads best; over ~24 gets clipped by pace.
- No speaker prefix (`ENEMY:`), no stage directions (`*laughs*`).
- No brackets or placeholders.
- The speaker never knows the pilot's name — no "Indy", no "Shiny".
- No question mark inside a word (encoding corruption guard).

---

## Anchors

### pirate_predation

1. **Abe:** "Nothing personal dude. My kids need to eat, and selling your cargo will make that happen."
   - Validator: OK (16 words, 89 chars).
   - ACCEPTED: comma before the direct address. Abe's tail kept as written --
     the shorter variant was optional, not a fix.
   - FINAL: "Nothing personal, dude. My kids need to eat, and selling your cargo will make that happen."
   - (Shorter alternative still available if wanted: "...and your cargo pays for it.")
   - Note: supersedes my authored "Nothing personal. You're just carrying." —
     drop mine rather than open two lines the same way.
2. **Abe:** "You are in the wrong place, at the right time.  Lets make this fast."
   - Validator: OK (14 words, 68 chars).
   - NEEDS FIX: `Lets` -> `Let's`. Without the apostrophe Kokoro can read it as
     the verb rather than the contraction. Double space normalised too.
   - Optional: `You are` -> `You're` sounds more natural spoken, but the
     uncontracted form reads as deliberate, which suits someone being cheerfully
     businesslike about robbing you. Recommended: keep "You are".
   - FINAL: "You are in the wrong place, at the right time. Let's make this fast."
     (apostrophe fixed, double space normalised, "You are" kept as deliberate.)
   - The comma before "at the right time" is the beat that sets up the twist.
3. **Abe:** "I really don't need your shit. I just like to hurt people."
   - Validator: OK (12 words, 58 chars).
   - CAUSE MISMATCH: pirate_predation fires because they want the CARGO. This
     line denies that motive outright, so the fight's stated reason and the
     enemy's stated reason disagree.
   - Recommended: move to `opportunist` (they started it, no provable reason,
     they do not justify themselves). A sadist fits it exactly, and that cause
     is currently the thinnest and blandest of the eight.
   - Alternative if it stays here: "Your cargo's a bonus. I'm mostly here for
     this part." (10 words, validates) -- stacks the motives instead of denying
     one. Weaker than the original.
   - PROFANITY: resolved -- PG-13 with mild profanity is the house standard.
   - MOVED to `opportunist` as written, unchanged. It makes that cause stronger
     and stops contradicting the cargo motive here.
   - FINAL (under opportunist): "I really don't need your shit. I just like to hurt people." 

### contract_hit

1. **Abe:** "I know i must have pissed off someone.  Mind telling me who you kill me?"
   - TYPO: "who you kill me" does not parse. Corrected options, all validating:
     - A: "...Mind telling me who before you kill me?" (16 words)
     - B: "...Mind telling me who, before you kill me?" (16 words) RECOMMENDED --
       the comma is the pause that lands the resigned beat.
     - C: "...Mind telling me who paid you?" (14 words) tighter, loses the shrug.
   - ACCEPTED: B.
   - FINAL: "I know I must have pissed off someone. Mind telling me who, before you kill me?"
   - Also capitalised "i" -> "I", normalised double space.
   - REGISTER NOTE: resigned and mildly curious, NOT bitter or wounded. This is
     better than what I briefed the model toward; write the rest of the cause
     toward it. It states all three facts the player needs (a price on me, you
     came to collect, I do not know who) in plain words.
2. **Abe:** "The price on my head cant be enough for you to put your life at risk."
   - Grammar fixed: `cant` -> `can't`. Validator OK (16 words, 70 chars).
   - FINAL: "The price on my head can't be enough for you to put your life at risk."
   - NOT applied (offered, Abe can still take it): "The price on my head can't be
     worth your life." (10 words) -- tighter but loses "put your life at risk",
     which is the phrase doing the threatening.
   - REGISTER NOTE: a threat wearing the costume of concern. He is not pleading,
     he is telling the pilot they misjudged the trade -- implying he is the
     reason it was a bad trade. Distinct move from line 1's shrug.
3. **Abe:** "how about you just say you killed me, and we can split the money. Sixty, forty."
   - Validator OK (16 words). Grammar: capitalise "How".
   - SYSTEM CONFLICT: the game already has a bribe mechanic --
     `TARGET_WITH_COMMS_REVERSAL` missions hail the player mid-fight with a real
     branching take-the-deal / finish-the-kill choice, and
     `CombatManager._is_comms_reversal_target()` SUPPRESSES the generic taunt
     for those enemies so it cannot step on that dialog.
     So as a contract_hit taunt this line lands in the worst possible spot: on a
     normal kill it offers a deal with no button behind it (and players who have
     seen the real mechanic will go looking), and on an actual bribe mission it
     never plays at all.
   - Options, all validating:
     - A: as written (16 words)
     - B: "I'd offer you sixty-forty to say you killed me, but you don't look creative." (14)
     - C: "Suppose you say you killed me and we split it. No? Worth asking." (13) RECOMMENDED --
       the enemy answers his own offer, so nothing implies an interaction, and it
       matches the resigned register of his line 1.
   - AWAITING ABE'S PICK. Nothing applied.
   - SEPARATE OPPORTUNITY: version A is strong material for the comms-reversal
     HAIL itself, where the offer is real and the player does choose. Worth
     reusing there rather than discarding.

### unprovoked

1. **Abe:** "What the hell?  Your ass just shot the wrong guy!"
   - Validator OK (10 words, 48 chars). Double space normalised.
   - FINAL (pending the note below): "What the hell? Your ass just shot the wrong guy!"
   - REGISTER NOTE: best opening in the set so far. Shock lands FIRST, the threat
     rides underneath it, and "the wrong guy" does double duty as outrage and
     warning. This beats the mundane-detail angle I tuned the model toward --
     write the rest of this cause toward the shock-then-threat shape.
   - OPEN (Abe's call): "guy" assumes the player's gender, and the codebase never
     establishes one -- every other speaker uses "pilot", "you", or the nickname.
     "...shot the wrong pilot!" keeps the meter and validates identically, but is
     less colloquial and this speaker is furious rather than precise.
2. **Abe:** "I don't know why you pulled that trigger, but i do know you are going to regret it."
   - Grammar: `i` -> `I`. Validator OK (18 words, 83 chars).
   - FINAL: "I don't know why you pulled that trigger, but I do know you are going to regret it."
   - Longest line in the set, right at the edge for combat pace -- but the length
     IS the effect: he is taking his time, which is what makes it cold. Keep.
   - NOT applied: "you're" (17 words). Uncontracted reads as deliberate, and
     deliberate is the point.
   - REGISTER NOTE: line 1 is hot shock, this is controlled and rehearsed. Two
     temperatures in one cause is what stops the rotation feeling samey -- worth
     preserving deliberately when I fill this cause out.
3. **Abe:** "You better have a good apology and a drink waiting or your ass is going to die today."
   - Validator OK (18 words). Comma added before "or" (compound sentence, and it
     is the beat before the threat lands).
   - FINAL: "You better have a good apology and a drink waiting, or your ass is going to die today."
   - REGISTER NOTE: the clearest example of the house voice so far. The joke is
     the ESCALATION OF BANALITY -- the alternative to dying today is an apology
     AND a drink, as if those are comparable terms. Nobody is telling a joke; the
     situation is absurd and the speaker is dead serious. This is the target.
   - Happens to land on a real system: the lounge has drinks, so "a drink
     waiting" reads as an in-world thing rather than a figure of speech.
   - CAUSE COMPLETE: three distinct temperatures -- hot shock, cold promise,
     furious absurdity. Preserve that spread when filling out.

_(filled in as we go)_
