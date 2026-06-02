#!/usr/bin/env bash
#
# Build the whole TRIQS summer-school 2026 channel LOCALLY, in dependency order,
# on the current platform. Delegates each package to build_one.sh (the same unit
# CI uses), so local and CI builds stay in sync.
#
# Run ON THE NATIVE TARGET PLATFORM:
#   - osx-arm64 : natively on an Apple-Silicon Mac
#   - linux-64  : on a Linux box or Docker (conda-forge linux-anvil)
# A Linux machine can ONLY produce linux-64; osx-arm64 needs an Apple-Silicon Mac.
# osx-64 (Intel Mac) is NOT supported (no Intel runner; TRIQS can't cross-compile).
# For both platforms at once, prefer CI: .github/workflows/build-channel.yml
#
# By default this builds the FULL mpi x python matrix per package (no upload).
# To also upload to a staging label, set STAGING_LABEL + ANACONDA_TOKEN (see
# build_one.sh). Requires: conda-build (+ anaconda-client to upload). Builds need
# NETWORK at configure time (TRIQS 4.0 fetches deps via CPM).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

# Dependency order: triqs first; modest bundles its own dftkit/dmftproj
# (Fortran); metapackage last.
PKGS=(
  triqs
  triqs_hartree_fock
  triqs_cthyb
  triqs_ctseg
  triqs_tprf
  triqs_maxent
  triqs_hubbardI
  modest
  triqs-all
)

for pkg in "${PKGS[@]}"; do
  "$HERE/build_one.sh" "$pkg"
done

echo
echo "All packages built locally for $(conda info --json | python -c 'import sys,json;print(json.load(sys.stdin)["platform"])' 2>/dev/null || echo this platform)."
echo "To publish: set ANACONDA_TOKEN + STAGING_LABEL and re-run, or use the CI workflow."
