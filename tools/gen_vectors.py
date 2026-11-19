"""Regenerate test/fixtures/core_vectors.json from the Python core.

    PYTHONPATH=<path to trainhorn-calc>/src python3 tools/gen_vectors.py

The Ruby unit test compares the plugin's math with these values, so the
macro and trainhorn_calc.acoustics.spl_at_distance stay in sync.
"""
import json
import pathlib

from trainhorn_calc.acoustics import spl_at_distance

CASES = [
    (150, 10, "ft", [25, 50, 100, 250, 500, 1000]),
    (120, 1, "m", [25, 50, 100, 250, 500, 1000]),
    (118, 10, "ft", [10, 5, 2.5, 33.3]),
    (96.5, 3, "m", [0.5, 7, 1234.5]),
    (0, 1, "ft", [100]),
    (250, 0.25, "m", [1e-3, 1e6]),
]

out = []
for source, ref, unit, ds in CASES:
    out.append({
        "source": source, "ref": ref, "unit": unit,
        "levels": [[d, spl_at_distance(source, d, ref_distance=ref, unit=unit)] for d in ds],
    })
path = pathlib.Path(__file__).resolve().parents[1] / "test" / "fixtures" / "core_vectors.json"
path.write_text(json.dumps(out, indent=1) + "\n")
print(f"wrote {sum(len(c['levels']) for c in out)} vectors to {path}")
