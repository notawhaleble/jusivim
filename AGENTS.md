# AGENTS

## Project

Jusivim is a standalone Vim plugin project for editing and executing plain-text notebook files with the `.vipynb` extension.

This repository owns the Vim plugin side only. Backend execution logic belongs in a separate project.

## Working Rules

- Preserve the user-facing notebook format and interactive workflow.
- Do not preserve accidental behavior, manual repair rituals, or fragile internals.
- Keep Vim 8 support.
- Avoid Vim and Neovim behavioral divergence unless the difference is optional and cosmetic.
- Treat syntax and signs as projections of the notebook model, not as sources of truth.
- Treat cell type as derived from cell text, not from syntax state.

## Architecture Baseline

- `docs/compatibility.md` defines the user-facing contract.
- `docs/architecture.md` defines the internal design direction and implementation phases.
- The notebook model is the center of the plugin architecture.
- Runtime cell identity must be separate from current line coordinates.
- Backend/session state should be explicit and observable.

## Implementation Guidance

- Prefer standard Vim plugin layout and classic Vimscript compatible with Vim 8.
- Keep modules focused: notebook model, rendering, commands, session state, transport adapter.
- Favor correctness first, then optimize hot paths deliberately.
- Avoid full-buffer recomputation on ordinary edits where practical, but do not sacrifice clarity or correctness for premature optimization.
- When adding a new cell field, define its preservation policy in the notebook reconciler instead of scattering field-copy logic across commands.

## Testing

- Add tests as features are introduced.
- Prefer automated Vim-based tests for notebook editing behavior.
- Keep parser/model logic testable in isolation where possible.
- Current batch test command:

```sh
vim -Nu NONE -n -es -S test/run.vim
```

## Session Continuity

At the start of a new session:

1. Read this file.
2. Read `docs/compatibility.md`.
3. Read `docs/architecture.md`.
4. Read `.local/current.md` and `.local/backlog.md` if they exist.
5. Summarize the current state before making changes.

The `.local/` directory is intentionally gitignored and is used for rolling task state and session continuity.
