#!/usr/bin/env bash
# build-release-notes.sh — Emit release notes for <tag> to stdout.
#
# Usage: build-release-notes.sh <tag>
#
# Resolution order:
#   1. If ./RELEASE_NOTES.md exists at repo root, print it verbatim and exit.
#      Use this to override for releases that deserve a hand-crafted summary.
#   2. Otherwise synthesize Markdown from `git log <prev>..HEAD`, bucketing
#      commits by the "type:" prefix we already use (feat / fix / docs / ci
#      / installer / release / vendor / chore).  Unprefixed commits fall
#      into "Other".
#   3. If no previous v* tag exists, treat this as the first release and
#      list the entire history.
#
# Callers:
#   - .github/workflows/release.yml (CI release notes)
#   - scripts/release.sh            (local `gh release create` uploader)
#
# Exits non-zero only on unexpected git failures; an empty commit range
# still produces a valid (if short) notes body.

set -euo pipefail

[ $# -ge 1 ] || { echo "Usage: $0 <tag>" >&2; exit 2; }
TAG="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_SLUG="${GITHUB_REPOSITORY:-SenseTime-FVG/agent_pack}"

# Hand-written override wins.
if [ -f "$PROJECT_ROOT/RELEASE_NOTES.md" ]; then
    cat "$PROJECT_ROOT/RELEASE_NOTES.md"
    exit 0
fi

cd "$PROJECT_ROOT"

# Previous tag = newest v* tag that isn't the one we're releasing.  Empty
# string means "no prior release — walk the whole history".
prev="$(git tag --list 'v*' --sort=-v:refname | grep -v "^${TAG}$" | head -n1 || true)"

if [ -n "$prev" ]; then
    range="${prev}..HEAD"
    header="Changes since [$prev](https://github.com/${REPO_SLUG}/releases/tag/$prev)"
else
    range="HEAD"
    header="Initial release."
fi

echo "$header"
echo

# Bucket recognized prefixes into titled sections, in a stable order so
# diffs between consecutive releases look consistent.
for group in \
    "feat|Features" \
    "fix|Bug Fixes" \
    "docs|Documentation" \
    "installer|Installer" \
    "release|Release" \
    "ci|CI" \
    "vendor|Vendored Changes" \
    "chore|Chores"; do
    prefix="${group%|*}"
    title="${group#*|}"
    body="$(git log --no-merges --pretty=format:"- %s (%h)" "$range" \
            | grep -E "^- ${prefix}(\([^)]+\))?:" || true)"
    if [ -n "$body" ]; then
        echo "### $title"
        echo
        echo "$body"
        echo
    fi
done

# Anything that didn't match a known bucket.  Useful when someone commits
# without a prefix — it still shows up, just under "Other".
other="$(git log --no-merges --pretty=format:"- %s (%h)" "$range" \
         | grep -vE "^- (feat|fix|docs|installer|release|ci|vendor|chore)(\([^)]+\))?:" || true)"
if [ -n "$other" ]; then
    echo "### Other"
    echo
    echo "$other"
    echo
fi
