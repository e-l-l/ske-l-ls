#!/usr/bin/env bash
set -euo pipefail

# Push the current branch (if needed) and open a pull request.
#
# Usage:
#   create-pr.sh --title "<title>" --base <base> [--draft] [--head <branch>] < body.md
#
# The PR body is read from stdin so multi-line markdown survives without
# heredoc/quoting trouble. On success, prints the PR URL to stdout.

TITLE=""
BASE=""
HEAD=""
DRAFT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --title) TITLE="$2"; shift 2 ;;
    --base)  BASE="$2";  shift 2 ;;
    --head)  HEAD="$2";  shift 2 ;;
    --draft) DRAFT="--draft"; shift ;;
    *) echo "ERROR: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$TITLE" ] || [ -z "$BASE" ]; then
  echo "ERROR: --title and --base are required." >&2
  exit 2
fi

if ! command -v gh &>/dev/null; then
  echo "ERROR: gh CLI is not installed." >&2
  exit 1
fi

if [ -z "$HEAD" ]; then
  HEAD=$(git rev-parse --abbrev-ref HEAD)
  if [ "$HEAD" = "HEAD" ]; then
    echo "ERROR: Detached HEAD. Pass --head <branch> or check out a branch." >&2
    exit 1
  fi
fi

if [ "$HEAD" = "$BASE" ]; then
  echo "ERROR: head and base are both '$HEAD'. Switch to a feature branch." >&2
  exit 1
fi

# Read body from stdin.
BODY=$(cat)
if [ -z "$BODY" ]; then
  echo "ERROR: empty PR body on stdin." >&2
  exit 2
fi

# Refuse to duplicate an open PR.
EXISTING=$(gh pr list --head "$HEAD" --state open --json number,url --limit 1 2>/dev/null | jq -r '.[0].url // empty')
if [ -n "$EXISTING" ]; then
  echo "ERROR: an open PR already exists for $HEAD: $EXISTING" >&2
  exit 1
fi

# Push the branch with exponential-backoff retry on network failure.
push_with_retry() {
  local args=("$@")
  local attempt=1
  local delay=2
  while [ $attempt -le 5 ]; do
    if git push "${args[@]}"; then
      return 0
    fi
    local exit_code=$?
    # Don't retry on non-network failures (rejected, hook failure, auth).
    # `git push` exits 128 for most fatal errors; we treat anything other than
    # exit 1 as fatal. (1 is the typical exit for transient connection issues.)
    if [ $exit_code -ne 1 ] || [ $attempt -eq 5 ]; then
      return $exit_code
    fi
    echo "push failed; retrying in ${delay}s..." >&2
    sleep "$delay"
    delay=$((delay * 2))
    attempt=$((attempt + 1))
  done
}

if git ls-remote --exit-code --heads origin "$HEAD" &>/dev/null; then
  git fetch --quiet origin "$HEAD" 2>/dev/null || true
  LOCAL_SHA=$(git rev-parse HEAD)
  REMOTE_SHA=$(git rev-parse "origin/$HEAD" 2>/dev/null || echo "")
  if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
    # Fast-forward only — refuse to silently overwrite remote history.
    echo "Pushing $HEAD to origin..." >&2
    push_with_retry origin "$HEAD" || {
      echo "ERROR: push to origin/$HEAD failed. If the remote has diverged, resolve it manually before opening the PR." >&2
      exit 1
    }
  fi
else
  echo "Pushing $HEAD to origin (new branch)..." >&2
  push_with_retry -u origin "$HEAD" || {
    echo "ERROR: push to origin/$HEAD failed." >&2
    exit 1
  }
fi

# Create the PR. Pipe body via a temp file so newlines survive.
BODY_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE"' EXIT
printf '%s' "$BODY" > "$BODY_FILE"

# shellcheck disable=SC2086
PR_URL=$(gh pr create \
  --base "$BASE" \
  --head "$HEAD" \
  --title "$TITLE" \
  --body-file "$BODY_FILE" \
  $DRAFT)

echo "$PR_URL"
