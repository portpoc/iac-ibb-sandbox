#!/usr/bin/env bash
# Download the .claude skills from the iac-sdk repo on Bitbucket
# and sync them into this project's .claude directory.
#
# Usage:
#   ./scripts/fetch-skills.sh [DEST_DIR]
#
#   DEST_DIR defaults to the .claude directory of this repo.
#
# Requires: git with SSH access to bitbucket.dsv.com (port 7999) using
# your registered SSH key. The repo is readable by any employee with an
# account, but bitbucket.dsv.com does not allow anonymous/unauthenticated
# access, so a working SSH key (or HTTPS credentials) is still required.

set -euo pipefail

REPO_URL="${IAC_SDK_REPO_URL:-ssh://git@bitbucket.dsv.com:7999/transform/iac-sdk.git}"
BRANCH="${IAC_SDK_BRANCH:-develop}"
SOURCE_SUBDIR=".claude"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="${1:-$SCRIPT_DIR/../.claude}"
DEST_DIR="$(cd "$(dirname "$DEST_DIR")" && pwd)/$(basename "$DEST_DIR")" 2>/dev/null || DEST_DIR="$DEST_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Cloning ${REPO_URL} (branch: ${BRANCH}) with sparse checkout of '${SOURCE_SUBDIR}'..."

git -C "$TMP_DIR" init -q
git -C "$TMP_DIR" remote add origin "$REPO_URL"
git -C "$TMP_DIR" config core.sparseCheckout true
echo "$SOURCE_SUBDIR/*" > "$TMP_DIR/.git/info/sparse-checkout"
git -C "$TMP_DIR" fetch --depth 1 origin "$BRANCH"
git -C "$TMP_DIR" checkout -q "$BRANCH"

SRC="$TMP_DIR/$SOURCE_SUBDIR"
if [ ! -d "$SRC/skills" ]; then
  echo "Error: no '${SOURCE_SUBDIR}/skills' directory found in ${REPO_URL}@${BRANCH}" >&2
  exit 1
fi

mkdir -p "$DEST_DIR/skills"

echo "Syncing skills into ${DEST_DIR}/skills ..."
cp -a "$SRC/skills/." "$DEST_DIR/skills/"

echo "Done. Skills available under: $DEST_DIR/skills"
ls -1 "$DEST_DIR/skills"
