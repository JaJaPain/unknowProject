# The undercurrent nudge: draft for Abe's review (core loop step 11b)

Plan section 4.6: N.O.V.A. and Kaelen both keep nudging the Captain deeper,
lightly and constantly, and never say why. **Nothing here ships until Abe has
read every line against the canon.** Mark anything to cut or change; I'll only
build what's approved.

Ground rules these lines follow:

- **Authored only.** These exact lines, no model, no prompt.
- **Deniable.** Each has a plain reading: N.O.V.A. is restless and likes the
  open lanes; Kaelen is a broker who wants her pilot where the money is.
- **No reasons, no secrets.** Nothing about why, nothing about the Captain's
  past, nothing about either of them that the generated world could repeat.
- **N.O.V.A. never gives orders.** She voices a feeling, never an instruction.
- **Light.** At most one nudge from each of them per system visit, with long
  cooldowns (below). It should read as character, never as a quest marker.
- **They never mention each other's nudges.** The player is the only one who
  notices both are doing it.

---

## 1. N.O.V.A.

### 1a. Lingering shallow

**When:** in a system shallower than the deepest one you've reached, after
about 10 minutes of flight there. Once per visit, and at most once every 30
minutes of play.

1. "We've been here a while. I don't like standing still."
2. "Same stars as last time. I'd memorised them already."
3. "I keep plotting routes out of here. Just habit. Ignore me."
4. "It's quiet back here. Too quiet for me, anyway."
5. "Do you ever get the feeling a place has already said everything it's going to say?"

(Cut 2026-10-02, Abe: "I'm not complaining. I'm noticing." didn't move the
player forward.)

### 1b. A new gate class opens

**When:** right after an upgrade lifts the Ship Rating to a new gate class (in
place of, or just after, her existing line about the class).

1. "That opens the next ring. Good. That's... good."
2. "There. Now the deeper gates will take us. I feel better than I should about that."
3. "Another class open. I still hate the gates. I hate them a little less when they lead somewhere new."
4. "Rating's up. The map just got bigger. I like it bigger."

### 1c. A new deepest system

**When:** arriving in a system deeper than any you've visited before. At most
once per 2 new depths, so it stays rare.

1. "Further than we've been. It's calmer out here. Don't ask me why I think so."
2. "New depth record. I've logged it. I may have logged it twice."
3. "This far out, everything's new. I could get used to that."

---

## 2. Kaelen

She's never aboard, so all of hers arrive **over comms** (comms filter, a
Broker Kaelen line in the feed), or in person at a main station's agent screen.

### 2a. After an upgrade is fitted

**When:** the next time you undock after fitting an upgrade. At most once
every 45 minutes of play.

1. "Good. Now go."
2. "New parts. Now take them somewhere worth the money, Shiny."
3. "That's paid for. Don't waste it on the same old lanes."
4. "Fitted? Good. The work's further out. It always is."

### 2b. Back in a shallow system too long

**When:** in a system 2 or more jumps shallower than your deepest, after
about 15 minutes of flight there. At most once every 45 minutes of play.

1. "You don't belong back here, Shiny."
2. "Still in the shallows? The money moved on. So should you."
3. "Nothing out there for you this close to home. Trust me on that."
4. "I'm not paying you to sightsee the places you've already seen."

### 2c. Her gate leads point deeper

**Mechanics:** her paid gate reveals cost **30% less** when the gate leads
deeper than where you are (outward), and the same as now otherwise.

**When she offers an outward one**, one of these is added:

1. "This one goes deeper. I'll take less for it. Call it an investment."
2. "Outward lane. Cheaper than the rest. Don't read anything into it."

### 2d. Deep survey data

**Mechanics:** already built in step 11 (survey data pays +25% per depth).

**When you sell data from 4+ jumps out**, one of these:

1. "Deep charts. Now that's worth something. Bring me more of these."
2. "Further out pays better. You've noticed that by now."

### 2e. In her job pitches (added 2026-10-02, Abe)

**When:** at the end of some of her mission offers, not all: about **1 in 4**,
never two offers in a row, never on the tutorial job. Her pitch itself is
unchanged; one authored line is added after it, so no model ever writes or
sees the nudge. None of these claims anything about the job itself (who the
client is, where they're from), so they can't contradict the mission.

1. "Work like this is drying up back here. The good jobs are moving outward."
2. "Do this one well and I'll have something further out for you next."
3. "Small job. The real ones are a few jumps further out."
4. "Take it, get paid, then let's talk about lanes you haven't flown."
5. "Clients this close to home pay like it. Remember that."
6. "Think of this one as fuel money for somewhere further out."
7. "Everyone back here wants it cheap. Out there they pay for good pilots."

### 2f. If you ask why

There's no "ask her" option in the game today, so nothing here yet. If one is
added, she changes the subject like closing a deal, e.g. "Why does anyone want
anything, Shiny? Money. Next question."

---

## 3. What I'd build once approved

- Authored pools exactly as approved (code constants; not in any prompt or
  data file a model reads).
- The triggers and cooldowns above, saved with the campaign.
- Kaelen's lines through the comms path from playtest fix 4.
- The outward discount on her gate reveals.
- Tests: each trigger fires once and respects its cooldown; the two never fire
  on the same event; every line passes the reserved-topic check.
