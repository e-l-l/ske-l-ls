# ske-l-ls

Claude Code skills for automating PR workflows.

## Skills

### `fix-pr-comments`

Fetches unresolved inline review comments from the current branch's PR and spawns parallel subagents to address each file's comments. Actionable feedback gets fixed automatically; non-actionable comments are skipped with reasoning.

**Requires:** [`gh`](https://cli.github.com/) (authenticated) and `jq`.

**Install:**

```sh
npx @anthropic-ai/claude-code skills install github.com/e-l-l/ske-l-ls/skills/fix-pr-comments
```

**Usage:**

```
/fix-pr-comments
```

Run from any branch that has an open pull request with unresolved review comments.

## Install all skills

```sh
npx @anthropic-ai/claude-code skills install github.com/e-l-l/ske-l-ls
```
