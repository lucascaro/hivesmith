#!/usr/bin/env bash
set -euo pipefail

# release.sh — cut a release for this project.
#
# Usage: ./scripts/release.sh <version>     e.g. ./scripts/release.sh 0.2.0
#
# What it does:
#   1. Validates inputs and working tree
#   2. Bumps the version in VERSION_FILE
#   3. Stamps CHANGELOG.md with the release date
#   4. Commits and tags
#   5. (Optional) cross-compiles artifacts via BUILD_CMD
#   6. Creates a GitHub release with artifacts attached
#   7. Pushes the commit and tag
#
# Configuration — edit the variables below for your project.

# ---- CONFIG --------------------------------------------------------------

# Project/binary name used in artifact filenames and the release message.
PROJECT="${PROJECT:-myproject}"

# GitHub owner/repo, used in CHANGELOG compare links.
REPO="${REPO:-owner/${PROJECT}}"

# File containing the version string. Leave empty to skip the version bump.
# Examples: "VERSION", "package.json", "Cargo.toml", "cmd/version.go"
VERSION_FILE="${VERSION_FILE:-VERSION}"

# A sed expression that replaces the version in VERSION_FILE. `__VERSION__`
# is substituted with the new version before running. Leave empty to write
# the version verbatim to VERSION_FILE.
# Examples:
#   Go constant:     's/const Version = ".*"/const Version = "__VERSION__"/'
#   package.json:    's/"version": ".*"/"version": "__VERSION__"/'
#   Cargo.toml:      's/^version = ".*"/version = "__VERSION__"/'
VERSION_SED="${VERSION_SED:-}"

# If set, runs build once per PLATFORMS entry to produce artifacts.
# Leave empty to skip cross-compilation (source releases only).
#   %GOOS%, %GOARCH%, %OUTPUT%, %EXT% are substituted.
# Example (Go):
#   BUILD_CMD='GOOS=%GOOS% GOARCH=%GOARCH% go build -ldflags=-s\ -w -o %OUTPUT%%EXT% .'
BUILD_CMD="${BUILD_CMD:-}"

# Platforms to build for when BUILD_CMD is set (OS/ARCH pairs).
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
# CHANGELOG.md is hand-edited.
USE_CHANGESETS=0
if [[ -d .changesets ]] && [[ -x scripts/regen-generated.sh ]] && [[ -n "$(find .changesets -name '*.md' ! -name 'README.md' -print -quit 2>/dev/null)" ]]; then
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
    scripts/regen-generated.sh --release "$VERSION"
    find .changesets -name '*.md' ! -name 'README.md' -delete
else
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

# Pin check: refuse to push if main advanced after we started.
echo "Verifying release base is still tip of main..."
git fetch origin main --quiet
CURRENT_REMOTE_SHA="$(git rev-parse origin/main)"
if [[ "$CURRENT_REMOTE_SHA" != "$RELEASE_SHA" ]]; then
    echo "Error: origin/main has advanced since release started." >&2
    echo "  release base : ${RELEASE_SHA}" >&2
    echo "  current main : ${CURRENT_REMOTE_SHA}" >&2
    echo "Rebase and retry: git reset --hard ${TAG}^ && git tag -d ${TAG} && git pull --ff-only && $0 ${VERSION}" >&2
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
