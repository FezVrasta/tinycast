#!/bin/bash
# Verify that main's sources + compat/macos15.patch still build for macOS 15.
#
# Never touches the working tree: exports the tracked sources to a temp dir, patches the copy,
# and builds there. Safe to run from any branch with uncommitted changes.
#
#   ./compat/verify.sh            # typecheck at 15 AND 26, then full Release build + minos assert
#   ./compat/verify.sh --quick    # typecheck only (~35s) — the repair loop's inner iteration
#   ./compat/verify.sh --ref REF  # verify against a specific git ref (default: working tree)
#
# Exit codes: 0 ok · 1 patch failed to apply · 2 availability/compile error · 3 bad artifact
set -uo pipefail

QUICK=0
REF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --quick) QUICK=1; shift ;;
    --ref) REF="${2:?--ref needs a value}"; shift 2 ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"
PATCH="compat/macos15.patch"
[ -f "$PATCH" ] || { echo "::error::$PATCH not found (are you on the compat/macos15 branch?)"; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# Prefer Xcode 26: the macOS 15 artifact is built with the NEW SDK and only the deployment
# target lowered. Building with an older toolchain instead drags in a pile of unrelated churn.
if [ -z "${DEVELOPER_DIR:-}" ]; then
  XC="$(ls -d /Applications/Xcode_26*.app /Applications/Xcode.app 2>/dev/null | sort -V | tail -n1)"
  [ -n "$XC" ] && export DEVELOPER_DIR="$XC/Contents/Developer"
fi
SDK="$(xcrun --sdk macosx --show-sdk-path)"

# Export tracked files only, so the build can never pick up a stray local artifact.
if [ -n "$REF" ]; then
  git archive "$REF" | tar -x -C "$STAGE"
else
  git archive HEAD | tar -x -C "$STAGE"
  # Carry over uncommitted edits to tracked files so WIP is verified too.
  if ! git diff --quiet HEAD; then
    git diff HEAD --binary | git -C "$STAGE" apply --allow-empty - 2>/dev/null \
      || echo "note: could not overlay uncommitted changes; verifying HEAD instead" >&2
  fi
fi

# Strict apply on purpose: the stage dir is a plain export, so there are no git objects for
# --3way to fall back on, and a moved call site SHOULD fail loudly rather than fuzz into place.
echo "==> applying $PATCH"
if ! git -C "$STAGE" apply --whitespace=nowarn "$REPO_ROOT/$PATCH" 2>&1; then
  echo "::error::$PATCH does not apply. The gated call sites in main have moved."
  echo "         Run the macos15-compat skill to regenerate it."
  exit 1
fi

SRCS=$(cd "$STAGE" && find Tinycast -name '*.swift')

fail=0
for T in 15.0 26.0; do
  echo "==> typecheck @ macos$T"
  OUT=$(cd "$STAGE" && xcrun swiftc -typecheck -swift-version 6 -strict-concurrency=complete \
    -target arm64-apple-macos"$T" -sdk "$SDK" $SRCS 2>&1)
  if [ -n "$OUT" ]; then
    # The compiler reports availability errors ONE PER RUN, so this list is not exhaustive —
    # fix the reported site and re-run until clean.
    echo "$OUT" | grep -E "error:" | sed "s|$STAGE/||" | sort -u
    echo "::error::macos$T typecheck failed (note: availability errors surface one per run)"
    fail=2
  else
    echo "    clean"
  fi
done
[ "$fail" -ne 0 ] && exit "$fail"

if [ "$QUICK" -eq 1 ]; then
  echo "==> quick mode: skipping full build"
  exit 0
fi

echo "==> Release build @ deployment target 15.0"
BUILD_LOG="$STAGE/build.log"
if ! (cd "$STAGE" && xcodebuild -project Tinycast.xcodeproj -scheme Tinycast \
        -configuration Release -derivedDataPath "$STAGE/DD" \
        MACOSX_DEPLOYMENT_TARGET=15.0 CODE_SIGNING_ALLOWED=NO build) > "$BUILD_LOG" 2>&1; then
  grep -E "error:" "$BUILD_LOG" | sed "s|$STAGE/||" | sort -u | head -20
  echo "::error::Release build failed"
  exit 2
fi

APP="$STAGE/DD/Build/Products/Release/Tinycast.app"
BIN="$APP/Contents/MacOS/Tinycast"
MINOS="$(xcrun vtool -show-build-version "$BIN" | awk '/minos/{print $2}')"
PLIST_MIN="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
echo "    minos=$MINOS  LSMinimumSystemVersion=$PLIST_MIN"
if [ "$MINOS" != "15.0" ] || [ "$PLIST_MIN" != "15.0" ]; then
  echo "::error::expected a macOS 15.0 floor, got minos=$MINOS plist=$PLIST_MIN"
  exit 3
fi

# The gates are only honored at runtime if the glass symbols are WEAK imports. A strong
# undefined symbol means dyld kills the app at launch on Sequoia — a green build that ships broken.
STRONG="$(xcrun nm -m "$BIN" 2>/dev/null | grep -i glass | grep -v weak || true)"
if [ -n "$STRONG" ]; then
  echo "$STRONG"
  echo "::error::non-weak glass symbol — would crash at launch on macOS 15"
  exit 3
fi
echo "    all glass symbols weak-imported"

echo "==> OK: main + $PATCH builds for macOS 15 and still compiles for macOS 26"
