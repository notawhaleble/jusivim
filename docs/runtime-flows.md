# Jusivim Runtime Flows

This file is a compact reference for the current runtime shape of Jusivim.

It focuses on:

- the main moving parts
- the links between them
- the protocol used on each link
- the current flow for ordinary execution and plugin-backed execution

The diagrams below use PlantUML.

## Component Overview

```plantuml
@startuml
skinparam componentStyle rectangle

package "Vim Process" {
  [Notebook Buffer\n(.vipynb text)]
  [Frontend Notebook Model]
  [Frontend Session Layer]
  [Frontend Transport / Adapter]
  [Frontend Client Buffer Layer]
  [Frontend Focus / Window Layer]
  [Native Terminal Buffer]
}

package "Backend Side" {
  [Jusi Backend Root]
  [Ordinary Client Runtime]
  [Plugin Runtime]
  [Jupyter Kernel]
}

[Notebook Buffer\n(.vipynb text)] --> [Frontend Notebook Model] : parse / reconcile
[Frontend Notebook Model] --> [Frontend Session Layer] : current cell / runtime state
[Frontend Session Layer] --> [Frontend Transport / Adapter] : requests / event handling
[Frontend Session Layer] --> [Frontend Client Buffer Layer] : attach / refresh / detach
[Frontend Session Layer] --> [Frontend Focus / Window Layer] : place / jump / open_path

[Frontend Transport / Adapter] <--> [Jusi Backend Root] : Jusivim protocol\nrequest/response/events
[Jusi Backend Root] <--> [Jupyter Kernel] : kernel execution / magics
[Jusi Backend Root] --> [Ordinary Client Runtime] : backend-private runtime control
[Jusi Backend Root] --> [Plugin Runtime] : backend-private plugin runtime control
[Jusi Backend Root] --> [Native Terminal Buffer] : attach_cmd + attach_env\nterminal I/O
[Frontend Client Buffer Layer] <--> [Jusi Backend Root] : inspect_client\n(handler control stays in session layer)

@enduml
```

## Protocol Boundaries

```plantuml
@startuml
skinparam componentStyle rectangle

[Frontend Session Layer] --> [Backend Root] : start_session\nattach_session\nreconnect_session\nexecute_cell\nshutdown_client\ninterrupt_cell\nhandler_message
[Backend Root] --> [Frontend Session Layer] : session_updated\ncell_updated\nhandler_message\nhealthcheck
[Frontend Session Layer] --> [Backend Root] : healthcheck_reply

[Frontend Client Buffer Layer] --> [Backend Root] : inspect_client
[Backend Root] --> [Frontend Client Buffer Layer] : inspect_client response

[Backend Root] --> [Native Terminal Buffer] : client-process terminal-attach\nterminal stream

note right of [Frontend Session Layer]
handler_message is the generic control channel.

Frontend -> backend:
- followup
- complete

Backend -> frontend:
- complete_result
- action_request
end note

@enduml
```

## Use Case 1: Simple `print('lalala')`

```plantuml
@startuml
actor User
participant "Notebook Buffer" as NB
participant "Frontend Session" as FS
participant "Frontend Transport" as FT
participant "Backend Root" as BR
participant "Jupyter Kernel" as JK
participant "Frontend Client Buffer" as FCB

User -> NB : execute current cell
NB -> FS : current cell text / cell id
FS -> FT : execute_cell
FT -> BR : request execute_cell
BR -> JK : execute code
JK --> BR : stdout / result
BR --> FT : cell_updated(busy/done,\nclient_id,...)
FT --> FS : callback_cell()
FS -> FCB : ensure local client buffer\nbind to cell
FCB -> BR : inspect_client
BR --> FCB : transcript snapshot / revision
FCB --> User : visible client text\n\"lalala\"

@enduml
```

### Notes

- No plugin runtime is involved.
- No native terminal handoff is involved.
- The visible client buffer is refreshed from `inspect_client`.

## Use Case 2: One Active Plugin

```plantuml
@startuml
actor User
participant "Notebook Buffer" as NB
participant "Frontend Session" as FS
participant "Backend Root" as BR
participant "Jupyter Kernel" as JK
participant "Plugin Runtime" as PR
participant "Native Terminal Buffer\nor Client Buffer" as UI

User -> NB : execute %%sql / %%vd / %%shell cell
NB -> FS : current cell text / cell id
FS -> BR : execute_cell
BR -> JK : execute cell / magic
JK --> BR : plugin handoff metadata
BR -> BR : validate handoff\ncreate handler-owned client
BR -> PR : start plugin runtime if needed
BR --> FS : cell_updated(owner=handler,\nclient_id, client_state,...)

alt ordinary attached output
  FS -> UI : create/bind client buffer
  UI -> BR : inspect_client
  BR --> UI : output snapshot
else native terminal
  BR --> FS : transport.kind=native_terminal\nattach_cmd + attach_env
  FS -> UI : launch terminal-attach
  PR <--> UI : terminal I/O
end

User -> NB : followup / completion
NB -> FS : current cell + cursor context
FS -> BR : handler_message(followup or complete)
BR -> PR : plugin-specific handling
PR --> BR : response / state update
BR --> FS : handler_message(complete_result\naction_request / snapshot ...)

@enduml
```

### Notes

- After execution starts, plugin identity is backend-owned.
- `handler_message` is the control channel around the plugin.
- Fullscreen interaction is on the native-terminal path, not through `handler_message`.

## Use Case 3: Two Active Plugins

```plantuml
@startuml
skinparam componentStyle rectangle

package "Vim / Jusivim" {
  [Notebook Buffer]
  [Frontend Session]
  [Client Surface A]
  [Client Surface B]
}

package "Backend" {
  [Backend Root]
  [Plugin Runtime A]
  [Plugin Runtime B]
  [Jupyter Kernel]
}

[Notebook Buffer] --> [Frontend Session] : execute / followup / complete
[Frontend Session] <--> [Backend Root] : single session protocol
[Backend Root] <--> [Jupyter Kernel] : one kernel session

[Backend Root] --> [Plugin Runtime A] : handler/client A
[Backend Root] --> [Plugin Runtime B] : handler/client B

[Frontend Session] --> [Client Surface A] : bind client_id A\nhandler_id A
[Frontend Session] --> [Client Surface B] : bind client_id B\nhandler_id B

note bottom of [Backend Root]
One backend root process supervises both active plugin clients.

Each plugin cell still has its own:
- cell id
- client_id
- handler_id
- local client surface
end note

@enduml
```

### Notes

- The session is shared.
- The kernel is shared.
- Cell/client/handler identity is separate per active plugin cell.
- This is why two active plugins are now a normal case rather than a special-mode workaround.

## Glossary

- Notebook Buffer
  - The actual `.vipynb` text buffer in Vim.
  - Source of truth for notebook text and cell delimiters.

- Frontend Notebook Model
  - In-memory parsed notebook state.
  - Owns runtime-stable cell ids, cell coordinates, cell status, and notebook-local state.

- Frontend Session Layer
  - Owns `b:jusi_nb.session`.
  - Sends backend requests.
  - Applies backend events.
  - Routes plugin control messages.

- Frontend Transport / Adapter
  - Encodes and decodes the Jusivim/backend protocol.
  - Handles request/response/event dispatch.

- Frontend Client Buffer Layer
  - Manages local Vim buffers used as output/client views.
  - Refreshes ordinary client content through `inspect_client`.
  - Tracks local notebook/cell/client attachment metadata.

- Frontend Focus / Window Layer
  - Places client buffers.
  - Switches notebook <-> client focus.
  - Handles built-in editor actions like `open_path`.

- Native Terminal Buffer
  - A real Vim/Neovim terminal buffer created from backend-provided `attach_cmd` and `attach_env`.
  - Used for fullscreen interactive plugin clients.

- Backend Root
  - The authoritative process for session truth, client truth, and handler/plugin truth.
  - Talks to the frontend over the explicit protocol.
  - Talks to the kernel and manages backend-side runtimes.

- Ordinary Client Runtime
  - Backend-managed execution/output surface for a normal code cell.
  - Not a separate frontend protocol boundary.

- Plugin Runtime
  - Backend-managed runtime for plugin-specific interactive behavior.
  - May be attached through a native terminal buffer.

- Jupyter Kernel
  - Executes ordinary code cells.
  - Executes plugin-provided magics through kernel extensions.

- Handler Channel
  - Structured plugin control channel carried through `handler_message`.
  - Frontend -> backend:
    - `followup`
    - `complete`
  - Backend -> frontend:
    - `complete_result`
    - `action_request`

- `inspect_client`
  - Frontend pull-based snapshot request used to refresh ordinary attached client buffers.
  - Not the rendering transport for fullscreen native-terminal clients.

- `cell_updated`
  - Backend event describing current cell/client lifecycle state.
  - The backend remains authoritative for client identity and ownership.

- `session_updated`
  - Backend event describing session lifecycle state.

- `healthcheck`
  - Backend liveness event while connected.
  - Frontend responds with `healthcheck_reply` for the matching connected session only.
