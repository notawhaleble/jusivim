# Jusivim Architecture

## Goal

Jusivim is a standalone Vim plugin project for editing and executing notebook-style plain-text documents. The plugin owns the editor experience. Kernel execution is delegated to an external backend through a small, explicit protocol boundary.

The architecture should favor:

- correctness of notebook structure
- explicit state transitions
- predictable recovery behavior
- Vim 8 portability
- performance on large buffers

## Design Principles

- Text is the source of truth for notebook structure.
- Cell state is owned by an in-memory notebook model.
- Syntax, signs, and buffer views are projections of that model.
- Structural edits and execution state must not be inferred from incidental UI state.
- Backend failures must be represented explicitly.
- The plugin should optimize common edit paths without compromising correctness.

## Project Shape

The repository should follow standard Vim plugin layout:

- `plugin/`
- `autoload/`
- `ftdetect/`
- `ftplugin/`
- `syntax/`
- `doc/`
- `test/`

Code organization should separate notebook model logic from rendering and backend/session logic.

Suggested module areas:

- notebook parsing and indexing
- cell operations
- syntax and sign rendering
- session and kernel state
- client buffer management
- backend transport adapter
- public commands and mappings

## Core Model

### Notebook

Each notebook buffer has an in-memory model.

Suggested fields:

```vim
{
  'bufnr': 12,
  'changedtick': 81,
  'next_cell_id': 24,
  'cells': [...],
  'session': {...},
  'ui': {...}
}
```

Responsibilities:

- represent the current parsed cell structure
- track whether cached structure matches the buffer
- provide lookup of cell by line number
- own notebook-local state needed by rendering and execution

### Cell

Each cell is a runtime object with stable identity for the lifetime of the notebook session.

Suggested fields:

```vim
{
  'id': 7,
  'start': 21,
  'end': 32,
  'kind': 'magic',
  'magic': 'sql',
  'syntax': 'sql',
  'status': 'busy',
  'sign_id': 1007,
  'client_bufnr': 45,
  'exec': {...}
}
```

Key properties:

- `id` is an opaque runtime identifier
- `start` and `end` are current coordinates, not identity
- `kind` and `magic` are derived from cell text
- `syntax` is the currently resolved syntax dialect for the cell
- `status` describes the current editor-visible execution state

Cell ids should be allocated monotonically per notebook buffer and preserved across incremental reparses whenever the cell continues to exist.
Default syntax is derived locally from cell type and may later be refined by backend-aware updates.

Cell fields should be treated by policy class during reconciliation:

- parsed fields are rebuilt from buffer text
- runtime fields are preserved for surviving cells
- override-capable fields are preserved only when they differ from their local defaults

This policy should remain centralized in the notebook reconciler rather than spread across commands.

## Parsing And Indexing

### Parsing Rules

Notebook parsing is based on plain-text delimiters.

Parser responsibilities:

- identify cell boundaries
- derive cell type from cell content
- preserve stable ids for unaffected cells when structure changes
- report malformed or ambiguous structure in a controlled way

### Incremental Updates

The plugin should distinguish:

- non-structural edits
- structural edits

Non-structural edits:

- modify text inside a cell body
- do not change cell boundaries
- may require reparsing only the current cell header or content-derived metadata

Structural edits:

- insert or delete delimiters
- split or merge cells
- delete ranges spanning cell boundaries

Structural changes should trigger recomputation only from the earliest affected cell onward where practical.

### Lookup Strategy

The notebook model should support:

- line-to-cell lookup
- cell-by-id lookup
- navigation to previous and next cells

This can be implemented with:

- ordered cell list
- searchable boundary list
- buffer-local dictionaries for id-based lookup

The exact representation may evolve as long as common operations remain cheap.

## Cell Type Detection

Cell type is derived from cell text and cached in the model.

Rules:

- default code cells are the fallback
- magic cells are detected from the first meaningful content line
- syntax state does not define cell type

This keeps behavior deterministic and prevents syntax desynchronization from corrupting structural interpretation.

## Rendering

### Signs

Signs represent cell state and must be rendered from the notebook model.

Rules:

- signs are attached to current cell coordinates
- sign meaning belongs to the cell object
- structural edits must trigger sign reconciliation

Recommended behavior:

- remove stale Jusivim-owned signs after structural changes
- place signs according to current cell list and current statuses

Sign placement should never be treated as authoritative state.

### Syntax

Syntax is a rendering layer driven by the notebook model.

Responsibilities:

- reflect cell boundaries
- reflect cell type
- update automatically after structural changes

Implementation should favor local updates where practical, but correctness comes first.

Plugin syntax and indentation should be described through declarative metadata rather than per-plugin Vim extension files. Unknown magic cells should not be treated as syntax dialect names. They should fall back to Python syntax and indentation until frontend metadata or backend metadata provides a better editor-facing dialect such as `sql`, `sh`, or `markdown`.

The frontend should receive plugin presentation metadata from the backend and store it in notebook-local session state. Core should not hardcode editor behavior for plugin names beyond true built-ins. `%%vd` is the only current built-in and uses ordinary Python syntax and indentation.

Notebook indentation must remain cell-bounded. Runtime language indentation may be delegated to Vim runtime indent files, but their result must not let syntax, brackets, or other context from a different cell become authoritative for the current cell.

Ownership rule:

- frontend metadata may influence local syntax and indentation only
- cell type still comes from notebook text
- executed plugin identity and handler ownership still come from backend handoff
- plugin-specific behavior should remain behind the generic handler channel unless it is a genuine editor action

### Statusline And UI Indicators

Mode indicators, current-cell indicators, and related UI state should read from explicit notebook state rather than recalculate editor structure repeatedly.

## Session Model

Each notebook may bind to a kernel session and associated client resources.

Suggested session fields:

```vim
{
  'state': 'connected',
  'kernel_id': '...',
  'connection': '...',
  'target': {...},
  'expires_at': '...',
  'backend': '...',
  'last_error': ''
}
```

Session states should be explicit, for example:

- `idle`
- `starting`
- `connected`
- `disconnected`
- `stopping`
- `failed`
- `stopped`

Exact labels may change, but state transitions must be deliberate and observable.

Target identity should be explicit and separate from transient connection state. The frontend should be able to record what target a notebook was started or attached against without baking teardown policy directly into that target description.

Backend session payloads currently keep only explicit target metadata. Durable-session behavior, disconnect expiry, and reconnect failure handling should be modeled from backend session state and response codes rather than from a frontend-only link classification. Frontend-local `link` or `ownership` guesses should not become an alternate source of session truth. A disconnected session may also time out and disappear on the backend before any reconnect attempt, so reconnect should keep treating backend failure codes as authoritative rather than as a prompt for frontend-local recovery heuristics.

For attached `connection_file` sessions, frontend may also persist a local alias registry so user-facing attach UX does not depend on remembering raw connection-file paths. That registry is a frontend convenience layer over explicit target identity, not a replacement for backend session ids or reconnect behavior.

Frontend-owned user config should be modeled as a local file, currently `~/.jusi/jusi.toml`, with an override hook for local testing. Until backend grows a separate session-config payload, frontend may merge that config into `target.config` for new session establishment paths. Invalid local config should block start/attach locally instead of sending malformed or ambiguous config downstream.

Unknown bare attach aliases should fail locally rather than being silently reinterpreted as `connection_file` targets. Frontend should only treat a plain `:JusiAttach {value}` string as `connection_file` when it looks path-like enough to be a real connection-file target.

While a session is `connected`, backend may also emit explicit `healthcheck` events. Frontend should answer those with `healthcheck_reply` for the matching connected session only. Missed replies are backend-owned liveness decisions and should feed the ordinary backend-driven `disconnected` timeout path rather than a separate frontend timeout model.

Fresh session establishment in an already-open notebook should clear stale cell runtime bindings only once the new session establishment has actually succeeded and become authoritative. Failed or timed-out attach/reconnect attempts must preserve the previous notebook runtime state. Old cell-local `client_id` / `client_bufnr` state must not be allowed to collide with a newly created execution client after successful reattach, reconnect, or start.

## Backend Boundary

The Vim plugin should interact with the backend through a narrow adapter layer.

Adapter responsibilities:

- start kernel
- attach to kernel
- execute cell
- reply to backend healthchecks
- reply to pending execution input
- interrupt execution
- request completion
- receive execution status and results
- stop or detach session

The adapter should convert transport messages into notebook/session updates without leaking protocol details into unrelated editing code.

## Client Buffer Management

Client buffers are editor resources attached to cells and sessions.

Responsibilities:

- create client buffer when needed
- track whether a client buffer is alive and bound
- rebind focus and navigation reliably
- detect stale or missing client buffers

The plugin should maintain explicit ownership rules:

- notebook owns cells
- cell may reference a client buffer
- session may own process-level resources

Binding rules:

- an attached client buffer belongs to a single cell attachment
- stale local buffers left behind by failure handling are cleanup targets, not alternate sources of truth

Failure to create or reuse a client buffer must produce a clear state transition and user-visible error.

Native terminal pivot status:

- interactive handler clients should now prefer backend-advertised `transport.kind=native_terminal`
- frontend launches a real editor terminal buffer from backend `attach_cmd` / `attach_env`
- notebook/session/handler ownership still remains in the notebook model
- `handler_message` remains the control channel for handler-specific lifecycle/control events and runtime geometry updates such as `terminal_resize`
- client close should be UX-first:
  - detach notebook interaction immediately after accepted shutdown
  - hide local client buffers while teardown finishes
  - only destroy buffers at a safe finalization point

Frontend-side profiling and real fullscreen-client testing showed that a first-class interactive PTY client implemented as:

- structured PTY bytes over the handler channel
- terminal parsing in pure Vimscript
- projection into an ordinary buffer

is unlikely to feel native enough even if correctness keeps improving.

Long-term direction:

- prefer real editor terminal buffers as the client surface
- keep the notebook/session/handler ownership model
- stop treating the custom normal-buffer PTY renderer as the final architecture

Important constraint:

- a native terminal buffer needs a real attached stream/job substrate, not already-framed control-channel bytes

So a real terminal-buffer pivot requires a backend-facing substrate first, for example:

- a stream/socket endpoint suitable for a local terminal bridge process
- or another raw PTY relay path that a native terminal buffer can attach to

That substrate now exists for the active native-terminal path, so frontend work should stay focused on simplifying around terminal buffers rather than preserving PTY-era abstractions.

## Lifecycle And Cleanup

Lifecycle behavior must be explicit and robust.

Required cleanup cases:

- notebook buffer unload
- editor exit
- kernel stop
- backend failure
- abnormal termination where recovery hooks still run

Cleanup logic should attempt to:

- stop helper jobs owned by the plugin
- clear buffer-local bindings
- detach UI state from dead sessions
- avoid orphaned long-lived processes

Exit policy should distinguish ordinary and forced user actions:

- ordinary quit and notebook wipeout should be blocked while active sessions exist
- forced quit or wipeout should bypass graceful frontend cleanup instead of manufacturing teardown state
- forced exit should preserve local recovery metadata where practical, but reconnectability remains a backend fact rather than a frontend guarantee

No cleanup path should depend on a single fragile autocmd alone.

## Error Handling

The architecture should prefer explicit errors over implicit desynchronization.

Guidelines:

- failed transitions should record reason
- commands should validate prerequisites before acting
- broken session state should become visible and inspectable
- recovery commands, if any, should be intentional maintenance tools rather than normal workflow requirements

## Performance Strategy

The main performance target is to keep common notebook editing operations responsive in large buffers.

Practical rules:

- avoid full-buffer rescans during ordinary typing
- avoid repeated syntax-driven structure discovery
- avoid storing semantic truth in rendered artifacts
- recompute only affected cells when possible
- prefer model updates followed by render reconciliation

Likely hot paths to control carefully:

- cursor-move autocmd handlers
- text-change handlers
- structural cell insertion and deletion
- sign refresh
- syntax refresh

## Testing Strategy

The rewrite should include tests from the start.

Test layers:

- parser and notebook model unit tests
- cell operation tests
- session state transition tests
- Vim integration tests for commands and mappings
- cleanup and failure-path tests

Initial automated focus should be on:

- correct cell boundary parsing
- stable behavior under cell insertion and deletion
- sign correctness after structural edits
- syntax correctness after header changes
- session cleanup on buffer unload and exit

## Phased Implementation

### Phase 1: Foundations

- repository layout
- notebook parser
- notebook and cell model
- test harness

### Phase 2: Editing Core

- cell navigation
- insert/delete/split/merge operations
- cell-aware commands
- sign rendering from model

### Phase 3: Syntax And UI

- syntax driven by parsed cells
- status indicators
- current-cell UI updates

### Phase 4: Backend Integration

- backend adapter
- kernel start and attach
- execution workflow
- interrupt workflow
- completion hooks

### Phase 5: Client Buffer Reliability

- client buffer creation and binding
- focus switching
- follow-up workflows
- recovery from dead buffers

### Phase 6: Session Targets And Kernel Types

- target identity and aliasing
- local, virtualenv, ssh, docker, and related launch surfaces
- attach/start/reconnect behavior across target classes
- notebook editing isolated from target-specific transport details

### Phase 7: Plugin Subsystem

- backend-owned plugin presentation metadata
- generic follow-up and completion requests
- generic backend-to-frontend action requests
- plugin syntax and indentation without per-plugin frontend shims
- real validation through `%%sql`, `%%shell`, and `jusi-open`

This phase is considered complete for the frontend core. Future plugin commands should use the generic action-request path and be handled as incremental issues unless they disprove the model.

### Phase 8: External Session Recovery

- explicit disconnected state
- attach and reconnect behavior
- transport timeout ambiguity handling
- recovery errors without destructive local state loss

This phase is considered done enough to stop proactive work. Revisit only for concrete recovery bugs.

### Phase 9: Magic History Workflow

- connect history capture to explicit execution-attempt semantics
- add history navigation and toggle UX
- preserve the structural split between main body and history region
- keep history frontend-local unless the backend contract requires otherwise

Initial capture rule:

- accepted normal execute requests and accepted handler follow-up requests for magic cells record the active body without the `%%...` header in the cell-local history region
- new entries are prepended so recent history reads top-to-bottom
- duplicate entries are removed before the newest copy is inserted
- regular code cells do not create magic history
- non-follow-up handler control messages do not create magic history
- history insertion updates notebook ranges in place instead of forcing identity reconciliation
- history fold/apply/navigation behavior is cell-mode UX on top of the notebook model
- applying a history entry replaces the magic body after the `%%...` header and does not execute the cell
- history mutation must clear affected manual folds before editing history lines
- history fold creation must be idempotent to avoid nested fold layers

This phase is considered complete enough for the frontend core.

What it now covers in practice:

- magic history capture and UX
- plugin navigation/config completion surface through `:J` / `:J!`
- restart workflow through `:JusiRestartKernel`
- the remaining cleanup/recovery work is now ordinary bug-fixing, not a missing architectural slice

What it does not claim:

- richer nonterminal output integration as a v1 requirement
- that every future plugin/product workflow is already finished

## Immediate Implementation Target

The first implementation milestone should prove the architecture with a narrow, complete slice:

- parse `.vipynb` into cells
- navigate cells
- insert a cell above or below
- render cell signs from model
- keep syntax and signs correct after structural edits

That slice should be completed and tested before backend work begins.
