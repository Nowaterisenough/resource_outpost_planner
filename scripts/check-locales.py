"""Validate the English and Simplified Chinese localisation catalogues."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ("en", "zh-CN")


def catalogue(language):
    entries = {}
    for path in sorted((ROOT / "locale" / language).glob("*.cfg")):
        section = ""
        for number, raw in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
            line = raw.strip()
            if line.startswith("[") and line.endswith("]"):
                section = line[1:-1]
            elif "=" in line and not line.startswith(";"):
                key, value = line.split("=", 1)
                key = f"{section}.{key}"
                if key in entries:
                    raise ValueError(f"{path}:{number}: duplicate key {key}")
                entries[key] = value
    return entries


def main():
    catalogues = {language: catalogue(language) for language in LANGUAGES}
    expected = set().union(*(set(entries) for entries in catalogues.values()))
    errors = []
    for language, entries in catalogues.items():
        errors.extend(f"{language}: missing {key}" for key in sorted(expected - set(entries)))

    references = set()
    for path in ROOT.rglob("*.lua"):
        references.update(re.findall(r"\{\s*[\"']((?:mpp|mpp-oil)\.[A-Za-z0-9_-]+)[\"']", path.read_text(encoding="utf-8-sig")))
    for key in sorted(references):
        if key.endswith("_"):
            continue
        for language, entries in catalogues.items():
            if key not in entries:
                errors.append(f"{language}: missing referenced key {key}")

    for key in sorted(set(catalogues["en"]) & set(catalogues["zh-CN"])):
        placeholders = [sorted(re.findall(r"__(?:\d+|CONTROL(?:_KEY_SHIFT|_RIGHT_CLICK)?[^\s]*?)__", catalogues[language][key])) for language in LANGUAGES]
        if placeholders[0] != placeholders[1]:
            errors.append(f"{key}: placeholder mismatch: {placeholders}")
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"Locales OK: {len(expected)} keys per language; {len(references)} literal references checked.")


if __name__ == "__main__":
    main()
