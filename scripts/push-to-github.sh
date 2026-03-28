#!/usr/bin/env bash
# Create the GitHub repository (if needed) and push main.
# Prerequisites: brew install gh && gh auth login
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

GH_BIN="/opt/homebrew/bin/gh"
if [[ ! -x "$GH_BIN" ]]; then
  GH_BIN="$(command -v gh || true)"
fi
if [[ -z "$GH_BIN" || ! -x "$GH_BIN" ]]; then
  echo "Install GitHub CLI: brew install gh"
  exit 1
fi

if ! "$GH_BIN" auth status &>/dev/null; then
  echo "Not logged in to GitHub. Run this once in your terminal:"
  echo "  $GH_BIN auth login"
  exit 1
fi

# Drop a stale remote so gh can attach origin (e.g. after deleting the remote repo).
if git remote get-url origin &>/dev/null; then
  echo "Removing existing origin remote…"
  git remote remove origin
fi

REPO_NAME="hentpant"
DESC="PantCollect — iOS app connecting pant (deposit bottle) givers with collectors in Denmark. SwiftUI, MapKit, Sign in with Apple. MVP uses an in-memory store; structured for Firebase."

echo "Creating ${REPO_NAME} on GitHub and pushing main…"
"$GH_BIN" repo create "$REPO_NAME" \
  --public \
  --description "$DESC" \
  --source=. \
  --remote=origin \
  --push

echo "Done. Remote:"
git remote -v
