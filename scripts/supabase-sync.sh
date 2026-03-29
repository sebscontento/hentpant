#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  source .env
fi

PROJECT_REF="${SUPABASE_PROJECT_REF:-jfyuhjxmjbhxtfgtfkhd}"
DB_PASSWORD="${SUPABASE_DB_PASSWORD:-}"
DRY_RUN="${1:-}"

echo "Syncing Supabase migrations for project: $PROJECT_REF"
echo "Repo root: $ROOT"

if ! command -v supabase >/dev/null 2>&1; then
  echo "Supabase CLI is not installed."
  echo "Install it first: https://supabase.com/docs/guides/cli"
  exit 1
fi

if ! supabase projects list >/dev/null 2>&1; then
  echo "Supabase CLI is not logged in."
  echo "Run ./scripts/supabase-login.sh first."
  exit 1
fi

link_args=(link --project-ref "$PROJECT_REF")
push_args=(db push --linked --include-all)

if [[ -n "$DB_PASSWORD" ]]; then
  link_args+=(--password "$DB_PASSWORD")
  push_args+=(--password "$DB_PASSWORD")
fi

if [[ "$DRY_RUN" == "--dry-run" ]]; then
  push_args+=(--dry-run)
fi

echo ""
echo "Linking local Supabase config to remote project..."
supabase "${link_args[@]}"

echo ""
echo "Pushing migrations from supabase/migrations..."
supabase "${push_args[@]}"

echo ""
if [[ "$DRY_RUN" == "--dry-run" ]]; then
  echo "Dry run complete."
else
  echo "Supabase migrations are up to date."
fi
