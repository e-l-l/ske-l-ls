# ske-l-ls

Claude Code skills for automating PR workflows.

## Skills

### `fix-pr-comments`

Fetches unresolved inline review comments from the current branch's PR and spawns parallel subagents to address each file's comments. Actionable feedback gets fixed automatically; non-actionable comments are skipped with reasoning.

**Requires:** [`gh`](https://cli.github.com/) (authenticated) and `jq`.

**Install:**

```sh
npx skills add e-l-l/ske-l-ls -s fix-pr-comments
```

**Usage:**

```
/fix-pr-comments
```

Run from any branch that has an open pull request with unresolved review comments.

### `create-pr`

Opens a pull request from the current branch with a title and description that follow the project's conventions. Gathers commits, diff, and recent merged PRs as style examples, then drafts a title (imperative mood, specific, conventional-commits prefix if the repo uses them) and a structured body (Summary / Changes / Test plan / Notes) before confirming with you and running `gh pr create`. Pushes the branch first if needed.

**Requires:** [`gh`](https://cli.github.com/) (authenticated) and `jq`.

**Install:**

```sh
npx skills add e-l-l/ske-l-ls -s create-pr
```

**Usage:**

```
/create-pr
```

Run from a feature branch with at least one commit ahead of the default branch.

## Install all skills

```sh
npx skills add e-l-l/ske-l-ls
```
