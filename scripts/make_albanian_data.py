#!/usr/bin/env python3
# Version: 0.002
# MAINTAINER-ONLY (build 0.064): builds the Albanian data of the alb=1 sessions.  NOT part of Robert's run loop: make, make ship,
# make slice and make check never call it; its outputs are committed:
#   data/sq_book.txt        Tatoeba sentence id <TAB> Albanian <TAB> English (the book the wesen find), UTF-8
#   data/sq_nouns.txt       lemma <TAB> gender (m/f/n) <TAB> plural <TAB> definite singular <TAB> definite plural (trimmed)
#   data/sq_noun_forms.txt  form <TAB> lemma <TAB> kind (is = indefinite singular, ds = definite singular, ip, dp = plurals)
# Rerun:
#   curl -L -o /tmp/kaikki-Albanian.jsonl https://kaikki.org/dictionary/Albanian/kaikki.org-dictionary-Albanian.jsonl  (~65 MB,
#   linked from https://kaikki.org/dictionary/Albanian/index.html; never commit it)
#   python3 scripts/make_albanian_data.py <tatoeba-en-sq.tsv> /tmp/kaikki-Albanian.jsonl
# The TSV: Tatoeba English-Albanian pairs, 4 tab columns en_id, en_text, sq_id, sq_text (CC BY 2.0 FR).  Credits:
# data/CREDITS-albanian.txt.  Deterministic: the same inputs give the same bytes.  It prints the counts it reports.
import collections, json, re, sys, unicodedata

STRIPPED = {   # whole-word, case-insensitive: words written without their diacritics (checked by hand against the sentences)
    "nje", "eshte", "esht", "jane", "shum", "shume", "per", "qe", "mire", "nevoje", "tjeter", "ler", "dicka", "plake",
    "vjeter", "shoqeri", "ketu", "perdorur", "pershendetje", "filxhane", "zvarraniket", "fishekzjarret", "kete", "cfare",
    "keshtu", "gjithcka", "ishe"}
# kept on purpose: te ('at/to'), me ('with'), dhe ('and'), veten, sillen, futet, katrore, Meri, Baker (real words or names)
PER_ENDING = 4          # nouns kept per (last two letters, gender) besides the book nouns: enough to show every ending
TOK = re.compile(r"[^\W\d_]+")


def unstress(x):
    """Wiktionary tables mark the stress (máce): drop acute and grave accents, keep ë and ç"""
    return unicodedata.normalize("NFC", "".join(c for c in unicodedata.normalize("NFD", x) if c not in "\u0300\u0301"))


def toks(s):
    return [t.lower() for t in TOK.findall(s)]


def gender_of(d):
    """first arg of sq-noun, else g of the head template, else sense / form tags; '' if none or ambiguous"""
    hts = d.get("head_templates", [])
    for h in hts:
        if h.get("name") == "sq-noun":
            g = h.get("args", {}).get("1", "")
            if g:
                return norm(g)
    for h in hts:
        g = h.get("args", {}).get("g", "")
        if g:
            return norm(g)
    tags = set()
    for s in d.get("senses", []):
        tags.update(s.get("tags", []))
    for f in d.get("forms", []):
        tags.update(f.get("tags", []))
    gs = [x for x, t in (("m", "masculine"), ("f", "feminine"), ("n", "neuter")) if t in tags]
    return gs[0] if len(gs) == 1 else ""


def norm(g):
    g = g.strip().lower()
    return g[0] if g[:1] in ("m", "f", "n") and not g.startswith("mf") else ""


def main():
    tsv, jsonl = sys.argv[1], sys.argv[2]
    rows = [l.rstrip("\n").split("\t") for l in open(tsv, encoding="utf-8") if l.strip()]
    no_dia = [r for r in rows if not re.search("[ëçËÇ]", r[3])]
    has = [r for r in rows if re.search("[ëçËÇ]", r[3])]
    kept = [r for r in has if not (set(toks(r[3])) & STRIPPED)]
    # nouns
    nouns = {}            # lemma -> (gender, plural, def sg, def pl)
    all_w = set()         # every word with a recorded gender (the count a peer compares)
    ambiguous = set()     # noun forms left out because another part of speech has them too
    forms_all = {}        # form -> (lemma, kind), first lemma (sorted) wins
    other = set()         # words and forms of entries that are not nouns (verbs, pronouns, particles, adjectives ...)
    for line in open(jsonl, encoding="utf-8"):
        d = json.loads(line)
        if d.get("pos") in ("noun", "name", "character", "symbol", "suffix", "prefix"):
            continue
        other.add(unstress(d.get("word", "")).lower())
        for f in d.get("forms", []):
            other.add(unstress(f.get("form", "")).lower())
    for line in open(jsonl, encoding="utf-8"):
        d = json.loads(line)
        if d.get("pos") != "noun":
            continue
        w = d.get("word", "")
        g = gender_of(d)
        if not g:
            continue
        all_w.add(w)
        if not w or " " in w or w[0].isupper():
            continue
        pl = ds = dp = ""
        for f in d.get("forms", []):
            t = set(f.get("tags", []))
            x = unstress(f.get("form", ""))
            if not x or " " in x or x.startswith("sq-noun") or x == "no-table-tags":
                continue
            if "nominative" in t or len(t) <= 2:
                if "plural" in t and "definite" in t and not dp:
                    dp = x
                elif "plural" in t and "indefinite" in t and not pl:
                    pl = x
                elif t == {"plural"} and not pl:
                    pl = x
                elif "definite" in t and "plural" not in t and "indefinite" not in t and not ds:
                    ds = x
        lw = w.lower()
        if lw not in nouns:
            nouns[lw] = (g, pl.lower(), ds.lower(), dp.lower())
    for lw in sorted(nouns):
        g, pl, ds, dp = nouns[lw]
        for x, k in ((lw, "is"), (ds, "ds"), (pl, "ip"), (dp, "dp")):
            if x and x not in forms_all and x not in other:   # only forms that can only be a noun: "ka", "dua", "më" are not cues
                forms_all[x] = (lw, k)
            elif x and x in other:
                ambiguous.add(x)
    # matches: distinct word forms of the kept sentences that are a noun lemma or a noun form
    book_tokens = collections.Counter(t for r in kept for t in toks(r[3]))
    matched = sorted(t for t in book_tokens if t in forms_all)
    book_lemmas = sorted({forms_all[t][0] for t in matched})
    # trim: the book nouns + PER_ENDING per (ending, gender), alphabetical
    keep = set(book_lemmas)
    per = collections.defaultdict(list)
    for lw in sorted(nouns):
        g = nouns[lw][0]
        if g in ("m", "f") and nouns[lw][2]:
            per[(lw[-2:], g)].append(lw)
    for k in sorted(per):
        keep.update(per[k][:PER_ENDING])
    with open("data/sq_book.txt", "w", encoding="utf-8") as o:
        o.write("# diary-sim build 0.064: the Albanian book (alb=1).  Tatoeba sentence id <TAB> Albanian <TAB> English.\n")
        o.write("# Tatoeba (https://tatoeba.org), CC BY 2.0 FR; see data/CREDITS-albanian.txt.  Built by scripts/make_albanian_data.py.\n")
        for r in kept:
            o.write("%s\t%s\t%s\n" % (r[2], r[3].strip(), r[1].strip()))
    with open("data/sq_nouns.txt", "w", encoding="utf-8") as o:
        o.write("# diary-sim build 0.064: Albanian nouns with gender (trimmed).  lemma <TAB> m/f/n <TAB> plural <TAB> definite sg <TAB> definite pl\n")
        o.write("# from English Wiktionary via kaikki.org (CC BY-SA 4.0 / GFDL; share-alike: data/CREDITS-albanian.txt)\n")
        for lw in sorted(keep):
            g, pl, ds, dp = nouns[lw]
            o.write("%s\t%s\t%s\t%s\t%s\n" % (lw, g, pl or "-", ds or "-", dp or "-"))
    with open("data/sq_noun_forms.txt", "w", encoding="utf-8") as o:
        o.write("# diary-sim build 0.064: noun form <TAB> lemma <TAB> is/ds/ip/dp (forms of the nouns of sq_nouns.txt)\n")
        o.write("# from English Wiktionary via kaikki.org (CC BY-SA 4.0 / GFDL; share-alike: data/CREDITS-albanian.txt)\n")
        for x in sorted(forms_all):
            if forms_all[x][0] in keep:
                o.write("%s\t%s\t%s\n" % (x, forms_all[x][0], forms_all[x][1]))
    n_all = len(all_w)
    gc = collections.Counter(v[0] for v in nouns.values())
    print("rows %d, no diacritics %d, with a stripped token %d, kept %d" % (len(rows), len(no_dia), len(has) - len(kept), len(kept)))
    print("(all noun entries with a gender: %d unique words incl. %d capitalised / multi-word ones left out)" % (n_all, n_all - len(nouns)))
    print("nouns with gender %d (m %d, f %d, n %d), kept %d (book %d)" % (len(nouns), gc["m"], gc["f"], gc["n"], len(keep), len(book_lemmas)))
    loose = sorted(t for t in book_tokens if t in forms_all or t in ambiguous)
    print("loose: book word forms matching any noun form, also those of other parts of speech: %d" % len(loose))
    print("distinct book word forms %d, matching a noun or form %d (tokens %d)" % (len(book_tokens), len(matched), sum(book_tokens[t] for t in matched)))


if __name__ == "__main__":
    main()
