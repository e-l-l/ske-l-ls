#!/usr/bin/env bash
set -euo pipefail

# Fetch unresolved PR review comments for the current branch.
# Outputs JSON grouped by file path:
# [{ "path": "src/foo.ts", "line": 42, "comments": [{ "author": "user", "body": "..." }] }, ...]

# Check prerequisites
if ! command -v gh &>/dev/null; then
  echo "ERROR: gh CLI is not installed. Install it from https://cli.github.com" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is not installed. Install it with: brew install jq" >&2
  exit 1
fi

# Resolve repo owner and name
REPO_INFO=$(gh repo view --json owner,name -q '"\(.owner.login)/\(.name)"' 2>/dev/null) || {
  echo "ERROR: Could not determine repository. Are you in a git repo with a GitHub remote?" >&2
  exit 1
}

OWNER=$(echo "$REPO_INFO" | cut -d'/' -f1)
REPO=$(echo "$REPO_INFO" | cut -d'/' -f2)

# Resolve PR number from current branch
PR_NUMBER=$(gh pr view --json number -q '.number' 2>/dev/null) || {
  echo "ERROR: No pull request found for the current branch. Make sure a PR exists." >&2
  exit 1
}

# Fetch unresolved review threads via GraphQL
QUERY='
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100) {
        pageInfo {
          hasNextPage
        }
        nodes {
          isResolved
          path
          line
          diffSide
          comments(first: 50) {
            nodes {
              body
              author {
                login
              }
              createdAt
            }
          }
        }
      }
    }
  }
}
'

RESPONSE=$(gh api graphql -f query="$QUERY" -F owner="$OWNER" -F repo="$REPO" -F pr="$PR_NUMBER" 2>/dev/null) || {
  echo "ERROR: GraphQL query failed. Check your GitHub authentication with: gh auth status" >&2
  exit 1
}

# Check for pagination
HAS_NEXT=$(echo "$RESPONSE" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage')
if [ "$HAS_NEXT" = "true" ]; then
  echo "WARNING: PR has more than 100 review threads. Only the first 100 are fetched." >&2
fi

# Filter to unresolved threads and format output
echo "$RESPONSE" | jq '[
  .data.repository.pullRequest.reviewThreads.nodes[]
  | select(.isResolved == false)
  | {
      path: .path,
      line: .line,
      diff_side: .diffSide,
      comments: [
        .comments.nodes[]
        | {
            author: .author.login,
            body: .body,
            created_at: .createdAt
          }
      ]
    }
]'
