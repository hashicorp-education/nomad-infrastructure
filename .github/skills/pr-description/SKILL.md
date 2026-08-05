---
name: pr-description
description: "Draft or update a pull request description for this repo. Use when asked to write/create/update a PR description, summarize changes for a PR, or push a description to an open GitHub PR."
argument-hint: "PR number or URL, and optionally which branch/commit range to describe"
---

# PR Description Writer

Drafts a clear, correctly-scoped pull request description and (if asked) pushes
it to GitHub. Structure and anti-patterns are based on
[Writing a Great Pull Request Description](https://www.hackerone.com/blog/writing-great-pull-request-description).

## When to Use

- "Create a PR description for #6"
- "Write up what we changed on this branch"
- "Update the description on https://github.com/.../pull/N"

## Step 1 — Scope the diff correctly

Do not assume the diff against local `main` is the right scope — branches in
this repo are often stacked (one feature branch merged into another before
its own PR opens), and a PR's actual GitHub base is not always `main`.

```bash
gh pr view <number> --json baseRefName,headRefName,url
```

Then find the *real* range to describe:

```bash
git log --oneline --graph origin/<base>..<head>       # commits the PR actually introduces
git merge-base origin/<base> <head>                    # where the branches diverge
git log --oneline origin/<base>..<merge-base-if-relevant>  # if head includes merges of other branches
```

If the branch's history includes a merge of another branch that already has
its own PR (or will), exclude that branch's commits from this description —
scope to what's unique to *this* PR. Note the exclusion explicitly in the
description (see the scope-note pattern below) so it's clear the omission was
intentional, not an oversight.

```bash
git diff --stat origin/<base>..<head>   # confirm the file list matches the intended scope
```

## Step 2 — Structure

Use this five/six-part shape. Keep every section as short as it can be while
still being useful — an oversized PR description is often a sign the PR
itself should have been split up.

1. **Summary** — one or two sentences: what this PR does and why, in plain
   language, so a reviewer doesn't need to open a linked ticket to understand
   the point of the change.
2. **What changed** — explicit prose describing the net change, grouped by
   area/feature if there are several. Not a restatement of the diff — say
   what the change *does*, not just which files moved.
3. **Why** — the business/engineering goal this serves. Justifies even small
   or incidental-looking changes that are part of a larger effort.
4. **How** (when non-obvious) — call out real design decisions and trade-offs
   that aren't already visible by reading the diff. Skip this section if the
   change is straightforward.
5. **Testing** — what was actually verified and how. For infrastructure/config
   changes with no test suite, say what was run and what the observed result
   was (e.g. `terraform plan` showed no diff for existing resources;
   `curl -k https://<ip>:8447/` returned `200`).
6. **Not in this PR / known gaps** (when relevant) — scope exclusions,
   deferred work, or gaps, so reviewers don't assume silence means "not
   considered."

### Anti-patterns to avoid

- "See #JIRA-123 / see linked issue" with no inline context.
- Restating the title or repeating the "What" section under "Why".
- Cryptic one-liners that require the reviewer to go read the code to
  understand what happened.
- Padding: if a section has nothing worth saying, omit it rather than filling
  it with filler.

## Step 3 — Draft to a file first, then push

Write the draft to a scratch file before calling `gh`. Inline
`gh pr edit/create --body "$(cat <<'EOF' ... EOF)"` heredocs are fragile —
apostrophes/contractions in the body have caused shell-quoting failures
(`unexpected EOF while looking for matching` errors) even with a quoted
heredoc delimiter. `--body-file` sidesteps this entirely:

```bash
gh pr edit <number> --body-file /path/to/draft.md
# or, for a new PR:
gh pr create --title "..." --body-file /path/to/draft.md
```

Per this project's confirmation-before-push norm: draft first, show the user
the draft (or a summary of it), and only run the `gh pr edit`/`gh pr create`
command after they explicitly say to push it — don't push automatically just
because a draft was written.

## Step 4 — Confirm

```bash
gh pr view <number> --json url -q .url
```
