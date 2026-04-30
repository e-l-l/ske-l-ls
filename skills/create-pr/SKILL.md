---
name: create-pr
description: Open a well-written pull request from the current branch using the gh CLI. Use when the user wants to raise, create, or open a PR.
disable-model-invocation: true
---

# Create PR

Open a pull request from the current branch with a title and description that follow the project's conventions.

## Branch context

!`${CLAUDE_SKILL_DIR}/scripts/gather-context.sh`

## Instructions

### Step 1 — Validate the context

Parse the JSON above.

- **If output starts with `ERROR:`** — show it to the user and stop. Common causes: not in a git repo, on the default branch, `gh` not authenticated.
- **If `existing_pr` is non-null and its `state` is `OPEN`** — stop and tell the user a PR already exists, with the URL. Do not create a duplicate. (If it's `CLOSED` or `MERGED`, continue — a new PR is fine.)
- **If `uncommitted_changes` is non-empty** — stop and ask the user whether to commit them first or proceed without them. Don't silently include or exclude work.
- **If `commits` is empty** — stop and tell the user there's nothing to PR.

### Step 2 — Push the branch if needed

- If `remote_branch_exists` is false: `git push -u origin <current_branch>`.
- If `remote_branch_exists` is true and `branch_up_to_date_with_remote` is false: `git push origin <current_branch>` (do **not** force-push without explicit user permission; if the push is rejected as non-fast-forward, stop and ask).
- Otherwise skip.

On network failure, retry up to 4 times with exponential backoff (2s, 4s, 8s, 16s).

### Step 3 — Draft the title

Read the `commits`, `files_changed`, `diff_stat`, and `diff` to understand the change. Then write a title that follows these rules:

**Form**
- Imperative mood, present tense: `Add retry logic to token refresh`, not `Added` / `Adds` / `Adding`.
- Under ~70 characters. If it doesn't fit, the title is too vague — cut adjectives, not specifics.
- No trailing period. No trailing issue number (`(#123)` belongs in the body).
- Sentence case unless `recent_pr_examples` shows the project uses Title Case or all-lowercase.

**Content**
- Specific over generic. `Fix race condition in token refresh` beats `Fix auth bug`. Name the actual subsystem and the actual change.
- Lead with the verb that describes the *user-visible* effect when there is one (`Add`, `Fix`, `Remove`, `Rename`, `Speed up`, `Prevent`). Use `Refactor` / `Extract` / `Inline` only when there's no behavior change.
- Don't pad with filler: drop "some", "various", "minor", "small", "a bunch of".
- Don't describe the process (`WIP`, `Cleanup after review`, `Address comments`) — describe the change.

**Match the project's style**
- Look at `recent_pr_examples`. If they use Conventional Commits prefixes (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`), use the same prefix. If they don't, don't add one.
- Mirror their capitalization and punctuation conventions.

### Step 4 — Draft the description

Use this structure. Drop sections that don't apply — empty headers are noise.

```markdown
## Summary

<1–3 sentences. Lead with WHY: the problem, the user-facing motivation, or the
constraint that forced this change. Then state WHAT the PR does at a high level.
Do not narrate the diff — reviewers can read it.>

## Changes

- <Notable change with file reference, e.g. `src/auth/token.ts:42`>
- <Notable change>
- <Notable change>

## Test plan

- [ ] <Concrete verification step a reviewer can actually run or check>
- [ ] <Edge case worth covering>

## Notes

<Optional: breaking changes, migration steps, follow-ups, things deliberately
left out, screenshots for UI changes, links to the issue/RFC.>
```

**Description guidance**

- **Lead with motivation, not mechanics.** `The token refresh races when two requests refresh simultaneously, double-spending the refresh token.` — that's a good first sentence. `This PR modifies token.ts to add a mutex.` is not.
- **One bullet per meaningful change**, not one bullet per file. If you renamed `foo` to `bar` across 12 files, that's one bullet.
- **Reference files with `path:line`** when pointing at a specific decision — it makes the PR navigable.
- **The test plan should be runnable.** `Tested locally` is useless. `Run `npm test -- auth/token` and confirm the new race-condition test passes` is useful. For UI: list the flows to click through. For backend: list the curl commands or the manual check.
- **Don't include**: a restatement of the title, a paragraph summarizing the diff, generated commit logs, AI/tool attribution, or `Generated with Claude` footers (the user can add those manually if they want).
- **Match the repo's tone.** Skim `recent_pr_examples` for length and formality. A repo whose merged PRs are 2-line bodies doesn't need a 5-section essay.
- **Linked issues**: if the user mentioned an issue or one appears in commit messages, add `Closes #N` / `Fixes #N` in the Notes section.

### Step 5 — Confirm before creating

Show the user the drafted title and body and the base branch, and ask whether to proceed, edit, or cancel. PRs are visible to collaborators — don't create one without confirmation unless the user already said "just do it".

### Step 6 — Create the PR

Once confirmed, create it with `gh pr create`. Pass the body via a heredoc so multi-line markdown survives intact:

```sh
gh pr create \
  --base "<base_branch>" \
  --head "<current_branch>" \
  --title "<title>" \
  --body "$(cat <<'EOF'
<body>
EOF
)"
```

If the user asked for a draft PR, add `--draft`.

### Step 7 — Report back

Print the PR URL returned by `gh pr create`. Offer to subscribe to PR activity (CI, reviews) if the user wants.
