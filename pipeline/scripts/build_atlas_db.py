"""Add word-atlas entries (the mid level) to the bundled dictionary.

word-atlas text, illustrations and recordings are CC BY 4.0
("Word Atlas contributors"); the app's About page must credit them.

usage: build_atlas_db.py WORD_ATLAS_JSON THUMB_DIR DICT_SQLITE
"""
from __future__ import annotations

import json, sqlite3, sys
from pathlib import Path


def split_pair(s: str) -> dict[str, str]:
    en, _, zh = s.partition("｜")
    return {"en": en.strip(), "zh": zh.strip()}


def main() -> None:
    src, thumbs, dst = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    entries = json.loads(src.read_text(encoding="utf-8"))
    db = sqlite3.connect(dst)
    db.executescript("""
        DROP TABLE IF EXISTS atlas;
        CREATE TABLE atlas (word TEXT PRIMARY KEY, id TEXT NOT NULL, uk TEXT, us TEXT,
                            senses TEXT NOT NULL, examples TEXT NOT NULL, collocations TEXT NOT NULL,
                            family TEXT NOT NULL, synonyms TEXT NOT NULL, antonyms TEXT NOT NULL,
                            tip TEXT, note TEXT, cefr TEXT, topic TEXT, image TEXT,
                            route INTEGER NOT NULL) WITHOUT ROWID;
    """)
    rows, with_image = [], 0
    for i, e in enumerate(entries):
        img = f"{e['id']}.webp" if (thumbs / f"{e['id']}.webp").exists() else None
        with_image += img is not None
        rows.append((
            e["w"], e["id"], e.get("uk"), e.get("us"),
            json.dumps(e["senses"], ensure_ascii=False),
            json.dumps(e.get("ex", []), ensure_ascii=False),
            json.dumps([split_pair(c) for c in e.get("col", [])], ensure_ascii=False),
            json.dumps(e.get("fam", []), ensure_ascii=False),
            json.dumps(e.get("syn", []), ensure_ascii=False),
            json.dumps(e.get("ant", []), ensure_ascii=False),
            e.get("tip") or None, e.get("note") or None, e.get("cefr"), e.get("topic"), img,
            i,  # word-atlas learning-route order (CEFR easy -> hard)
        ))
    db.executemany("INSERT OR REPLACE INTO atlas VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", rows)
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(f"atlas={len(rows)} with_image={with_image} size={dst.stat().st_size / 1e6:.1f}MB")


if __name__ == "__main__":
    main()
