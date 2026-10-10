"""Import the fixed 1..8 matrix, preserving each source blueprint's topology."""

import argparse
import base64
import copy
import importlib.util
import json
from pathlib import Path
import re
import zlib

ROOT = Path(__file__).resolve().parents[1]
module = importlib.util.spec_from_file_location("blueprints", Path(__file__).with_name("import-balancer-blueprints.py"))
blueprints = importlib.util.module_from_spec(module)
module.loader.exec_module(blueprints)


def read_book(path):
    raw = path.read_text().strip()
    return json.loads(raw if raw.startswith("{") else zlib.decompress(base64.b64decode(raw[1:], validate=True)))


def walk(value):
    if "blueprint" in value:
        yield value["blueprint"]
    elif "blueprint_book" in value:
        for child in value["blueprint_book"].get("blueprints", []):
            yield from walk(child)


def normalize(source, direction):
    blueprint = copy.deepcopy(source)
    turn = (8 - direction) % 16
    underground_names = set()
    for entity in blueprint["entities"]:
        supported = {"entity_number", "name", "position", "direction", "type", "input_priority", "output_priority", "filter"}
        if set(entity) - supported:
            raise ValueError(f"{source['label']}: unsupported entity fields {set(entity) - supported}")
        if entity["name"].endswith("underground-belt"):
            underground_names.add(entity["name"])
        x, y = entity["position"]["x"], entity["position"]["y"]
        for _ in range(turn // 4):
            x, y = -y, x
        entity["position"] = {"x": x, "y": y}
        entity["direction"] = (entity.get("direction", 0) * (2 if blueprint["version"] >> 48 < 2 else 1) + turn) % 16
    if len(underground_names) > 1:
        raise ValueError(f"{source['label']}: mixed-tier underground pairing cannot be substituted")
    blueprint["version"] = 2 << 48
    layout, error = blueprints.inspect(blueprint, strict=True)
    if error:
        raise ValueError(f"{source['label']}: {error}")
    if len(layout["specs"]) != len(source["entities"]):
        raise ValueError(f"{source['label']}: unsupported non-belt entities")
    return layout


def compactness(layout):
    specs = layout["specs"]
    area = (max(e["x"] for e in specs) - min(e["x"] for e in specs) + 1) * (max(e["y"] for e in specs) - min(e["y"] for e in specs) + 1)
    return area, len(specs), layout["label"]


def load_matrix(book, compatibility):
    matrix = {(n, m): [] for n in range(1, 9) for m in range(1, 9)}
    for source in walk(book):
        match = re.match(r"(\d+)_(\d+)(?:_|$)", source.get("label", ""))
        if not match or tuple(map(int, match.groups())) not in matrix:
            continue
        layout = normalize(source, 0)
        layout["source"] = "user-book"
        matrix[layout["n"], layout["m"]].append(layout)
    for pair, variants in matrix.items():
        variants.sort(key=compactness)
        if not variants and pair not in ((1, 2), (2, 1)):
            raise ValueError(f"Missing user blueprint {pair}")
    # The book omits these two single-splitter blueprints. Store them literally too.
    for n, m in ((1, 2), (2, 1)):
        matrix[n, m] = [{"label": f"{n}_{m}_single_splitter", "n": n, "m": m, "reach": 0,
                         "source": "single-splitter", "specs": [{"kind": "splitter", "x": .5, "y": 0, "direction": 8}],
                         "inputs": [{"x": x, "y": -1} for x in range(n)],
                         "outputs": [{"x": x, "y": 1} for x in range(m)]}]
    for source in walk(compatibility):
        layout = normalize(source, 8)
        layout["source"] = "tier-compatibility"
        matrix[layout["n"], layout["m"]].append(layout)
    return matrix


def encode_layout(layout):
    def number(value):
        return str(int(value)) if value == int(value) else str(value)
    def text(value):
        if isinstance(value, dict):
            return "{" + ",".join(key + "=" + text(val) for key, val in sorted(value.items())) + "}"
        return "nil" if value is None else json.dumps(value, ensure_ascii=True)
    def ports(name):
        return "{" + ",".join("{" + number(p["x"]) + "," + number(p["y"]) + "}" for p in layout[name]) + "}"
    entities = []
    for e in layout["specs"]:
        values = [text(e["kind"]), number(e["x"]), number(e["y"]), str(e["direction"]), text(e.get("type")),
                  text(e.get("input_priority")), text(e.get("output_priority")), text(e.get("filter"))]
        while values[-1] == "nil":
            values.pop()
        entities.append("{" + ",".join(values) + "}")
    return ("{label=" + text(layout["label"]) + ",n=" + str(layout["n"]) + ",m=" + str(layout["m"]) +
            ",reach=" + str(layout["reach"]) + ",source=" + text(layout["source"]) +
            ",lane=" + str("lane" in layout["label"]).lower() + ",\n" +
            "\t\t\tinputs=" + ports("inputs") + ",outputs=" + ports("outputs") + ",\n" +
            "\t\t\tentities={" + ",".join(entities) + "}},")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--book", type=Path, default=ROOT / "tests/fixtures/balancers/user-1-8.txt")
    parser.add_argument("--compatibility", type=Path, default=ROOT / "tests/fixtures/balancers/tier-compatibility.txt")
    parser.add_argument("--output", type=Path, default=ROOT / "mpp/balancer_matrix.lua")
    args = parser.parse_args()
    matrix = load_matrix(read_book(args.book), read_book(args.compatibility))
    lines = ["-- Generated by scripts/import-balancer-matrix.py; see BALANCER_BLUEPRINTS.md.", "return {"]
    for n in range(1, 9):
        lines.append(f"\t[{n}]={{")
        for m in range(1, 9):
            lines.append(f"\t\t[{m}]={{")
            lines.extend("\t\t\t" + encode_layout(v) for v in matrix[n, m])
            lines.append("\t\t},")
        lines.append("\t},")
    lines.append("}")
    args.output.write_text("\n".join(lines) + "\n")
    print(f"Imported 64 exact matrix cells ({sum(map(len, matrix.values()))} variants) into {args.output}")


if __name__ == "__main__":
    main()
