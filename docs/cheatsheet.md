# Jusivim Cheatsheet

This file summarizes the default command and mapping surface shipped by Jusivim.

Assumptions:

- notebook buffer filetype is `jusinb`
- `<leader>` is whatever your Vim/Neovim leader is set to
- some mappings behave differently in normal edit mode and cell mode

## Core Concepts

- Edit mode:
  - ordinary text editing inside the notebook buffer
- Cell mode:
  - cell-oriented navigation and actions
  - toggle with `<Space>`
- Client buffer:
  - output or interactive surface attached to a cell

## Global Focus Mapping

Available outside notebook buffers too:

| Mapping | Mode | Action |
| --- | --- | --- |
| `<C-\><C-\>` | Normal | Toggle focus between notebook and client; from an unrelated buffer, jump to the first known notebook |
| `<C-\><C-\>` | Insert | Same, returning through a one-command insert-mode escape |

## Notebook Mappings

Available in normal mode in a notebook buffer:

| Mapping | Action |
| --- | --- |
| `<Space>` | Toggle cell mode |
| `<leader>r` | Rebuild notebook model |
| `<leader>a` | Insert cell above |
| `<leader>b` | Insert cell below |
| `<leader>x` | Delete current cell |
| `<leader>c` | Enter edit mode for current cell |
| `<leader>y` | Copy current cell |
| `<leader>p` | Paste copied cell below |
| `<leader>h` | Toggle current cell history fold |
| `<leader>j` | Execute current cell or apply history entry |
| `<leader>s` | Toggle parked state for attached client |
| `<leader>00` | Restart kernel |
| `<leader>ii` | Interrupt kernel |
| `<leader>q` | Close current cell client |
| `<leader>g` | Jump to client by count |

## Cell Mode Mappings

After toggling into cell mode with `<Space>`:

| Mapping | Action |
| --- | --- |
| `j` | Move to next cell-mode target |
| `n` | Move to next cell-mode target |
| `k` | Move to previous cell-mode target |
| `<CR>` | Execute current cell or apply history entry |
| `<C-P>` | Apply previous history entry |
| `<C-N>` | Apply next history entry |
| `H` | Toggle current cell history fold |
| `X` | Delete current cell |
| `C` | Edit current cell |
| `Y` | Copy current cell |
| `P` | Paste copied cell below |
| `S` | Toggle parked state |
| `Q` | Close attached client; count selects a relative cell client |
| `G` | Jump to attached client; count selects a relative cell client |
| `R` | Rebuild notebook model |

Notes:

- history-aware navigation treats open history entries as part of the movement surface
- `<CR>` on a history entry applies that history entry back into the active Jusi-plugin cell body
- cell mode remaps the listed normal-mode keys only while the current notebook buffer is in cell mode

## Insert Mode Mappings

| Mapping | Action |
| --- | --- |
| `<Tab>` | Request completion |
| `<C-Y>` | Execute current cell and remain in editing flow |
| `<C-C>` | Leave insert mode and force notebook insert-exit reconciliation |

Completion behavior:

- plain code cells use `complete_cell`
- plugin cells complete only after they already have an active handler client

## Session Commands

| Command | Action |
| --- | --- |
| `:JusiStartKernel [alias]` | Start a kernel session |
| `:JusiAttach {target}` | Attach to an existing session |
| `:JusiDisconnect [reason]` | Disconnect current session |
| `:JusiReconnect` | Reconnect a disconnected session |
| `:JusiRestartKernel` | Restart a start-managed session |
| `:JusiStopKernel` | Stop current session |
| `:JusiInterruptKernel` | Interrupt the busy cell |

## Execution And Completion Commands

| Command | Action |
| --- | --- |
| `:JusiExecute` | Execute current cell |
| `:JusiComplete` | Request completion for current cell |
| `:JusiHandlerComplete` | Alias of `:JusiComplete` |
| `:JusiReplyInput [text]` | Reply to pending kernel input |
| `:JusiHandlerInput [text]` | Send input to active handler |
| `:JusiHandlerFollowup` | Send follow-up message to active handler |

## Cell Editing Commands

| Command | Action |
| --- | --- |
| `:JusiRebuild` | Rebuild notebook model from buffer text |
| `:JusiCellNext` | Jump to next cell |
| `:JusiCellPrev` | Jump to previous cell |
| `:JusiCellNewAbove` | Insert cell above |
| `:JusiCellNewBelow` | Insert cell below |
| `:JusiCellDelete` | Delete current cell |
| `:JusiCellEdit` | Edit current cell |
| `:JusiCellCopy` | Copy current cell |
| `:JusiCellPasteBelow` | Paste copied cell below |
| `:JusiHistoryToggle` | Toggle current history fold |
| `:JusiHistoryApply` | Apply history entry at cursor |
| `:JusiCellModeEnable` | Enter cell mode |
| `:JusiCellModeDisable` | Leave cell mode |
| `:JusiCellModeToggle` | Toggle cell mode |

## Client And Focus Commands

| Command | Action |
| --- | --- |
| `:JusiCloseClient` | Close the current cell's attached client |
| `:JusiTogglePark` | Park/unpark a client |
| `:JusiToggleFocus` | Toggle focus between notebook and client; from an unrelated buffer, jump to the first known notebook |

## Palette Command

| Command | Action |
| --- | --- |
| `:J {args}` | Plugin/session palette command with completion; prepare or reuse the target cell |
| `:J! {args}` | Same target-cell behavior, then execute immediately |

The exact palette surface depends on backend-provided metadata such as:

- `palette`
- `plugin_specs`

Both forms reuse the target notebook window in the current tab when present, or open that notebook in a vertical split in the current tab.

When invoked from Visual mode or with a command range, `:J` / `:J!` use the selected text as the target cell body. If the target cell already exists, the selection replaces its body; if the target cell is new, the selection becomes its initial body. With `:J!`, that cell is executed after this update.

## Common Flows

Start and run a plain code cell:

```vim
:JusiStartKernel local
:JusiExecute
```

Open a client and jump back:

```vim
<C-\><C-\>
<C-\><C-\>
```

Restart a managed kernel:

```vim
<leader>00
```

Interrupt a busy cell:

```vim
<leader>ii
```

## Notes

- Session quit and wipeout are guarded while a Jusi session is active.
- Forced quit still works with `:q!` and forced wipeout still works with `:bwipeout!`.
- Interactive plugin clients prefer native terminal buffers when backend advertises that transport.
- History features are for Jusi plugin-backed magic cells, not arbitrary magic syntax in general.
