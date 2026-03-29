#!/usr/bin/env bash
# Browser-based Supabase CLI login — same idea as: gh auth login
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
echo "Supabase CLI will open your browser to sign in."
echo "(Like GitHub: gh auth login → web device flow.)"
echo "Repo root: $ROOT"
echo ""
exec supabase login
