#!/usr/bin/env bash
set -euo pipefail

# release.sh — cut a release for hivesmith.
#
# Usage: ./scripts/release.sh <version>     e.g. ./scripts/release.sh 0.2.0

# ---- CONFIG --------------------------------------------------------------

PROJECT="${PROJECT:-hivesmith}"
REPO="${REPO:-lucascaro/hivesmith}"
VERSION_FILE="${VERSION_FILE:-VERSION}"
VERSION_SED="${VERSION_SED:-}"
BUILD_CMD="${BUILD_CMD:-}"

PLATFORMS=(
    "darwin/arm64"
    "darwin/amd64"
    "linux/amd64"
    "linux/arm64"
    "windows/amd64"
)

# ---- VALIDATION ----------------------------------------------------------

cd "$(git rev-parse --show-toplevel)"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 <version>"
    echo "  e.g. $0 0.2.0"
    exit 1
fi

TAG="v${VERSION}"
TODAY=$(date +%Y-%m-%d)

command -v gh >/dev/null || { echo "Error: gh (GitHub CLI) required"; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Error: working tree not clean"; exit 1; }
! git rev-parse "$TAG" &>/dev/null || { echo "Error: tag $TAG already exists"; exit 1; }
grep -q '## \[Unreleased\]' CHANGELOG.md || { echo "Error: CHANGELOG.md has no [Unreleased] section"; exit 1; }

# Pin to the start-of-release SHA. Every step below operates against this
# revision; if main advances mid-release (e.g. the regenerator bot lands a
# commit), we detect the drift before pushing and refuse to clobber it.
RELEASE_SHA="$(git rev-parse HEAD)"
echo "Pinned release base: ${RELEASE_SHA}"

# Detect the changeset-driven layout. New layout: CHANGELOG.md [Unreleased] body
# is regenerated from .changesets/*.md by scripts/regen-generated.sh. Old layout:
# CHANGELOG.md is hand-edited. We support both for one release.
USE_CHANGESETS=0
if [[ -d .changesets ]] && [[ -x scripts/regen-generated.sh ]] && [[ -n "$(find .changesets -name '*.md' ! -name 'README.md' -print -quit)" ]]; then
    USE_CHANGESETS=1
    echo "Detected .changesets/ layout — release will roll changesets into the version section."
fi

# ---- VERSION BUMP --------------------------------------------------------

if [[ -n "$VERSION_FILE" ]]; then
    echo "Bumping version to ${VERSION} in ${VERSION_FILE}..."
    if [[ -n "$VERSION_SED" ]]; then
        expr="${VERSION_SED//__VERSION__/$VERSION}"
        sed -i.bak "$expr" "$VERSION_FILE"
        rm -f "${VERSION_FILE}.bak"
    else
        echo "$VERSION" > "$VERSION_FILE"
    fi
fi

# ---- CHANGELOG STAMP -----------------------------------------------------

echo "Stamping changelog..."

PREV_TAG=$(git tag -l 'v*' --sort=-v:refname | head -1)
[[ -n "$PREV_TAG" ]] || PREV_TAG="v0.0.0"

if [[ "$USE_CHANGESETS" == "1" ]]; then
    # New layout: regenerator promotes the generated [Unreleased] body into a
    # stamped ## [VERSION] — DATE section. We then delete the per-PR changeset
    # files; the next regen produces an empty [Unreleased] until the first
    # post-release changeset lands.
    scripts/regen-generated.sh --release "$VERSION"
    find .changesets -name '*.md' ! -name 'README.md' -delete
else
    # Legacy layout — preserved for one release while downstream projects migrate.
    sed -i.bak "s/^## \[Unreleased\]/## [Unreleased]\n\n## [${VERSION}] — ${TODAY}/" CHANGELOG.md
    rm -f CHANGELOG.md.bak
fi

# Update or append compare links at bottom (layout-independent).
if grep -q "^\[Unreleased\]: " CHANGELOG.md; then
    sed -i.bak "s|\[Unreleased\]: https://github.com/${REPO}/compare/.*\.\.\.HEAD|[Unreleased]: https://github.com/${REPO}/compare/${TAG}...HEAD\n[${VERSION}]: https://github.com/${REPO}/compare/${PREV_TAG}...${TAG}|" CHANGELOG.md
    rm -f CHANGELOG.md.bak
fi

# ---- COMMIT + TAG --------------------------------------------------------

echo "Committing and tagging ${TAG}..."
git add CHANGELOG.md ${VERSION_FILE:+"$VERSION_FILE"}
if [[ "$USE_CHANGESETS" == "1" ]]; then
    # Stage the deleted changesets too. `git add -A .changesets/` picks up
    # deletions; the README/.gitkeep are unchanged so they stay.
    git add -A .changesets/
fi
git commit -m "release: ${TAG}"
git tag "$TAG"

# ---- CROSS-COMPILE -------------------------------------------------------

ARTIFACTS=()
if [[ -n "$BUILD_CMD" ]]; then
    echo "Building artifacts..."
    mkdir -p dist
    for platform in "${PLATFORMS[@]}"; do
        GOOS="${platform%/*}"
        GOARCH="${platform#*/}"
        EXT=""
        [[ "$GOOS" == "windows" ]] && EXT=".exe"
        OUTPUT="dist/${PROJECT}-${GOOS}-${GOARCH}"
        cmd="${BUILD_CMD//%GOOS%/$GOOS}"
        cmd="${cmd//%GOARCH%/$GOARCH}"
        cmd="${cmd//%OUTPUT%/$OUTPUT}"
        cmd="${cmd//%EXT%/$EXT}"
        echo "  Building ${OUTPUT}${EXT}..."
        bash -c "$cmd"
        ARTIFACTS+=("${OUTPUT}${EXT}")
    done
fi

# ---- PUSH ----------------------------------------------------------------

# Pin check: refuse to push if main advanced after we started (e.g., the
# regenerator bot landed a commit between RELEASE_SHA and now). The release
# must always be cut from the SHA we validated against.
echo "Verifying release base is still tip of main..."
git fetch origin main --quiet
CURRENT_REMOTE_SHA="$(git rev-parse origin/main)"
if [[ "$CURRENT_REMOTE_SHA" != "$RELEASE_SHA" ]]; then
    cat >&2 <<EOF
Error: origin/main has advanced since release started.
  release base SHA : ${RELEASE_SHA}
  current main SHA : ${CURRENT_REMOTE_SHA}

Rebase or rerun the release on the new tip:
  git reset --hard ${TAG}^      # undo the release commit
  git tag -d ${TAG}             # undo the tag
  git pull --ff-only            # advance to new main
  scripts/release.sh ${VERSION} # try again
EOF
    exit 1
fi

echo "Pushing to origin..."
git push origin HEAD "$TAG"

# ---- GITHUB RELEASE ------------------------------------------------------

echo "Creating GitHub release ${TAG}..."
NOTES=$(awk "/^## \[${VERSION}\]/{found=1; next} found && /^## \[/{exit} found" CHANGELOG.md)
gh release create "$TAG" --title "$TAG" --notes "$NOTES" ${ARTIFACTS[@]+"${ARTIFACTS[@]}"}

# ---- CLEANUP -------------------------------------------------------------

[[ -d dist ]] && rm -rf dist
echo ""
echo "Released ${TAG} successfully!"
echo "  https://github.com/${REPO}/releases/tag/${TAG}"
