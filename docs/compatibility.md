# Jusivim Compatibility

## Purpose

Jusivim is a Vim plugin for working with notebook-like files entirely inside the editor and terminal. The project centers on a plain-text notebook format, cell-oriented editing, interactive execution, and tight keyboard-driven workflows.

This document defines the user-facing contract of the plugin. Internal implementation may evolve freely as long as the behaviors described here remain true.

## Supported Editors

- Vim 8+
- Neovim

Behavior should remain functionally aligned across supported editors. Editor-specific features are optional and must not become structural dependencies of the plugin.

## Notebook Format

Jusivim works with notebook files using the `.vipynb` extension.

A notebook is a plain-text document split into cells by delimiter lines:

```text
##
print("hello")
##
%%sql main
select 1
```

Core rules:

- A cell begins at a delimiter line.
- Cell content continues until the next delimiter line or end of file.
- The file remains directly editable as text.
- Delimiters are part of the notebook format and remain visible to the user.

## Cell Semantics

Each cell has:

- a stable runtime identity
- a current line range in the buffer
- a derived cell type
- an execution status

Cell type is derived from the cell's own text. It is not defined by syntax highlighting state.

Expected type behavior:

- A regular cell is interpreted as a default code cell.
- A cell whose first meaningful content line begins with `%%name` is interpreted as a magic cell.
- The plugin may store parsed type information in memory for speed, but that information must always be recomputable from buffer text.

## Editing Model

Notebook editing remains text-first and cell-aware.

Expected editing behavior:

- moving between cells is reliable
- creating a new cell above or below is reliable
- deleting a cell is reliable
- splitting and merging cells is reliable where supported
- cell operations continue to behave predictably in large notebooks

Editing inside a cell must not require manual recovery steps.

## Syntax And Highlighting

Syntax and highlighting are part of the presentation layer.

Required properties:

- syntax reflects the current cell structure and cell type
- syntax remains stable during routine editing
- syntax repair must be automatic when structure changes
- users should not need manual reinitialization commands to restore correctness

## Signs And Status

Each cell may be associated with a visible status sign.

Statuses include the notebook interaction states currently exposed by the plugin, including:

- initial
- follow-up
- busy
- done
- error
- parked

Required properties:

- sign placement always reflects the current cell structure
- status belongs to the cell, not to an absolute line number
- structural edits must not leave stale signs behind

## Execution Workflow

Jusivim integrates with an external backend to execute notebook cells.

Required user-facing behavior:

- starting a kernel is explicit and observable
- executing the current cell is explicit and observable
- replying to a pending kernel input request is explicit and observable
- interrupting execution is explicit and observable
- backend failures are surfaced clearly
- execution failures must not silently corrupt notebook state

Prepared execution behavior:

- a connected session has at most one authoritative prepared client at a time
- executing a cell consumes the current prepared client and binds it to that cell
- once a client is bound to a cell, it stays attached to that cell and must not be rebound to another cell
- the next prepared client is created only after the previous prepared client has been consumed into cell execution
- a prepared client buffer belongs to that specific prepared client identity and must not be reused for another prepared client identity

The plugin must behave predictably when the backend is absent, misconfigured, or unhealthy.

## Client Buffers And Output

Execution output is presented through client buffers managed by the plugin.

Required properties:

- session-prepared and cell-attached clients are distinct roles
- there is at most one authoritative prepared client buffer per session
- a cell can be associated with its output/client view
- switching focus between notebook and client buffers is reliable
- follow-up workflows remain coherent
- broken or missing client buffers are detected and handled explicitly
- attached client buffers are placed predictably when they become active
- attached client buffers can reflect backend-provided output content
- client placement defaults to a bottom split and remains configurable

Prepared-buffer identity rules:

- a prepared client buffer belongs to one backend prepared client identity
- a cell-attached client buffer belongs to one cell/client attachment
- frontend cleanup may temporarily observe stale local buffers after failures or out-of-order events, but such buffers are not authoritative prepared state
- the frontend must not relabel one prepared buffer as a different prepared client

Client buffer creation, binding, and loss of binding must not appear as mysterious failures.

Current placement compatibility:

- default layout is `bsplit`
- configurable through `g:jusi_client_layout`
- supported layout names are:
  - `asplit`
  - `Asplit`
  - `bsplit`
  - `Bsplit`
  - `rsplit`
  - `lsplit`
  - `tab`

Current output refresh compatibility:

- attached client buffers currently refresh content through backend inspection rather than push-streamed editor updates
- refresh timing is configurable through `g:jusi_client_poll_ms`
- long-running managed executions may update client buffers incrementally while the cell remains `busy`
- a busy client view may surface pending kernel `input_request` prompts, and the frontend may answer them with `input_reply` for that same tracked cell/client

## Kernel Sessions

The plugin supports local kernel startup and kernel attachment workflows.

Required properties:

- a notebook can bind to a kernel session
- a buffer can accurately reflect whether it is connected
- attach workflows report clear success or failure
- stopping a kernel or leaving the editor must not leave orphaned helper processes behind

Session state must be explicit enough to recover from broken transport or broken backend conditions without leaving the editor in an unclear state.

## Failure Handling

Jusivim should fail clearly, locally, and recoverably.

This means:

- no silent desynchronization between notebook structure and UI state
- no hidden requirement to call repair functions during normal use
- no unclear half-connected state between cell, client buffer, and kernel
- no orphaned background processes after normal exit, abnormal exit, or session shutdown

## Performance Expectations

Jusivim must remain responsive in large notebooks and under long editing sessions.

Expected properties:

- common editing operations do not degrade sharply with notebook size
- structural edits remain responsive in notebooks around and above 1,000 lines
- cells with substantial execution history remain usable
- rendering and bookkeeping work should scale with the affected region rather than the whole buffer whenever practical

Current known limitation:

- large multi-cell notebooks can still feel slower than expected during normal-mode navigation and edits
- the current visible-cell syntax and repair model is functionally correct but not yet performance-tuned for notebooks around and above 1,000 cells

## Compatibility Priorities

The project preserves:

- the `.vipynb` text format
- cell delimiters
- cell statuses
- core editing workflows
- kernel-driven execution workflows
- the overall interactive user experience

The project does not preserve:

- internal implementation details
- incidental failure modes
- manual repair rituals
- unclear or fragile process management
