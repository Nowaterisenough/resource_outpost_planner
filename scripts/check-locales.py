"""Check all shipped catalogues against the English keys and substitutions."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = tuple(sorted(path.name for path in (ROOT / "locale").iterdir() if path.is_dir()))


def catalogue(language):
    entries = {}
    for path in sorted((ROOT / "locale" / language).glob("*.cfg")):
        section = ""
        for number, raw in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
            line = raw.strip()
            if line.startswith("[") and line.endswith("]"):
                section = line[1:-1]
            elif "=" in line and not line.startswith((";", "#")):
                key, value = line.split("=", 1)
                key = f"{section}.{key}"
                if key in entries:
                    raise ValueError(f"{path}:{number}: duplicate key {key}")
                entries[key] = value
    return entries


def main():
    catalogues = {language: catalogue(language) for language in LANGUAGES}
    expected = set(catalogues["en"])
    errors = []
    for language, entries in catalogues.items():
        errors.extend(f"{language}: missing {key}" for key in sorted(expected - set(entries)))

    references = set()
    sources = list(ROOT.glob("*.lua"))
    for directory in ("gui", "layouts", "mpp", "oil", "prototypes", "tests"):
        sources.extend((ROOT / directory).rglob("*.lua"))
    for path in sources:
        references.update(re.findall(r"\{\s*[\"']((?:mpp|mpp-oil)\.[A-Za-z0-9_-]+)[\"']", path.read_text(encoding="utf-8-sig")))
    for key in sorted(references):
        if key.endswith("_"):
            continue
        for language, entries in catalogues.items():
            if key not in entries:
                errors.append(f"{language}: missing referenced key {key}")

    def substitutions(text):
        # Languages may express a quantity without a plural suffix.
        text = re.sub(r"__plural_for_parameter__\d+__\{[^}]*\}__", "", text)
        return sorted(re.findall(r"__CONTROL__[\w-]+__|__CONTROL_[A-Z_]+?__|__\d+__", text))

    for key in sorted(expected):
        wanted = substitutions(catalogues["en"][key])
        for language, entries in catalogues.items():
            value = entries.get(key, "")
            if not value.strip() or substitutions(value) != wanted:
                errors.append(f"{language}: empty or incorrect substitutions in {key}")
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"Locales OK: {len(expected)} keys in {len(LANGUAGES)} languages; {len(references)} literal references checked.")


if __name__ == "__main__":
    main()
