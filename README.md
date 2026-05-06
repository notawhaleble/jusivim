# Jusivim

<p align="center">
  <img src="docs/assets/jusi_logo.jpg" alt="Jusi logo" width="220">
</p>

Jusivim is a Vim/Neovim plugin for editing and running plain-text notebook files inside the editor.

It works together with [Jusi](https://github.com/notawhaleble/jusi), a separate Python backend that manages kernel sessions, execution, client runtimes, and plugin-backed interactive cells.

Instead of hiding notebooks behind JSON and a browser UI, Jusivim keeps everything as editable text:

- cells are separated by visible `##` delimiters
- regular code cells and magic/plugin cells live in the same buffer
- output is attached to cells through local client buffers
- execution, follow-up, completion, and session control stay keyboard-first

## Demo

![Jusivim demo](docs/assets/demo.gif)

## What Are Jusivim And Jusi?

Jusivim is the editor frontend.

Jusi is the execution backend.

Jusivim owns the editor experience:

- notebook parsing and cell identity
- syntax and indentation projection
- key mappings and commands
- client buffer placement and focus
- session state visible inside Vim

Jusi owns runtime and execution behavior:

- kernel sessions and execution
- attach/reconnect/restart/stop behavior
- plugin-backed cells such as `%%shell`, `%%sql`, `%%vd`
- completion for plain code cells and active plugin handlers
- output/runtime integration used by the editor

You need both pieces:

- this repo: `jusivim`
- backend repo: `jusi`

## Features

- Plain-text notebook format with `.vipynb` files
- Stable runtime cell identity across structural edits
- Vim 8 and Neovim support
- Cell-aware editing, navigation, copy/paste, and delete
- Session start, attach, reconnect, interrupt, restart, and stop
- Cell-local output/client views
- Interactive plugin workflows through handler-backed cells
- Magic-cell local history with fold/apply/navigation support
- Insert-mode completion for plain code cells
- Keyboard-first notebook/client focus switching
- Per-cell syntax and indentation projection
- Multiple active plugin clients in one notebook session

## Notebook Format

Jusivim notebooks are ordinary text files.

```text
##
print("hello from a code cell")
##
%%sql main
select 1
##
%%shell
ls
```

Rules:

- `##` starts a new cell
- cell text continues until the next delimiter or end of file
- a cell whose first meaningful line starts with `%%name` is treated as a magic/plugin cell
- the file remains directly editable at all times

Magic cells may also contain a frontend-local history region:

```text
##
%%sql main
select 1
##<<
###
select 0
##>>
```

## Requirements

- Vim 8+ or Neovim
- Python 3
- a working [Jusi](https://github.com/notawhaleble/jusi) installation

## Installation

### 1. Install Jusi

Install the backend in the environment or target you want Jusivim to use:

```sh
pip install jusi
```

### 2. Install Jusivim

Use your preferred plugin manager.

`vim-plug`:

```vim
Plug 'notawhaleble/jusivim'
```

`lazy.nvim`:

```lua
{
  "notawhaleble/jusivim",
}
```

Native packages:

```sh
git clone git@github.com:notawhaleble/jusivim.git \
  ~/.vim/pack/jusi/start/jusivim
```

For Neovim:

```sh
git clone git@github.com:notawhaleble/jusivim.git \
  ~/.local/share/nvim/site/pack/jusi/start/jusivim
```

### 3. Point Jusivim At The Backend

For basic usage, setting a single target alias is enough.

Example Vim config:

```vim
let g:jusi_kernel_targets = {
      \ 'local': 'venv:///path/to/your/project/.venv',
      \ }
```

Then:

- `:JusiStartKernel local` starts against that target
- start-command completion comes from `g:jusi_kernel_targets`
- attach-command completion uses remembered attach aliases

If you use a local virtualenv, point the target at that environment. If you use a different target kind, point the alias at that target instead.

### 4. Open A Notebook

Create a file ending in `.vipynb`:

```text
##
print("hello")
```

Then in Vim:

```vim
:JusiStartKernel local
:JusiExecute
```

## Quick Start

1. Open or create `something.vipynb`.
2. Start a kernel with `:JusiStartKernel {alias}`.
3. Toggle cell mode with `<Space>`.
4. Execute the current cell with `<CR>` in cell mode or `:JusiExecute`.
5. Jump between notebook and client with `<C-\><C-\>`.
6. Use `<Tab>` in insert mode for plain code-cell completion.

## Cell Mode

Jusivim has two editing surfaces in the notebook buffer:

- edit mode
  - normal text editing
- cell mode
  - cell-oriented navigation and actions

Cell mode is toggled with `<Space>`.

In cell mode, keys are reinterpreted around notebook structure instead of plain text motion. That is where actions such as execute, close client, history apply, and cell navigation are meant to happen.

## Plugins

Plugins are notebook cell behaviors exposed as magic-style cells.

Examples:

- `%%shell`
  - interactive shell-backed cells
- `%%sql`
  - SQL-backed cells
- `%%vd`
  - VisiData-backed cells

From the user point of view, these should behave as normal notebook features, not as optional hacks around the editor.

The broad model is:

- a magic header such as `%%shell` declares the cell family
- backend may hand execution off to a plugin runtime
- Jusivim keeps the cell, client, and follow-up workflow attached to that runtime

### `%%vd`

`%%vd` is the bundled VisiData-oriented plugin path.

It uses ordinary Python editor presentation on the frontend, while the backend/plugin side provides the actual runtime behavior.

### `~/.jusi/jusi.toml`

This is the user-local Jusi config file.

It is the place for backend/plugin-oriented user configuration that should travel with session target setup, such as plugin config or runtime options understood by Jusi.

### `~/.jusi/visidatarc`

This is the VisiData startup config used by the `%%vd` workflow.

If you customize VisiData behavior, this file is the relevant user-local config surface.

## Palette And Command Discovery

Jusivim exposes a palette-style command surface through `:J`.

That surface is meant for plugin-oriented creation and discovery flows. The exact entries come from backend-provided session metadata.

Useful facts:

- `:J` supports completion
- `:J!` is the bang form
- `:JusiStartKernel` completion comes from configured `g:jusi_kernel_targets`
- `:JusiAttach` completion comes from remembered attach aliases

## Syntax And Indentation

Syntax and indentation are resolved per cell.

That means:

- regular code cells default to Python presentation
- magic/plugin cells can use plugin-specific syntax and indentation
- frontend may start with broad family-level defaults
- backend can refine presentation for an executed cell when it knows more

This is editor presentation only. Cell type still comes from the text in the notebook itself.

## Client Buffers

Execution output appears in client buffers attached to cells.

Important rules:

- a client buffer belongs to one cell/client attachment
- client buffers are placed predictably and default to a bottom split
- switching between notebook and client is explicit with `<C-\><C-\>`
- closing a client with `Q` or `:JusiCloseClient` closes the local client surface for that cell
- ordinary disposable clients can disappear when execution moves on
- active plugin clients are allowed to coexist in the same notebook session

This coexistence is important for workflows such as multiple long-lived plugin cells in one notebook.

## Follow-Up State

Jusivim uses a cell status called `follow-up`.

This is not a standard Jupyter execution state. It means:

- the cell has an active backend-owned runtime context
- subsequent execute-like actions should continue talking to that existing client/runtime
- this is common for interactive plugin cells

So `follow-up` is a notebook interaction state, not just “finished running”.

## Configuration

Useful globals:

```vim
let g:jusi_kernel_targets = {
      \ 'local': 'venv:///path/to/.venv',
      \ }
let g:jusi_client_layout = 'bsplit'
let g:jusi_transport_timeout_ms = 5000
```

## Cheatsheet

Default mappings and the main command surface live in [docs/cheatsheet.md](docs/cheatsheet.md).

It includes:

- normal-mode notebook mappings
- cell-mode mappings
- insert-mode mappings
- session commands
- cell-editing commands
- client/focus commands

## Main Commands

Most day-to-day work uses these:

- `:JusiStartKernel [alias]`
- `:JusiAttach {target}`
- `:JusiExecute`
- `:JusiComplete`
- `:JusiInterruptKernel`
- `:JusiRestartKernel`
- `:JusiStopKernel`
- `:JusiToggleFocus`
- `:JusiCloseClient`

## Documentation

- [Cheatsheet](docs/cheatsheet.md)
- [Compatibility Contract](docs/compatibility.md)
- [Architecture](docs/architecture.md)
- [Runtime Flows](docs/runtime-flows.md)
- [Session Bootstrap Notes](docs/session-bootstrap.md)

## Current Scope

Jusivim is intentionally a two-component system. This repository is only the editor plugin.

It does not include:

- the Python backend implementation
- kernel management internals
- plugin runtime implementation

Those live in [Jusi](https://github.com/notawhaleble/jusi).

## Contributing

If you are working on the frontend/editor side, start with:

- [AGENTS.md](AGENTS.md)
- [docs/compatibility.md](docs/compatibility.md)
- [docs/architecture.md](docs/architecture.md)

## License

[MIT](LICENSE)
