#!/bin/bash
# Cut a macOS 15 (Sequoia) release: sync with main, verify, tag, push. One command, no manual git.
#
#   ./compat/release.sh              # full release
#   ./compat/release.sh --dry-run    # sync + verify + show the tag, publish nothing
#   ./compat/release.sh --version 0.8.0
#   ./compat/release.sh --retag      # replace an existing tag (re-runs that release)
#
# Version defaults to the newest STABLE mainline tag (v0.7.5 -> v0.7.5-sequoia), so the Sequoia
# build tracks whatever shipped on macOS 26.
#
# Exit codes: 0 ok · 1 merge conflict · 2 verify failed (patch rotted / new 26 API) · 3 preflight
set -uo pipefail

DRY=0; RETAG=0; VERSION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --retag) RETAG=1; shift ;;
    --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

cd "$(git rev-parse --show-toplevel)"
BRANCH="compat/macos15"
step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
die() { echo "::error::$1" >&2; exit "${2:-3}"; }

step "Preflight"
[ -f compat/verify.sh ] || die "compat/verify.sh missing — are you on $BRANCH?"
CUR="$(git rev-parse --abbrev-ref HEAD)"
if [ "$CUR" != "$BRANCH" ]; then
  # Refuse rather than switch: a surprise branch switch under the user is worse than stopping.
  die "on '$CUR', expected '$BRANCH'. Run: git checkout $BRANCH"
fi
if ! git diff-index --quiet HEAD -- || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  git status --short
  die "working tree not clean — commit or stash first"
fi
echo "    on $BRANCH, clean"

step "Fetching origin"
git fetch origin --tags --quiet || die "git fetch failed"

step "Merging origin/main"
BEFORE="$(git rev-parse HEAD)"
if git merge-base --is-ancestor origin/main HEAD; then
  echo "    already up to date with origin/main"
else
  if ! git merge --no-edit origin/main; then
    git merge --abort 2>/dev/null
    die "merge conflict with origin/main. Resolve it (take main's side for anything under Tinycast/) then re-run." 1
  fi
  echo "    merged $(git rev-parse --short origin/main)"
fi
# The branch must never carry its own edits to app sources — that's the whole point of the patch.
if git diff --name-only origin/main..HEAD | grep -q '^Tinycast/'; then
  git diff --name-only origin/main..HEAD | grep '^Tinycast/'
  die "$BRANCH has diverged from main under Tinycast/ — it must only add compat/ files"
fi

step "Verifying macOS 15 compatibility"
./compat/verify.sh
RC=$?
if [ "$RC" -ne 0 ]; then
  case "$RC" in
    1) echo "::error::compat/macos15.patch no longer applies — a gated call site moved." ;;
    2) echo "::error::a macOS 26-only API is unguarded (see the file:line above)." ;;
    3) echo "::error::built, but the artifact is wrong (deployment floor or non-weak glass symbol)." ;;
  esac
  echo "         Run the macos15-compat skill to repair, then re-run this script."
  exit 2
fi

step "Resolving version"
if [ -z "$VERSION" ]; then
  LATEST="$(git tag -l 'v*' | grep -Ev -- '-(alpha|beta|rc)\.' | grep -v -- '-sequoia' | sort -V | tail -1)"
  [ -n "$LATEST" ] || die "no stable mainline tag found — pass --version X.Y.Z"
  VERSION="${LATEST#v}"
  echo "    derived from newest stable mainline tag $LATEST"
fi
printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$' \
  || die "bad version '$VERSION' — expected X.Y.Z or X.Y.Z-beta.N"
TAG="v${VERSION}-sequoia"
echo "    tag: $TAG"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null \
   || git ls-remote --exit-code --tags origin "$TAG" >/dev/null 2>&1; then
  if [ "$RETAG" -eq 0 ]; then
    die "$TAG already exists. Use --retag to replace it, or --version for a new one."
  fi
  echo "    --retag: replacing existing $TAG"
fi

if [ "$DRY" -eq 1 ]; then
  step "Dry run — nothing published"
  echo "    would push $BRANCH and tag $TAG"
  [ "$BEFORE" != "$(git rev-parse HEAD)" ] && echo "    note: the local merge commit is kept (harmless; it's what you'd ship)"
  exit 0
fi

step "Pushing $BRANCH"
git push origin "$BRANCH" || die "push failed"

step "Tagging $TAG"
if [ "$RETAG" -eq 1 ]; then
  git tag -d "$TAG" 2>/dev/null
  git push origin ":refs/tags/$TAG" 2>/dev/null
fi
git tag -a "$TAG" -m "Tinycast $VERSION for macOS 15 (Sequoia)" || die "tag failed"
git push origin "$TAG" || die "tag push failed"

REPO="$(git config --get remote.origin.url | sed -E 's#.*github.com[:/]([^/]+/[^/.]+).*#\1#')"
step "Released"
cat <<EOF
    tag:      $TAG
    workflow: https://github.com/$REPO/actions/workflows/release-sequoia.yml
    watch:    gh run watch \$(gh run list --workflow=release-sequoia.yml -L1 --json databaseId -q '.[0].databaseId')
EOF
