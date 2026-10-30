"""Build the offline brief-level dictionary bundled in the app.

Keeps ECDICT entries that are ranked, exam-tagged or marked by Collins/Oxford,
plus an inflection table (fled -> flee) taken from each kept lemma's exchange.

usage: build_brief_db.py ECDICT_CSV OUT_SQLITE
"""
from __future__ import annotations

import csv, re, sqlite3, sys
from pathlib import Path

WORD_RE = re.compile(r"^[A-Za-z]+([-'][A-Za-z]+)*$")
FORM_KEYS = {"p", "d", "i", "3", "s", "r", "t"}  # past, past participle, -ing, 3sg, plural, -er, -est


def keep(r: dict) -> bool:
    if not WORD_RE.match(r["word"]) or not r["translation"].strip():
        return False
    return any(int(r[k] or 0) > 0 for k in ("frq", "bnc", "collins", "oxford")) or bool(r["tag"].strip())


def clean_translation(t: str) -> str:
    lines = [l.strip() for l in t.split("\\n")]
    return "\n".join(l for l in lines if l and not l.startswith("["))


def main() -> None:
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    dst.unlink(missing_ok=True)
    db = sqlite3.connect(dst)
    db.executescript("""
        CREATE TABLE entry (word TEXT PRIMARY KEY, phonetic TEXT, translation TEXT NOT NULL,
                            rank INTEGER NOT NULL, tags TEXT NOT NULL) WITHOUT ROWID;
        CREATE TABLE form (form TEXT NOT NULL, lemma TEXT NOT NULL, PRIMARY KEY (form, lemma)) WITHOUT ROWID;
    """)
    entries, forms = [], set()
    with open(src, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if not keep(r):
                continue
            tr = clean_translation(r["translation"])
            if not tr:
                continue
            ranks = [int(x) for x in (r["frq"], r["bnc"]) if x and int(x) > 0]
            entries.append((r["word"], r["phonetic"], tr, min(ranks) if ranks else 0, r["tag"]))
            for part in r["exchange"].split("/"):
                k, _, v = part.partition(":")
                if k in FORM_KEYS and v and v != r["word"]:
                    forms.add((v, r["word"]))
    db.executemany("INSERT OR IGNORE INTO entry VALUES (?,?,?,?,?)", entries)
    db.executemany("INSERT OR IGNORE INTO form VALUES (?,?)", sorted(forms))
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(f"entries={len(entries)} forms={len(forms)} size={dst.stat().st_size / 1e6:.1f}MB")


if __name__ == "__main__":
    main()
