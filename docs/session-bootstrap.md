# Session Bootstrap

Use one of the following prompts to resume work in a new session.

## Full Prompt

```text
We are continuing work in this repo.

Before making changes:
1. Read `AGENTS.md`.
2. Read `docs/compatibility.md` and `docs/architecture.md`.
3. Read `.local/current.md` and `.local/backlog.md` for current state and pending work.
4. Summarize where the project stands and continue with the next concrete step unless something is unclear.
5. Preserve Vim 8 compatibility and avoid Vim/Nvim behavioral divergence unless purely cosmetic.
```

## Short Prompt

```text
Continue work in this repo. Read `AGENTS.md`, `docs/compatibility.md`, `docs/architecture.md`, and `.local/*` first, summarize current status, then proceed with the next concrete task.
```
