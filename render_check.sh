#!/usr/bin/env bash
#
# Fast pre-flight: render EVERY recipe (jinja + selectors + variant expansion)
# WITHOUT solving dependencies, so it catches recipe typos / bad meta in seconds
# before the heavy build matrix starts.
#
# Why no dependency solve: the app recipes depend on triqs ==<our school
# version>, which doesn't exist on any channel until WE build it. A
# normal `conda render` (or `conda build`) would try to solve those and fail
# (and slowly retry). conda-build's render API with bypass_env_check=True
# renders jinja/YAML/variants but skips the environment solve — exactly the
# typo-catching gate we want pre-build.
#
# Usage: render_check.sh
# Requires: conda-build (provides the conda_build python module).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

python - "$HERE" <<'PY'
import sys, glob, os
from conda_build.api import render

here = sys.argv[1]
fail = 0
for recipe in sorted(glob.glob(os.path.join(here, "recipes", "*", "recipe"))):
    pkg = os.path.basename(os.path.dirname(recipe))
    try:
        metas = render(
            recipe,
            finalize=False,                     # don't pin/solve the env
            bypass_env_check=True,              # skip the dependency solve
            permit_unsatisfiable_variants=True,
        )
        print(f"==> {pkg:20s} ... ok ({len(metas)} variant(s))")
    except Exception as e:
        print(f"==> {pkg:20s} ... FAILED")
        print("    " + str(e).replace("\n", "\n    "))
        fail = 1

print("pre-flight: " + ("one or more recipes failed to render."
                         if fail else "all recipes render cleanly."))
sys.exit(fail)
PY
