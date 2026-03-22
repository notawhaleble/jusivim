function! s:normalize_bufnr(bufnr) abort
  if a:bufnr is# 0 || a:bufnr is# ''
    return bufnr('%')
  endif
  return str2nr(a:bufnr)
endfunction

function! s:is_notebook_buffer(bufnr) abort
  return bufexists(a:bufnr) && getbufvar(a:bufnr, '&filetype') ==# 'jusinb'
endfunction

function! s:copy_update(current, update) abort
  let l:next = copy(a:current)
  for [l:key, l:value] in items(a:update)
    let l:next[l:key] = l:value
  endfor
  return l:next
endfunction

function! s:notebook_state(bufnr) abort
  if !s:is_notebook_buffer(a:bufnr)
    return {}
  endif
  return jusi#notebook#state(a:bufnr)
endfunction

function! s:update_state(bufnr, state) abort
  call setbufvar(a:bufnr, 'jusi_nb', a:state)
  return a:state
endfunction

function! s:update_session(bufnr, update) abort
  let l:state = s:notebook_state(a:bufnr)
  if empty(l:state)
    return {}
  endif
  let l:state.session = s:copy_update(l:state.session, a:update)
  return s:update_state(a:bufnr, l:state)
endfunction

function! s:update_prepared(bufnr, update) abort
  let l:state = s:notebook_state(a:bufnr)
  if empty(l:state)
    return {}
  endif
  let l:prepared = get(l:state.session, 'prepared', jusi#session#default_prepared_state())
  let l:state.session.prepared = s:copy_update(l:prepared, a:update)
  return s:update_state(a:bufnr, l:state)
endfunction

function! s:find_cell_index(state, cell_id) abort
  for l:idx in range(0, len(a:state.cells) - 1)
    if get(a:state.cells[l:idx], 'id', 0) == a:cell_id
      return l:idx
    endif
  endfor
  return -1
endfunction

function! s:update_cell_sign(bufnr, cell) abort
  execute 'sign unplace ' . a:cell.sign_id
        \ . ' group=' . jusi#render#sign_group()
        \ . ' buffer=' . a:bufnr
  execute 'sign place ' . a:cell.sign_id
        \ . ' line=' . jusi#render#sign_lnum(a:cell)
        \ . ' name=' . jusi#render#sign_name(a:cell.status)
        \ . ' group=' . jusi#render#sign_group()
        \ . ' buffer=' . a:bufnr
endfunction

function! s:update_cell(bufnr, cell_id, update) abort
  let l:state = s:notebook_state(a:bufnr)
  if empty(l:state)
    return {}
  endif
  let l:idx = s:find_cell_index(l:state, a:cell_id)
  if l:idx < 0
    return {}
  endif

  let l:previous_status = get(l:state.cells[l:idx], 'status', '')
  let l:state.cells[l:idx] = s:copy_update(l:state.cells[l:idx], a:update)
  call s:update_state(a:bufnr, l:state)

  if get(l:state.cells[l:idx], 'status', '') !=# l:previous_status
    call s:update_cell_sign(a:bufnr, l:state.cells[l:idx])
  endif
  return l:state.cells[l:idx]
endfunction

function! s:echo_error(message) abort
  echohl ErrorMsg
  echom a:message
  echohl None
endfunction

function! s:connected_session_state(session) abort
  return index(['starting', 'connected', 'stopping'], get(a:session, 'state', 'idle')) >= 0
endfunction

function! s:fail_session(bufnr, update, message) abort
  let l:state = s:update_session(a:bufnr, extend(copy(a:update), {
        \ 'state': 'failed',
        \ 'last_error': a:message,
        \ }))
  call s:echo_error(a:message)
  return l:state
endfunction

function! s:require_notebook_buffer(bufnr, action) abort
  if s:is_notebook_buffer(a:bufnr)
    return 1
  endif
  call s:echo_error('Jusivim ' . a:action . ' requires a .vipynb notebook buffer')
  return 0
endfunction

function! s:apply_response(bufnr, response, session_fallback, prepared_fallback, ...) abort
  let l:cell_update = a:0 >= 1 ? a:1 : {}
  let l:cell_id = a:0 >= 2 ? a:2 : 0

  let l:session_update = copy(a:session_fallback)
  if has_key(a:response, 'session') && type(a:response.session) == type({})
    call extend(l:session_update, a:response.session)
  endif
  let l:session_update.last_error = get(l:session_update, 'last_error', '')
  call s:update_session(a:bufnr, l:session_update)

  let l:prepared_update = copy(a:prepared_fallback)
  if has_key(a:response, 'prepared') && type(a:response.prepared) == type({})
    call extend(l:prepared_update, a:response.prepared)
  endif
  call s:update_prepared(a:bufnr, l:prepared_update)

  if l:cell_id > 0 && !empty(l:cell_update)
    if has_key(a:response, 'cell') && type(a:response.cell) == type({})
      call extend(l:cell_update, a:response.cell)
    endif
    call s:update_cell(a:bufnr, l:cell_id, l:cell_update)
  endif

  return jusi#notebook#state(a:bufnr)
endfunction

function! jusi#session#default_prepared_state() abort
  return {
        \ 'state': 'missing',
        \ 'bufnr': -1,
        \ }
endfunction

function! jusi#session#default_state() abort
  return {
        \ 'state': 'idle',
        \ 'backend': '',
        \ 'kernel_name': '',
        \ 'connection': '',
        \ 'attachable': 0,
        \ 'last_error': '',
        \ 'last_action': '',
        \ 'request': {},
        \ 'prepared': jusi#session#default_prepared_state(),
        \ }
endfunction

function! jusi#session#state(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  let l:state = s:notebook_state(l:bufnr)
  if empty(l:state)
    return {}
  endif
  return get(l:state, 'session', jusi#session#default_state())
endfunction

function! jusi#session#prepared(...) abort
  let l:session = jusi#session#state(a:0 >= 1 ? a:1 : bufnr('%'))
  if empty(l:session)
    return {}
  endif
  return get(l:session, 'prepared', jusi#session#default_prepared_state())
endfunction

function! jusi#session#apply(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  let l:update = a:0 >= 2 ? a:2 : {}
  return s:update_session(l:bufnr, l:update)
endfunction

function! jusi#session#apply_prepared(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  let l:update = a:0 >= 2 ? a:2 : {}
  return s:update_prepared(l:bufnr, l:update)
endfunction

function! jusi#session#apply_cell(cell_id, update, ...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  return s:update_cell(l:bufnr, a:cell_id, a:update)
endfunction

function! jusi#session#callback_session(update, ...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  return s:update_session(l:bufnr, a:update)
endfunction

function! jusi#session#callback_prepared(update, ...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  return s:update_prepared(l:bufnr, a:update)
endfunction

function! jusi#session#callback_cell(cell_id, update, ...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  return s:update_cell(l:bufnr, a:cell_id, a:update)
endfunction

function! jusi#session#callback_response(response, ...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  let l:response = type(a:response) == type({}) ? a:response : {}
  let l:session_fallback = has_key(l:response, 'session') ? {} : {}
  let l:prepared_fallback = has_key(l:response, 'prepared') ? {} : {}
  let l:cell_update = get(l:response, 'cell', {})
  let l:cell_id = get(l:cell_update, 'id', 0)
  if l:cell_id > 0
    let l:cell_update = copy(l:cell_update)
    call remove(l:cell_update, 'id')
    return s:apply_response(l:bufnr, l:response, l:session_fallback, l:prepared_fallback, l:cell_update, l:cell_id)
  endif
  return s:apply_response(l:bufnr, l:response, l:session_fallback, l:prepared_fallback)
endfunction

function! jusi#session#set_connected(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  let l:update = a:0 >= 2 ? a:2 : {}
  let l:default_update = {
        \ 'state': 'connected',
        \ 'last_error': '',
        \ }
  if !has_key(l:update, 'prepared')
    let l:default_update.prepared = jusi#session#default_prepared_state()
  endif
  return s:update_session(l:bufnr, extend(l:default_update, copy(l:update)))
endfunction

function! jusi#session#set_detached(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  return s:update_session(l:bufnr, {
        \ 'state': 'detached',
        \ 'last_error': '',
        \ 'request': {},
        \ 'prepared': jusi#session#default_prepared_state(),
        \ })
endfunction

function! jusi#session#set_stopped(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  return s:update_session(l:bufnr, {
        \ 'state': 'stopped',
        \ 'last_error': '',
        \ 'request': {},
        \ 'prepared': jusi#session#default_prepared_state(),
        \ })
endfunction

function! jusi#session#start(...) abort
  let l:bufnr = s:normalize_bufnr(bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'start')
    return {}
  endif

  let l:kernel_name = a:0 >= 1 && !empty(a:1) ? a:1 : 'python3'
  let l:session = jusi#session#state(l:bufnr)
  if s:connected_session_state(l:session)
    return s:fail_session(l:bufnr, {'last_action': 'start'}, 'Kernel session is already active for this notebook')
  endif

  let l:request = {'kernel_name': l:kernel_name}
  call s:update_session(l:bufnr, {
        \ 'state': 'starting',
        \ 'kernel_name': l:kernel_name,
        \ 'last_action': 'start',
        \ 'last_error': '',
        \ 'request': l:request,
        \ 'prepared': {'state': 'missing', 'bufnr': -1},
        \ })
  let l:response = jusi#adapter#call('start', l:bufnr, l:request)
  if get(l:response, 'ok', 0)
    return s:apply_response(l:bufnr, l:response, {'state': 'connected'}, jusi#session#default_prepared_state())
  endif
  return s:fail_session(l:bufnr, {
        \ 'last_action': 'start',
        \ 'kernel_name': l:kernel_name,
        \ 'request': l:request,
        \ 'prepared': jusi#session#default_prepared_state(),
        \ }, get(l:response, 'error', 'Failed to start kernel session'))
endfunction

function! jusi#session#attach(target) abort
  let l:bufnr = s:normalize_bufnr(bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'attach')
    return {}
  endif

  let l:session = jusi#session#state(l:bufnr)
  if s:connected_session_state(l:session)
    return s:fail_session(l:bufnr, {'last_action': 'attach'}, 'Kernel session is already active for this notebook')
  endif

  let l:request = {'target': a:target}
  call s:update_session(l:bufnr, {
        \ 'state': 'starting',
        \ 'last_action': 'attach',
        \ 'last_error': '',
        \ 'request': l:request,
        \ 'prepared': {'state': 'missing', 'bufnr': -1},
        \ })
  let l:response = jusi#adapter#call('attach', l:bufnr, l:request)
  if get(l:response, 'ok', 0)
    return s:apply_response(l:bufnr, l:response, {'state': 'connected', 'connection': a:target}, jusi#session#default_prepared_state())
  endif
  return s:fail_session(l:bufnr, {
        \ 'last_action': 'attach',
        \ 'request': l:request,
        \ 'prepared': jusi#session#default_prepared_state(),
        \ }, get(l:response, 'error', 'Failed to attach kernel session'))
endfunction

function! jusi#session#execute_current() abort
  let l:bufnr = s:normalize_bufnr(bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'execute')
    return {}
  endif

  let l:session = jusi#session#state(l:bufnr)
  if get(l:session, 'state', 'idle') !=# 'connected'
    return s:fail_session(l:bufnr, {'last_action': 'execute'}, 'Cannot execute cell without a connected session')
  endif

  let l:prepared = get(l:session, 'prepared', jusi#session#default_prepared_state())
  if get(l:prepared, 'state', 'missing') !=# 'ready'
    return s:fail_session(l:bufnr, {'last_action': 'execute'}, 'Cannot execute cell without a prepared client buffer')
  endif

  let l:cell = jusi#notebook#cell_at_line(l:bufnr, line('.'))
  if empty(l:cell)
    return s:fail_session(l:bufnr, {'last_action': 'execute'}, 'Cannot execute without an active cell')
  endif

  call s:update_session(l:bufnr, {
        \ 'state': 'connected',
        \ 'last_action': 'execute',
        \ 'last_error': '',
        \ 'request': {'cell_id': l:cell.id},
        \ })
  call s:update_prepared(l:bufnr, {'state': 'spawning', 'bufnr': -1})
  call s:update_cell(l:bufnr, l:cell.id, {
        \ 'status': 'busy',
        \ 'client_bufnr': get(l:prepared, 'bufnr', -1),
        \ })

  let l:response = jusi#adapter#call('execute', l:bufnr, {
        \ 'cell': copy(l:cell),
        \ 'prepared': copy(l:prepared),
        \ 'main_lines': jusi#notebook#cell_main_lines(l:cell),
        \ 'history_lines': jusi#notebook#cell_history_lines(l:cell),
        \ })
  if get(l:response, 'ok', 0)
    return s:apply_response(
          \ l:bufnr,
          \ l:response,
          \ {'state': 'connected', 'request': {'cell_id': l:cell.id}},
          \ {'state': 'spawning', 'bufnr': -1},
          \ {'status': 'busy', 'client_bufnr': get(l:prepared, 'bufnr', -1)},
          \ l:cell.id)
  endif

  call s:update_cell(l:bufnr, l:cell.id, {'status': 'error', 'client_bufnr': -1})
  return s:fail_session(l:bufnr, {
        \ 'last_action': 'execute',
        \ 'request': {'cell_id': l:cell.id},
        \ 'prepared': jusi#session#default_prepared_state(),
        \ }, get(l:response, 'error', 'Failed to execute cell'))
endfunction

function! jusi#session#interrupt_current() abort
  let l:bufnr = s:normalize_bufnr(bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'interrupt')
    return {}
  endif

  let l:session = jusi#session#state(l:bufnr)
  if get(l:session, 'state', 'idle') !=# 'connected'
    return s:fail_session(l:bufnr, {'last_action': 'interrupt'}, 'Cannot interrupt without a connected session')
  endif

  let l:cell = jusi#notebook#cell_at_line(l:bufnr, line('.'))
  if empty(l:cell) || get(l:cell, 'status', '') !=# 'busy'
    return s:fail_session(l:bufnr, {'last_action': 'interrupt'}, 'Cannot interrupt the current cell unless it is busy')
  endif

  let l:response = jusi#adapter#call('interrupt', l:bufnr, {'cell': copy(l:cell)})
  if get(l:response, 'ok', 0)
    return s:apply_response(l:bufnr, l:response, {'state': 'connected'}, get(l:session, 'prepared', jusi#session#default_prepared_state()))
  endif
  return s:fail_session(l:bufnr, {
        \ 'last_action': 'interrupt',
        \ }, get(l:response, 'error', 'Failed to interrupt current cell'))
endfunction

function! jusi#session#interrupt() abort
  return jusi#session#interrupt_current()
endfunction

function! jusi#session#stop() abort
  let l:bufnr = s:normalize_bufnr(bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'stop')
    return {}
  endif

  let l:session = jusi#session#state(l:bufnr)
  if index(['starting', 'connected', 'stopping'], get(l:session, 'state', 'idle')) < 0
    return s:fail_session(l:bufnr, {'last_action': 'stop'}, 'Cannot stop a session that is not active')
  endif

  call s:update_session(l:bufnr, {
        \ 'state': 'stopping',
        \ 'last_action': 'stop',
        \ 'last_error': '',
        \ })
  call s:update_prepared(l:bufnr, {'state': 'missing', 'bufnr': -1})
  let l:response = jusi#adapter#call('stop', l:bufnr, {'session': copy(l:session)})
  if get(l:response, 'ok', 0)
    let l:next_state = get(l:session, 'attachable', 0) ? 'detached' : 'stopped'
    return s:apply_response(l:bufnr, l:response, {'state': l:next_state, 'request': {}}, jusi#session#default_prepared_state())
  endif
  return s:fail_session(l:bufnr, {
        \ 'last_action': 'stop',
        \ }, get(l:response, 'error', 'Failed to stop kernel session'))
endfunction
