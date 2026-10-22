#!/usr/bin/env python3
"""Translations: content/i18n/<code>.json maps each English string to its translation.

The English strings are every `L("…")` in Storyleaf/**/*.swift and the text fields of content/*.json
that content/i18n/fields.json names. A string with no translation shows in English.

  python3 tools/i18n.py extract            list every English string (JSON: text → where it's used)
  python3 tools/i18n.py status             per language: how many are translated, missing or stale
  python3 tools/i18n.py missing <code>     the English strings <code> lacks, as a JSON object to fill in
  python3 tools/i18n.py merge <code> <file>  add a JSON object of translations to <code>'s table
  python3 tools/i18n.py prune              drop translations whose English is gone from the game
  python3 tools/i18n.py check              errors only: broken placeholders, keys an L() can't use

Placeholders ({name}) must survive translation unchanged; `check` (and tools/check_content.py)
rejects a translation that loses or invents one.
"""
import glob
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
I18N = ROOT / "content" / "i18n"
PLACEHOLDER = re.compile(r"\{[A-Za-z_][A-Za-z0-9_]*\}")
CALL = re.compile(r'(?<![A-Za-z0-9_.])L\(\s*"((?:[^"\\\n]|\\.)*)"')
DYNAMIC = re.compile(r'(?<![A-Za-z0-9_.])L\(\s*(?!")(?!\))')


def unescape(literal):
    """A Swift string literal's contents as the string it makes."""
    out, i = [], 0
    while i < len(literal):
        c = literal[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        nxt = literal[i + 1]
        if nxt == "u" and literal[i + 2] == "{":
            end = literal.index("}", i)
            out.append(chr(int(literal[i + 3:end], 16)))
            i = end + 1
            continue
        out.append({"n": "\n", "t": "\t", "0": "\0", "\\": "\\", '"': '"', "'": "'"}.get(nxt, "\\" + nxt))
        i += 2
    return "".join(out)


def swift_strings():
    """(text, where) for every L("…") in the app's code, and problems found on the way."""
    found, problems = [], []
    for path in sorted(glob.glob(str(ROOT / "Storyleaf" / "**" / "*.swift"), recursive=True)):
        rel = Path(path).relative_to(ROOT)
        for number, line in enumerate(Path(path).read_text().splitlines(), 1):
            if line.lstrip().startswith("//") or "func L(" in line:
                continue
            for match in CALL.finditer(line):
                literal = match.group(1)
                if "\\(" in literal:
                    problems.append(f"{rel}:{number}: L() key has a \\( interpolation; use a {{placeholder}} and args")
                    continue
                found.append((unescape(literal), f"{rel}:{number}"))
            if DYNAMIC.search(line):
                problems.append(f"{rel}:{number}: L() needs a string literal, so the key can be found")
    return found, problems


def content_strings():
    """(text, where) for every translatable string in content/*.json."""
    fields = json.loads((I18N / "fields.json").read_text())
    found = []
    for file, keys in fields.items():
        if file.startswith("_"):
            continue
        data = json.loads((ROOT / "content" / f"{file}.json").read_text())
        everything = keys == "*"
        keys = set() if everything else set(keys)

        def walk(value, key):
            if isinstance(value, dict):
                for name, child in value.items():
                    if not name.startswith("_"):
                        walk(child, name)
            elif isinstance(value, list):
                for child in value:
                    walk(child, key)
            elif isinstance(value, str) and (everything or key in keys) and value.strip():
                found.append((value, f"content/{file}.json {key}"))

        walk(data, None)
    return found


def english():
    """Every English string, in order of first use, with where it's used."""
    swift, problems = swift_strings()
    texts = {}
    for text, where in swift + content_strings():
        texts.setdefault(text, []).append(where)
    return texts, problems


def languages():
    return [entry["code"] for entry in json.loads((I18N / "languages.json").read_text())["languages"]]


def table_path(code):
    return I18N / f"{code}.json"


def load_table(code):
    path = table_path(code)
    if not path.exists():
        return {}
    return json.loads(path.read_text()).get("strings", {})


def save_table(code, strings, order):
    rank = {text: index for index, text in enumerate(order)}
    ordered = dict(sorted(strings.items(), key=lambda item: (rank.get(item[0], len(rank)), item[0])))
    body = {
        "_about": f"{code} translations, keyed by the English text (tools/i18n.py). Missing ones show in English.",
        "strings": ordered,
    }
    table_path(code).write_text(json.dumps(body, indent=2, ensure_ascii=False) + "\n")


def placeholder_errors(code, strings):
    errors = []
    for source, target in strings.items():
        if not target:
            continue
        if sorted(PLACEHOLDER.findall(source)) != sorted(PLACEHOLDER.findall(target)):
            errors.append(f"{code}: placeholders differ: {source!r} → {target!r}")
    return errors


def check():
    """Errors: placeholders, L() calls the extractor can't read, a listed language with no table."""
    _, problems = english()
    errors = list(problems)
    for code in languages():
        if code == "en":
            continue
        if not table_path(code).exists():
            errors.append(f"{code}: content/i18n/{code}.json is missing")
            continue
        errors += placeholder_errors(code, load_table(code))
    return errors


def main(args):
    command = args[0] if args else "status"
    texts, problems = english()
    if command == "extract":
        print(json.dumps({text: where[:3] for text, where in texts.items()}, indent=2, ensure_ascii=False))
    elif command == "status":
        print(f"{len(texts)} English strings ({sum(len(t.split()) for t in texts)} words)")
        for code in languages():
            if code == "en":
                continue
            table = load_table(code)
            done = sum(1 for text in texts if table.get(text))
            stale = sum(1 for text in table if text not in texts)
            print(f"  {code:8} {done:5} translated, {len(texts) - done:5} missing, {stale:4} stale")
        for problem in problems:
            print("  ! " + problem)
    elif command == "missing":
        table = load_table(args[1])
        print(json.dumps({text: "" for text in texts if not table.get(text)}, indent=2, ensure_ascii=False))
    elif command == "merge":
        code, path = args[1], args[2]
        table = load_table(code)
        incoming = json.loads(Path(path).read_text())
        added = {k: v for k, v in incoming.items() if isinstance(v, str) and v}
        table.update(added)
        save_table(code, table, list(texts))
        print(f"{code}: merged {len(added)}")
        for error in placeholder_errors(code, added):
            print("  ! " + error)
    elif command == "prune":
        for code in languages():
            if code == "en" or not table_path(code).exists():
                continue
            table = load_table(code)
            kept = {k: v for k, v in table.items() if k in texts}
            save_table(code, kept, list(texts))
            print(f"{code}: dropped {len(table) - len(kept)}")
    elif command == "check":
        errors = check()
        for error in errors:
            print(error)
        sys.exit(1 if errors else 0)
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == "__main__":
    main(sys.argv[1:])
