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

## Backend Boundary

The Vim plugin should interact with the backend through a narrow adapter layer.

Adapter responsibilities:

- start kernel
- attach to kernel
- execute cell
- reply to pending execution input
- interrupt execution
- request completion
- receive execution status and results
- stop or detach session

The adapter should convert transport messages into notebook/session updates without leaking protocol details into unrelated editing code.

Prepared-client lifecycle should also remain explicit:

- `missing`
- `spawning`
- `binding`
- `ready`

Prepared-client invariants:

- one session has at most one authoritative prepared client at a time
- the prepared client is a session-level resource, not a cell-level one
- executing a cell consumes the prepared client into a cell-owned active client
- once consumed, that client remains attached to that cell and is never rebound to another cell
- the replacement prepared client starts only after the previous prepared client has been consumed
- prepared buffer identity is tied to prepared client identity and must not be reused across different prepared client ids

The frontend owns Vim buffer creation and must acknowledge prepared binding before the backend can treat the client as `ready`.

## Client Buffer Management

Client buffers are editor resources attached to cells and sessions.

Responsibilities:

- create client buffer when needed
- track whether a client buffer is alive and bound
- rebind focus and navigation reliably
- detect stale or missing client buffers

The plugin should maintain explicit ownership rules:

- notebook owns cells
- session owns the current prepared client
- cell may reference a client buffer
- session may own process-level resources

Binding rules:

- session prepared buffer and cell-attached buffers are separate lifecycles
- at most one prepared buffer is authoritative for a session
- a prepared buffer belongs to a single backend prepared client id
- an attached client buffer belongs to a single cell attachment
- stale local buffers left behind by failure handling are cleanup targets, not alternate sources of truth

Failure to create or reuse a client buffer must produce a clear state transition and user-visible error.

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

### Phase 6: Cleanup And Recovery

- process and session cleanup
- exit and unload hooks
- failure-state inspection and recovery behavior

### Phase 7: Compatibility Refinement

- command and mapping coverage
- output placement rules
- user workflow polish
- performance tuning on large notebooks

## Immediate Implementation Target

The first implementation milestone should prove the architecture with a narrow, complete slice:

- parse `.vipynb` into cells
- navigate cells
- insert a cell above or below
- render cell signs from model
- keep syntax and signs correct after structural edits

That slice should be completed and tested before backend work begins.
