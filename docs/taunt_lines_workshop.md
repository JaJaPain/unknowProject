# Enemy taunt lines — authoring session

Working file for the guided pass. Abe writes 2-3 anchor lines per cause; those
anchors set the register and I fill out the rest toward them. Every line here is
checked against the real runtime validator
(`LLMInterface.validate_taunt_line`) before it is accepted, so nothing lands in
the game that the speech path would mangle.

**Status legend:** ⬜ not started · 🟡 in progress · ✅ anchors done

| Cause | When it fires | Status |
|---|---|---|
| `pirate_predation` | Pirates jumped you for your cargo | ✅ |
| `contract_hit` | You shot them to collect a bounty | 🟡 |
| `unprovoked` | You shot a neutral going about their business | ✅ |
| `preemptive_strike` | You shot first at someone already coming for you | ✅ |
| `code_enforcement` | Patrol collecting your unpaid mining fine | ✅ |
| `reputation_grudge` | A faction acting on your bad standing | ✅ |
| `reinforcement` | Backup, after you fought their people earlier | ✅ |
| `opportunist` | They started it and won't say why | ✅ |

**Standing decisions from Abe (2026-08-18):**
- **Enemies exist fully in this world.** Their motivation can be greed or
  revenge, but equally survival, fear, or a mental condition. They are not a
  menace-delivery system. This is the single most useful note of the session --
  it turns each cause from one emotion into a range, and it is why `opportunist`
  can hold both a sadist and a frightened pilot.
- **Creepy/menacing is intentional.** These NPCs are attacking the player; an
  unsettling register is wanted, not an accident. "naughty, naughty boy" stands.
- **Male-default address is fine.** The speaker does not know the player's
  gender, and male assumption is standard speech. "guy" / "boy" stay, and
  fill-in lines may use them.
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

### preemptive_strike

1. **Abe:** "You just gave me a second reason to kill you today."
   - Validator OK (11 words, 51 chars). No changes needed.
   - FINAL: as written.
   - REGISTER NOTE, the important one: the word "SECOND" carries the whole cause.
     It tells the player there was already a first reason without explaining it,
     so the enemy sounds like they have history and the player fills in the rest.
     My briefs kept pushing the model to STATE the situation, which is exactly
     why its lines came out explaining themselves. Implying it in one word is
     better, and it works because the player already knows they shot first.
     Apply this shape to the other causes when filling out.
2. **Abe:** "Mealy a flesh wound.  My turn!"
   - Typo fixed: `Mealy` -> `Merely`. Double space normalised. Validator OK
     (6 words, 30 chars) -- shortest line in the pool, which is the "simple
     bark" Abe asked for earlier.
   - FINAL (pending the note): "Merely a flesh wound. My turn!"
   - "My turn!" is the whole cause in two words: not offended, not surprised,
     just taking their go. Also nods at the turn-based combat itself.
   - OPEN (Abe's call): "Merely a flesh wound" sits close to the Monty Python
     Black Knight cadence. "Just a flesh wound" exists independently, but
     "Merely" leans into the echo. Alternative without it: "Barely a scratch.
     My turn!" (5 words, validates).
   - Accidental world consistency either way: calling HULL damage a flesh wound
     personifies the ship, and N.O.V.A. already talks about her hull as her body.
3. **Abe:** "If you thought that shot was good, wait till you see mine!"
   - Validator OK (12 words, 58 chars). No changes.
   - FINAL: as written.
   - Acknowledges the player landed first and dismisses it in the same breath.
     The only line so far that ANTICIPATES rather than reacts.
   - CAUSE COMPLETE: menace-with-history / dismissive shrug / competitive
     swagger. Three voices, like unprovoked.

### code_enforcement

**Design finding (Abe was right):** there is NO way to pay the fine.
`IllegalMiningEnforcement.pay_fine()` and `fine_due()` exist and are complete,
but have zero callers anywhere. Logged in docs/bugs.md. Consequence for lines:
never quote a sum, or the taunt advertises a mechanic that is not there.

1. **Abe:** "Mining without a permit. Don't take this personally.  I'm just doing my job."
   - Validator OK (13 words, 75 chars). Double space normalised.
   - REGISTER NOTE: stating the violation as a flat FRAGMENT -- no verb, just the
     charge -- is exactly how someone reads off a form. "I'm just doing my job"
     is the whole bureaucratic register in six words.
   - FINAL: "Mining without a permit. Don't take this personally. I'm just doing my job."
     (Abe's original KEPT -- he liked it, and chose to ADD a variant rather than
     swap. The overlap with the pirate "Nothing personal" is acceptable now that
     this cause has three lines and only one uses the formula: it reads as one
     officer's phrasing rather than a house tic.)
2. **Abe:** "No permit, no rocks.  Sorry!"
   - Validator OK (5 words, 27 chars). Double space normalised. Tied shortest.
   - FINAL: "No permit, no rocks. Sorry!"
   - REGISTER NOTE: built like a shop sign -- "no shirt, no shoes, no service" --
     which is exactly right for someone enforcing a rule they did not write. The
     "Sorry!" is insincere in a specific, recognisable way: cheerful, procedural,
     not sorry at all. Bureaucratic register in one word.
3. **Claude, Abe-approved:** "I don't write the rules, I just enforce them."
   - Validator OK (9 words, 45 chars).
   - Abe picked option B over A, and asked to keep his own line too.
   - DE-DUPLICATED: B originally opened "Mining without a permit." like line 1.
     Two lines in the SAME rotation opening identically is more noticeable than
     the cross-cause overlap, since the player hears them back to back. Dropping
     the prefix also improved it -- no charge, no procedure, just a man declining
     responsibility for what he is about to do.
   - CAUSE COMPLETE (3 lines): flat charge + "just my job" / shop-sign aphorism /
     responsibility-declining shrug.

### reputation_grudge

1. **Abe:** "My records show you've been a naughty, naughty boy."
   - Validator OK (9 words, 51 chars).
   - REGISTER NOTE: "My records show" is the institutional handle this cause
     needed -- it is a FILE talking, not a person, which is what separates it
     from the freelance pirate and the bored officer. The doubled adjective is
     the patronising rhythm: condescending rather than merely threatening.
   - RESOLVED: both flags were deliberate. Creepy/menacing is the intent, and
     male-default address is fine since the speaker does not know. Kept as written.
   - FINAL: "My records show you've been a naughty, naughty boy." 
2. **Abe:** "I was told our records show you are dirty.  Well I'm the cleaner!"
   - Comma added after "Well" (interjection); double space normalised.
     Validator OK (13 words, 65 chars).
   - REGISTER NOTE: "I'm the cleaner" is the best turn in the cause -- cleaner as
     the one who scrubs dirt AND the professional who disposes of problems. Two
     meanings, one word, both threats.
   - REPETITION: reuses "records show" from line 1, and they share a rotation, so
     the player hears them close together. Options, all validate:
     - A: as written (13)
     - B: "I was told you are dirty. Well, I'm the cleaner!" (10)
     - C: "The file says you're dirty. Well, I'm the cleaner!" (9) RECOMMENDED --
       swaps records->file so line 1 keeps "records", tightest, and "the file
       says" holds the same reading-off-a-screen quality.
   - ACCEPTED: C, with Abe's change "the" -> "these". That pulled file -> files
     and says -> say with it.
   - FINAL: "These files say you're dirty. Well, I'm the cleaner!"
3. **Abe:** "My computer shows you gotta bad rap.  Let me fix that for ya."
   - CORRECTION (mine): I "fixed" `gotta` -> `got a`. Abe is right that "gotta"
     colloquially renders "got a" ("you gotta problem?"), not only "got to".
     REVERTED to his spelling -- identical in TTS, and it carries the accent
     better in the on-screen text. Double space normalised. Validator OK (13
     words, 60 chars).
   - "Let me fix that for ya" is a strong dark joke -- fixing the reputation by
     removing the person from the record. "Bad rap" is a good register clash:
     street slang from someone reading an official file.
   - MONOTONE TRIO, my fault: all three lines open with the same MOVE --
     "My records show" / "These files say" / "My computer shows". I varied the
     vocabulary each time and missed that the underlying device never changed.
     Caused by my scenario brief over-steering toward the record/file angle.
   - Alternative that keeps the punchline but attacks from elsewhere:
     "You've got a bad rap around here. Let me fix that for ya." (13) -- hearsay
     and local reputation instead of another database lookup, and it implies the
     faction TALKS about the player, which is its own menace.
   - AWAITING ABE'S PICK.
   - LESSON for fill-out: vary the MOVE, not just the nouns. Check each cause's
     lines for a repeated underlying device, not repeated words.

### reinforcement

1. **Abe:** "You hurt one of ours.  Now we going to hurt you."
   - Validator OK (11 words). Double space normalised.
   - REGISTER NOTE: "one of ours" does the whole cause in three words -- there
     was a previous fight, these people are connected to it, and this is
     collective rather than personal. Blunt, and it should be: this crew is not
     clever, it is numerous.
   - OPEN: is the dropped copula in "we going" deliberate dialect or a typo?
     Both validate. A dropped "are" is a real dialect feature and would make this
     speaker sound distinct from the bureaucrat and the broker; it is also what a
     fast typo looks like. Asked rather than assumed, since Abe had just
     corrected an over-eager "fix" on `gotta`.
     - A (as written): "You hurt one of ours. Now we going to hurt you."
     - B (default): "You hurt one of ours. Now we're going to hurt you."
   - RESOLVED: Abe chose B.
   - FINAL: "You hurt one of ours. Now we're going to hurt you."
2. **Abe:** "Um. . . . That was my friend you just shot!"
   - Validator OK either spelling. Settled on "Um..." -- spaced periods read as a
     typo on screen, and (see below) the spelling never drove the pause anyway.
   - FINAL: "Um... That was my friend you just shot!"
   - REGISTER NOTE: the best beat in the whole set. Not a threat, not outrage --
     someone genuinely thrown, processing what they flew into. The only line that
     sounds like a person rather than a combatant, and it lands the cause exactly:
     they arrived AFTER, and found the aftermath.
   - MY EARLIER CLAIM WAS WRONG. I told Abe that Kokoro takes its pauses from
     punctuation and that commas were "the spoken beat". Measured: ". . . ." 2.67s,
     "..." 2.55s, "," 2.55s, "." 2.52s, "…" 2.50s -- a 0.17s spread. Punctuation
     barely moves it. Fixed properly instead, see below.
3. **Abe:** "If you ever blow someone up again, you should probably check  if he has friends first."
   - Validator OK (16 words, 85 chars). Double space normalised.
   - FINAL: as written.
   - REGISTER NOTE: best-constructed line of the session. It is ADVICE, delivered
     calmly, for a next time that obviously is not coming -- and it explains the
     whole cause without stating it: you shot someone, someone had friends, the
     friends are here. The player learns the mechanic from the taunt.
   - CAUSE COMPLETE: blunt collective threat / stunned disbelief / calm advice.

### opportunist

0. **Abe (moved here from pirate_predation):** "I really don't need your shit. I just like to hurt people."
   - Works BECAUSE the only motive offered is enjoyment, which is not a
     grievance the player can catch as a lie.

1. **Abe:** "I told my girl i wouldn't hurt anyone today.  I'm pretty sure she'll forgive me."
   - Grammar: `i` -> `I`. Double space normalised. Validator OK (15 words).
   - FINAL: "I told my girl I wouldn't hurt anyone today. I'm pretty sure she'll forgive me."
   - REGISTER NOTE: offers NO grievance at all -- the nearest thing to a motive is
     being mildly amused about breaking a promise, which cannot be caught as a
     lie. Exactly the constraint this cause needs, and the hardest to write to.
     "I'm pretty sure she'll forgive me" implies this is routine.
   - PATTERN (good, but do not overuse): Abe's second line using a DOMESTIC LIFE
     outside the violence as the humanising device -- the pirate has kids to
     feed, this one has a girl he promised. It is becoming a signature: his
     antagonists have lives, which makes killing them land differently. Vary the
     device when filling out rather than writing forty men with families.
2. **Abe:** "I don't know why you are flying so close.  But i cant take any chances."
   - Grammar: `i` -> `I`, `cant` -> `can't`. Double space normalised.
     Validator OK (15 words, 71 chars).
   - FINAL: "I don't know why you are flying so close. But I can't take any chances."
   - REGISTER NOTE: the most interesting line in the set. It makes the PLAYER the
     villain -- they really were just flying, and this person is scared, has no
     information, and shot first. The only line that reframes the encounter
     rather than colouring it.
   - It also fits the cause's constraint better than anything else: it does not
     merely decline to give a reason, it says outright there is not one. "I don't
     know why" IS the cause, spoken.
   - ACTION: update the OPPORTUNIST brief in TauntCause.gd. "Curt and unbothered"
     is too narrow and would steer every fill-in line toward swagger. Abe's
     framing gives the cause four registers: greed, revenge, survival, or
     something wrong with them.
   - Optional, not applied: "you're" (14 words), marginally more natural for a
     nervous speaker; uncontracted reads more deliberate, which suits someone
     choosing to shoot.
3. **Abe:** "Who sent you?  Stay back!  Stay back!"
   - Double spaces normalised. Validator OK (7 words, 35 chars).
   - FINAL: "Who sent you? Stay back! Stay back!"
   - REGISTER NOTE: pure panic, and the repetition does work no adjective could.
     Pairs with line 2 as the same person seconds later, giving the cause a
     frightened voice alongside the sadist.
   - WORTH KNOWING (kept deliberately): "Who sent you?" implies someone sent the
     player, and in this cause nobody did. He is WRONG, which is the point --
     but the game has real hidden-agenda machinery, so a player may read it as a
     plot hook. Keeping it: NPCs being wrong about the player is good
     worldbuilding, and strangers assuming you were sent fits the paranoid
     texture.

## ALL 8 CAUSES ANCHORED — 24 lines, every one validated against the runtime.

### What Abe's lines taught me that my briefs had wrong

1. **Imply the cause, don't state it.** "You just gave me a SECOND reason" tells
   the player there was a first without explaining it. My briefs pushed the model
   to state the situation, which is exactly why its lines explained themselves.
2. **Give the writer a concrete handle, not an emotion.** "Outraged and baffled"
   produced an argument; naming the dull thing they were interrupted doing
   produced "My shift ends in twelve minutes."
3. **Enemies have lives.** Kids to feed, a girl he promised, a shift ending.
   The humanising detail is what makes the dark humour land.
4. **A cause is a RANGE, not an emotion.** `opportunist` holds both a sadist and
   a frightened man who shot first. Greed, revenge, survival, or something wrong
   with them.
5. **Escalation of banality is the house joke.** "A good apology and a drink
   waiting, or your ass is going to die today."

### Remaining opens for Abe
- `contract_hit` line 3: bribe line A / B / C (system conflict with the real
  comms-reversal mechanic — see that entry).
- `reputation_grudge` line 3: keep "My computer shows..." or swap to the
  non-database variant, since all three lines currently open with the same move.
- TTS pause default is 0.7s globally, for every speaker, at any "...".

