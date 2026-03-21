---
name: fix-pr-comments
description: Fetch unresolved inline PR review comments and spawn parallel subagents to address each file's comments. Use when the user wants to fix, address, or resolve PR review feedback automatically.
disable-model-invocation: true
---

# Fix PR Comments

Automatically address unresolved inline review comments on the current branch's pull request by spawning parallel subagents — one per file.

## Unresolved PR Comments

!`${CLAUDE_SKILL_DIR}/scripts/fetch-comments.sh`

## Instructions

### Step 1 — Parse and validate

Parse the JSON above. It contains unresolved inline review comments grouped by thread.

**If the output starts with `ERROR:`**, stop and show the error to the user. Common issues:
- No PR for current branch — user needs to push and create a PR first
- `gh` not installed or not authenticated — direct user to `gh auth login`

**If the JSON is an empty array `[]`**, inform the user there are no unresolved comments and stop.

### Step 2 — Group comments by file

Group the comment threads by their `path` field. Each unique file path becomes one unit of work for a subagent.

Build a mapping:
```
file_path → [{ line, comments: [{ author, body }] }, ...]
```

### Step 3 — Spawn subagents (max 5 in parallel)

For each file, spawn one subagent using the Agent tool. If there are more than 5 files, process in batches of 5 — wait for each batch to complete before starting the next.

For each subagent, use these parameters:
- `subagent_type`: `"general-purpose"`
- `isolation`: `"worktree"`
- `description`: Short label like `"Fix comments in auth.ts"`

The subagent prompt MUST include:
1. The full file path
2. Every comment thread for that file, with line numbers and comment text
3. The instructions below (copy verbatim into each prompt):

---

**Subagent instructions (include in each prompt):**

You are fixing PR review comments on a specific file. For each comment thread provided:

1. **Read the file** at the given path to understand the current code.
2. **Classify the comment** as one of:
   - **Actionable**: A request to change code (refactor, rename, fix bug, add handling, use a constant, etc.)
   - **Non-actionable**: A question, praise, discussion point, or FYI that doesn't require a code change
3. **For actionable comments**: Use the Edit tool to apply the fix. Make minimal, targeted changes — fix exactly what the reviewer asked for, nothing more.
4. **For non-actionable comments**: Skip and note the reason.
5. **If you cannot determine what change is needed**: Do not guess. Mark as unresolved with an explanation.

**Return a structured summary in exactly this format:**

```
FILE: <file_path>

FIXED:
- Line <N>: <one-line description of what was changed> (requested by @<author>)

SKIPPED:
- Line <N>: <reason> (comment by @<author>)

UNRESOLVED:
- Line <N>: <why it couldn't be resolved> (requested by @<author>)
```

If a category is empty, omit it.

---

### Step 4 — Merge worktree changes

After each batch of subagents completes, collect the results. For each subagent that made changes (indicated by a returned worktree path/branch):

1. Merge the worktree branch into the current branch: `git merge <branch> --no-edit`
2. If a merge conflict occurs, do NOT auto-resolve. Instead, abort the merge (`git merge --abort`) and flag the conflict in the summary — the user will resolve it manually.

### Step 5 — Present summary

After all batches are done, compile a summary from all subagent reports. Present it to the user in this format:

```
## PR Comments Addressed

### <file_path>
- Fixed: <count>
  - Line <N>: <description>
- Skipped: <count> (non-actionable)
- Unresolved: <count>
  - Line <N>: <reason>

### <file_path>
...

---
Total: <X> fixed, <Y> skipped, <Z> unresolved across <N> files
```

If there were merge conflicts, add a section:

```
### Merge Conflicts
The following worktree branches could not be auto-merged:
- <branch>: conflicts in <file>
Run `git merge <branch>` to resolve manually.
```
