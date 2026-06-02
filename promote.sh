#!/usr/bin/env bash
#
# Promote a fully-built, verified staging set to the public `main` label.
# Run only after the verify step passed for ALL platforms.
#
# Usage: promote.sh <staging-label>
# Env:   CHANNEL (default triqs-summer-school), VERSION (default 4.0.0.school2026),
#        ANACONDA_TOKEN (required)
#
# Relabels the existing staging artifacts to `main` (no rebuild, no re-upload):
# the live channel is updated here, only after verify.
set -euo pipefail

LABEL="${1:?staging label required (e.g. staging-123456)}"
CHANNEL="${CHANNEL:-triqs-summer-school}"
VERSION="${VERSION:-4.0.0.school2026}"
: "${ANACONDA_TOKEN:?ANACONDA_TOKEN required}"

# anaconda-client is installed in the base env, but only the `conda` shim is on
# PATH in CI — resolve the `anaconda` binary explicitly from the base prefix
# (same as build_one.sh; a bare `anaconda` call gives exit 127 there).
ANACONDA="$(conda info --base)/bin/anaconda"
[[ -x "$ANACONDA" ]] || ANACONDA="anaconda"

# conda PACKAGE names (note triqs_modest, not the recipe dir `modest`).
PKGS=(
  triqs
  triqs_hartree_fock
  triqs_cthyb
  triqs_ctseg
  triqs_tprf
  triqs_maxent
  triqs_hubbardi
  triqs_modest
  triqs-all
)

# We use `anaconda move`, NOT `anaconda copy` or `anaconda label --copy`:
#   * `anaconda copy` defaults --to-owner to the authenticated token owner, not
#     the source org (it duplicates into a personal account); forcing --to-owner
#     to the org then conflicts on the existing files, and even `--update`
#     reports "Copied file" without ever adding the to-label to the org files.
#   * `anaconda label -o <org> --copy <src> <dst>` (server-side copy_channel)
#     returns HTTP 500 for this channel.
#   * `anaconda move` uses the per-file add_channel/remove_channel endpoints,
#     scoped to the spec's owner (the org) — these work. It adds `main` then
#     removes the staging label, so each version ends carrying only `main`
#     (never label-less, so nothing is deleted). This consumes the staging
#     label, which is the correct end state for a final promotion.
#
# Token via ANACONDA_API_TOKEN (read natively by anaconda-client) rather than -t:
# the -t 'file_or_token' arg type rejects tokens that look like a path but aren't
# an existing file (same reason as build_one.sh).
for p in "${PKGS[@]}"; do
  echo "promote ${CHANNEL}/${p}/${VERSION}: ${LABEL} -> main"
  ANACONDA_API_TOKEN="$ANACONDA_TOKEN" "$ANACONDA" move \
    --from-label "$LABEL" --to-label main \
    "${CHANNEL}/${p}/${VERSION}"
done

echo "promotion complete: ${VERSION} is live on ${CHANNEL} (label main)."
