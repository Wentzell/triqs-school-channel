#!/usr/bin/env bash
#
# Build (and optionally upload) ONE package of the school channel — the shared
# unit used by both local builds (build_all.sh) and CI (build-package.yml).
#
# Usage:
#   build_one.sh <pkg-dir> [mpi] [python]
#     <pkg-dir>  recipe dir under recipes/ (e.g. triqs, triqs_cthyb, modest, triqs-all)
#     [mpi]      optional: mpich | openmpi  -> pin this single MPI variant
#     [python]   optional: 3.12 | 3.13 | 3.14 -> pin this single Python variant
#   With no mpi/python the recipe's full conda_build_config matrix is built
#   (used for local builds); CI passes a single (mpi, python) per job.
#
# Environment:
#   CHANNEL         conda owner/channel (default: triqs-summer-school)
#   STAGING_LABEL   if set, build deps are pulled from this label first and the
#                   built artifacts are uploaded to it (needs ANACONDA_TOKEN).
#   ANACONDA_TOKEN  anaconda.org token; enables upload when STAGING_LABEL is set.
#   CCACHE          "1" -> route the C/C++/Fortran compilers through ccache.
#
# Network is required at configure time (TRIQS 4.0 fetches deps via CPM).
set -euo pipefail

PKG="${1:?package dir required (e.g. triqs)}"
MPI="${2:-}"
PY="${3:-}"
CHANNEL="${CHANNEL:-triqs-summer-school}"

HERE="$(cd "$(dirname "$0")" && pwd)"
RECIPE="$HERE/recipes/$PKG/recipe"
[[ -d "$RECIPE" ]] || { echo "ERROR: no recipe at $RECIPE" >&2; exit 1; }

# ---- ccache wiring -----------------------------------------------------------
# CMake initialises CMAKE_<LANG>_COMPILER_LAUNCHER from the env var of the same
# name, but conda-build runs build.sh in a SANITIZED environment and strips
# these, so they must be whitelisted via `build: script_env:` in each recipe
# (done) for them to reach the actual compile. Two more details:
#   * Resolve ccache to an ABSOLUTE path here: it is on PATH in this driver
#     shell (ccache-action) but not necessarily inside conda-build's sandbox;
#     the absolute path is valid there since the filesystem is shared.
#   * CCACHE_DIR must point at ccache-action's persisted dir so the cache
#     survives across runs.
if [[ "${CCACHE:-0}" == "1" ]]; then
  CCACHE_BIN="$(command -v ccache || true)"
  if [[ -n "$CCACHE_BIN" ]]; then
    export CMAKE_C_COMPILER_LAUNCHER="$CCACHE_BIN"
    export CMAKE_CXX_COMPILER_LAUNCHER="$CCACHE_BIN"
    export CMAKE_Fortran_COMPILER_LAUNCHER="$CCACHE_BIN"
    export CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache}"   # respect ccache-action's dir
    export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-2G}"
  else
    echo "WARNING: CCACHE=1 but no ccache binary found on PATH; building without it." >&2
  fi
fi

# ---- single-variant pinning --------------------------------------------------
# The recipe's conda_build_config.yaml lists the FULL axis (python 3.12/3.13/3.14,
# mpi mpich/openmpi). To build a single cell we must OVERRIDE those axes, not add
# to them — otherwise conda-build enumerates the entire cross product per job
# (every python x every mpi), defeating the per-variant split.
#   * python: the dedicated --python flag reliably overrides the cbc python list.
#   * mpi:    no dedicated flag, so override via --variants with a LIST value.
declare -a EXTRA=()
[[ -n "$PY"  ]] && EXTRA+=(--python "$PY")
[[ -n "$MPI" ]] && EXTRA+=(--variants "{mpi: [${MPI}]}")

# ---- channels ----------------------------------------------------------------
# When staging, pull just-built deps from the staging label first; otherwise use
# conda-build's local output channel so earlier packages on this host are found.
if [[ -n "${STAGING_LABEL:-}" ]]; then
  CH=(-c "${CHANNEL}/label/${STAGING_LABEL}" -c "${CHANNEL}" -c conda-forge)
else
  CH=(-c local -c "${CHANNEL}" -c conda-forge)
fi

echo "==================================================================="
echo " building ${PKG}  ${MPI:+mpi=${MPI}}  ${PY:+py=${PY}}  ccache=${CCACHE:-0}"
echo " channels: ${CH[*]}"
echo "==================================================================="

# Reference timestamp: artifacts written by the build below are newer than this.
# (Locating artifacts this way is robust; re-running `conda build --output` to
# predict the path can render a different hash than the one actually built.)
STAMP="$(mktemp)"

conda build "$RECIPE" "${CH[@]}" "${EXTRA[@]}" --no-anaconda-upload

if [[ "${CCACHE:-0}" == "1" ]]; then ccache --show-stats || true; fi

# ---- upload to staging label (idempotent on re-run via --force) --------------
if [[ -n "${STAGING_LABEL:-}" && -n "${ANACONDA_TOKEN:-}" ]]; then
  # anaconda-client is installed in the base env, but only the `conda` shim is on
  # PATH in CI — resolve the `anaconda` binary explicitly from the base prefix.
  ANACONDA="$(conda info --base)/bin/anaconda"
  [[ -x "$ANACONDA" ]] || ANACONDA="anaconda"
  BLD="${CONDA_BLD_PATH:-$(conda info --base)/conda-bld}"
  # Collect built artifacts without `mapfile` (a bash-4 builtin absent from macOS's
  # stock bash 3.2, where the macos runner's `#!/usr/bin/env bash` lands).
  OUTPUTS=()
  while IFS= read -r f; do OUTPUTS+=("$f"); done \
    < <(find "$BLD" -type f \( -name '*.conda' -o -name '*.tar.bz2' \) -newer "$STAMP")
  if [[ ${#OUTPUTS[@]} -eq 0 ]]; then
    echo "ERROR: build produced no artifacts under $BLD (nothing newer than build start)" >&2
    exit 1
  fi
  for f in "${OUTPUTS[@]}"; do
    echo "uploading $(basename "$f") -> ${CHANNEL}/label/${STAGING_LABEL}"
    # Pass the token via ANACONDA_API_TOKEN (read natively by anaconda-client)
    # rather than -t: the -t 'file_or_token' arg type rejects tokens that look
    # like a path (contain '.'/'/') but aren't an existing file.
    ANACONDA_API_TOKEN="$ANACONDA_TOKEN" \
      "$ANACONDA" upload -u "$CHANNEL" --label "$STAGING_LABEL" --force "$f"
  done
elif [[ -n "${STAGING_LABEL:-}" ]]; then
  echo "STAGING_LABEL set but ANACONDA_TOKEN missing -> built only, not uploaded." >&2
fi
