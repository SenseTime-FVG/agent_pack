#!/usr/bin/env bash
# release.sh — Publish a GitHub Release from locally-built artifacts.
#
# Usage:
#   scripts/release.sh <tag> [--draft] [--prerelease] [--notes-file <path>]
#
# Examples:
#   scripts/release.sh v1.0.0
#   scripts/release.sh v1.1.0-rc1 --prerelease
#   scripts/release.sh v1.0.0 --notes-file RELEASE_NOTES.md
#
# What it does:
#   1. Verifies dist/AgentPack-Setup-<ver>.exe exists (mandatory).
#   2. Includes dist/AgentPack-<ver>.pkg if present (skipped with a warning
#      otherwise — you can re-run with --include-pkg-only after you build
#      the .pkg on a Mac, and `gh release upload` will add it then).
#   3. Generates dist/SHA256SUMS over whatever files are being uploaded.
#   4. Creates the git tag locally if missing, pushes it, then calls
#      `gh release create` with all artifacts attached.
#
# Prefer the GitHub Actions workflow (.github/workflows/release.yml) when
# possible: push a tag, CI builds both platforms in clean environments, and
# attaches .exe + .pkg automatically.  Use this script only when you need
# to publish a one-off release from your own machine.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"

die() { echo "[!] $*" >&2; exit 1; }
note() { echo "[*] $*"; }
ok() { echo "[OK] $*"; }

[ $# -ge 1 ] || die "Usage: $(basename "$0") <tag> [--draft] [--prerelease] [--notes-file <path>]"
TAG="$1"; shift

# Passthrough flags for `gh release create` — we don't interpret them.
GH_FLAGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --draft|--prerelease|--latest|--generate-notes)
            GH_FLAGS+=("$1"); shift ;;
        --notes-file|--notes|--title|--target)
            GH_FLAGS+=("$1" "$2"); shift 2 ;;
        *)
            die "Unknown flag: $1" ;;
    esac
done

# Guard rails.
command -v gh >/dev/null 2>&1 || die "gh CLI not found. Install from https://cli.github.com/"
command -v git >/dev/null 2>&1 || die "git not found."
command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 \
    || die "sha256sum / shasum not found."

# Extract the version from the tag (strip leading v).  We use it to locate
# files by exact name, so a tag like v1.0.0 must match AgentPack-Setup-1.0.0.exe.
VER="${TAG#v}"
EXE="$DIST_DIR/AgentPack-Setup-${VER}.exe"
PKG="$DIST_DIR/AgentPack-${VER}.pkg"

# Collect whatever's actually built.  The .exe is required — releasing
# without the Windows installer would mean the README links 404 on Windows.
FILES=()
[ -f "$EXE" ] || die "Missing $EXE. Build it first (see README.md → Building from Source → Windows)."
FILES+=("$EXE")
ok "Found $(basename "$EXE")"

if [ -f "$PKG" ]; then
    FILES+=("$PKG")
    ok "Found $(basename "$PKG")"
else
    echo "[!] Missing $PKG — publishing without the macOS installer." >&2
    echo "    Build it on a Mac with: cd macos && ./build-pkg.sh" >&2
    echo "    Then: gh release upload $TAG '$PKG' --clobber" >&2
fi

# Generate checksums for everything we're about to upload.
CHECKSUMS="$DIST_DIR/SHA256SUMS"
note "Writing $CHECKSUMS"
(
    cd "$DIST_DIR"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${FILES[@]##*/}" > SHA256SUMS
    else
        # macOS native shasum — output format matches sha256sum.
        shasum -a 256 "${FILES[@]##*/}" > SHA256SUMS
    fi
)
FILES+=("$CHECKSUMS")

# Tag handling: if the tag doesn't exist locally, create it on HEAD; then
# make sure origin has it (release creation needs the tag to be visible to
# GitHub, not just local).
if git rev-parse "$TAG" >/dev/null 2>&1; then
    ok "Local tag $TAG already exists"
else
    note "Creating local tag $TAG on HEAD ($(git rev-parse --short HEAD))"
    git tag "$TAG"
fi

if git ls-remote --tags origin "$TAG" | grep -q "$TAG"; then
    ok "Remote tag $TAG already pushed"
else
    note "Pushing tag $TAG to origin"
    git push origin "$TAG"
fi

# Default release notes come from the git log since the previous tag; if
# the caller wants custom notes they pass --notes-file themselves.
HAS_NOTES=0
for f in "${GH_FLAGS[@]}"; do
    case "$f" in
        --notes|--notes-file|--generate-notes) HAS_NOTES=1 ;;
    esac
done
if [ "$HAS_NOTES" -eq 0 ]; then
    GH_FLAGS+=(--generate-notes)
fi

note "Creating release $TAG with ${#FILES[@]} asset(s)"
gh release create "$TAG" \
    --title "Agent Pack $TAG" \
    "${GH_FLAGS[@]}" \
    "${FILES[@]}"

ok "Release published: $(gh release view "$TAG" --json url -q .url)"
