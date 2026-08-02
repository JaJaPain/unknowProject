class_name QuietMomentChecks
extends RefCounted

# Deterministic screening for generated quiet-moment lines.
#
# Every check here came from a defect seen in real model output during the
# research in docs/research/quiet_moment/. None of them are speculative.
#
# IMPORTANT: this is a SAFETY NET, not a quality gate. A deterministic
# validator cannot tell a good line from a bland one — measured: a
# corpus-derived allow-list caught 11/11 real failures and false-rejected
# 30/30 legitimate lines. Quality comes from the beat's hook, its demos and
# the model. Do not tune this hoping lines get better.
#
# Method and rationale: skills/skill_llm_character_dialogue.md

# Models emit U+2019 for apostrophes; ASCII patterns silently miss it. This
# cost two checks before it was noticed.
const SMART_QUOTES := {
	"’": "'", "‘": "'", "“": "\"", "”": "\"",
	"—": "-", "–": "-",
}

const PRAISE_TERMS := [
	"you're good at", "youre good at", "you're good", "you did good",
	"you did well", "nice work", "well done", "good work", "proud of you",
	"you handled it", "impressive", "you earned",
]

const NUMBER_WORDS := [
	"two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
	"eleven", "twelve", "dozen", "hundred", "thousand",
]

# N.O.V.A. is close to being in love with the Captain. Three separate beats
# drifted into implying he is deficient, demanding an apology, or inverting
# her own affection. It recurs across beats, so it lives here rather than in
# three separate beat briefs.
const BELITTLE_TERMS := [
	"lost", "slow", "slower", "clumsy", "careless", "useless", "sloppy",
	"hopeless", "reckless", "amateur",
]
const APOLOGY_TERMS := [
	"apolog", "say sorry", "owe me an", "make it up to me", "feel guilty",
	"should feel bad",
]
const INVERSION_TERMS := [
	"hate being touched", "don't like being touched", "hate it when you touch",
	"don't want you near", "keep your hands off",
]

# Third parties whose masculine pronoun is legitimately theirs. Without this
# a blanket he/his ban false-flags every line about the yard mechanic.
const THIRD_PARTY_TERMS := [
	"mechanic", "engineer", "crew", "yard", "dockhand", "technician",
	"fitter", "someone else", "somebody else", "stranger",
]

# These lines are SPOKEN. A construction that reads fine but renders badly is
# still a defect. See docs/tts_hygiene_notes.md.
const TTS_SYMBOLS := ["/", "&", "%", "@", "#", "*", "_", "~"]

const STOP_WORDS := [
	"a", "an", "the", "and", "or", "but", "so", "of", "to", "in", "on", "at",
	"for", "with", "from", "as", "by", "if", "is", "are", "was", "were", "be",
	"been", "am", "i", "my", "me", "you", "your", "it", "its", "this", "that",
	"these", "those", "we", "us", "our", "they", "them", "their", "he", "she",
	"not", "no", "do", "does", "did", "done", "have", "has", "had", "will",
	"would", "can", "could", "should", "may", "might", "must", "there", "here",
	"just", "still", "only", "even", "yet", "again", "now", "than", "too",
	"very", "much", "more", "most", "all", "any", "some", "what", "which",
	"who", "when", "where", "why", "how", "i'm", "i'll", "i've", "you're",
	"you'll", "you've", "it's", "that's", "don't", "doesn't", "didn't",
	"won't", "can't", "isn't", "aren't", "wasn't", "weren't", "they're",
	"there's", "let's",
]


static func normalize(text: String) -> String:
	var clean := text
	for raw in SMART_QUOTES:
		clean = clean.replace(raw, SMART_QUOTES[raw])
	return clean


static func words_of(text: String) -> PackedStringArray:
	var clean := normalize(text).to_lower()
	var kept := ""
	for i in clean.length():
		var c := clean[i]
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "'":
			kept += c
		else:
			kept += " "
	return kept.split(" ", false)


static func _has_word(text: String, term: String) -> bool:
	var padded := " " + " ".join(words_of(text)) + " "
	return padded.contains(" " + term.to_lower() + " ")


static func _has_any_word(text: String, terms: Array) -> bool:
	for t in terms:
		if _has_word(text, str(t)):
			return true
	return false


static func _has_any_substring(text: String, terms: Array) -> bool:
	var low := normalize(text).to_lower()
	for t in terms:
		if low.contains(str(t).to_lower()):
			return true
	return false


# Shared run of n words, used for every echo check.
static func shares_run(a: String, b: String, n: int = 5) -> bool:
	var aw := words_of(a)
	var bw := words_of(b)
	if aw.size() < n or bw.size() < n:
		return false
	var bs := " ".join(bw)
	for start in range(aw.size() - n + 1):
		if bs.contains(" ".join(aw.slice(start, start + n))):
			return true
	return false


# Returns an array of failure tags. Empty means the line may be spoken.
#
# context keys (all optional):
#   packet, lead_in, brief, speaker, word_cap, demos, third_parties
static func screen(line: String, context: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	var clean := normalize(line).strip_edges()
	if clean.is_empty():
		errors.append("empty_line")
		return errors

	var speaker := str(context.get("speaker", ""))
	var packet := str(context.get("packet", ""))
	var lead_in := str(context.get("lead_in", ""))
	var brief := str(context.get("brief", ""))
	var cap := int(context.get("word_cap", 28))

	# --- echoes: never hand our own inputs back to the player
	for demo in context.get("demos", []):
		if shares_run(clean, str(demo), 5):
			errors.append("demo_echo")
			break
	if not packet.is_empty() and shares_run(clean, packet, 5):
		errors.append("packet_echo")
	if not brief.is_empty() and shares_run(clean, brief, 6):
		errors.append("brief_echo")
	if not lead_in.is_empty():
		# A 5-word run misses short lead-ins ("They're finished." is two words
		# and was echoed verbatim), so compare opening words directly too.
		var lw := words_of(lead_in)
		var xw := words_of(clean)
		var shared := mini(lw.size(), xw.size())
		var prefix_match := shared >= 2
		for i in shared:
			if lw[i] != xw[i]:
				prefix_match = false
				break
		if prefix_match or shares_run(clean, lead_in, 4):
			errors.append("lead_in_echo")
		if (lead_in + " " + clean).to_lower().count("captain") > 1:
			errors.append("double_address")

	# --- shape
	if clean.split(" ", false).size() > cap:
		errors.append("too_long")
	if clean.contains("\n"):
		errors.append("multiline")

	# --- character
	if speaker == "kaelen":
		if clean.to_lower().contains("captain"):
			errors.append("wrong_address")
		if _has_any_substring(clean, PRAISE_TERMS):
			errors.append("generic_praise")
	elif speaker == "nova":
		if clean.to_lower().contains("shiny"):
			errors.append("wrong_address")
		if _has_word(clean, "you") and _has_any_word(clean, BELITTLE_TERMS):
			errors.append("belittles_captain")
		if _has_any_substring(clean, APOLOGY_TERMS):
			errors.append("demands_apology")
		if _has_any_substring(clean, INVERSION_TERMS):
			errors.append("inverts_affection")

	# he/him/his is only wrong when it means the CAPTAIN
	if _has_any_word(clean, ["he", "him", "his"]):
		var third_party := _has_any_word(clean, THIRD_PARTY_TERMS)
		if not third_party:
			for name in context.get("third_parties", []):
				# match on tokens: the pool holds "old Ferro", she says "Ferro"
				for token in str(name).split(" ", false):
					if token.length() > 2 and _has_word(clean, token):
						third_party = true
						break
				if third_party:
					break
		if not third_party:
			errors.append("assumes_captain_gender")

	# --- invented quantities the packet never supplied
	var has_digit := false
	for i in clean.length():
		if clean[i] >= "0" and clean[i] <= "9":
			has_digit = true
			break
	# "one" is deliberately excluded: it is overwhelmingly a demonstrative
	# here ("this one paid small") and flagged 9/20 good lines when included.
	if (has_digit or _has_any_word(clean, NUMBER_WORDS)) \
			and not _packet_has_number(packet):
		errors.append("invented_number")

	# --- spoken-word hazards
	if _has_hyphen_compound(clean):
		errors.append("tts_hyphen_compound")
	if _has_all_caps_run(clean):
		errors.append("tts_all_caps")
	if _has_any_substring(clean, TTS_SYMBOLS):
		errors.append("tts_symbol")
	if clean.contains("...") or clean.contains("…"):
		errors.append("tts_ellipsis")

	# --- intra-line repetition ("My hips are full. My knees are full...")
	var counts := {}
	for w in words_of(clean):
		if STOP_WORDS.has(w):
			continue
		counts[w] = int(counts.get(w, 0)) + 1
		if int(counts[w]) >= 3:
			errors.append("word_echo")
			break

	return errors


static func _packet_has_number(packet: String) -> bool:
	if packet.is_empty():
		return false
	for i in packet.length():
		if packet[i] >= "0" and packet[i] <= "9":
			return true
	return _has_any_word(packet, NUMBER_WORDS)


static func _has_hyphen_compound(text: String) -> bool:
	var low := normalize(text).to_lower()
	for i in range(1, low.length() - 1):
		if low[i] != "-":
			continue
		var before := low[i - 1]
		var after := low[i + 1]
		if before >= "a" and before <= "z" and after >= "a" and after <= "z":
			return true
	return false


static func _has_all_caps_run(text: String) -> bool:
	for word in normalize(text).split(" ", false):
		var core := ""
		for i in word.length():
			var c := word[i]
			if (c >= "A" and c <= "Z") or (c >= "a" and c <= "z"):
				core += c
		if core.length() < 2:
			continue
		if core == core.to_upper():
			return true
	return false
