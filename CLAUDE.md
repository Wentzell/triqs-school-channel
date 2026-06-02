# CLAUDE.md — triqs-school-channel

Guidance for Claude Code (and humans) working in this directory.

## Purpose

A **throwaway conda channel** that snapshots the **TRIQS summer-school 2026** software set:
the pre-release of **TRIQS 4.0 + applications** (never tagged upstream). Students install the
whole set with one command and later move to the official conda-forge 4.0 release.

This is **NOT a conda-forge feedstock**. Do not run `conda smithy rerender` here. The recipes were
*copied* from the conda-forge feedstocks (and the conda-forge ones left untouched) and then modified
for the school. Never sync these edits back to the canonical feedstocks.

## Conventions

- **Version label:** `4.0.0.school2026` (uniform across all packages). In conda's ordering a string
  component sorts *before* an empty one, so `4.0.0.school2026 < 4.0.0` → `conda update` will move
  students onto conda-forge `4.0.0` final once it exists (for packages that track the triqs version
  line). *Verified* with `conda.models.version.VersionOrder`:
  `VersionOrder("4.0.0.school2026") < VersionOrder("4.0.0")` is `True`. The recommended upgrade path
  is still a **fresh conda-forge env** (robust for all).
- **Matrix:** `mpich` + `openmpi` × Python `3.12`/`3.13`/`3.14`. The cbc defines the full axis
  values; the CI `build-package.yml` matrix selects which cells actually run (currently all 12).
  conda-forge has confirmed `python 3.14.5` (cp314) + `numpy 2.3.2` (cp314) host deps on both
  linux-64 and osx-arm64. Note the build-string convention: `3.12.* *_cpython` but `3.13.* *_cp313`
  and `3.14.* *_cp314` (conda-forge switched the suffix at 3.13) — using `*_cpython` for 3.13/3.14
  is wrong.
- **numpy pin:** the cbc pins `numpy: '2'` — a **bare major version**, matching conda-forge's global
  pinning. It floats across the whole 2.x series so the solver picks the right per-python build
  (2.1+ ships cp313, 2.3+ ships cp314); a *specific* pin like `2.0`/`2.1` lacks those and makes the
  py3.13/3.14 env solve **unsatisfiable** — the bug that blocked the matrix until this was fixed.
  numpy is a bare `host` dep with **no `run:` entry** (the runtime constraint comes from numpy's
  `run_exports`), and the 2.x forward-compatible C-ABI keeps the extensions runnable against
  numpy `>=1.x` and `2.x`. Don't re-pin to a minor version when adding a newer Python.
- **Toolchain:** every `conda_build_config.yaml` is **identical**. Because we build WITHOUT
  conda-smithy, conda-forge's global pinning is not injected and conda-build does **not** auto-read it
  from `$CONDA_PREFIX` — so the cbc itself defines the compiler/stdlib *base* variables that
  `{{ compiler() }}`/`{{ stdlib() }}` expand against (`c_compiler` gcc/clang, `cxx_compiler`
  gxx/clangxx, `fortran_compiler` gfortran, `c_stdlib` sysroot/macosx_deployment_target +
  `c_stdlib_version` 2.17 / 10.13 / 11.0). Without this, `{{ stdlib("c") }}` expands to the bogus
  `c_<platform>` package and every build fails the env solve. Compiler **versions** are left
  unpinned: conda solves each to the latest available, identical across every package built in one
  run, so `triqs` and the apps that link it share one toolchain/ABI (and modest's `gfortran` stays
  coupled to its `gcc`). Earlier the recipes diverged (triqs pinned gcc-13 linux-only, cthyb clang-16
  osx-only) — a latent ABI mismatch, now removed. `mpich`/`openmpi` are pinned to `4`/`5` uniformly.
- **Platforms:** linux-64, osx-arm64 (both built natively). **osx-64 (Intel Mac) is NOT
  supported** — see "CI design" for why (no Intel runner; TRIQS can't cross-compile).
- **Channel:** anaconda.org `triqs-summer-school` (public). Upload with `anaconda upload -u triqs-summer-school`.
  anaconda.org auto-indexes — no manual `conda index`.

## Package → commit provenance (the school snapshot)

| package (conda name)   | repo                | commit / pin |
|------------------------|---------------------|--------------|
| triqs                  | TRIQS/triqs         | `18fb9558a8378be412d5c8516d88d6d478a94fff` |
| triqs_cthyb            | TRIQS/cthyb         | `85466c825c684e5ee79d015fd383d16011040cdb` |
| triqs_ctseg           | TRIQS/ctseg         | `790d8d91ec0f71408d7ab945d8504706e13f43b0` |
| triqs_modest (dir `modest`) | TRIQS/modest   | `5936a266ed3a664148f6747d54f26fcc81a6c126` |
| triqs_tprf             | TRIQS/tprf          | `dd7586ed6f4be318528de728b7f48955797f225e` |
| triqs_maxent           | TRIQS/maxent        | `ed47c9b3a3e4f3c77b29864bf35b6c4ccc4e8118` |
| triqs_hubbardi (dir `triqs_hubbardI`, import `triqs_hubbardI`) | TRIQS/hubbardI | `90f6198d082fa8a578b0915b318295b8e8b68d6b` |
| triqs_hartree_fock     | TRIQS/hartree_fock  | `0a6923ed3a390094070d4d924b606df521d05c96` |
| triqs-all              | (metapackage)       | pulls in all of the above at `==4.0.0.school2026` |

**`dft_tools` was dropped** from the school set (not used). With it gone, `modest` is the only
consumer of `dmftproj`/dftkit, so the separate `triqs_dftkit` package is no longer needed — `modest`
CPM-bundles and ships dftkit itself (Fortran `dmftproj` + the `triqs_dftkit` python module). See below.

**`ctint` was dropped** from the school set. It built cleanly (the host-libm link bug was fixed via
`-DMATH_LIBRARY=m`, see git history), but its `Py_anderson` test differed from the `.ref.h5` on
`/G2_iw` by ~1e-6 — consistent with this snapshot computing the two-particle G2 via the new
`Wentzell/finufft@DLR2D` NFFT path while the reference predates that backend swap. Rather than carry
a non-blocking exception, the package was removed entirely (recipe dir, DAG job, metapackage dep,
scripts, docs). Recipe history is recoverable from git if it is ever reinstated.

## Key architectural facts (TRIQS 4.0)

- **No git submodules.** TRIQS 4.0 fetches its C++ deps at CMake **configure time** via CPM /
  `external_dependency()`. So `git_url`+`git_rev` sources work, but **builds need network**.
- **`external_dependency()` default is `Build_Deps=Always`** (refetch from source even if installed).
  All app `build.sh` set **`-DBuild_Deps=IfNotFound`** so apps reuse the `nda`/`h5`/`mpi`/`itertools`/
  `cppdlr`/`cpp2py` that **triqs builds and installs**. Consequence: the core-lib versions are fixed
  once, in the **triqs** build. `triqs` itself keeps the default (it must build+install them).
- The "pure-python" apps (`maxent`, `hubbardI`, `hartree_fock`) are actually **TRIQS-cmake apps**
  (`project(... LANGUAGES CXX)` + `find_package(TRIQS 4.0)`); PyPI only has stale 3.3.0. They are
  built from git via the cmake flow, **not** noarch/PyPI.

## dftkit / dmftproj (bundled inside modest)

At 4.0 the Fortran `dmftproj` moved out of `dft_tools` into **dftkit** (Fortran `dmftproj` + a
`triqs_dftkit` python module; **no C++ library / no exported CMake target**). Both `dft_tools` and
`modest` CPM-bundle dftkit and each install `bin/dmftproj` — which would **ClobberError** in a
combined env. We *originally* solved that by packaging `triqs_dftkit` separately and patching both
consumers to `find_package` it. **Since `dft_tools` was dropped from the school set, that whole dance
is gone:** `modest` is the only `dmftproj` consumer, so it simply builds its CPM-bundled dftkit
in-tree (no separate package, no `perl` patch, no clobber). The dftkit CMake declares
`LANGUAGES CXX Fortran` and `add_subdirectory(deps); add_subdirectory(fortran/dmftproj);
add_subdirectory(python/triqs_dftkit)` under `EXCLUDE_FROM_ALL NO`, so a normal `modest` build
compiles `dmftproj` and installs the `triqs_dftkit` python module into the `triqs_modest` package
(hence `import triqs_dftkit` works, and the metapackage/verify keep it as a smoke check).

Consequences / notes:
- `modest`'s recipe therefore **needs a Fortran compiler** (`{{ compiler('fortran') }}`) — the only
  package in the set that does. dftkit's `gfortran` is kept ABI-coupled to its `gcc` by the
  toolchain-pin policy above (no per-recipe compiler version pins).
- dftkit is bundled at modest's `GIT_TAG unstable` (floating), like modest's other CPM deps — no
  longer pinned to an explicit commit (it previously was, only because it was packaged separately).

## Reproducibility / CPM pins

Each package's own source is pinned (`git_rev` in `meta.yaml`), but the C++ deps each build fetches
via CPM float at current branch HEAD (a "4.0-pre build done today", not bit-identical to the school):
- triqs core: `nda`/`h5`/`mpi`/`itertools` @ `unstable`, `cppdlr`/`cpp2py` @ `main`
- modest: `c2py@unstable`, `TartanLlama/ranges@main`, `dftkit@unstable`
To tighten later, pin these (note `external_dependency()` clones with `git clone --branch`, which
won't take a raw SHA — push internal tags or patch the clone mechanism in `build.sh`).

## Per-package build notes

- **cthyb** 4.0 dropped nfft entirely (the old osx-arm64 nfft-from-source recipe is gone).
- App `build.sh` share a generic template (Build_Deps=IfNotFound, `$PKG_NAME`-guarded
  targets-file sed; `tprf`'s 3.x feedstock build.sh was brought in line). `modest` additionally
  needs a Fortran compiler (it builds bundled dftkit/dmftproj). **Exceptions:** `cthyb`, `ctseg`
  and `tprf` deviate from the template only in the test step — see the DLR-test policy below.
- **Known-failing DLR tests (accepted, non-blocking).** At this pre-release snapshot the DLR path
  is broken for a fixed set of tests in `cthyb`/`ctseg`/`tprf`. Their `build.sh` run everything
  else strictly (any *other* failure still blocks the build) and run just the known DLR test(s)
  separately as non-blocking, emitting a `::warning::`. The exact `ctest -E/-R` regex lives in each
  recipe's `build.sh` (`dlr_re=...`); the source-build script (`install_from_source.py`)
  mirrors them via `KNOWN_DLR_FAILURES` — keep the two in sync. This is a deliberate, documented
  exception (unlike `ctint`, which had a *silent* G2_iw discrepancy and was dropped entirely).
- **`modest` pulls c2py/googletest/ranges/dftkit via raw `CPMAddPackage`**, not
  `external_dependency()`. `-DBuild_Deps=IfNotFound` only governs the latter, so it's a **no-op for
  modest's CPM deps** — they fetch from source at configure time regardless (network needed).

## How to build / upload

Two paths, sharing one unit (`build_one.sh <pkg> [mpi] [python]`):

- **Local:** `./build_all.sh` builds every recipe (full mpi×py matrix) in dependency order on the
  current platform → local channel, no upload. A Linux box can only make `linux-64`; an Apple
  Silicon Mac makes `osx-arm64` natively.
- **CI (both platforms):** `.github/workflows/build-channel.yml` (manual `workflow_dispatch`).
  This is the recommended way to produce the full set. Needs one repo secret **`ANACONDA_TOKEN`**
  (org-scoped upload token for `triqs-summer-school`).

### CI design (robustness)
- **Per-variant split:** the reusable `build-package.yml` fans each package over
  `linux-64/osx-arm64 × mpich/openmpi × py3.12/3.13/3.14` = 12 jobs, one variant each, so every
  job stays well under GitHub's 6 h cap and a re-run rebuilds only the failed variant. Runner map:
  `ubuntu-latest`→linux-64, `macos-14`→osx-arm64, **both native**.
- **osx-64 (Intel Mac) is NOT built.** GitHub's Intel `macos-13` runners are retired/capacity-
  starved (jobs queue forever), and **cross-compiling osx-64 on the arm64 runner does not work for
  TRIQS**: its CMake runs target-arch tools at configure/build time that can't execute cross —
  libclang header introspection (`FindLibClang` → empty `LIBCLANG_CXX_FLAGS`), the MPI version
  probe (`try_run()` in cross mode), `FindPython` (CMP0190 needs `CMAKE_CROSSCOMPILING_EMULATOR`),
  and the c2py binding generator. conda-forge builds osx-arm64 *natively* for the same reason. The
  `CONDA_BUILD_CROSS_COMPILATION` blocks (and the `# [build_platform != target_platform]` cross
  deps) in the recipes are no-ops here, but are **kept verbatim from the conda-forge feedstocks on
  purpose** — these recipes are re-synced from those feedstocks for future schools, so the smaller
  the deliberate diff, the easier the re-sync. Don't strip them.
  If osx-64 is ever needed, the only viable path is a Rosetta-emulated *native* osx-64 build
  (x86_64 Miniforge on the arm64 runner, build_platform == target_platform == osx-64) — slow but
  TRIQS's build system works unchanged and tests run under emulation.
- **ccache** via `hendrikmuhs/ccache-action`, keyed per (platform, package, mpi, py). `build_one.sh`
  routes compilers through it with `CMAKE_<LANG>_COMPILER_LAUNCHER=ccache` (no recipe edits).
- **Staging-label safety:** everything uploads to `staging-<run_id>` first; downstream jobs pull
  deps from that label; the public **`main`** label is written ONLY by the final `promote` job
  (`promote.sh`), gated on `verify`. A failed/timed-out build never corrupts the live channel — just
  "Re-run failed jobs" (build uploads use `--force`, so the staging label is stable across re-runs of
  the same run). The `promote` job uses a `production` GitHub Environment — add required reviewers
  there for a manual approval gate.
- **Promotion mechanism (`promote.sh`):** per-package `anaconda move --from-label <staging>
  --to-label main`. Do NOT "simplify" this to `anaconda copy` or `anaconda label --copy`: `copy`
  defaults `--to-owner` to the token owner (it copies into a *personal* account), and even
  `--to-owner <org> --update` never adds `main` to the pre-existing org files while still printing
  "Copied file"; `label --copy` (server-side `copy_channel`) returns HTTP 500 for this channel.
  `move` uses the per-file add/remove-channel endpoints that actually work. Verify a promotion via
  the package API (`api.anaconda.org/package/<org>/<pkg>` → each file's `labels` must include
  `main`) — `conda search` repodata can lag. **Caveat:** `move` CONSUMES the staging label, so
  re-running ONLY the promote job after it already succeeded finds nothing on staging. To re-promote
  a still-staged, already-verified run without rebuilding, use the standalone **`promote-channel.yml`**
  (manual `workflow_dispatch`, `label` input).
- **Pre-flight:** a `preflight` job runs `render_check.sh`, which renders all recipes via
  conda-build's `render(..., bypass_env_check=True)` — jinja/YAML/variant validation **without a
  dependency solve**. The solve must be skipped: the apps depend on `triqs ==<school version>`,
  which doesn't exist on any channel until we build it (a plain `conda render`/`conda build` would
  fail+retry on that). The root `triqs` job needs `preflight`, so a recipe typo fails the run before
  the heavy matrix starts. Run locally: `./render_check.sh` (needs conda-build).
- **DAG:** preflight → triqs → {hartree_fock, cthyb, ctseg, tprf, maxent, hubbardI, modest} →
  triqs-all (noarch, built once) → verify → promote. **verify** installs + imports the full set
  natively on linux-64 and osx-arm64.
- **macOS:** a per-job step sets `CONDA_BUILD_SYSROOT=$(xcrun --show-sdk-path)` and
  `MACOSX_DEPLOYMENT_TARGET` (11.0 osx-arm64).

### Speed levers if jobs run long
The recipes build with `make -j${CPU_COUNT}` (full runner parallelism). The main lever for
re-runs is **ccache** (keyed per platform/package/mpi/py); beyond that, use a larger or
self-hosted runner. If a job OOMs under full parallelism, cap it (e.g. `make -j2`) in that
recipe's `build.sh`.

## Deprecation

Retire this channel once official TRIQS 4.0 conda-forge packages exist. Tell students to recreate
their env from conda-forge (see README.md).
