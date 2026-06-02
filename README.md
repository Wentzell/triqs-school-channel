# TRIQS Summer School 2026 — conda channel

This channel provides a **binary snapshot of the TRIQS 4.0 pre-release + applications** used during
the school, so you can reproduce the school software set with a single command.

## Install

```bash
conda create -n triqs-summer-school -c triqs-summer-school -c conda-forge triqs-all
conda activate triqs-summer-school
```

`triqs-all` is a metapackage that pulls in the whole set:
`triqs`, `triqs_cthyb`, `triqs_ctseg`, `triqs_modest`, `triqs_tprf`,
`triqs_maxent`, `triqs_hubbardi`, `triqs_hartree_fock`.
(`triqs_modest` bundles the `dmftproj` tool and the `triqs_dftkit` python module.)

The solver picks a consistent MPI/Python combination automatically. To pin a specific
combination — we ship **mpich** + **openmpi** × **Python 3.12 / 3.13 / 3.14**:

```bash
conda create -n triqs-summer-school -c triqs-summer-school -c conda-forge triqs-all "openmpi" python=3.13
```

Supported platforms: **linux-64, osx-arm64** (Apple Silicon). Intel Macs (osx-64) are not
supported — no GitHub Intel runner, and TRIQS does not cross-compile.

## Verify

```bash
python -c "import triqs, triqs_cthyb, triqs_ctseg, triqs_dftkit, \
triqs_modest, triqs_tprf, triqs_maxent, triqs_hubbardI, triqs_hartree_fock; \
print('school stack OK')"
```

## Upgrading to the official TRIQS 4.0 release

These are **pre-release** packages (version `4.0.0.school2026`). Once TRIQS 4.0 is published on
conda-forge, switch to it with a **fresh environment** (the robust path):

```bash
conda create -n triqs -c conda-forge triqs triqs_cthyb triqs_ctseg triqs_tprf \
    triqs_maxent triqs_hubbardi triqs_hartree_fock
```

(In-place `conda update` does **not** work: `triqs-all` exact-pins the stack to
`4.0.0.school2026` and conda-forge ships no `triqs-all`. To upgrade without recreating, first
`conda remove triqs-all`, then `conda update -c conda-forge --all`. See `installation.md`.)

---

Maintainers:

- **Full set, both platforms:** run the GitHub Actions workflow `build-channel` (manual dispatch).
  It builds every package per-variant across linux-64/osx-arm64, verifies a fresh `triqs-all`
  install on each, and only then promotes to the public `main` label. Requires a repo secret
  `ANACONDA_TOKEN`.
- **Local (one platform):** `./build_all.sh` (delegates to `build_one.sh`). A Linux machine builds
  only `linux-64`; an Apple Silicon Mac builds `osx-arm64`.

See `CLAUDE.md` for provenance (exact commits), the full CI design, and known caveats.
