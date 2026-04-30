#!/usr/bin/env bash
set -euo pipefail

# Gather context for opening a pull request on the current branch.
# Outputs a single JSON document with everything Claude needs to draft a PR:
# {
#   "repo": "owner/name",
#   "current_branch": "feat-x",
#   "base_branch": "main",
#   "remote_branch_exists": true|false,
#   "branch_up_to_date_with_remote": true|false|null,
#   "uncommitted_changes": "<git status --short>",
#   "existing_pr": null | { "number": 42, "url": "...", "state": "OPEN" },
#   "commits": [ { "sha": "...", "subject": "...", "body": "..." } ],
#   "files_changed": [ { "path": "...", "additions": N, "deletions": N } ],
#   "diff_stat": "<git diff --stat output>",
#   "diff": "<truncated unified diff>",
#   "diff_truncated": true|false,
#   "recent_pr_examples": [ { "title": "...", "body": "..." } ]
# }

if ! command -v gh &>/dev/null; then
  echo "ERROR: gh CLI is not installed. Install it from https://cli.github.com" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is not installed. Install it with: brew install jq" >&2
  exit 1
fi

if ! git rev-parse --git-dir &>/dev/null; then
  echo "ERROR: Not inside a git repository." >&2
  exit 1
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" = "HEAD" ]; then
  echo "ERROR: Detached HEAD. Check out a branch before creating a PR." >&2
  exit 1
fi

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) || {
  echo "ERROR: Could not determine repository. Is this a git repo with a GitHub remote?" >&2
  exit 1
}

# Default base branch (the repo's default — usually main or master).
BASE_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo "main")

if [ "$CURRENT_BRANCH" = "$BASE_BRANCH" ]; then
  echo "ERROR: You're on the default branch ($BASE_BRANCH). Switch to a feature branch first." >&2
  exit 1
fi

# Make sure we have an up-to-date view of the base branch for diffing.
git fetch --quiet origin "$BASE_BRANCH" 2>/dev/null || true

# Merge base — find the divergence point. Prefer origin/<base>; fall back to local <base>.
if git rev-parse --verify --quiet "origin/$BASE_BRANCH" >/dev/null; then
  BASE_REF="origin/$BASE_BRANCH"
elif git rev-parse --verify --quiet "$BASE_BRANCH" >/dev/null; then
  BASE_REF="$BASE_BRANCH"
else
  echo "ERROR: Could not find base branch $BASE_BRANCH locally or on origin." >&2
  exit 1
fi

MERGE_BASE=$(git merge-base "$BASE_REF" HEAD 2>/dev/null) || {
  echo "ERROR: Could not find a merge base between $BASE_REF and HEAD." >&2
  exit 1
}

# Remote branch state.
REMOTE_BRANCH_EXISTS=false
BRANCH_UP_TO_DATE=null
if git ls-remote --exit-code --heads origin "$CURRENT_BRANCH" &>/dev/null; then
  REMOTE_BRANCH_EXISTS=true
  git fetch --quiet origin "$CURRENT_BRANCH" 2>/dev/null || true
  LOCAL_SHA=$(git rev-parse HEAD)
  REMOTE_SHA=$(git rev-parse "origin/$CURRENT_BRANCH" 2>/dev/null || echo "")
  if [ "$LOCAL_SHA" = "$REMOTE_SHA" ]; then
    BRANCH_UP_TO_DATE=true
  else
    BRANCH_UP_TO_DATE=false
  fi
fi

UNCOMMITTED=$(git status --short)

# Existing PR for this branch, if any.
EXISTING_PR=$(gh pr list --head "$CURRENT_BRANCH" --state all --json number,url,state,title --limit 1 2>/dev/null | jq '.[0] // null')

# Commits on this branch since divergence (oldest first).
# Use 0x1f (US) as field separator and 0x1e (RS) as record separator so commit
# bodies — which can contain newlines — survive intact through the pipeline.
COMMITS_JSON=$(git log --reverse --pretty=format:'%H%x1f%s%x1f%b%x1e' "$MERGE_BASE..HEAD" \
  | jq -R -s '
      split("")
      | map(select(length > 0))
      | map(
          split("")
          | {
              sha: .[0],
              subject: (.[1] // ""),
              body: ((.[2] // "") | sub("^\\s+"; "") | sub("\\s+$"; ""))
            }
        )
    ')

# Files changed.
FILES_JSON=$(git diff --numstat "$MERGE_BASE..HEAD" | jq -R -s '
  split("\n") | map(select(length > 0)) | map(
    split("\t") | {
      additions: (.[0] | tonumber? // 0),
      deletions: (.[1] | tonumber? // 0),
      path: .[2]
    }
  )
')

DIFF_STAT=$(git diff --stat "$MERGE_BASE..HEAD")

# Full diff, capped so we don't blow context. ~80KB is plenty for most PRs.
MAX_DIFF_BYTES=80000
FULL_DIFF=$(git diff "$MERGE_BASE..HEAD")
DIFF_TRUNCATED=false
DIFF_BYTES=$(printf '%s' "$FULL_DIFF" | wc -c | tr -d ' ')
if [ "$DIFF_BYTES" -gt "$MAX_DIFF_BYTES" ]; then
  DIFF=$(printf '%s' "$FULL_DIFF" | head -c "$MAX_DIFF_BYTES")
  DIFF_TRUNCATED=true
else
  DIFF="$FULL_DIFF"
fi

# A few recent merged PRs as style examples (so Claude matches the project's tone).
RECENT_PRS=$(gh pr list --state merged --limit 3 --json title,body 2>/dev/null || echo "[]")

jq -n \
  --arg repo "$REPO" \
  --arg current_branch "$CURRENT_BRANCH" \
  --arg base_branch "$BASE_BRANCH" \
  --argjson remote_branch_exists "$REMOTE_BRANCH_EXISTS" \
  --argjson branch_up_to_date_with_remote "$BRANCH_UP_TO_DATE" \
  --arg uncommitted_changes "$UNCOMMITTED" \
  --argjson existing_pr "$EXISTING_PR" \
  --argjson commits "$COMMITS_JSON" \
  --argjson files_changed "$FILES_JSON" \
  --arg diff_stat "$DIFF_STAT" \
  --arg diff "$DIFF" \
  --argjson diff_truncated "$DIFF_TRUNCATED" \
  --argjson recent_pr_examples "$RECENT_PRS" \
  '{
    repo: $repo,
    current_branch: $current_branch,
    base_branch: $base_branch,
    remote_branch_exists: $remote_branch_exists,
    branch_up_to_date_with_remote: $branch_up_to_date_with_remote,
    uncommitted_changes: $uncommitted_changes,
    existing_pr: $existing_pr,
    commits: $commits,
    files_changed: $files_changed,
    diff_stat: $diff_stat,
    diff: $diff,
    diff_truncated: $diff_truncated,
    recent_pr_examples: $recent_pr_examples
  }'
