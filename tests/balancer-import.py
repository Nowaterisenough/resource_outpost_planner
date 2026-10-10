"""Verify source fidelity and reproducible generation of the fixed matrix."""

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("matrix", ROOT / "scripts/import-balancer-matrix.py")
matrix = importlib.util.module_from_spec(spec)
spec.loader.exec_module(matrix)


class MatrixImport(unittest.TestCase):
    def test_original_entities_survive_normalization(self):
        counts = set()
        for path, direction in (("user-1-8.txt", 0), ("tier-compatibility.txt", 8)):
            for blueprint in matrix.walk(matrix.read_book(ROOT / "tests/fixtures/balancers" / path)):
                layout = matrix.normalize(blueprint, direction)
                self.assertEqual(len(blueprint["entities"]), len(layout["specs"]))
                self.assertEqual(len(layout["inputs"]), layout["n"])
                self.assertEqual(len(layout["outputs"]), layout["m"])
                if direction == 0:
                    counts.add((layout["n"], layout["m"]))
                translation = None
                for original, normalized in zip(blueprint["entities"], layout["specs"]):
                    factor = -1 if direction == 0 else 1
                    offset = tuple(normalized[axis] - factor * original["position"][axis] for axis in ("x", "y"))
                    translation = offset if translation is None else translation
                    self.assertEqual(offset, translation)
                    scale = 2 if blueprint["version"] >> 48 < 2 else 1
                    self.assertEqual(normalized["direction"], (scale * original.get("direction", 0) + 8 - direction) % 16)
                    for key in ("type", "input_priority", "output_priority", "filter"):
                        self.assertEqual(normalized.get(key), original.get(key))
        self.assertEqual(counts, {(n, m) for n in range(1, 9) for m in range(1, 9)} - {(1, 2), (2, 1)})

    def test_checked_in_data_is_reproducible(self):
        with tempfile.TemporaryDirectory() as directory:
            generated = Path(directory) / "matrix.lua"
            subprocess.run([sys.executable, str(ROOT / "scripts/import-balancer-matrix.py"), "--output", str(generated)], check=True)
            self.assertEqual(generated.read_bytes(), (ROOT / "mpp/balancer_matrix.lua").read_bytes())


if __name__ == "__main__":
    unittest.main()
