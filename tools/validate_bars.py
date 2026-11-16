"""Check the bar cards of the song system (assets/data/bars/*.json): plain Python, no engine.

    python tools/validate_bars.py                 # every pack: each problem by card, then the tables; exit 1 on a problem
    python tools/validate_bars.py --lyrics        # every card's words, pack by pack (to read them)
    python tools/validate_bars.py --grid [ID ...] # cards on the sixteen-step grid, a column a step, | every beat
    python tools/validate_bars.py --line "I@0 broke^@2 the@4 win^@6 -dow@7"
                                                  # a line written short, printed as a card's {"text", "syl"}
    python tools/validate_bars.py --selftest      # broken cards made up here: each must be refused, by name
    python tools/validate_bars.py --digest        # the slot fills' digest (bars:check in the game prints the same)

The short way to write a line (--line): syllables in order, each `syllable@step`, `^` before the @ for a
strong stress (2), `+` for a medium one (1), nothing for weak (0); a syllable that goes on the word
before it starts with `-`; punctuation stays with its syllable and is left out of what is sung:
"Rose^@0 Hill+@2 Ter^@4 -race,@5 I@6 was@7 raised^@8 on@10 the@11 block^@12".

What a card must be (the contract, workers-20261116-songs.md; the rules here are the bars worker's):
  id                 unique, a-z 0-9 _
  lines              two, each {"text", "syl"} (plain ASCII); syl is [step, syllable, stress] for every sung syllable:
                     step 0-15 (sixteenths of its own bar) rising, stress 0 weak / 1 medium / 2 strong;
                     the syllables joined are the text (letters and digits; spaces, case and punctuation aside),
                     and no syllable runs across two words
  scansion           in each line most strong syllables (more than half) are on a beat or a sixteenth either
                     side of one (steps 0, 4, 8, 12 give or take 1), and the last strong one, the rhyme, is too
                     and is in the line's last word
  rhyme              a family of rules/rhymes.json; both lines' last words end in it
  tags               words for what it is about; exactly one flow: on_beat (most strong syllables right on the
                     beat), behind (most a sixteenth late), double (a run of 8 syllables on 8 sixteenths in a
                     row), rests (a gap of a beat or more inside a line, or a line that starts or ends a beat clear)
  true               true if it claims something he did: then it must have an unlock (the deed is the evidence)
  unlock             left out for the starter pack, else {"deed": a name in assets/data/deeds.json, "count": n >= 1}
  slot               optional {"line": 0 or 1 (lines[line]), "from": a list of rules/words.json}: the line ends in
                     one of that list's entries (its default); every entry of the list must scan there too
  hooks              a hook is four bars, two cards: ids hook_<name>_a and hook_<name>_b, both tagged hook,
                     the same rhyme, unlock and true
"""
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
POPUP = os.path.dirname(HERE)
BARS = os.path.join(POPUP, "assets", "data", "bars")
RULES = os.path.join(BARS, "rules")
DEEDS = os.path.join(POPUP, "assets", "data", "deeds.json")
SCRIPTS = os.path.join(POPUP, "scripts")

FIELDS = {"id", "lines", "rhyme", "tags", "true", "unlock", "slot"}
FLOWS = ("on_beat", "behind", "double", "rests")
PREFIXES = ("visited_", "met_", "chose_")      # deed names made in the code from a place, a person, a side


def letters(s):
    """What is sung of a piece of text: its letters and digits, lower case."""
    return "".join(ch for ch in s.lower() if ch.isalnum())


def words_of(text):
    """The text's words, each as its letters (E.R. is one word, er; a hyphen parts two words)."""
    out = []
    for w in re.findall(r"[A-Za-z0-9'][A-Za-z0-9'.]*", text):
        w = letters(w)
        if w:
            out.append(w)
    return out


def beat_gap(step):
    """How far a step is from the nearest beat (0, 4, 8, 12, 16): 0, 1 or 2 sixteenths."""
    r = step % 4
    return min(r, 4 - r)


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


# ------------------------------------------------------------------ the rules

class Rules:
    def __init__(self):
        self.deeds = load(DEEDS)["deeds"]
        self.rhymes = load(os.path.join(RULES, "rhymes.json"))["families"]
        self.lists = load(os.path.join(RULES, "words.json"))["lists"]

    def family_of(self, word):
        """The rhyme family a word (its letters) ends in, or ""."""
        for name, fam in self.rhymes.items():
            if word in fam.get("not", []):
                continue
            if word in fam.get("words", []) or any(word.endswith(e) for e in fam.get("endings", [])):
                return name
        return ""

    def rhymes_with(self, word, family):
        fam = self.rhymes.get(family, {})
        if word in fam.get("not", []):
            return False
        return word in fam.get("words", []) or any(word.endswith(e) for e in fam.get("endings", []))


# ------------------------------------------------------------------ one line

def line_problems(line, where, rules=None, rhyme=None):
    """What is wrong with one line {"text", "syl"} (a list of words; empty if nothing)."""
    bad = []
    if not isinstance(line, dict) or set(line) != {"text", "syl"}:
        return ["%s is not {\"text\", \"syl\"}" % where]
    text, syl = line["text"], line["syl"]
    if not isinstance(text, str) or not letters(text):
        return ["%s has no text" % where]
    if not text.isascii():
        return ["%s is not plain ASCII" % where]      # (scripts/bars.gd reads letters a-z, 0-9)
    if not isinstance(syl, list) or not syl:
        return ["%s has no syllables" % where]
    last = -1
    for i, s in enumerate(syl):
        if not (isinstance(s, list) and len(s) == 3 and isinstance(s[0], int) and not isinstance(s[0], bool)
                and isinstance(s[1], str) and isinstance(s[2], int) and not isinstance(s[2], bool)):
            return ["%s syllable %d is not [step, syllable, stress]" % (where, i)]
        step, sound, stress = s
        if not 0 <= step <= 15:
            bad.append("%s syllable %d (%s) is on step %d, not 0-15" % (where, i, sound, step))
        if step <= last:
            bad.append("%s syllable %d (%s) on step %d does not come after step %d" % (where, i, sound, step, last))
        last = step
        if stress not in (0, 1, 2):
            bad.append("%s syllable %d (%s) has stress %r, not 0, 1 or 2" % (where, i, sound, stress))
        if not letters(sound):
            bad.append("%s syllable %d is empty" % (where, i))
    if bad:
        return bad
    sung = "".join(letters(s[1]) for s in syl)
    if sung != letters(text):
        return ["%s: the syllables give \"%s\", the text \"%s\"" % (where, sung, letters(text))]
    # Which word each syllable is in: none may run across two.
    words = words_of(text)
    owner, w, used = [], 0, 0
    for s in syl:
        part = letters(s[1])
        while w < len(words) and used == len(words[w]):
            w, used = w + 1, 0
        if w >= len(words) or not words[w][used:].startswith(part):
            return ["%s: the syllable \"%s\" runs across two words" % (where, s[1])]
        owner.append(w)
        used += len(part)
    strong = [i for i, s in enumerate(syl) if s[2] == 2]
    if not strong:
        return ["%s has no strong syllable" % where]
    near = [i for i in strong if beat_gap(syl[i][0]) <= 1]
    if len(near) * 2 <= len(strong):
        bad.append("%s: only %d of its %d strong syllables are on or by a beat" % (where, len(near), len(strong)))
    if beat_gap(syl[strong[-1]][0]) > 1:
        bad.append("%s: its last strong syllable (%s, step %d) is not on or by a beat" % (where, syl[strong[-1]][1], syl[strong[-1]][0]))
    if owner[strong[-1]] != len(words) - 1:
        bad.append("%s: its last strong syllable (%s) is not in its last word" % (where, syl[strong[-1]][1]))
    if rules is not None and rhyme is not None and not rules.rhymes_with(words[-1], rhyme):
        bad.append("%s ends in \"%s\", not in the rhyme family %s" % (where, words[-1], rhyme))
    return bad


def flow_ok(flow, lines):
    """Does the card's flow tag say what its steps do?"""
    syls = [ln["syl"] for ln in lines]
    strong = [s for syl in syls for s in syl if s[2] == 2]
    if flow == "on_beat":
        return sum(1 for s in strong if s[0] % 4 == 0) * 2 > len(strong)
    if flow == "behind":
        return sum(1 for s in strong if s[0] % 4 == 1) * 2 > len(strong)
    if flow == "double":
        for syl in syls:
            run = 1
            for a, b in zip(syl, syl[1:]):
                run = run + 1 if b[0] == a[0] + 1 else 1
                if run >= 8:
                    return True
        return False
    if flow == "rests":
        for syl in syls:
            steps = [s[0] for s in syl]
            if steps[0] >= 4 or steps[-1] <= 11 or any(b - a >= 5 for a, b in zip(steps, steps[1:])):
                return True
        return False
    return False


# ------------------------------------------------------------------ slots

def anchor_of(sy):
    """The syllable a word is pinned by: its last strong one (else its last most stressed)."""
    top = max(s[-1] for s in sy)
    return max(i for i, s in enumerate(sy) if s[-1] == top)


def default_of(line, entries):
    """The entry of a list a line ends in (its default), and how many syllables it takes: (entry, n) or (None, 0)."""
    syl = line["syl"]
    best = (None, 0)
    for e in entries:
        n = len(e["syl"])
        if n <= len(syl) and [letters(s[1]) for s in syl[-n:]] == [letters(s[0]) for s in e["syl"]] and n > best[1]:
            best = (e, n)
    return best


def fill(line, n, entry):
    """The line with its last n syllables (its default) swapped for `entry`: {"text", "syl"}, or None if it does not
    fit. The entry's anchor goes on the default's anchor step; the syllables before it go 2 sixteenths apart (1 if
    2 would not clear the syllable before the slot), those after it 2 apart (1 if 2 would pass step 15).
    scripts/bars.gd's fill() is the same rule (the digest checks it)."""
    syl = line["syl"]
    head, old = syl[:len(syl) - n], syl[len(syl) - n:]
    at = old[anchor_of([[s[2]] for s in old])][0]
    prev = head[-1][0] if head else -1
    sy = entry["syl"]
    j = anchor_of(sy)
    before, after = j, len(sy) - 1 - j
    h = 2 if at + 2 * after <= 15 else 1
    if at + h * after > 15:
        return None
    g = 2 if at - 2 * before > prev else 1
    if at - g * before <= prev:
        return None
    out = [list(s) for s in head]
    for i, (sound, stress) in enumerate(sy):
        step = at - g * (before - i) if i < j else (at if i == j else at + h * (i - j))
        out.append([step, sound, stress])
    text = line["text"]
    tail = re.search(r"[^A-Za-z0-9]*$", text).group(0)
    body = text[:len(text) - len(tail)]
    return {"text": body[:cut_at(body, len(letters("".join(s[1] for s in old))))] + entry["text"] + tail, "syl": out}


def cut_at(body, n):
    """Where the last n letters (and digits) of `body` begin."""
    count = 0
    for i in range(len(body) - 1, -1, -1):
        if body[i].isalnum():
            count += 1
            if count == n:
                return i
    return 0


def fill_digest(cards, rules):
    """A digest of every slot fill, in order: bars.gd's bars:check prints the same if its fill() is the same."""
    parts = []
    for cid in sorted(cards):
        card = cards[cid]
        slot = card.get("slot")
        if not slot:
            continue
        line = card["lines"][slot["line"]]
        entries = rules.lists[slot["from"]]["entries"]
        _, n = default_of(line, entries)
        for e in entries:
            got = fill(line, n, e) if n else None
            parts.append("%s/%s:%s;" % (cid, e["id"], ",".join(str(s[0]) for s in got["syl"]) if got else "none"))
    return hashlib.md5("".join(parts).encode("utf-8")).hexdigest()


# ------------------------------------------------------------------ one card

def card_problems(card, rules, packs_ids=None):
    """What is wrong with one card (a list of words; empty if nothing)."""
    if not isinstance(card, dict):
        return ["not an object"]
    bad = []
    extra = set(card) - FIELDS
    if extra:
        bad.append("fields not in the contract: %s" % ", ".join(sorted(extra)))
    for need in ("id", "lines", "rhyme", "tags", "true"):
        if need not in card:
            bad.append("no %s" % need)
    if bad:
        return bad
    if not isinstance(card["id"], str) or not re.fullmatch(r"[a-z0-9_]+", card["id"]):
        bad.append("id %r is not a-z 0-9 _" % (card["id"],))
    rhyme = card["rhyme"]
    if rhyme not in rules.rhymes:
        bad.append("rhyme %r is not a family of rhymes.json" % (rhyme,))
        rhyme = None
    lines = card["lines"]
    if not isinstance(lines, list) or len(lines) != 2:
        return bad + ["lines: not two"]
    for i, ln in enumerate(lines):
        bad += line_problems(ln, "line %d" % i, rules, rhyme)
    tags = card["tags"]
    if not isinstance(tags, list) or not tags or not all(isinstance(t, str) and t for t in tags):
        bad.append("tags: not a list of words")
    else:
        flows = [t for t in tags if t in FLOWS]
        if len(flows) != 1:
            bad.append("tags: %d flows (one of %s)" % (len(flows), ", ".join(FLOWS)))
        elif not any(b.startswith("line") for b in bad) and not flow_ok(flows[0], lines):
            bad.append("tags: its steps are not the flow it names (%s)" % flows[0])
    if not isinstance(card["true"], bool):
        bad.append("true: not true or false")
    unlock = card.get("unlock")
    if unlock is not None:
        if not isinstance(unlock, dict) or set(unlock) != {"deed", "count"}:
            bad.append("unlock: not {\"deed\", \"count\"}")
        else:
            if unlock["deed"] not in rules.deeds:
                bad.append("unlock: no deed %r in deeds.json" % (unlock["deed"],))
            if not isinstance(unlock["count"], int) or isinstance(unlock["count"], bool) or unlock["count"] < 1:
                bad.append("unlock: count %r is not a whole number from 1" % (unlock["count"],))
    elif card["true"] is True:
        bad.append("true: it claims a deed but has no unlock")
    slot = card.get("slot")
    if slot is not None:
        bad += slot_problems(card, slot, rules)
    return bad


def slot_problems(card, slot, rules):
    if not isinstance(slot, dict) or set(slot) != {"line", "from"}:
        return ["slot: not {\"line\", \"from\"}"]
    if slot["line"] not in (0, 1) or isinstance(slot["line"], bool):
        return ["slot: line %r is not 0 or 1" % (slot["line"],)]
    if slot["from"] not in rules.lists:
        return ["slot: no list %r in words.json" % (slot["from"],)]
    line = card["lines"][slot["line"]]
    if line_problems(line, "x"):
        return []
    entries = rules.lists[slot["from"]]["entries"]
    default, n = default_of(line, entries)
    if default is None:
        return ["slot: line %d does not end in an entry of %s" % (slot["line"], slot["from"])]
    bad = []
    for e in entries:
        got = fill(line, n, e)
        if got is None:
            bad.append("slot: %s (%s) does not fit line %d" % (e["id"], e["text"], slot["line"]))
            continue
        for p in line_problems(got, "with %s" % e["id"]):
            bad.append("slot: " + p)
    return bad


def word_problems(rules):
    """The lists of words: each entry {"id", "text", "syl": [[syllable, stress]...], and what gives it: "deed" or "weapon"}."""
    bad = []
    for name, lst in rules.lists.items():
        seen = set()
        for e in lst.get("entries", []):
            where = "words.json %s/%s" % (name, e.get("id"))
            if set(e) - {"id", "text", "syl", "deed", "weapon"} or not {"id", "text", "syl"} <= set(e):
                bad.append("%s: fields" % where)
                continue
            if e["id"] in seen:
                bad.append("%s: the id twice" % where)
            seen.add(e["id"])
            if ("deed" in e) == ("weapon" in e):
                bad.append("%s: needs a deed or a weapon (one)" % where)
            if "deed" in e and e["deed"] not in rules.deeds:
                bad.append("%s: no deed %s" % (where, e["deed"]))
            if not all(isinstance(s, list) and len(s) == 2 and isinstance(s[0], str) and s[1] in (0, 1, 2) for s in e["syl"]):
                bad.append("%s: syl is not [[syllable, stress] ...]" % where)
            elif "".join(letters(s[0]) for s in e["syl"]) != letters(e["text"]):
                bad.append("%s: the syllables are not the text" % where)
            elif 2 not in [s[1] for s in e["syl"]]:
                bad.append("%s: no strong syllable" % where)
    return bad


def load_packs():
    """Every pack: (file name, its about, its cards), and problems with the files themselves."""
    packs, bad = [], []
    for name in sorted(os.listdir(BARS)):
        path = os.path.join(BARS, name)
        if not name.endswith(".json") or not os.path.isfile(path):
            continue
        try:
            data = load(path)
        except (OSError, ValueError) as e:
            bad.append("%s: not JSON (%s)" % (name, e))
            continue
        if not isinstance(data, dict) or set(data) != {"about", "cards"} or not isinstance(data["cards"], list):
            bad.append("%s: not {\"about\", \"cards\": [...]}" % name)
            continue
        packs.append((name, data["about"], data["cards"]))
    return packs, bad


def check_all(rules):
    """Every card of every pack. Returns (good cards by id, their packs, problems)."""
    packs, problems = load_packs()
    problems += word_problems(rules)
    cards, pack_of = {}, {}
    for name, _, pack in packs:
        for i, card in enumerate(pack):
            cid = card.get("id") if isinstance(card, dict) else None
            label = "%s %s" % (name, cid if isinstance(cid, str) else "card %d" % i)
            bad = card_problems(card, rules)
            if isinstance(cid, str) and cid in pack_of:
                bad.append("the id is also in %s" % pack_of[cid])
            if bad:
                problems += ["%s: %s" % (label, b) for b in bad]
                continue
            cards[cid] = card
            pack_of[cid] = name
    # Hooks: two halves that go together.
    for cid, card in cards.items():
        is_hook = "hook" in card["tags"]
        m = re.fullmatch(r"hook_([a-z0-9]+)_([ab])", cid)
        if is_hook != bool(m):
            problems.append("%s %s: a hook is tagged hook and named hook_<name>_a or _b (both or neither)" % (pack_of[cid], cid))
            continue
        if m:
            other = "hook_%s_%s" % (m.group(1), "b" if m.group(2) == "a" else "a")
            if other not in cards:
                problems.append("%s %s: its other half %s is missing" % (pack_of[cid], cid, other))
            elif any(cards[other].get(k) != card.get(k) for k in ("rhyme", "unlock", "true")):
                problems.append("%s %s: its halves differ in rhyme, unlock or true" % (pack_of[cid], cid))
    return cards, pack_of, problems, packs


def hooked_deeds(rules):
    """Deed names the code counts: (every deeds.json name a script names, names in deed() calls that are not deeds)."""
    named, unknown = set(), []
    for root, _, files in os.walk(SCRIPTS):
        for f in files:
            if not f.endswith(".gd"):
                continue
            with open(os.path.join(root, f), encoding="utf-8") as fh:
                src = "\n".join(ln for ln in fh.read().splitlines() if not ln.strip().startswith("#"))     # not the comments
            for lit in re.findall(r'"([a-z_]+)"', src):
                if lit in rules.deeds:
                    named.add(lit)
                elif lit in PREFIXES:
                    named.update(d for d in rules.deeds if d.startswith(lit))
            for m in re.finditer(r'(?:\bdeed|Deeds\.once)\((?:main,\s*)?"([a-z_]+)"(?:\s+if[^"]*else\s+"([a-z_]+)")?', src):
                for lit in m.groups():
                    if lit and lit not in rules.deeds and lit not in PREFIXES:
                        unknown.append("%s: %s" % (f, lit))
    return named, unknown


# ------------------------------------------------------------------ printing

def grid(line):
    """A line on the sixteen steps: a column a step (UPPER strong, Capitalised medium, lower weak), | every beat."""
    at = {s[0]: s for s in line["syl"]}
    cols = []
    for step in range(16):
        if step and step % 4 == 0:
            cols.append("|")
        s = at.get(step)
        if s is None:
            cols.append(".")
        else:
            w = re.sub(r"[^A-Za-z0-9']", "", s[1])
            cols.append(w.upper() if s[2] == 2 else (w[:1].upper() + w[1:].lower() if s[2] == 1 else w.lower()))
    return " ".join(cols)


def short_line(spec):
    """The short way of writing a line (see the top) to {"text", "syl"}."""
    text, syl = "", []
    for tok in spec.split():
        if "@" not in tok:
            raise SystemExit("no @step in %r" % tok)
        left, step = tok.rsplit("@", 1)
        stress = 0
        while left.endswith(("^", "+")):
            stress = max(stress, 2 if left.endswith("^") else 1)
            left = left[:-1]
        joined = left.startswith("-")
        piece = left[1:] if joined else left
        text += piece if joined or not text else " " + piece
        syl.append([int(step), re.sub(r"[^A-Za-z0-9'.]", "", piece).strip("."), stress])
    return {"text": text, "syl": syl}


def table(title, rows):
    print("\n%s" % title)
    width = max([len(k) for k, _ in rows] + [4])
    for k, v in rows:
        print("  %-*s  %s" % (width, k, v))


def report(cards, pack_of, packs, rules):
    fams = {}
    for cid, c in cards.items():
        fams.setdefault(c["rhyme"], []).append(cid)
    table("Cards by rhyme family (%d families)" % len(fams), [(f, "%2d  %s" % (len(v), " ".join(sorted(v)))) for f, v in sorted(fams.items())])
    tags = {}
    for cid, c in cards.items():
        for t in c["tags"]:
            tags.setdefault(t, []).append(cid)
    table("Cards by tag", [(t, "%2d" % len(v)) for t, v in sorted(tags.items(), key=lambda kv: (-len(kv[1]), kv[0]))])
    deeds = {}
    for cid, c in cards.items():
        u = c.get("unlock")
        deeds.setdefault("%s x%d" % (u["deed"], u["count"]) if u else "(starter)", []).append(cid)
    table("Cards by deed (what unlocks them)", [(d, "%2d  %s" % (len(v), " ".join(sorted(v)))) for d, v in sorted(deeds.items())])
    table("Packs", [(name, "%2d cards: %s" % (len(pack), about)) for name, about, pack in packs])
    rows = []
    for cid in sorted(cards):
        slot = cards[cid].get("slot")
        if not slot:
            continue
        line = cards[cid]["lines"][slot["line"]]
        entries = rules.lists[slot["from"]]["entries"]
        default, n = default_of(line, entries)
        keep = [e["id"] for e in entries if rules.rhymes_with(words_of(e["text"])[-1], cards[cid]["rhyme"])]
        rows.append((cid, "%s, line %d, default %s: all %d fit; keep the rhyme: %s" % (slot["from"], slot["line"], default["id"], len(entries), " ".join(keep))))
    table("Slots", rows)
    true_n = sum(1 for c in cards.values() if c["true"])
    hooks = sorted({re.sub(r"_[ab]$", "", cid) for cid in cards if "hook" in cards[cid]["tags"]})
    print("\n%d cards in %d packs; %d starter, %d unlocked by a deed, %d true; %d hooks (%s)" % (
        len(cards), len(packs), sum(1 for c in cards.values() if "unlock" not in c), sum(1 for c in cards.values() if "unlock" in c),
        true_n, len(hooks), ", ".join(hooks)))


def selftest(rules):
    """Made-up broken cards: each must be refused, and a good one kept."""
    good = {"id": "test_good", "lines": [short_line("Rose^@0 Hill+@2 Ter^@4 -race,@5 I@6 was@7 raised^@8 on@10 the@11 block^@12"),
                                          short_line("Where@0 the@1 cor+@2 -ners@3 tell^@4 the@5 time^@6 we@7 nev^@8 -er@9 had@10 a@11 clock^@12")],
            "rhyme": "ock", "tags": ["block", "on_beat"], "true": False}

    def broken(**change):
        c = json.loads(json.dumps(good))
        for k, v in change.items():
            if v is None:
                c.pop(k, None)
            else:
                c[k] = v
        return c

    def line_with(i, **change):
        c = json.loads(json.dumps(good))
        c["lines"][i].update(change)
        return c

    lines = good["lines"]
    cases = {
        "one line": broken(lines=lines[:1]),
        "a step past 15": line_with(0, syl=[[0, "Rose", 2], [2, "Hill", 1], [4, "Ter", 2], [5, "race", 0], [6, "I", 0], [7, "was", 0], [8, "raised", 2], [10, "on", 0], [11, "the", 0], [16, "block", 2]]),
        "steps not rising": line_with(0, syl=[[0, "Rose", 2], [2, "Hill", 1], [4, "Ter", 2], [5, "race", 0], [6, "I", 0], [6, "was", 0], [8, "raised", 2], [10, "on", 0], [11, "the", 0], [12, "block", 2]]),
        "syllables not the text": line_with(0, text="Rose Hill Terrace, I was born on the block"),
        "not plain ASCII": line_with(0, text="Rose Hill Terrace, I was raised on the blöck"),
        "a stress of 3": line_with(0, syl=[[0, "Rose", 3]] + lines[0]["syl"][1:]),
        "strong syllables off the beat": line_with(0, syl=[[2, "Rose", 2], [3, "Hill", 1], [6, "Ter", 2], [7, "race", 0], [8, "I", 0], [9, "was", 0], [10, "raised", 2], [11, "on", 0], [12, "the", 0], [14, "block", 2]]),
        "not in its rhyme": line_with(1, text="Where the corners tell the time we never had a watch",
                                      syl=lines[1]["syl"][:-1] + [[12, "watch", 2]]),
        "an unknown rhyme family": broken(rhyme="orange"),
        "an unknown deed": broken(unlock={"deed": "flew_to_the_moon", "count": 1}),
        "a count of 0": broken(unlock={"deed": "shot_fired", "count": 0}),
        "true with no deed": broken(true=True),
        "two flows": broken(tags=["block", "on_beat", "double"]),
        "a flow its steps are not": broken(tags=["block", "behind"]),
        "a field not in the contract": broken(mood="sad"),
        "a slot from no list": broken(slot={"line": 1, "from": "planets"}),
        "a slot on line 2": broken(slot={"line": 2, "from": "places"}),
        "a slot whose line ends in none of the list": broken(slot={"line": 1, "from": "places"}),
        "no id": broken(id=None),
    }
    ok = not card_problems(good, rules)
    print("selftest: the good card is %s" % ("kept" if ok else "REFUSED: " + "; ".join(card_problems(good, rules))))
    for name, c in cases.items():
        bad = card_problems(c, rules)
        ok = ok and bool(bad)
        print("selftest: %-44s %s" % (name, ("refused: " + bad[0]) if bad else "KEPT (wrong)"))
    print("selftest: %s" % ("ok" if ok else "FAILED"))
    return ok


def main():
    args = sys.argv[1:]
    if args and args[0] == "--line":
        print(json.dumps(short_line(" ".join(args[1:]))))
        return 0
    rules = Rules()
    if args and args[0] == "--selftest":
        return 0 if selftest(rules) else 1
    cards, pack_of, problems, packs = check_all(rules)
    if args and args[0] == "--digest":
        print("fill digest %s" % fill_digest(cards, rules))
        return 0
    if args and args[0] == "--lyrics":
        for name, about, pack in packs:
            print("\n== %s: %s" % (name, about))
            for c in pack:
                if c.get("id") in cards:
                    print("\n[%s] %s%s" % (c["id"], c["rhyme"], "  (" + ", ".join(c["tags"]) + ")"))
                    for ln in c["lines"]:
                        print("    " + ln["text"])
        return 0
    if args and args[0] == "--grid":
        for cid in (args[1:] or sorted(cards)):
            c = cards.get(cid)
            if c is None:
                print("%s: no such card (or refused)" % cid)
                continue
            print("\n[%s] %s, %s" % (cid, c["rhyme"], ", ".join(c["tags"])))
            for ln in c["lines"]:
                print("  %s\n  %s" % (ln["text"], grid(ln)))
        return 0
    named, unknown = hooked_deeds(rules)
    for u in unknown:
        problems.append("a deed() in %s is not in deeds.json" % u)
    for d in sorted(set(rules.deeds) - named):
        problems.append("deeds.json: %s is not counted anywhere in scripts/" % d)
    report(cards, pack_of, packs, rules)
    print("deeds: %d in deeds.json, every one counted in scripts/: %s" % (len(rules.deeds), "yes" if named >= set(rules.deeds) else "NO"))
    print("fill digest %s" % fill_digest(cards, rules))
    if problems:
        print("\n%d problems:" % len(problems))
        for p in problems:
            print("  " + p)
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
