function! s:is_notebook_buffer(bufnr) abort
  return bufexists(a:bufnr) && getbufvar(a:bufnr, '&filetype') ==# 'jusinb'
endfunction

function! s:echo_error(message) abort
  echohl ErrorMsg
  echom a:message
  echohl None
endfunction

function! s:window_id() abort
  return exists('*win_getid') ? win_getid() : 0
endfunction

function! s:current_context(bufnr) abort
  if !s:is_notebook_buffer(a:bufnr)
    return {'ok': 0, 'error': 'Jusivim terminal mode requires a .vipynb notebook buffer'}
  endif
  let l:session = jusi#session#state(a:bufnr)
  if get(l:session, 'state', 'idle') !=# 'connected'
    return {'ok': 0, 'error': 'Terminal mode requires a connected session'}
  endif
  let l:cell = jusi#notebook#cell_at_line(a:bufnr, line('.'))
  if empty(l:cell)
    return {'ok': 0, 'error': 'Terminal mode requires an active cell'}
  endif
  if get(l:cell, 'status', '') !=# 'follow-up'
    return {'ok': 0, 'error': 'Terminal mode requires a follow-up client'}
  endif
  if get(get(l:cell, 'owner', {}), 'kind', '') !=# 'handler'
    return {'ok': 0, 'error': 'Terminal mode requires a handler-owned client'}
  endif
  let l:handler = get(l:cell, 'handler', {})
  if empty(get(l:handler, 'id', ''))
    return {'ok': 0, 'error': 'Terminal mode requires a tracked handler id'}
  endif
  if get(get(l:handler, 'snapshot', {}), 'transport', '') !=# 'pty'
    return {'ok': 0, 'error': 'Terminal mode requires a PTY-backed handler client'}
  endif
  if empty(get(l:cell, 'client_id', '')) || get(l:cell, 'client_bufnr', -1) < 0
    return {'ok': 0, 'error': 'Terminal mode requires an attached handler client buffer'}
  endif
  return {
        \ 'ok': 1,
        \ 'cell': l:cell,
        \ 'handler_id': get(l:handler, 'id', ''),
        \ }
endfunction

function! jusi#terminalmode#text_mappings() abort
  return [
        \ 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
        \ 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
        \ 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'L', 'M',
        \ 'K', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
        \ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
        \ '<Space>', '.', ',', '/', '-', '_',
        \ '!', '@', '#', '$', '%', '^', '&', '*', '(', ')',
        \ '[', ']', '{', '}', '?', '=', '+', '~', '`', "'", '"',
        \ '<Bar>', '<Bslash>', '<lt>', '>',
        \ ]
endfunction

function! jusi#terminalmode#text_for_lhs(lhs) abort
  if a:lhs ==# '<Space>'
    return ' '
  endif
  if a:lhs ==# '<Bar>'
    return '|'
  endif
  if a:lhs ==# '<Bslash>'
    return '\'
  endif
  if a:lhs ==# '<lt>'
    return '<'
  endif
  return a:lhs
endfunction

function! jusi#terminalmode#key_mappings() abort
  return [
        \ {'lhs': '<CR>', 'key': 'enter'},
        \ {'lhs': '<BS>', 'key': 'backspace'},
        \ {'lhs': '<Tab>', 'key': 'tab'},
        \ {'lhs': '<Esc>', 'key': 'escape'},
        \ {'lhs': '<Up>', 'key': 'up'},
        \ {'lhs': '<Down>', 'key': 'down'},
        \ {'lhs': '<Left>', 'key': 'left'},
        \ {'lhs': '<Right>', 'key': 'right'},
        \ ]
endfunction

function! s:window_metrics(winid) abort
  for l:info in getwininfo()
    if get(l:info, 'winid', 0) == a:winid
      return {
            \ 'rows': get(l:info, 'height', 0),
            \ 'cols': get(l:info, 'width', 0),
            \ }
    endif
  endfor
  return {}
endfunction

function! s:client_resize_context_for_winid(winid) abort
  if a:winid <= 0
    return {}
  endif
  let l:bufnr = winbufnr(a:winid)
  if l:bufnr <= 0 || !getbufvar(l:bufnr, 'jusi_client_managed', 0)
    return {}
  endif
  let l:snapshot = getbufvar(l:bufnr, 'jusi_handler_snapshot', {})
  if get(l:snapshot, 'transport', '') !=# 'pty'
    return {}
  endif
  let l:notebook_bufnr = getbufvar(l:bufnr, 'jusi_client_notebook_bufnr', 0)
  if !s:is_notebook_buffer(l:notebook_bufnr)
    return {}
  endif
  let l:session = jusi#session#state(l:notebook_bufnr)
  if get(l:session, 'state', 'idle') !=# 'connected'
    return {}
  endif
  let l:client_id = getbufvar(l:bufnr, 'jusi_client_id', '')
  let l:handler_id = getbufvar(l:bufnr, 'jusi_handler_id', '')
  if empty(l:client_id) || empty(l:handler_id)
    return {}
  endif
  let l:metrics = s:window_metrics(a:winid)
  if get(l:metrics, 'rows', 0) <= 0 || get(l:metrics, 'cols', 0) <= 0
    return {}
  endif
  return {
        \ 'winid': a:winid,
        \ 'bufnr': l:bufnr,
        \ 'notebook_bufnr': l:notebook_bufnr,
        \ 'client_id': l:client_id,
        \ 'handler_id': l:handler_id,
        \ 'rows': l:metrics.rows,
        \ 'cols': l:metrics.cols,
        \ }
endfunction

function! s:send_client_resize_for_context(ctx, force) abort
  if empty(a:ctx)
    return 0
  endif
  let l:last_rows = getwinvar(a:ctx.winid, 'jusi_terminal_last_rows', -1)
  let l:last_cols = getwinvar(a:ctx.winid, 'jusi_terminal_last_cols', -1)
  if !a:force && l:last_rows ==# a:ctx.rows && l:last_cols ==# a:ctx.cols
    return 0
  endif
  let l:response = jusi#session#send_handler_message(
        \ a:ctx.client_id,
        \ a:ctx.handler_id,
        \ 'terminal_resize',
        \ {'rows': a:ctx.rows, 'cols': a:ctx.cols},
        \ a:ctx.notebook_bufnr)
  if get(l:response, 'ok', 0)
    call setwinvar(a:ctx.winid, 'jusi_terminal_last_rows', a:ctx.rows)
    call setwinvar(a:ctx.winid, 'jusi_terminal_last_cols', a:ctx.cols)
    call jusi#terminalscreen#resize(a:ctx.bufnr, a:ctx.rows, a:ctx.cols)
    return 1
  endif
  return 0
endfunction

function! jusi#terminalmode#sync_client_resize_for_buffer(notebook_bufnr, client_bufnr, ...) abort
  let l:force = a:0 >= 1 ? a:1 : 0
  for l:info in getwininfo()
    if get(l:info, 'bufnr', 0) != a:client_bufnr
      continue
    endif
    let l:ctx = s:client_resize_context_for_winid(get(l:info, 'winid', 0))
    if empty(l:ctx)
      continue
    endif
    if l:ctx.notebook_bufnr != a:notebook_bufnr
      continue
    endif
    return s:send_client_resize_for_context(l:ctx, l:force)
  endfor
  return 0
endfunction

function! jusi#terminalmode#sync_current_client_resize() abort
  return s:send_client_resize_for_context(s:client_resize_context_for_winid(s:window_id()), 0)
endfunction

function! jusi#terminalmode#sync_visible_client_resizes() abort
  let l:sent = 0
  for l:info in getwininfo()
    let l:ctx = s:client_resize_context_for_winid(get(l:info, 'winid', 0))
    if empty(l:ctx)
      continue
    endif
    let l:sent += s:send_client_resize_for_context(l:ctx, 0)
  endfor
  return l:sent
endfunction

function! jusi#terminalmode#is_active(...) abort
  let l:winid = a:0 >= 1 ? a:1 : s:window_id()
  if l:winid <= 0 || !getwinvar(l:winid, 'jusi_terminal_mode_active', 0)
    return 0
  endif
  return jusi#cellmode#mode(getwinvar(l:winid, 'jusi_terminal_mode_notebook_bufnr', 0)) ==# 'terminal'
endfunction

function! s:input_context() abort
  let l:winid = s:window_id()
  if l:winid <= 0 || !getwinvar(l:winid, 'jusi_terminal_mode_active', 0)
    return {'ok': 0, 'error': 'Terminal mode is not active'}
  endif
  let l:bufnr = getwinvar(l:winid, 'jusi_terminal_mode_notebook_bufnr', 0)
  if !s:is_notebook_buffer(l:bufnr) || bufnr('%') != l:bufnr
    return {'ok': 0, 'error': 'Terminal mode requires the active notebook window'}
  endif
  if jusi#cellmode#mode(l:bufnr) !=# 'terminal'
    return {'ok': 0, 'error': 'Terminal mode is not active'}
  endif
  let l:client_id = getwinvar(l:winid, 'jusi_terminal_mode_client_id', '')
  let l:handler_id = getwinvar(l:winid, 'jusi_terminal_mode_handler_id', '')
  if empty(l:client_id) || empty(l:handler_id)
    return {'ok': 0, 'error': 'Terminal mode lost client context'}
  endif
  return {
        \ 'ok': 1,
        \ 'bufnr': l:bufnr,
        \ 'client_id': l:client_id,
        \ 'handler_id': l:handler_id,
        \ }
endfunction

function! jusi#terminalmode#send_text(text) abort
  let l:ctx = s:input_context()
  if !get(l:ctx, 'ok', 0)
    call s:echo_error(get(l:ctx, 'error', 'Cannot send terminal input'))
    return 0
  endif
  let l:response = jusi#session#send_handler_message(
        \ l:ctx.client_id,
        \ l:ctx.handler_id,
        \ 'terminal_input',
        \ {'text': a:text},
        \ l:ctx.bufnr)
  return get(l:response, 'ok', 0)
endfunction

function! jusi#terminalmode#send_lhs(lhs) abort
  return jusi#terminalmode#send_text(jusi#terminalmode#text_for_lhs(a:lhs))
endfunction

function! jusi#terminalmode#send_key(key, ...) abort
  let l:ctx = s:input_context()
  if !get(l:ctx, 'ok', 0)
    call s:echo_error(get(l:ctx, 'error', 'Cannot send terminal key'))
    return 0
  endif
  let l:payload = {'key': a:key}
  if a:0 >= 1 && type(a:1) == type({})
    call extend(l:payload, copy(a:1))
  endif
  let l:response = jusi#session#send_handler_message(
        \ l:ctx.client_id,
        \ l:ctx.handler_id,
        \ 'terminal_key',
        \ l:payload,
        \ l:ctx.bufnr)
  return get(l:response, 'ok', 0)
endfunction

function! jusi#terminalmode#enter() abort
  let l:bufnr = bufnr('%')
  let l:ctx = s:current_context(l:bufnr)
  if !get(l:ctx, 'ok', 0)
    call s:echo_error(get(l:ctx, 'error', 'Cannot enter terminal mode'))
    return 0
  endif
  let l:winid = s:window_id()
  if l:winid <= 0
    call s:echo_error('Cannot enter terminal mode without an active notebook window')
    return 0
  endif
  call setwinvar(l:winid, 'jusi_terminal_mode_active', 1)
  call setwinvar(l:winid, 'jusi_terminal_mode_notebook_bufnr', l:bufnr)
  call setwinvar(l:winid, 'jusi_terminal_mode_cell_id', get(l:ctx.cell, 'id', 0))
  call setwinvar(l:winid, 'jusi_terminal_mode_client_id', get(l:ctx.cell, 'client_id', ''))
  call setwinvar(l:winid, 'jusi_terminal_mode_handler_id', get(l:ctx, 'handler_id', ''))
  call jusi#cellmode#set_mode('terminal', l:bufnr)
  return 1
endfunction

function! jusi#terminalmode#exit() abort
  let l:winid = s:window_id()
  if l:winid <= 0 || !getwinvar(l:winid, 'jusi_terminal_mode_active', 0)
    return 0
  endif
  let l:bufnr = getwinvar(l:winid, 'jusi_terminal_mode_notebook_bufnr', bufnr('%'))
  call setwinvar(l:winid, 'jusi_terminal_mode_active', 0)
  call setwinvar(l:winid, 'jusi_terminal_mode_notebook_bufnr', 0)
  call setwinvar(l:winid, 'jusi_terminal_mode_cell_id', 0)
  call setwinvar(l:winid, 'jusi_terminal_mode_client_id', '')
  call setwinvar(l:winid, 'jusi_terminal_mode_handler_id', '')
  if s:is_notebook_buffer(l:bufnr)
    call jusi#cellmode#set_mode('cell', l:bufnr)
  endif
  return 1
endfunction

function! jusi#terminalmode#toggle() abort
  if jusi#terminalmode#is_active()
    return jusi#terminalmode#exit()
  endif
  return jusi#terminalmode#enter()
endfunction
