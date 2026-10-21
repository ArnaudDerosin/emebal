#!/usr/bin/env bash
# Publishes a new version of Emebal:
#
#   ./scripts/release.sh 0.2.0
#
# 1. Checks: on an up-to-date main with no uncommitted changes, tests pass,
#    and CHANGELOG.md has notes under "## [Unreleased]".
# 2. Sets the version in Info.plist and turns the Unreleased notes into a
#    dated section for this version.
# 3. Builds the app and zips it.
# 4. After you confirm: commits, tags vX.Y.Z, pushes, and creates the GitHub
#    Release with the changelog notes and the zip attached.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 <version>   (for example: $0 0.2.0)" >&2
  exit 1
fi
TAG="v$VERSION"
REPO="ArnaudDerosin/emebal"

fail() { echo "error: $*" >&2; exit 1; }

# --- Checks -----------------------------------------------------------------

command -v gh >/dev/null || fail "the GitHub CLI (gh) is needed: brew install gh"
gh auth status >/dev/null 2>&1 || fail "run 'gh auth login' first"
[ "$(git branch --show-current)" = main ] || fail "releases are made from main"
[ -z "$(git status --porcelain)" ] || fail "commit or stash your changes first"
git fetch --quiet origin main --tags
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "main isn't in sync with origin/main"
! git rev-parse "$TAG" >/dev/null 2>&1 || fail "$TAG already exists"

CURRENT=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)
if git rev-parse "v$CURRENT" >/dev/null 2>&1; then
  # The current version was released: the new one must be higher.
  [ "$(printf '%s\n' "$CURRENT" "$VERSION" | sort -V | tail -1)" = "$VERSION" ] && [ "$CURRENT" != "$VERSION" ] \
    || fail "$VERSION must be higher than the released $CURRENT"
  BUILD=$((BUILD + 1))
fi

echo "Running tests…"
swift test >/dev/null || fail "tests fail: run 'swift test' to see why"

# --- Version and changelog --------------------------------------------------

NOTES=$(mktemp)
trap 'rm -f "$NOTES"' EXIT

python3 - "$VERSION" "$(date +%Y-%m-%d)" "$REPO" "$NOTES" <<'PYTHON'
import re
import sys

version, date, repo, notes_path = sys.argv[1:]
text = open("CHANGELOG.md").read()

match = re.search(r"^## \[Unreleased\]\n(.*?)(?=^## \[|^\[Unreleased\]:|\Z)", text, re.S | re.M)
notes = match.group(1).strip() if match else ""
if not notes:
    sys.exit("error: add release notes under '## [Unreleased]' in CHANGELOG.md first")

# The Unreleased notes become this version's section, and Unreleased starts empty.
text = text[:match.start()] + f"## [Unreleased]\n\n## [{version}] - {date}\n\n{notes}\n\n" + text[match.end():]

# Links at the bottom: Unreleased compares with this version, which links to its release.
text = re.sub(r"^\[Unreleased\]:.*\n?", "", text, flags=re.M).rstrip() + "\n"
links = re.findall(r"^\[[0-9.]+\]:.*$", text, flags=re.M)
text = re.sub(r"^\[[0-9.]+\]:.*\n?", "", text, flags=re.M).rstrip() + "\n\n"
text += f"[Unreleased]: https://github.com/{repo}/compare/v{version}...HEAD\n"
text += f"[{version}]: https://github.com/{repo}/releases/tag/v{version}\n"
text += "".join(link + "\n" for link in links)
open("CHANGELOG.md", "w").write(text)

open(notes_path, "w").write(notes + f"""

### Install

Download **Emebal-{version}.zip** below, unzip it, and move **Emebal** to
Applications. Emebal isn't notarized by Apple yet, so the first time macOS
won't open it: go to **System Settings → Privacy & Security** and click
**Open Anyway**. Then allow Emebal in **Accessibility** for the ⌘C ⌘C shortcut.

Updating from an earlier version? Quit Emebal, replace it in Applications, then
in **Accessibility** remove Emebal with **−** and allow it again.

You can also build it from source: see the
[README](https://github.com/{repo}#install).
""")
PYTHON

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" Resources/Info.plist

# --- Build ------------------------------------------------------------------

./scripts/build-app.sh >/dev/null
ZIP="build/Emebal-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/Emebal.app "$ZIP"

# --- Publish ----------------------------------------------------------------

echo
echo "Emebal $VERSION (build $BUILD), $(du -h "$ZIP" | cut -f1) zip. Release notes:"
echo "------------------------------------------------------------------------"
cat "$NOTES"
echo "------------------------------------------------------------------------"
read -r -p "Commit, tag $TAG, push and publish the release? [y/N] " answer
if [ "$answer" != y ] && [ "$answer" != Y ]; then
  git checkout -- CHANGELOG.md Resources/Info.plist
  echo "Cancelled: nothing was committed or published."
  exit 1
fi

git commit --quiet -m "chore: release $TAG" -- CHANGELOG.md Resources/Info.plist
git tag -a "$TAG" -m "Emebal $VERSION"
git push --quiet origin main "$TAG"
gh release create "$TAG" "$ZIP" --repo "$REPO" --title "Emebal $VERSION" --notes-file "$NOTES"
