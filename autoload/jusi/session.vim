let s:debug_clock = {'sec': localtime(), 'rel': reltime()}

function! s:normalize_bufnr(bufnr) abort
  if a:bufnr is# 0 || a:bufnr is# ''
    return bufnr('%')
  endif
  return str2nr(a:bufnr)
endfunction

function! s:debug_log_enabled() abort
  return type(get(g:, 'jusi_session_debug_log', 0)) == type('')
        \ && !empty(get(g:, 'jusi_session_debug_log', ''))
endfunction

function! s:debug_string(value) abort
  if type(a:value) == type('')
    return a:value
  endif
  try
    return string(a:value)
  catch
    return '<unprintable>'
  endtry
endfunction

function! s:debug_timestamp() abort
  let l:elapsed_ms = float2nr(reltimefloat(reltime(s:debug_clock.rel)) * 1000.0)
  let l:sec = s:debug_clock.sec + (l:elapsed_ms / 1000)
  let l:ms = l:elapsed_ms % 1000
  return strftime('%Y-%m-%d %H:%M:%S', l:sec) . printf('.%03d', l:ms)
endfunction

function! s:debug_log(bufnr, message, ...) abort
  if !s:debug_log_enabled()
    return
  endif
  let l:path = get(g:, 'jusi_session_debug_log', '')
  let l:parts = [s:debug_timestamp(), 'bufnr=' . a:bufnr, a:message]
  for l:item in a:000
    call add(l:parts, s:debug_string(l:item))
  endfor
  call writefile([join(l:parts, ' | ')], l:path, 'a')
endfunction

function! s:terminal_debug_log_enabled() abort
  return type(get(g:, 'jusi_terminal_debug_log', 0)) == type('')
        \ && !empty(get(g:, 'jusi_terminal_debug_log', ''))
endfunction

function! s:terminal_debug_log(message, payload) abort
  if !s:terminal_debug_log_enabled()
    return
  endif
  let l:path = get(g:, 'jusi_terminal_debug_log', '')
  let l:parts = [s:debug_timestamp(), a:message]
  call add(l:parts, s:debug_string(a:payload))
  call writefile([join(l:parts, ' | ')], l:path, 'a')
endfunction

function! s:apply_presentation_update(update) abort
  let l:update = type(a:update) == type({}) ? copy(a:update) : {}
  let l:presentation = get(l:update, 'presentation', {})
  if type(l:presentation) == type({})
    let l:syntax = get(l:presentation, 'syntax', '')
    if type(l:syntax) == type('') && !empty(l:syntax)
      let l:update.syntax = l:syntax
    endif
  endif
  return l:update
endfunction

function! s:is_notebook_buffer(bufnr) abort
  return bufexists(a:bufnr) && getbufvar(a:bufnr, '&filetype') ==# 'jusinb'
endfunction

function! s:copy_update(current, update) abort
  let l:next = copy(a:current)
  for [l:key, l:value] in items(a:update)
    if l:key ==# 'client_id' && !has_key(l:next, 'id')
      let l:next.id = l:value
    endif
    if l:key ==# 'client_bufnr' && !has_key(l:next, 'bufnr')
      let l:next.bufnr = l:value
    endif
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

function! s:refresh_statuslines() abort
  silent! redrawstatus
endfunction

function! s:session_update_affects_statusline(update) abort
  if type(a:update) != type({})
    return 0
  endif
  for l:key in ['state', 'last_error', 'last_action', 'attach_name', 'target', 'kernel_name']
    if has_key(a:update, l:key)
      return 1
    endif
  endfor
  return 0
endfunction

function! s:update_session(bufnr, update) abort
  let l:state = s:notebook_state(a:bufnr)
  if empty(l:state)
    return {}
  endif
  call s:debug_log(a:bufnr, 'update-session-begin', a:update, get(l:state, 'session', {}))
  let l:state.session = s:copy_update(l:state.session, a:update)
  call s:update_state(a:bufnr, l:state)
  if s:session_update_affects_statusline(a:update)
    call s:refresh_statuslines()
  endif
  call s:debug_log(a:bufnr, 'update-session-end', get(l:state, 'session', {}))
  return l:state
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
  let l:previous_syntax = get(l:state.cells[l:idx], 'syntax', '')
  let l:previous_bufnr = get(l:state.cells[l:idx], 'client_bufnr', -1)
  let l:update = copy(a:update)
  let l:client_effects_changed = has_key(l:update, 'client_bufnr')
        \ || has_key(l:update, 'client_state')
        \ || has_key(l:update, 'client_id')
        \ || has_key(l:update, 'status')
        \ || has_key(l:update, 'owner')
  let l:preserve_local_buffer = get(l:update, '_preserve_local_buffer', 0)
  if has_key(l:update, '_preserve_local_buffer')
    call remove(l:update, '_preserve_local_buffer')
  endif
  if has_key(l:update, 'status')
        \ && get(l:update, 'status', '') !=# 'parked'
        \ && !has_key(l:update, 'parked_status')
    let l:update.parked_status = ''
  endif
  if has_key(l:update, 'status')
        \ && get(l:update, 'status', '') !=# 'busy'
        \ && !has_key(l:update, 'pending_input')
    let l:update.pending_input = {}
  endif
  if has_key(l:update, 'client_state')
        \ && get(l:update, 'client_state', '') !=# 'active'
        \ && !has_key(l:update, 'pending_input')
    let l:update.pending_input = {}
  endif
  if has_key(l:update, 'client_bufnr')
        \ && get(l:update, 'client_bufnr', -1) < 0
        \ && !has_key(l:update, 'pending_input')
    let l:update.pending_input = {}
  endif
  if !has_key(l:update, 'client_state')
        \ && has_key(l:update, 'client_bufnr')
        \ && get(l:update, 'client_bufnr', -1) > 0
    let l:update.client_state = 'active'
  endif
  let l:state.cells[l:idx] = s:copy_update(l:state.cells[l:idx], l:update)
  if l:previous_bufnr > 0
        \ && get(l:state.cells[l:idx], 'client_bufnr', -1) < 0
        \ && !l:preserve_local_buffer
    call jusi#client#destroy_buffer(l:previous_bufnr)
  endif
  call s:update_state(a:bufnr, l:state)

  if l:client_effects_changed && get(l:state.cells[l:idx], 'client_bufnr', -1) > 0
    call jusi#client#mark_attached_buffer(
          \ a:bufnr,
          \ l:state.cells[l:idx].id,
          \ get(l:state.cells[l:idx], 'client_id', ''),
          \ l:state.cells[l:idx].client_bufnr)
    if get(l:state.cells[l:idx], 'client_state', '') ==# 'active'
          \ && get(l:state.cells[l:idx], 'status', '') !=# 'initial'
      call jusi#focus#place_client_buffer(l:state.cells[l:idx].client_bufnr)
      call jusi#client#schedule_attached_refresh(
            \ a:bufnr,
            \ l:state.cells[l:idx].id,
            \ get(l:state.cells[l:idx], 'client_id', ''),
            \ l:state.cells[l:idx].client_bufnr)
    endif
  endif

  if get(l:state.cells[l:idx], 'status', '') !=# l:previous_status
    call s:update_cell_sign(a:bufnr, l:state.cells[l:idx])
  endif
  if get(l:state.cells[l:idx], 'syntax', '') !=# l:previous_syntax
    call jusi#syntax#sync(a:bufnr, l:state.cells)
  endif
  return l:state.cells[l:idx]
endfunction

function! s:cell_close_reset_update() abort
  return {
        \ 'client_state': 'shutdown',
        \ 'client_bufnr': -1,
        \ 'close_requested': 0,
        \ 'handler': {'id': '', 'last_message_type': '', 'payload': {}, 'snapshot': {}},
        \ 'pending_input': {},
        \ 'parked_status': '',
        \ }
endfunction

function! s:cell_runtime_reset_update(cell) abort
  let l:update = extend(copy(s:cell_close_reset_update()), {
        \ 'client_id': '',
        \ 'handler': {'id': '', 'last_message_type': '', 'payload': {}, 'snapshot': {}},
        \ 'presentation': {},
        \ 'owner': {'kind': ''},
        \ })
  let l:status = get(a:cell, 'status', 'initial')
  if index(['busy', 'parked', 'follow-up'], l:status) >= 0
    let l:update.status = 'initial'
  endif
  return l:update
endfunction

function! s:cell_close_final_update(cell) abort
  let l:update = copy(s:cell_close_reset_update())
  if index(['busy', 'parked', 'follow-up'], get(a:cell, 'status', '')) >= 0
    let l:update.status = 'initial'
  endif
  if get(get(a:cell, 'owner', {}), 'kind', '') ==# 'handler'
    let l:update.client_id = ''
    let l:update.owner = {'kind': ''}
  endif
  return l:update
endfunction

function! s:release_current_cell_client_for_execute(bufnr, session, cell) abort
  if empty(a:cell) || get(a:cell, 'client_bufnr', -1) < 0
    return a:cell
  endif

  if s:has_trustworthy_client_identity(a:session, get(a:cell, 'client_id', ''))
    call s:request_shutdown_client(
          \ a:bufnr,
          \ a:session,
          \ a:cell.id,
          \ get(a:cell, 'client_id', ''),
          \ 'execute_replace')
  endif
  call jusi#client#detach_buffer(get(a:cell, 'client_bufnr', -1))
  return s:update_cell(a:bufnr, a:cell.id, extend(copy(s:cell_close_reset_update()), {
        \ '_preserve_local_buffer': 1,
        \ }))
endfunction

function! s:restore_cell_update(cell) abort
  return {
        \ 'status': get(a:cell, 'status', 'initial'),
        \ 'pending_input': copy(get(a:cell, 'pending_input', {})),
        \ 'client_id': get(a:cell, 'client_id', ''),
        \ 'client_state': get(a:cell, 'client_state', 'shutdown'),
        \ 'client_bufnr': get(a:cell, 'client_bufnr', -1),
        \ 'owner': copy(get(a:cell, 'owner', {'kind': ''})),
        \ 'close_requested': get(a:cell, 'close_requested', 0),
        \ 'parked_status': get(a:cell, 'parked_status', ''),
        \ '_preserve_local_buffer': get(a:cell, 'client_bufnr', -1) > 0 ? 1 : 0,
        \ }
endfunction

function! s:is_retained_cell(cell, executing_cell_id) abort
  let l:status = get(a:cell, 'status', '')
  if l:status ==# 'parked' && get(a:cell, 'id', 0) == a:executing_cell_id
    return 0
  endif
  return index(['busy', 'parked', 'follow-up'], l:status) >= 0
endfunction

function! s:release_disposable_cell_clients(bufnr, executing_cell_id) abort
  let l:state = s:notebook_state(a:bufnr)
  if empty(l:state)
    return {}
  endif

  for l:cell in copy(l:state.cells)
    if get(l:cell, 'client_bufnr', -1) < 0
      continue
    endif
    if s:is_retained_cell(l:cell, a:executing_cell_id)
      continue
    endif
    if s:has_trustworthy_client_identity(get(l:state, 'session', {}), get(l:cell, 'client_id', ''))
      call s:request_shutdown_client(
            \ a:bufnr,
            \ get(l:state, 'session', {}),
            \ l:cell.id,
            \ get(l:cell, 'client_id', ''),
            \ 'healthcheck')
    endif
    call jusi#client#destroy_buffer(l:cell.client_bufnr)
    call s:update_cell(a:bufnr, l:cell.id, s:cell_close_reset_update())
  endfor

  return jusi#notebook#state(a:bufnr)
endfunction

function! s:clear_all_cell_runtime(bufnr) abort
  let l:state = s:notebook_state(a:bufnr)
  if empty(l:state)
    return {}
  endif

  for l:cell in copy(get(l:state, 'cells', []))
    call s:update_cell(a:bufnr, l:cell.id, s:cell_runtime_reset_update(l:cell))
  endfor

  return jusi#notebook#state(a:bufnr)
endfunction

function! s:maybe_finalize_closed_cell(bufnr, cell) abort
  if empty(a:cell) || !get(a:cell, 'close_requested', 0)
    return a:cell
  endif
  if get(a:cell, 'client_state', '') !=# 'shutdown'
    return a:cell
  endif
  return s:update_cell(a:bufnr, a:cell.id, s:cell_close_final_update(a:cell))
endfunction

function! s:refresh_stale_cells(bufnr) abort
  let l:state = s:notebook_state(a:bufnr)
  if empty(l:state)
    return {}
  endif

  for l:cell in copy(get(l:state, 'cells', []))
    if get(l:cell, 'client_bufnr', -1) < 0
      continue
    endif
    let l:missing_locally = !bufexists(l:cell.client_bufnr)
    if l:missing_locally
      let l:recovered_bufnr = jusi#client#recover_attached_buffer(
            \ a:bufnr,
            \ l:cell.id,
            \ get(l:cell, 'client_id', ''))
      if l:recovered_bufnr > 0
        let l:cell = s:update_cell(a:bufnr, l:cell.id, {
              \ 'client_bufnr': l:recovered_bufnr,
              \ 'client_state': 'active',
              \ })
        let l:missing_locally = 0
      endif
    endif
    let l:validation = jusi#client#validate_attached_binding(
          \ a:bufnr,
          \ l:cell.id,
          \ get(l:cell, 'client_id', ''),
          \ l:cell.client_bufnr)
    if get(l:validation, 'ok', 0)
      continue
    endif
    if s:has_trustworthy_client_identity(get(l:state, 'session', {}), get(l:cell, 'client_id', ''))
      call s:request_shutdown_client(
            \ a:bufnr,
            \ get(l:state, 'session', {}),
            \ l:cell.id,
            \ get(l:cell, 'client_id', ''),
            \ 'healthcheck')
    endif
    let l:update = s:cell_close_reset_update()
    if !l:missing_locally
      let l:update._preserve_local_buffer = 1
    endif
    call s:update_cell(a:bufnr, l:cell.id, l:update)
    call s:update_session(a:bufnr, {
          \ 'last_action': s:has_trustworthy_client_identity(get(l:state, 'session', {}), get(l:cell, 'client_id', ''))
          \   ? 'shutdown_client'
          \   : 'clear_client_binding',
          \ 'last_error': get(l:validation, 'message', 'Client binding became inconsistent locally') . ' for cell ' . l:cell.id,
          \ })
  endfor

  return jusi#notebook#state(a:bufnr)
endfunction

function! s:repair_local_client_binding(bufnr, cell_id, client_id, client_bufnr) abort
  if !jusi#buffer#is_valid_bufnr(a:client_bufnr)
    return {}
  endif
  return s:update_cell(a:bufnr, a:cell_id, {
        \ 'client_id': a:client_id,
        \ 'client_bufnr': a:client_bufnr,
        \ 'client_state': 'active',
        \ })
endfunction

function! s:echo_error(message) abort
  echohl ErrorMsg
  echom a:message
  echohl None
endfunction

function! s:pending_input_equal(left, right) abort
  return string(type(a:left) == type({}) ? a:left : {}) ==# string(type(a:right) == type({}) ? a:right : {})
endfunction

function! s:pending_input_from_view(view) abort
  if get(a:view, 'execution_status', '') !=# 'busy'
    return {}
  endif
  let l:lines = get(a:view, 'lines', [])
  if empty(l:lines)
    return {}
  endif
  let l:last = l:lines[-1]
  if l:last =~# '^input>\s*'
    return {
          \ 'prompt': matchstr(l:last, '^input>\s*\zs.*$'),
          \ 'password': 0,
          \ }
  endif
  if l:last =~# '^password>\s*'
    return {
          \ 'prompt': matchstr(l:last, '^password>\s*\zs.*$'),
          \ 'password': 1,
          \ }
  endif
  return {}
endfunction

function! s:reply_input_prompt(pending_input) abort
  let l:prompt = get(a:pending_input, 'prompt', '')
  if empty(l:prompt)
    let l:prompt = get(a:pending_input, 'password', 0) ? 'password> ' : 'input> '
  endif
  call inputsave()
  try
    if get(a:pending_input, 'password', 0)
      return inputsecret(l:prompt)
    endif
    return input(l:prompt)
  finally
    call inputrestore()
  endtry
endfunction

function! s:can_shutdown_client(session) abort
  return get(a:session, 'state', 'idle') ==# 'connected' && jusi#adapter#has('shutdown_client')
endfunction

function! s:has_trustworthy_client_identity(session, client_id) abort
  return !empty(get(a:session, 'id', '')) && !empty(a:client_id)
endfunction

function! s:use_async_transport_shutdown(bufnr) abort
  if !jusi#transport#can_request(a:bufnr)
    return 0
  endif
  let l:adapter = get(g:, 'jusi_session_adapter', {})
  if type(l:adapter) == type({}) && !empty(l:adapter)
    return 0
  endif
  return 1
endfunction

function! s:request_shutdown_client(bufnr, session, cell_id, client_id, reason) abort
  if !s:can_shutdown_client(a:session)
    return {'ok': 0, 'error': 'Shutdown support is unavailable'}
  endif
  let l:response = jusi#adapter#call_async('shutdown_client', a:bufnr, {
        \ 'cell': {'id': a:cell_id},
        \ 'client_id': a:client_id,
        \ 'reason': a:reason,
        \ })
  if !get(l:response, 'ok', 0)
    call s:update_session(a:bufnr, {
          \ 'last_action': 'shutdown_client',
          \ 'last_error': get(l:response, 'error', 'Failed to shutdown client'),
          \ })
  endif
  return l:response
endfunction

function! s:connected_session_state(session) abort
  return index(['starting', 'connected', 'stopping'], get(a:session, 'state', 'idle')) >= 0
endfunction

function! s:is_stopping_session_state(session) abort
  return index(['stopping', 'stopped'], get(a:session, 'state', 'idle')) >= 0
endfunction

function! s:accept_runtime_callbacks(session) abort
  return index(['disconnected', 'stopping', 'stopped'], get(a:session, 'state', 'idle')) < 0
endfunction

function! s:ignore_session_callback(current_session, update) abort
  let l:current_state = get(a:current_session, 'state', 'idle')
  let l:update_state = get(a:update, 'state', '')
  if index(['disconnected', 'stopping', 'stopped'], l:current_state) >= 0
        \ && index(['starting', 'connected'], l:update_state) >= 0
    return 1
  endif
  return 0
endfunction

function! s:fail_session(bufnr, update, message) abort
  let l:state = s:update_session(a:bufnr, extend(copy(a:update), {
        \ 'state': 'failed',
        \ 'last_error': a:message,
        \ }))
  call s:echo_error(a:message)
  return l:state
endfunction

function! s:reject_action(bufnr, update, message) abort
  let l:session = jusi#session#state(a:bufnr)
  let l:state = s:update_session(a:bufnr, extend(copy(a:update), {
        \ 'state': get(l:session, 'state', 'idle'),
        \ 'last_error': a:message,
        \ }))
  call s:echo_error(a:message)
  return l:state
endfunction

function! s:is_transport_failure(response) abort
  return index(['transport_unreachable', 'transport_timeout'], get(a:response, 'error_code', '')) >= 0
endfunction

function! s:transport_message(response, fallback) abort
  let l:error = get(a:response, 'error', '')
  if empty(l:error)
    let l:error = a:fallback
  endif
  return 'Backend is unreachable: ' . l:error
endfunction

function! s:reject_transport_failure(bufnr, update, response, fallback) abort
  let l:update = extend(copy(a:update), {
        \ 'last_error_code': get(a:response, 'error_code', ''),
        \ })
  if has_key(l:update, 'state')
    let l:state = s:update_session(a:bufnr, extend(l:update, {
          \ 'last_error': s:transport_message(a:response, a:fallback),
          \ }))
    call s:echo_error(get(l:state.session, 'last_error', s:transport_message(a:response, a:fallback)))
    return l:state
  endif
  return s:reject_action(a:bufnr, l:update, s:transport_message(a:response, a:fallback))
endfunction

function! s:require_notebook_buffer(bufnr, action) abort
  if s:is_notebook_buffer(a:bufnr)
    return 1
  endif
  call s:echo_error('Jusivim ' . a:action . ' requires a .vipynb notebook buffer')
  return 0
endfunction

function! s:apply_response(bufnr, response, session_fallback, ...) abort
  let l:cell_update = a:0 >= 1 ? a:1 : {}
  let l:cell_id = a:0 >= 2 ? a:2 : 0

  let l:session_update = copy(a:session_fallback)
  if has_key(a:response, 'session') && type(a:response.session) == type({})
    call extend(l:session_update, a:response.session)
  endif
  let l:session_update.last_error = get(l:session_update, 'last_error', '')
  let l:session_update.last_error_code = get(l:session_update, 'last_error_code', '')
  call s:update_session(a:bufnr, l:session_update)
  let l:session = jusi#session#state(a:bufnr)
  if get(l:session, 'state', '') ==# 'stopped'
    call s:remove_attach_registry_session(l:session)
  else
    call s:sync_attach_registry(a:bufnr, l:session)
  endif

  if l:cell_id > 0 && !empty(l:cell_update)
    if has_key(a:response, 'cell') && type(a:response.cell) == type({})
      call extend(l:cell_update, a:response.cell)
    endif
    if !empty(get(l:cell_update, 'client_id', ''))
          \ && get(l:cell_update, 'client_state', '') ==# 'active'
          \ && get(l:cell_update, 'client_bufnr', -1) < 0
      let l:current = jusi#notebook#cell_by_id(a:bufnr, l:cell_id)
      if get(l:current, 'client_bufnr', -1) < 0
        let l:cell_update.client_bufnr = jusi#client#create_attached_buffer(a:bufnr, l:cell_id, l:cell_update.client_id)
      endif
    endif
    call s:update_cell(a:bufnr, l:cell_id, l:cell_update)
  endif

  return jusi#notebook#state(a:bufnr)
endfunction

function! s:response_has_state_updates(response) abort
  return (has_key(a:response, 'session') && type(a:response.session) == type({}) && !empty(a:response.session))
        \ || (has_key(a:response, 'cell') && type(a:response.cell) == type({}) && !empty(a:response.cell))
endfunction

function! jusi#session#default_target() abort
  return {
        \ 'source': '',
        \ 'alias': '',
        \ 'kind': '',
        \ 'value': '',
        \ 'config': {},
        \ }
endfunction

function! s:kernel_targets_config() abort
  let l:targets = get(g:, 'jusi_kernel_targets', {})
  return type(l:targets) == type({}) ? l:targets : {}
endfunction

function! s:attach_registry_path() abort
  let l:path = get(g:, 'jusi_attach_registry_file', '')
  if type(l:path) == type('') && !empty(l:path)
    return fnamemodify(l:path, ':p')
  endif
  return fnamemodify('~/.jusi/attach-targets.json', ':p')
endfunction

function! s:read_attach_registry() abort
  let l:path = s:attach_registry_path()
  if !filereadable(l:path)
    return {}
  endif
  try
    let l:decoded = json_decode(join(readfile(l:path), "\n"))
  catch
    return {}
  endtry
  return type(l:decoded) == type({}) ? l:decoded : {}
endfunction

function! s:write_attach_registry(registry) abort
  let l:path = s:attach_registry_path()
  let l:dir = fnamemodify(l:path, ':h')
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
  call writefile([json_encode(a:registry)], l:path)
endfunction

function! s:sanitize_attach_alias(value) abort
  let l:alias = tolower(a:value)
  let l:alias = substitute(l:alias, '\.[^.]\+$', '', '')
  let l:alias = substitute(l:alias, '[^A-Za-z0-9_-]\+', '-', 'g')
  let l:alias = substitute(l:alias, '^-\\+', '', '')
  let l:alias = substitute(l:alias, '-\\+$', '', '')
  return empty(l:alias) ? 'connection' : l:alias
endfunction

function! s:attach_registry_alias_for_session(registry, session_id) abort
  if empty(a:session_id)
    return ''
  endif
  for [l:alias, l:entry] in items(a:registry)
    if type(l:entry) != type({})
      continue
    endif
    if get(l:entry, 'session_id', '') ==# a:session_id
      return l:alias
    endif
  endfor
  return ''
endfunction

function! s:registry_target(entry) abort
  let l:target = get(a:entry, 'target', {})
  if type(l:target) == type({})
    return l:target
  endif
  return {
        \ 'kind': get(a:entry, 'kind', ''),
        \ 'value': get(a:entry, 'value', ''),
        \ }
endfunction

function! s:attach_registry_entry(name) abort
  let l:registry = s:read_attach_registry()
  let l:entry = get(l:registry, a:name, {})
  return type(l:entry) == type({}) ? l:entry : {}
endfunction

function! s:registry_basename(bufnr) abort
  let l:name = bufname(a:bufnr)
  if empty(l:name)
    return 'notebook'
  endif
  let l:tail = fnamemodify(l:name, ':t:r')
  return s:sanitize_attach_alias(empty(l:tail) ? 'notebook' : l:tail)
endfunction

function! s:registry_kernel_label(session) abort
  let l:kernel_id = get(a:session, 'kernel_id', '')
  if !empty(l:kernel_id)
    return s:sanitize_attach_alias(l:kernel_id)
  endif
  let l:target = get(a:session, 'target', {})
  let l:target_alias = get(l:target, 'alias', '')
  if !empty(l:target_alias)
    return s:sanitize_attach_alias(l:target_alias)
  endif
  let l:value = get(l:target, 'value', '')
  if !empty(l:value)
    return s:sanitize_attach_alias(fnamemodify(l:value, ':t:r'))
  endif
  let l:kind = get(l:target, 'kind', '')
  if !empty(l:kind)
    return s:sanitize_attach_alias(l:kind)
  endif
  return 'session'
endfunction

function! s:attach_registry_alias_for_session_data(registry, bufnr, session) abort
  let l:existing = s:attach_registry_alias_for_session(a:registry, get(a:session, 'id', ''))
  if !empty(l:existing)
    return l:existing
  endif
  let l:target = get(a:session, 'target', {})
  for [l:alias, l:entry] in items(a:registry)
    if type(l:entry) != type({})
      continue
    endif
    let l:entry_target = s:registry_target(l:entry)
    if get(l:entry_target, 'kind', '') ==# get(l:target, 'kind', '')
          \ && get(l:entry_target, 'value', '') ==# get(l:target, 'value', '')
          \ && get(l:entry, 'notebook_path', '') ==# bufname(a:bufnr)
      return l:alias
    endif
  endfor
  let l:base = s:registry_basename(a:bufnr) . '-' . s:registry_kernel_label(a:session)
  let l:alias = l:base
  let l:suffix = 2
  while has_key(a:registry, l:alias)
    let l:alias = l:base . '-' . l:suffix
    let l:suffix += 1
  endwhile
  return l:alias
endfunction

function! s:is_registry_trackable_session(session) abort
  let l:target = get(a:session, 'target', {})
  return !empty(get(a:session, 'id', ''))
        \ && type(l:target) == type({})
        \ && !empty(get(l:target, 'source', ''))
endfunction

function! s:registry_entry(bufnr, session, alias) abort
  let l:target = copy(get(a:session, 'target', {}))
  let l:target.alias = a:alias
  return {
        \ 'session_id': get(a:session, 'id', ''),
        \ 'kernel_id': get(a:session, 'kernel_id', ''),
        \ 'notebook_path': bufname(a:bufnr),
        \ 'expires_at': get(a:session, 'expires_at', ''),
        \ 'last_seen_at': strftime('%Y-%m-%dT%H:%M:%SZ'),
        \ 'target': l:target,
        \ }
endfunction

function! s:sync_attach_registry(bufnr, session) abort
  if !s:is_registry_trackable_session(a:session)
    return ''
  endif
  let l:state = get(a:session, 'state', '')
  if index(['connected', 'disconnected'], l:state) < 0
    return ''
  endif
  let l:registry = s:read_attach_registry()
  let l:alias = s:attach_registry_alias_for_session_data(l:registry, a:bufnr, a:session)
  let l:registry[l:alias] = s:registry_entry(a:bufnr, a:session, l:alias)
  call s:write_attach_registry(l:registry)
  call s:update_session(a:bufnr, {'attach_name': l:alias})
  return l:alias
endfunction

function! s:remove_attach_registry_session(session) abort
  let l:session_id = get(a:session, 'id', '')
  if empty(l:session_id)
    return
  endif
  let l:registry = s:read_attach_registry()
  let l:changed = 0
  for l:alias in keys(copy(l:registry))
    let l:entry = get(l:registry, l:alias, {})
    if type(l:entry) != type({})
      continue
    endif
    if get(l:entry, 'session_id', '') ==# l:session_id
      call remove(l:registry, l:alias)
      let l:changed = 1
    endif
  endfor
  if l:changed
    call s:write_attach_registry(l:registry)
  endif
endfunction

function! s:target_kind_from_value(value) abort
  if type(a:value) != type('') || empty(a:value)
    return ''
  endif
  let l:kind = matchstr(a:value, '^[A-Za-z0-9_+-]\+\ze://')
  return empty(l:kind) ? '' : l:kind
endfunction

function! s:session_target_kind(session) abort
  let l:target = get(a:session, 'target', {})
  let l:kind = get(l:target, 'kind', '')
  return tolower(type(l:kind) == type('') ? l:kind : '')
endfunction

function! s:session_supports_local_filesystem_actions(session) abort
  let l:kind = s:session_target_kind(a:session)
  return empty(l:kind) || index(['kernel', 'local', 'venv', 'connection_file'], l:kind) >= 0
endfunction

function! s:reject_local_filesystem_action(bufnr, action_name) abort
  let l:kind = s:session_target_kind(jusi#session#state(a:bufnr))
  let l:message = 'Cannot use local-only action "' . a:action_name . '" for non-local session target'
  if !empty(l:kind)
    let l:message .= ' kind "' . l:kind . '"'
  endif
  call s:reject_action(a:bufnr, {'last_action': 'handler_message'}, l:message)
  return 0
endfunction

function! s:normalize_target_config(alias, spec) abort
  let l:target = jusi#session#default_target()
  let l:target.alias = a:alias
  let l:target.source = 'start'
  if type(a:spec) == type('')
    let l:target.value = a:spec
    let l:target.kind = s:target_kind_from_value(a:spec)
    return l:target
  endif
  if type(a:spec) == type({})
    let l:target.config = copy(a:spec)
    let l:value = get(a:spec, 'value', get(a:spec, 'connection', get(a:spec, 'target', '')))
    let l:target.value = type(l:value) == type('') ? l:value : ''
    let l:target.kind = get(a:spec, 'kind', s:target_kind_from_value(l:target.value))
    return l:target
  endif
  let l:target.kind = 'kernel'
  return l:target
endfunction

function! s:resolve_start_target(kernel_name) abort
  let l:targets = s:kernel_targets_config()
  if has_key(l:targets, a:kernel_name)
    return s:normalize_target_config(a:kernel_name, l:targets[a:kernel_name])
  endif
  let l:target = jusi#session#default_target()
  let l:target.source = 'start'
  let l:target.alias = a:kernel_name
  let l:target.kind = 'kernel'
  return l:target
endfunction

function! s:resolve_attach_target(target) abort
  let l:entry = type(a:target) == type('') ? s:attach_registry_entry(a:target) : {}
  if !empty(l:entry)
    let l:target = s:registry_target(l:entry)
    let l:resolved = jusi#session#default_target()
    let l:resolved.source = 'attach'
    let l:resolved.alias = get(l:target, 'alias', '')
    let l:resolved.kind = get(l:target, 'kind', '')
    let l:resolved.value = get(l:target, 'value', '')
    let l:resolved.config = {'registry': 'attach'}
    return l:resolved
  endif
  let l:resolved = jusi#session#default_target()
  let l:resolved.source = 'attach'
  if type(a:target) == type({})
    let l:value = get(a:target, 'value', get(a:target, 'connection', get(a:target, 'target', '')))
    let l:resolved.value = type(l:value) == type('') ? l:value : ''
    let l:resolved.kind = get(a:target, 'kind', s:target_kind_from_value(l:resolved.value))
    let l:resolved.config = copy(a:target)
    let l:resolved.alias = get(a:target, 'alias', '')
    return l:resolved
  endif
  let l:resolved.value = type(a:target) == type('') ? a:target : ''
  let l:resolved.kind = s:target_kind_from_value(l:resolved.value)
  if empty(l:resolved.kind) && !empty(l:resolved.value)
    let l:resolved.kind = 'connection_file'
  endif
  return l:resolved
endfunction

function! s:is_probable_connection_file_target(target) abort
  if type(a:target) != type('') || empty(a:target)
    return 0
  endif
  if !empty(s:target_kind_from_value(a:target))
    return 0
  endif
  return a:target =~# '[/\\]'
        \ || a:target =~# '^\.\./'
        \ || a:target =~# '^\./'
        \ || a:target =~# '^\~[/\\]'
        \ || a:target =~# '\.json$'
endfunction

function! s:load_session_config_result() abort
  return jusi#config#load()
endfunction

function! s:load_visidatarc_result() abort
  return jusi#config#load_visidatarc()
endfunction

function! s:start_kernel_session(bufnr, kernel_name, target, action) abort
  let l:visidatarc_result = s:load_visidatarc_result()
  if !get(l:visidatarc_result, 'ok', 0)
    return s:reject_action(a:bufnr, {'last_action': a:action}, get(l:visidatarc_result, 'error', 'Failed to load VisiData config'))
  endif
  let l:request = {
        \ 'kernel_name': a:kernel_name,
        \ 'target': copy(a:target),
        \ 'visidatarc': get(l:visidatarc_result, 'content', ''),
        \ }
  call s:update_session(a:bufnr, {
        \ 'state': 'starting',
        \ 'kernel_name': a:kernel_name,
        \ 'target': copy(a:target),
        \ 'restart_request': {},
        \ 'expires_at': '',
        \ 'last_action': a:action,
        \ 'last_error': '',
        \ 'last_error_code': '',
        \ 'request': l:request,
        \ })
  let l:response = jusi#adapter#call('start', a:bufnr, l:request)
  call s:debug_log(a:bufnr, a:action . '-response', l:response)
  if get(l:response, 'ok', 0)
    if get(l:response, '_transport', 0) && !s:response_has_state_updates(l:response)
      return jusi#notebook#state(a:bufnr)
    endif
    return s:apply_response(a:bufnr, l:response, {'state': 'connected', 'last_action': a:action})
  endif
  return s:fail_session(a:bufnr, {
        \ 'last_action': a:action,
        \ 'kernel_name': a:kernel_name,
        \ 'target': copy(a:target),
        \ 'expires_at': '',
        \ 'last_error_code': get(l:response, 'error_code', ''),
        \ 'request': l:request,
        \ }, get(l:response, 'error', 'Failed to start kernel session'))
endfunction

function! s:is_restartable_session(session) abort
  return get(get(a:session, 'target', {}), 'source', '') ==# 'start'
        \ && !empty(get(a:session, 'kernel_name', ''))
endfunction

function! jusi#session#default_state() abort
  return {
        \ 'state': 'idle',
        \ 'backend': '',
        \ 'kernel_name': '',
        \ 'connection': '',
        \ 'attach_name': '',
        \ 'target': jusi#session#default_target(),
        \ 'expires_at': '',
        \ 'last_error': '',
        \ 'last_error_code': '',
        \ 'last_action': '',
        \ 'request': {},
        \ 'restart_request': {},
        \ 'palette': {},
        \ 'plugin_specs': {},
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

function! jusi#session#target(...) abort
  let l:session = jusi#session#state(a:0 >= 1 ? a:1 : bufnr('%'))
  if empty(l:session)
    return {}
  endif
  return get(l:session, 'target', jusi#session#default_target())
endfunction

function! jusi#session#complete_start(arglead, cmdline, cursorpos) abort
  let l:names = keys(s:kernel_targets_config())
  call sort(l:names)
  return filter(l:names, 'v:val =~# ''^'' . escape(a:arglead, ''\.^$~[]*'')')
endfunction

function! jusi#session#complete_attach(arglead, cmdline, cursorpos) abort
  let l:aliases = keys(s:read_attach_registry())
  call sort(l:aliases)
  return filter(l:aliases, 'v:val =~# ''^'' . escape(a:arglead, ''\.^$~[]*'')')
endfunction

function! jusi#session#attach_registry() abort
  return s:read_attach_registry()
endfunction

function! jusi#session#is_active(...) abort
  if a:0 >= 1 && type(a:1) == type({})
    let l:session = a:1
  else
    let l:session = jusi#session#state(a:0 >= 1 ? a:1 : bufnr('%'))
  endif
  if empty(l:session)
    return 0
  endif
  return index(['starting', 'connected', 'disconnected', 'stopping'], get(l:session, 'state', 'idle')) >= 0
endfunction

function! jusi#session#apply(...) abort
  if a:0 >= 1 && type(a:1) == type({})
    let l:bufnr = bufnr('%')
    let l:update = a:1
  else
    let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
    let l:update = a:0 >= 2 ? a:2 : {}
  endif
  let l:state = s:update_session(l:bufnr, l:update)
  if has_key(l:update, 'plugin_specs')
    call jusi#notebook#refresh_plugin_presentation(l:bufnr)
  endif
  return l:state
endfunction

function! jusi#session#apply_cell(cell_id, update, ...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  return s:update_cell(l:bufnr, a:cell_id, a:update)
endfunction

function! jusi#session#callback_session(update, ...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  let l:session = jusi#session#state(l:bufnr)
  if s:ignore_session_callback(l:session, a:update)
    call s:debug_log(l:bufnr, 'callback-session-ignored-inactive', a:update, l:session)
    return jusi#notebook#state(l:bufnr)
  endif
  let l:state = s:update_session(l:bufnr, a:update)
  let l:next_session = get(l:state, 'session', {})
  if get(l:next_session, 'state', '') ==# 'stopped'
    call s:remove_attach_registry_session(l:next_session)
  else
    call s:sync_attach_registry(l:bufnr, l:next_session)
  endif
  if has_key(a:update, 'plugin_specs')
    call jusi#notebook#refresh_plugin_presentation(l:bufnr)
  endif
  let l:restart_request = get(l:next_session, 'restart_request', {})
  if get(l:next_session, 'state', '') ==# 'stopped'
        \ && type(l:restart_request) == type({})
        \ && !empty(l:restart_request)
    call s:update_session(l:bufnr, {'restart_request': {}})
    return s:start_kernel_session(
          \ l:bufnr,
          \ get(l:restart_request, 'kernel_name', ''),
          \ copy(get(l:restart_request, 'target', jusi#session#default_target())),
          \ 'restart')
  endif
  return l:state
endfunction

function! jusi#session#callback_cell(cell_id, update, ...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  let l:update = s:apply_presentation_update(a:update)
  let l:session = jusi#session#state(l:bufnr)
  call s:debug_log(l:bufnr, 'callback-cell-begin', a:cell_id, l:update, l:session)
  if !s:accept_runtime_callbacks(l:session)
    call s:debug_log(l:bufnr, 'callback-cell-ignored-inactive', a:cell_id, l:update, l:session)
    return jusi#notebook#state(l:bufnr)
  endif
  let l:state = s:notebook_state(l:bufnr)
  let l:idx = empty(l:state) ? -1 : s:find_cell_index(l:state, a:cell_id)
  if l:idx >= 0
    let l:current_cell = l:state.cells[l:idx]
    let l:update = jusi#plugins#sanitize_cell_update(l:bufnr, l:current_cell, l:update)
    if get(get(l:current_cell, 'owner', {}), 'kind', '') ==# 'handler'
          \ && get(l:update, 'client_state', get(l:current_cell, 'client_state', '')) ==# 'shutdown'
          \ && get(l:update, 'client_bufnr', get(l:current_cell, 'client_bufnr', -1)) < 0
      let l:update = extend(copy(s:cell_close_final_update(l:current_cell)), l:update, 'force')
    endif
    if get(l:current_cell, 'client_bufnr', -1) > 0
      let l:validation = jusi#client#validate_attached_binding(
            \ l:bufnr,
            \ get(l:current_cell, 'id', 0),
            \ get(l:current_cell, 'client_id', ''),
            \ get(l:current_cell, 'client_bufnr', -1))
      if !get(l:validation, 'ok', 0)
        let l:recovered = jusi#client#recover_attached_buffer(
              \ l:bufnr,
              \ get(l:current_cell, 'id', 0),
              \ get(l:current_cell, 'client_id', ''))
        if l:recovered > 0
          let l:current_cell = s:repair_local_client_binding(
                \ l:bufnr,
                \ get(l:current_cell, 'id', 0),
                \ get(l:current_cell, 'client_id', ''),
                \ l:recovered)
        endif
      endif
    endif
    let l:update_bufnr = get(l:update, 'client_bufnr', -1)
    let l:update_client_id = get(l:update, 'client_id', '')
    let l:resolved_client_state = get(l:update, 'client_state', get(l:current_cell, 'client_state', ''))
    if has_key(l:update, 'client_bufnr')
          \ && l:update_bufnr > 0
          \ && l:update_bufnr !=# get(l:current_cell, 'client_bufnr', -1)
          \ && jusi#buffer#is_valid_bufnr(get(l:current_cell, 'client_bufnr', -1))
      let l:update.client_bufnr = l:current_cell.client_bufnr
      let l:update_bufnr = get(l:update, 'client_bufnr', -1)
    endif
    if has_key(l:update, 'client_bufnr')
          \ && l:update_bufnr < 0
          \ && jusi#buffer#is_valid_bufnr(get(l:current_cell, 'client_bufnr', -1))
          \ && !empty(l:update_client_id)
          \ && l:update_client_id ==# get(l:current_cell, 'client_id', '')
          \ && l:resolved_client_state ==# 'active'
      let l:update.client_bufnr = l:current_cell.client_bufnr
      let l:update_bufnr = l:update.client_bufnr
    endif
    if !empty(l:update_client_id)
          \ && !empty(get(l:current_cell, 'client_id', ''))
          \ && l:update_client_id !=# get(l:current_cell, 'client_id', '')
          \ && get(l:current_cell, 'client_state', '') ==# 'active'
      call s:debug_log(l:bufnr, 'callback-cell-ignored-stale-client', a:cell_id, l:update, l:current_cell)
      return jusi#notebook#state(l:bufnr)
    endif
    if !empty(l:update_client_id)
          \ && get(l:update, 'client_state', get(l:current_cell, 'client_state', '')) ==# 'active'
          \ && l:update_bufnr < 0
          \ && get(l:current_cell, 'client_bufnr', -1) < 0
      let l:update.client_bufnr = jusi#client#create_attached_buffer(l:bufnr, a:cell_id, l:update_client_id)
    endif
  endif
  let l:cell = s:update_cell(l:bufnr, a:cell_id, l:update)
  call s:debug_log(l:bufnr, 'callback-cell-end', a:cell_id, l:cell)
  return s:maybe_finalize_closed_cell(l:bufnr, l:cell)
endfunction

function! jusi#session#repair_local_client_binding(cell_id, client_id, client_bufnr, ...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  return s:repair_local_client_binding(l:bufnr, a:cell_id, a:client_id, a:client_bufnr)
endfunction

function! jusi#session#callback_healthcheck(payload, ...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  let l:payload = type(a:payload) == type({}) ? a:payload : {}
  let l:session = jusi#session#state(l:bufnr)
  call s:debug_log(l:bufnr, 'callback-healthcheck', l:payload, l:session)

  if get(l:session, 'state', 'idle') !=# 'connected'
    return l:session
  endif
  if empty(get(l:session, 'id', ''))
    return l:session
  endif
  if get(l:payload, 'session_id', '') !=# get(l:session, 'id', '')
    return l:session
  endif
  if empty(get(l:payload, 'healthcheck_id', ''))
    return l:session
  endif

  let l:response = jusi#adapter#call_async('healthcheck_reply', l:bufnr, {
        \ 'session_id': get(l:payload, 'session_id', ''),
        \ 'healthcheck_id': get(l:payload, 'healthcheck_id', ''),
        \ })
  call s:debug_log(l:bufnr, 'callback-healthcheck-reply', l:response)
  return l:session
endfunction

function! jusi#session#callback_client_updated(payload, ...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  let l:payload = type(a:payload) == type({}) ? a:payload : {}
  let l:session = jusi#session#state(l:bufnr)
  call s:debug_log(l:bufnr, 'callback-client-updated', l:payload, l:session)

  if get(l:session, 'state', 'idle') !=# 'connected'
    return l:session
  endif
  if empty(get(l:session, 'id', ''))
        \ || get(l:payload, 'session_id', '') !=# get(l:session, 'id', '')
        \ || empty(get(l:payload, 'client_id', ''))
    return l:session
  endif

  let l:state = s:notebook_state(l:bufnr)
  if empty(l:state)
    return l:session
  endif

  for l:cell in copy(get(l:state, 'cells', []))
    if get(l:cell, 'client_id', '') !=# get(l:payload, 'client_id', '')
          \ || get(l:cell, 'client_bufnr', -1) < 0
      continue
    endif
    let l:client_bufnr = l:cell.client_bufnr
    let l:revision = get(l:payload, 'revision', -1)
    if type(l:revision) == type(0)
          \ && l:revision >= 0
          \ && getbufvar(l:cell.client_bufnr, 'jusi_client_revision', -1) == l:revision
      return l:session
    endif
    call jusi#client#schedule_attached_refresh(
          \ l:bufnr,
          \ l:cell.id,
          \ get(l:cell, 'client_id', ''),
          \ l:cell.client_bufnr)
    return l:session
  endfor

  return l:session
endfunction

function! jusi#session#callback_handler_message(payload, ...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  let l:payload = type(a:payload) == type({}) ? a:payload : {}
  let l:session = jusi#session#state(l:bufnr)
  call s:debug_log(l:bufnr, 'callback-handler-message', l:payload, l:session)

  if get(l:session, 'state', 'idle') !=# 'connected'
    return l:session
  endif
  if empty(get(l:session, 'id', ''))
        \ || get(l:payload, 'session_id', '') !=# get(l:session, 'id', '')
        \ || empty(get(l:payload, 'client_id', ''))
        \ || empty(get(l:payload, 'handler_id', ''))
        \ || empty(get(l:payload, 'message_type', ''))
    return l:session
  endif

  let l:state = s:notebook_state(l:bufnr)
  if empty(l:state)
    return l:session
  endif

  for l:cell in copy(get(l:state, 'cells', []))
    if get(l:cell, 'client_id', '') !=# get(l:payload, 'client_id', '')
      continue
    endif
    let l:message_type = get(l:payload, 'message_type', '')
    if l:message_type ==# 'complete_result'
      call jusi#session#apply_handler_completion_result(
            \ l:bufnr,
            \ l:cell.id,
            \ get(l:payload, 'client_id', ''),
            \ get(l:payload, 'handler_id', ''),
            \ get(l:payload, 'payload', {}))
    elseif l:message_type ==# 'action_request'
      call s:handle_handler_action_request(
            \ l:bufnr,
            \ l:cell.id,
            \ get(l:payload, 'client_id', ''),
            \ get(l:payload, 'handler_id', ''),
            \ get(l:payload, 'payload', {}))
    endif
    let l:handler_update = {
          \ 'id': get(l:payload, 'handler_id', ''),
          \ 'last_message_type': l:message_type,
          \ 'payload': copy(get(l:payload, 'payload', {})),
          \ 'snapshot': get(get(l:cell, 'handler', {}), 'snapshot', {}),
          \ }
    if l:message_type ==# 'handler_snapshot'
      let l:handler_update.snapshot = extend(
            \ copy(l:handler_update.snapshot),
            \ copy(get(l:payload, 'payload', {})),
            \ 'force')
    endif
    if get(l:cell, 'client_bufnr', -1) > 0
      call jusi#client#record_handler_message(
            \ l:cell.client_bufnr,
            \ get(l:payload, 'handler_id', ''),
            \ l:message_type,
            \ get(l:payload, 'payload', {}))
      call jusi#client#apply_handler_terminal_message(
            \ l:cell.client_bufnr,
            \ l:message_type,
            \ get(l:payload, 'payload', {}))
    endif
    let l:cell = s:update_cell(l:bufnr, l:cell.id, {
          \ 'handler': l:handler_update,
          \ })
    return jusi#notebook#state(l:bufnr)
  endfor

  return l:session
endfunction

function! s:open_path_command(open_in) abort
  let l:open_in = tolower(type(a:open_in) == type('') ? a:open_in : '')
  if empty(l:open_in)
    return 'belowright split'
  endif
  let l:map = {
        \ 'current': 'edit',
        \ 'edit': 'edit',
        \ 'split': 'belowright split',
        \ 'hsplit': 'belowright split',
        \ 'vsplit': 'vertical belowright split',
        \ 'tab': 'tabedit',
        \ 'tabedit': 'tabedit',
        \ }
  return get(l:map, l:open_in, '')
endfunction

function! s:open_path_action(bufnr, payload) abort
  if type(a:payload) != type({})
    return 0
  endif
  if !s:session_supports_local_filesystem_actions(jusi#session#state(a:bufnr))
    return s:reject_local_filesystem_action(a:bufnr, 'open_path')
  endif
  let l:path = get(a:payload, 'path', '')
  if empty(l:path)
    return 0
  endif
  let l:cmd = s:open_path_command(get(a:payload, 'open_in', ''))
  if empty(l:cmd)
    return 0
  endif

  execute 'keepalt ' . l:cmd . ' ' . fnameescape(l:path)

  let l:line = str2nr(get(a:payload, 'line', 1))
  let l:column = str2nr(get(a:payload, 'column', 1))
  if l:line > 0
    call cursor(l:line, l:column > 0 ? l:column : 1)
  endif
  return 1
endfunction

function! s:setup_edit_path_buffer(bufnr) abort
  let l:bufnr = str2nr(a:bufnr)
  if l:bufnr <= 0 || !bufexists(l:bufnr)
    return 0
  endif
  augroup jusi_edit_path
    execute 'autocmd! * <buffer=' . l:bufnr . '>'
    execute 'autocmd BufHidden <buffer=' . l:bufnr . '> call jusi#session#finish_edit_path(' . l:bufnr . ')'
    execute 'autocmd BufUnload <buffer=' . l:bufnr . '> call jusi#session#finish_edit_path(' . l:bufnr . ')'
    execute 'autocmd BufWipeout <buffer=' . l:bufnr . '> call jusi#session#finish_edit_path(' . l:bufnr . ')'
  augroup END
  return 1
endfunction

function! s:send_edit_path_action_result(bufnr, ctx, ok) abort
  let l:bufnr = str2nr(a:bufnr)
  let l:ctx = type(a:ctx) == type({}) ? copy(a:ctx) : {}
  let l:request_id = get(l:ctx, 'request_id', '')
  let l:client_id = get(l:ctx, 'client_id', '')
  let l:handler_id = get(l:ctx, 'handler_id', '')
  if l:bufnr <= 0 || empty(l:request_id) || empty(l:client_id) || empty(l:handler_id)
    return 0
  endif
  if !s:require_notebook_buffer(l:bufnr, 'send edit_path action_result')
    return 0
  endif

  let l:session = jusi#session#state(l:bufnr)
  if get(l:session, 'state', '') !=# 'connected'
    call s:debug_log(l:bufnr, 'edit-path-action-result-skipped', {
          \ 'request_id': l:request_id,
          \ 'client_id': l:client_id,
          \ 'handler_id': l:handler_id,
          \ 'ok': a:ok ? 1 : 0,
          \ 'reason': 'session-not-connected',
          \ })
    return 0
  endif

  let l:response = jusi#adapter#call_async('handler_message', l:bufnr, {
        \ 'client_id': l:client_id,
        \ 'handler_id': l:handler_id,
        \ 'message_type': 'action_result',
        \ 'payload': {
        \   'request_id': l:request_id,
        \   'ok': a:ok ? v:true : v:false,
        \   },
        \ })
  call s:debug_log(l:bufnr, 'edit-path-action-result', {
        \ 'request_id': l:request_id,
        \ 'client_id': l:client_id,
        \ 'handler_id': l:handler_id,
        \ 'ok': a:ok ? 1 : 0,
        \ 'response_ok': get(l:response, 'ok', 0),
        \ })
  return get(l:response, 'ok', 0)
endfunction

function! s:edit_path_action(bufnr, cell_id, client_id, handler_id, payload) abort
  if type(a:payload) != type({})
    return 0
  endif
  let l:path = get(a:payload, 'path', '')
  let l:request_id = get(a:payload, 'request_id', '')
  if empty(l:path) || empty(l:request_id)
    return 0
  endif
  if !s:session_supports_local_filesystem_actions(jusi#session#state(a:bufnr))
    call s:reject_local_filesystem_action(a:bufnr, 'edit_path')
    call s:send_edit_path_action_result(a:bufnr, {
          \ 'client_id': a:client_id,
          \ 'handler_id': a:handler_id,
          \ 'request_id': l:request_id,
          \ }, v:false)
    return 0
  endif

  let l:cmd = s:open_path_command(get(a:payload, 'open_in', 'split'))
  if empty(l:cmd)
    return 0
  endif
  execute 'keepalt ' . l:cmd . ' ' . fnameescape(l:path)
  let l:edit_bufnr = bufnr('%')
  let l:line = str2nr(get(a:payload, 'line', 1))
  if l:line > 0
    call cursor(l:line, 1)
  endif
  call setbufvar(l:edit_bufnr, 'jusi_edit_path_request', {
        \ 'notebook_bufnr': a:bufnr,
        \ 'cell_id': a:cell_id,
        \ 'client_id': a:client_id,
        \ 'handler_id': a:handler_id,
        \ 'request_id': l:request_id,
        \ 'path': fnamemodify(l:path, ':p'),
        \ })
  call setbufvar(l:edit_bufnr, 'jusi_edit_path_done', 0)
  call s:setup_edit_path_buffer(l:edit_bufnr)
  return 1
endfunction

function! s:yank_text_action(payload) abort
  if type(a:payload) != type({})
    return 0
  endif
  let l:text = get(a:payload, 'text', '')
  if type(l:text) != type('')
    let l:text = string(l:text)
  endif
  call setreg('"', l:text, 'v')
  call setreg('0', l:text, 'v')
  return 1
endfunction

function! s:handle_handler_action_request(bufnr, cell_id, client_id, handler_id, payload) abort
  if type(a:payload) != type({})
    return 0
  endif
  let l:action_type = get(a:payload, 'action_type', '')
  let l:action_payload = get(a:payload, 'payload', {})
  if l:action_type ==# 'open_path'
    call s:debug_log(a:bufnr, 'handler-action-open-path', {
          \ 'cell_id': a:cell_id,
          \ 'client_id': a:client_id,
          \ 'handler_id': a:handler_id,
          \ 'payload': l:action_payload,
          \ })
    return s:open_path_action(a:bufnr, l:action_payload)
  endif
  if l:action_type ==# 'edit_path'
    call s:debug_log(a:bufnr, 'handler-action-edit-path', {
          \ 'cell_id': a:cell_id,
          \ 'client_id': a:client_id,
          \ 'handler_id': a:handler_id,
          \ 'payload': l:action_payload,
          \ })
    return s:edit_path_action(a:bufnr, a:cell_id, a:client_id, a:handler_id, l:action_payload)
  endif
  if l:action_type ==# 'yank_text'
    call s:debug_log(a:bufnr, 'handler-action-yank-text', {
          \ 'cell_id': a:cell_id,
          \ 'client_id': a:client_id,
          \ 'handler_id': a:handler_id,
          \ 'payload': l:action_payload,
          \ })
    return s:yank_text_action(l:action_payload)
  endif
  call s:debug_log(a:bufnr, 'handler-action-ignored', {
        \ 'cell_id': a:cell_id,
        \ 'client_id': a:client_id,
        \ 'handler_id': a:handler_id,
        \ 'action_type': l:action_type,
        \ 'payload': l:action_payload,
        \ })
  return 0
endfunction

function! jusi#session#send_handler_message(client_id, handler_id, message_type, payload, ...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'send handler message')
    return {}
  endif

  let l:session = jusi#session#state(l:bufnr)
  if get(l:session, 'state', 'idle') !=# 'connected'
    return s:fail_session(l:bufnr, {'last_action': 'handler_message'}, 'Cannot send handler message without a connected session')
  endif
  if empty(a:client_id) || empty(a:handler_id) || empty(a:message_type)
    return s:fail_session(l:bufnr, {'last_action': 'handler_message'}, 'Handler message requires client_id, handler_id, and message_type')
  endif

  let l:response = jusi#adapter#call_async('handler_message', l:bufnr, {
        \ 'client_id': a:client_id,
        \ 'handler_id': a:handler_id,
        \ 'message_type': a:message_type,
        \ 'payload': type(a:payload) == type({}) ? copy(a:payload) : a:payload,
        \ })
  if get(l:response, 'ok', 0)
    return l:response
  endif
  return s:fail_session(l:bufnr, {
        \ 'last_action': 'handler_message',
        \ }, get(l:response, 'error', 'Failed to send handler message'))
endfunction

function! jusi#session#finish_edit_path(bufnr) abort
  let l:bufnr = s:normalize_bufnr(a:bufnr)
  let l:ctx = getbufvar(l:bufnr, 'jusi_edit_path_request', {})
  if type(l:ctx) != type({}) || empty(l:ctx) || getbufvar(l:bufnr, 'jusi_edit_path_done', 0)
    return 0
  endif
  call setbufvar(l:bufnr, 'jusi_edit_path_done', 1)
  let l:notebook = str2nr(get(l:ctx, 'notebook_bufnr', 0))
  let l:ok = getbufvar(l:bufnr, '&modified') ? v:false : v:true
  return s:send_edit_path_action_result(l:notebook, l:ctx, l:ok)
endfunction

function! jusi#session#apply_handler_completion_result(bufnr, cell_id, client_id, handler_id, payload) abort
  let l:bufnr = s:normalize_bufnr(a:bufnr)
  let l:items = get(a:payload, 'items', [])
  if type(l:items) != type([])
    let l:items = []
  endif

  let l:vim_items = []
  let l:preview_startcol = -1
  for l:item in l:items
    if type(l:item) != type({})
      continue
    endif
    let l:value = get(l:item, 'value', '')
    if empty(l:value)
      continue
    endif
    let l:vim_item = {
          \ 'word': l:value,
          \ 'abbr': get(l:item, 'label', l:value),
          \ 'menu': get(l:item, 'detail', ''),
          \ 'info': get(l:item, 'documentation', ''),
          \ 'kind': get(l:item, 'kind', ''),
          \ }
    if has_key(l:item, 'start_col') || has_key(l:item, 'end_col')
      if l:preview_startcol < 0 && get(l:item, 'start_col', -1) >= 0
        let l:preview_startcol = get(l:item, 'start_col', -1) + 1
      endif
      let l:vim_item.user_data = json_encode({
            \ 'start_col': get(l:item, 'start_col', -1),
            \ 'end_col': get(l:item, 'end_col', -1),
            \ })
    endif
    call add(l:vim_items, l:vim_item)
  endfor

  call setbufvar(l:bufnr, 'jusi_handler_completion_result', {
        \ 'cell_id': a:cell_id,
        \ 'client_id': a:client_id,
        \ 'handler_id': a:handler_id,
        \ 'items': copy(l:vim_items),
        \ })

  let l:request_ctx = getbufvar(l:bufnr, 'jusi_handler_completion_request', {})

  if bufnr('%') != l:bufnr || mode() !~# '^[iR]'
    return copy(l:vim_items)
  endif

  let l:cell = jusi#notebook#cell_at_line(l:bufnr, line('.'))
  if empty(l:cell)
        \ || get(l:cell, 'id', 0) != a:cell_id
        \ || get(l:cell, 'client_id', '') !=# a:client_id
        \ || get(get(l:cell, 'handler', {}), 'id', '') !=# a:handler_id
    return copy(l:vim_items)
  endif

  let l:startcol = get(l:request_ctx, 'startcol', 0)
  if l:preview_startcol > 0
    let l:startcol = l:preview_startcol
  endif
  if get(l:request_ctx, 'cell_id', 0) != a:cell_id
        \ || get(l:request_ctx, 'client_id', '') !=# a:client_id
        \ || get(l:request_ctx, 'handler_id', '') !=# a:handler_id
        \ || l:startcol < 1
    let l:current_word = expand('<cword>')
    let l:startcol = col('.') - len(l:current_word)
    if l:startcol < 1
      let l:startcol = col('.')
    endif
  endif
  if !empty(l:vim_items)
    call complete(l:startcol, l:vim_items)
  endif
  return copy(l:vim_items)
endfunction

function! s:current_handler_context(bufnr) abort
  let l:session = jusi#session#state(a:bufnr)
  if get(l:session, 'state', 'idle') !=# 'connected'
    return {'ok': 0, 'error': 'Cannot send handler message without a connected session'}
  endif

  let l:cell = jusi#notebook#cell_at_line(a:bufnr, line('.'))
  if empty(l:cell)
    return {'ok': 0, 'error': 'Cannot send handler message without an active cell'}
  endif
  if get(get(l:cell, 'owner', {}), 'kind', '') !=# 'handler'
    return {'ok': 0, 'error': 'Current cell is not handler-owned'}
  endif

  let l:handler = get(l:cell, 'handler', {})
  let l:handler_id = get(l:handler, 'id', '')
  if empty(l:handler_id)
    return {'ok': 0, 'error': 'Current cell has no tracked handler id'}
  endif
  if empty(get(l:cell, 'client_id', ''))
    return {'ok': 0, 'error': 'Current cell has no tracked handler client id'}
  endif
  if get(l:cell, 'client_bufnr', -1) < 0
    return {'ok': 0, 'error': 'Current cell has no attached handler client buffer'}
  endif

  return {
        \ 'ok': 1,
        \ 'cell': l:cell,
        \ 'handler_id': l:handler_id,
        \ }
endfunction

function! s:completion_span_from_item(item) abort
  if type(a:item) != type({})
    return {}
  endif
  let l:user_data = get(a:item, 'user_data', '')
  if type(l:user_data) != type('') || empty(l:user_data)
    return {}
  endif
  try
    let l:decoded = json_decode(l:user_data)
  catch
    return {}
  endtry
  if type(l:decoded) != type({})
    return {}
  endif
  return l:decoded
endfunction

function! s:apply_completion_span(line_text, word, start_col, end_col) abort
  let l:start_col = a:start_col
  let l:end_col = a:end_col
  if l:start_col < 0 || l:end_col < l:start_col
    return a:line_text
  endif
  return strpart(a:line_text, 0, l:start_col) . a:word . strpart(a:line_text, l:end_col)
endfunction

function! jusi#session#handle_completion_done(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  if !s:is_notebook_buffer(l:bufnr)
    return 0
  endif
  let l:item = exists('v:completed_item') ? v:completed_item : {}
  if type(l:item) != type({}) || empty(l:item)
    return 0
  endif
  let l:span = s:completion_span_from_item(l:item)
  if empty(l:span)
    return 0
  endif

  let l:request_ctx = getbufvar(l:bufnr, 'jusi_handler_completion_request', {})
  if type(l:request_ctx) != type({}) || empty(l:request_ctx)
    return 0
  endif
  let l:start_col = get(l:span, 'start_col', -1)
  let l:end_col = get(l:span, 'end_col', -1)
  if l:start_col < 0 || l:end_col < l:start_col
    return 0
  endif

  let l:line_nr = get(l:request_ctx, 'line_nr', 0)
  let l:line_text = get(l:request_ctx, 'line_text', '')
  if l:line_nr <= 0
    return 0
  endif

  let l:new_line = s:apply_completion_span(l:line_text, get(l:item, 'word', ''), l:start_col, l:end_col)
  call setbufline(l:bufnr, l:line_nr, l:new_line)
  if bufnr('%') == l:bufnr && line('.') == l:line_nr
    call cursor(l:line_nr, l:start_col + len(get(l:item, 'word', '')) + 1)
  endif
  return 1
endfunction

function! jusi#session#send_handler_input_current(...) abort
  let l:bufnr = s:normalize_bufnr(bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'send handler input')
    return {}
  endif

  let l:ctx = s:current_handler_context(l:bufnr)
  if !get(l:ctx, 'ok', 0)
    return s:reject_action(l:bufnr, {'last_action': 'handler_message'}, get(l:ctx, 'error', 'Cannot send handler input'))
  endif

  let l:text = a:0 >= 1 && !empty(a:1) ? a:1 : input('handler> ')
  let l:cell = l:ctx.cell
  return jusi#session#send_handler_message(
        \ get(l:cell, 'client_id', ''),
        \ get(l:ctx, 'handler_id', ''),
        \ 'send_input',
        \ {'text': l:text},
        \ l:bufnr)
endfunction

function! s:cell_cursor_row(cell) abort
  return max([0, line('.') - get(a:cell, 'start', 0)])
endfunction

function! s:line_prefix_before_cursor() abort
  let l:line_text = getline('.')
  let l:cursor_col = col('.')
  if l:cursor_col <= 1
    return ''
  endif
  return strpart(l:line_text, 0, l:cursor_col - 1)
endfunction

function! s:current_word_before_cursor() abort
  return matchstr(s:line_prefix_before_cursor(), '\k\+$')
endfunction

function! s:completion_startcol() abort
  let l:current_word = s:current_word_before_cursor()
  let l:startcol = col('.') - len(l:current_word)
  return l:startcol < 1 ? col('.') : l:startcol
endfunction

function! s:handler_followup_payload(bufnr, cell) abort
  let l:cursor_row = s:cell_cursor_row(a:cell)
  let l:line_text = getline('.')
  return {
        \ 'cell_text': join(jusi#notebook#cell_main_lines(a:cell), "\n"),
        \ 'cursor_row': l:cursor_row,
        \ 'cursor_col': col('.'),
        \ 'line_text': l:line_text,
        \ 'current_word': s:current_word_before_cursor(),
        \ }
endfunction

function! jusi#session#send_handler_followup_current() abort
  let l:bufnr = s:normalize_bufnr(bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'send handler followup')
    return {}
  endif

  let l:ctx = s:current_handler_context(l:bufnr)
  if !get(l:ctx, 'ok', 0)
    return s:reject_action(l:bufnr, {'last_action': 'handler_message'}, get(l:ctx, 'error', 'Cannot send handler followup'))
  endif

  let l:cell = l:ctx.cell
  let l:response = jusi#session#send_handler_message(
        \ get(l:cell, 'client_id', ''),
        \ get(l:ctx, 'handler_id', ''),
        \ 'followup',
        \ s:handler_followup_payload(l:bufnr, l:cell),
        \ l:bufnr)
  if get(l:response, 'ok', 0) && get(l:cell, 'kind', '') ==# 'magic'
    call jusi#notebook#capture_history_and_fold_all(l:cell, l:bufnr)
  endif
  return l:response
endfunction

function! jusi#session#request_handler_completion_current() abort
  let l:bufnr = s:normalize_bufnr(bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'request handler completion')
    return {}
  endif

  let l:ctx = s:current_handler_context(l:bufnr)
  if !get(l:ctx, 'ok', 0)
    return s:reject_action(l:bufnr, {'last_action': 'handler_message'}, get(l:ctx, 'error', 'Cannot request handler completion'))
  endif

  let l:cell = l:ctx.cell
  let l:payload = s:handler_followup_payload(l:bufnr, l:cell)
  call setbufvar(l:bufnr, 'jusi_handler_completion_request', {
        \ 'cell_id': get(l:cell, 'id', 0),
        \ 'client_id': get(l:cell, 'client_id', ''),
        \ 'handler_id': get(l:ctx, 'handler_id', ''),
        \ 'current_word': get(l:payload, 'current_word', ''),
        \ 'startcol': s:completion_startcol(),
        \ 'line_nr': line('.'),
        \ 'line_text': getline('.'),
        \ })
  return jusi#session#send_handler_message(
        \ get(l:cell, 'client_id', ''),
        \ get(l:ctx, 'handler_id', ''),
        \ 'complete',
        \ l:payload,
        \ l:bufnr)
endfunction

function! jusi#session#sync_client_view(bufnr, cell_id, client_id, view) abort
  let l:bufnr = s:normalize_bufnr(a:bufnr)
  let l:state = s:notebook_state(l:bufnr)
  if empty(l:state)
    return {}
  endif
  let l:idx = s:find_cell_index(l:state, a:cell_id)
  if l:idx < 0
    return {}
  endif
  let l:cell = l:state.cells[l:idx]
  if get(l:cell, 'client_id', '') !=# a:client_id
    return l:cell
  endif

  let l:pending_input = s:pending_input_from_view(a:view)
  if s:pending_input_equal(get(l:cell, 'pending_input', {}), l:pending_input)
    return l:cell
  endif
  return s:update_cell(l:bufnr, a:cell_id, {'pending_input': l:pending_input})
endfunction

function! jusi#session#callback_response(response, ...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  let l:response = type(a:response) == type({}) ? a:response : {}
  let l:session_fallback = has_key(l:response, 'session') ? {} : {}
  let l:cell_update = get(l:response, 'cell', {})
  let l:cell_id = get(l:cell_update, 'id', 0)
  if l:cell_id > 0
    let l:cell_update = copy(l:cell_update)
    call remove(l:cell_update, 'id')
    return s:apply_response(l:bufnr, l:response, l:session_fallback, l:cell_update, l:cell_id)
  endif
  return s:apply_response(l:bufnr, l:response, l:session_fallback)
endfunction

function! jusi#session#set_connected(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  let l:update = a:0 >= 2 ? a:2 : {}
  let l:default_update = {
        \ 'state': 'connected',
        \ 'last_error': '',
        \ }
  return s:update_session(l:bufnr, extend(l:default_update, copy(l:update)))
endfunction

function! jusi#session#set_disconnected(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  return s:update_session(l:bufnr, {
        \ 'state': 'disconnected',
        \ 'expires_at': '',
        \ 'last_error': '',
        \ 'last_error_code': '',
        \ 'request': {},
        \ })
endfunction

function! jusi#session#set_stopped(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  return s:update_session(l:bufnr, {
        \ 'state': 'stopped',
        \ 'expires_at': '',
        \ 'last_error': '',
        \ 'last_error_code': '',
        \ 'request': {},
        \ })
endfunction

function! jusi#session#start(...) abort
  let l:bufnr = s:normalize_bufnr(bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'start')
    return {}
  endif

  let l:kernel_name = a:0 >= 1 && !empty(a:1) ? a:1 : 'python3'
  let l:config_result = s:load_session_config_result()
  if !get(l:config_result, 'ok', 0)
    return s:reject_action(l:bufnr, {'last_action': 'start'}, get(l:config_result, 'error', 'Failed to load Jusi config'))
  endif
  let l:target = jusi#config#merge_target_config(
        \ s:resolve_start_target(l:kernel_name),
        \ get(l:config_result, 'config', {}))
  let l:session = jusi#session#state(l:bufnr)
  if s:connected_session_state(l:session)
    return s:fail_session(l:bufnr, {'last_action': 'start'}, 'Kernel session is already active for this notebook')
  endif

  call s:clear_all_cell_runtime(l:bufnr)
  return s:start_kernel_session(l:bufnr, l:kernel_name, l:target, 'start')
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
  let l:config_result = s:load_session_config_result()
  if !get(l:config_result, 'ok', 0)
    return s:reject_action(l:bufnr, {'last_action': 'attach'}, get(l:config_result, 'error', 'Failed to load Jusi config'))
  endif
  let l:visidatarc_result = s:load_visidatarc_result()
  if !get(l:visidatarc_result, 'ok', 0)
    return s:reject_action(l:bufnr, {'last_action': 'attach'}, get(l:visidatarc_result, 'error', 'Failed to load VisiData config'))
  endif

  let l:registry_entry = type(a:target) == type('') ? s:attach_registry_entry(a:target) : {}
  if type(a:target) == type('')
        \ && empty(l:registry_entry)
        \ && empty(s:target_kind_from_value(a:target))
        \ && !s:is_probable_connection_file_target(a:target)
    return s:reject_action(l:bufnr, {'last_action': 'attach'}, 'Unknown attach target alias: ' . a:target)
  endif

  if !empty(l:registry_entry) && !empty(get(l:registry_entry, 'session_id', ''))
    let l:reconnect_target = jusi#config#merge_target_config(
          \ s:resolve_attach_target(a:target),
          \ get(l:config_result, 'config', {}))
    call s:update_session(l:bufnr, {
          \ 'state': 'starting',
          \ 'id': get(l:registry_entry, 'session_id', ''),
          \ 'attach_name': a:target,
          \ 'target': l:reconnect_target,
          \ 'expires_at': get(l:registry_entry, 'expires_at', ''),
          \ 'last_action': 'attach',
          \ 'last_error': '',
          \ 'last_error_code': '',
          \ 'request': {'session_id': get(l:registry_entry, 'session_id', '')},
          \ })
    let l:response = jusi#adapter#call('reconnect', l:bufnr, {'session': copy(jusi#session#state(l:bufnr))})
    if get(l:response, 'ok', 0)
      call s:clear_all_cell_runtime(l:bufnr)
      if get(l:response, '_transport', 0) && !s:response_has_state_updates(l:response)
        return jusi#notebook#state(l:bufnr)
      endif
      return s:apply_response(
            \ l:bufnr,
            \ l:response,
            \ {'state': 'connected', 'target': l:reconnect_target, 'attach_name': a:target})
    endif
    if index(['session_not_found', 'session_stopped', 'session_expired'], get(l:response, 'error_code', '')) >= 0
      call s:remove_attach_registry_session({'id': get(l:registry_entry, 'session_id', '')})
    endif
    if s:is_transport_failure(l:response)
      return s:reject_transport_failure(l:bufnr, {
            \ 'state': 'disconnected',
            \ 'id': get(l:registry_entry, 'session_id', ''),
            \ 'attach_name': a:target,
            \ 'target': l:reconnect_target,
            \ }, l:response, 'Failed to attach session')
    endif
    return s:fail_session(l:bufnr, {
          \ 'last_action': 'attach',
          \ 'id': get(l:registry_entry, 'session_id', ''),
          \ 'attach_name': a:target,
          \ 'target': l:reconnect_target,
          \ 'last_error_code': get(l:response, 'error_code', ''),
          \ }, get(l:response, 'error', 'Failed to attach session'))
  endif

  let l:resolved_target = jusi#config#merge_target_config(
        \ s:resolve_attach_target(a:target),
        \ get(l:config_result, 'config', {}))
  let l:request = {
        \ 'target': copy(l:resolved_target),
        \ 'visidatarc': get(l:visidatarc_result, 'content', ''),
        \ }
  call s:update_session(l:bufnr, {
        \ 'state': 'starting',
        \ 'attach_name': '',
        \ 'target': l:resolved_target,
        \ 'expires_at': '',
        \ 'last_action': 'attach',
        \ 'last_error': '',
        \ 'last_error_code': '',
          \ 'request': l:request,
          \ })
  let l:response = jusi#adapter#call('attach', l:bufnr, l:request)
  if get(l:response, 'ok', 0)
    call s:clear_all_cell_runtime(l:bufnr)
    if get(l:response, '_transport', 0) && !s:response_has_state_updates(l:response)
      call s:update_session(l:bufnr, {'target': l:resolved_target})
      return jusi#notebook#state(l:bufnr)
    endif
    return s:apply_response(
          \ l:bufnr,
          \ l:response,
          \ {'state': 'connected', 'connection': a:target, 'target': l:resolved_target})
  endif
  if s:is_transport_failure(l:response)
    return s:reject_transport_failure(l:bufnr, {
          \ 'state': get(l:session, 'state', 'idle'),
          \ 'id': get(l:session, 'id', ''),
          \ 'backend': get(l:session, 'backend', ''),
          \ 'kernel_name': get(l:session, 'kernel_name', ''),
          \ 'connection': get(l:session, 'connection', ''),
          \ 'attach_name': get(l:session, 'attach_name', ''),
          \ 'target': copy(get(l:session, 'target', jusi#session#default_target())),
          \ 'expires_at': get(l:session, 'expires_at', ''),
          \ 'last_action': 'attach',
          \ }, l:response, 'Failed to attach kernel session')
  endif
  return s:fail_session(l:bufnr, {
        \ 'last_action': 'attach',
        \ 'target': l:resolved_target,
        \ 'expires_at': '',
        \ 'last_error_code': get(l:response, 'error_code', ''),
        \ 'request': l:request,
        \ }, get(l:response, 'error', 'Failed to attach kernel session'))
endfunction

function! jusi#session#execute_current() abort
  let l:bufnr = s:normalize_bufnr(bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'execute')
    return {}
  endif

  call s:debug_log(l:bufnr, 'execute-begin', jusi#session#state(l:bufnr))

  call s:refresh_stale_cells(l:bufnr)

  let l:session = jusi#session#state(l:bufnr)
  call s:debug_log(l:bufnr, 'execute-after-refresh', l:session)
  if get(l:session, 'state', 'idle') !=# 'connected'
    if get(l:session, 'state', 'idle') ==# 'disconnected'
      return s:reject_action(l:bufnr, {'last_action': 'execute'}, 'Cannot execute while the session is disconnected; reconnect or attach first')
    endif
    return s:fail_session(l:bufnr, {'last_action': 'execute'}, 'Cannot execute cell without a connected session')
  endif

  let l:cell = jusi#notebook#cell_at_line(l:bufnr, line('.'))
  if empty(l:cell)
    return s:fail_session(l:bufnr, {'last_action': 'execute'}, 'Cannot execute without an active cell')
  endif
  if get(l:cell, 'status', '') ==# 'follow-up'
        \ && get(get(l:cell, 'owner', {}), 'kind', '') ==# 'handler'
    return jusi#session#send_handler_followup_current()
  endif
  let l:previous_cell = copy(l:cell)

  call s:update_session(l:bufnr, {
        \ 'state': 'connected',
        \ 'last_action': 'execute',
        \ 'last_error': '',
        \ 'request': {'cell_id': l:cell.id},
        \ })
  call s:release_disposable_cell_clients(l:bufnr, l:cell.id)
  let l:cell = jusi#notebook#cell_at_line(l:bufnr, line('.'))
  let l:cell = s:release_current_cell_client_for_execute(l:bufnr, l:session, l:cell)
  let l:cell_start = {
        \ 'status': 'busy',
        \ 'pending_input': {},
        \ 'client_id': '',
        \ 'client_state': 'shutdown',
        \ 'client_bufnr': -1,
        \ }
  call s:update_cell(l:bufnr, l:cell.id, l:cell_start)

  let l:response = jusi#adapter#call('execute', l:bufnr, {
        \ 'cell': {
        \   'id': l:cell.id,
        \   'kind': l:cell.kind,
        \   'syntax': l:cell.syntax,
        \   'main_lines': jusi#notebook#cell_main_lines(l:cell),
        \   },
        \ })
  if get(l:response, 'ok', 0)
    if get(l:cell, 'kind', '') ==# 'magic'
      call jusi#notebook#capture_history_and_fold_all(l:cell, l:bufnr)
    else
      call jusi#notebook#fold_all_history(l:bufnr)
    endif
    if get(l:response, '_transport', 0)
      return jusi#notebook#state(l:bufnr)
    endif
    return s:apply_response(
          \ l:bufnr,
          \ l:response,
          \ {'state': 'connected', 'request': {'cell_id': l:cell.id}},
          \ l:cell_start,
          \ l:cell.id)
  endif

  call s:update_cell(l:bufnr, l:cell.id, s:restore_cell_update(l:previous_cell))

  if s:is_transport_failure(l:response)
    return s:reject_transport_failure(l:bufnr, {
          \ 'last_action': 'execute',
          \ 'request': {'cell_id': l:cell.id},
          \ }, l:response, 'Failed to execute cell')
  endif

  return s:fail_session(l:bufnr, {
        \ 'last_action': 'execute',
        \ 'request': {'cell_id': l:cell.id},
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
    return s:reject_action(l:bufnr, {'last_action': 'interrupt'}, 'Cannot interrupt the current cell unless it is busy')
  endif

  let l:response = jusi#adapter#call('interrupt', l:bufnr, {'cell': copy(l:cell)})
  if get(l:response, 'ok', 0)
    if get(l:response, '_transport', 0)
      return jusi#notebook#state(l:bufnr)
    endif
    return s:apply_response(l:bufnr, l:response, {'state': 'connected'})
  endif
  if s:is_transport_failure(l:response)
    return s:reject_transport_failure(l:bufnr, {
          \ 'last_action': 'interrupt',
          \ }, l:response, 'Failed to interrupt current cell')
  endif
  return s:fail_session(l:bufnr, {
        \ 'last_action': 'interrupt',
        \ }, get(l:response, 'error', 'Failed to interrupt current cell'))
endfunction

function! jusi#session#interrupt() abort
  return jusi#session#interrupt_current()
endfunction

function! jusi#session#reply_input_current(...) abort
  let l:bufnr = s:normalize_bufnr(bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'reply to input')
    return {}
  endif

  let l:session = jusi#session#state(l:bufnr)
  if get(l:session, 'state', 'idle') !=# 'connected'
    return s:fail_session(l:bufnr, {'last_action': 'input_reply'}, 'Cannot reply to input without a connected session')
  endif

  let l:cell = jusi#notebook#cell_at_line(l:bufnr, line('.'))
  if empty(l:cell) || get(l:cell, 'status', '') !=# 'busy'
    return s:fail_session(l:bufnr, {'last_action': 'input_reply'}, 'Cannot reply to input unless the current cell is busy')
  endif

  let l:pending_input = copy(get(l:cell, 'pending_input', {}))
  if empty(l:pending_input)
    return s:fail_session(l:bufnr, {'last_action': 'input_reply'}, 'Current cell is not waiting for input')
  endif
  if empty(get(l:cell, 'client_id', ''))
    return s:fail_session(l:bufnr, {'last_action': 'input_reply'}, 'Cannot reply to input without a tracked client id')
  endif

  if a:0 >= 1
    let l:value = a:1
  else
    try
      let l:value = s:reply_input_prompt(l:pending_input)
    catch /^Vim:Interrupt$/
      return jusi#notebook#state(l:bufnr)
    endtry
  endif

  let l:response = jusi#adapter#call('input_reply', l:bufnr, {
        \ 'cell': copy(l:cell),
        \ 'client_id': get(l:cell, 'client_id', ''),
        \ 'value': l:value,
        \ })
  if get(l:response, 'ok', 0)
    call s:update_session(l:bufnr, {
          \ 'state': 'connected',
          \ 'last_action': 'input_reply',
          \ 'last_error': '',
          \ 'request': {'cell_id': l:cell.id},
          \ })
    call s:update_cell(l:bufnr, l:cell.id, {'pending_input': {}})
    if get(l:cell, 'client_bufnr', -1) > 0
      let l:current_cell = {}
      for l:item in get(getbufvar(l:bufnr, 'jusi_nb', {}), 'cells', [])
        if get(l:item, 'id', 0) == l:cell.id
          let l:current_cell = l:item
          break
        endif
      endfor
      call jusi#client#schedule_attached_refresh(
            \ l:bufnr,
            \ l:cell.id,
            \ get(l:cell, 'client_id', ''),
            \ l:cell.client_bufnr)
    endif
    return jusi#notebook#state(l:bufnr)
  endif
  if s:is_transport_failure(l:response)
    return s:reject_transport_failure(l:bufnr, {
          \ 'last_action': 'input_reply',
          \ }, l:response, 'Failed to reply to input')
  endif
  return s:fail_session(l:bufnr, {
        \ 'last_action': 'input_reply',
        \ }, get(l:response, 'error', 'Failed to reply to input'))
endfunction

function! jusi#session#close_current_client() abort
  let l:bufnr = s:normalize_bufnr(bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'close client')
    return {}
  endif

  let l:cell = jusi#notebook#cell_at_line(l:bufnr, line('.'))
  return s:close_cell_client(l:bufnr, l:cell)
endfunction

function! s:close_cell_client(bufnr, cell) abort
  let l:cell = a:cell
  if empty(l:cell)
    return s:reject_action(a:bufnr, {'last_action': 'close_client'}, 'Cannot close client without an attached client buffer')
  endif
  let l:client_bufnr = get(l:cell, 'client_bufnr', -1)
  let l:binding = jusi#client#validate_attached_binding(
        \ a:bufnr,
        \ l:cell.id,
        \ get(l:cell, 'client_id', ''),
        \ l:client_bufnr)
  if !get(l:binding, 'ok', 0)
    let l:recovered = jusi#client#recover_attached_buffer(
          \ a:bufnr,
          \ l:cell.id,
          \ get(l:cell, 'client_id', ''))
    if l:recovered > 0
      let l:cell = s:update_cell(a:bufnr, l:cell.id, {
            \ 'client_bufnr': l:recovered,
            \ 'client_state': 'active',
            \ })
      let l:client_bufnr = l:recovered
    endif
  endif
  if get(l:cell, 'client_bufnr', -1) < 0
    return s:reject_action(a:bufnr, {'last_action': 'close_client'}, 'Cannot close client without an attached client buffer')
  endif

  let l:session = jusi#session#state(a:bufnr)
  if get(l:session, 'state', 'idle') !=# 'connected'
        \ || !jusi#adapter#has('shutdown_client')
    if index(['busy', 'follow-up'], get(l:cell, 'status', '')) >= 0
      return s:reject_action(a:bufnr, {'last_action': 'close_client'}, 'Cannot close an active client without shutdown support')
    endif
    call jusi#client#destroy_buffer(l:client_bufnr)
    call s:update_session(a:bufnr, {
          \ 'last_action': 'close_client',
          \ 'last_error': '',
          \ 'request': {'cell_id': l:cell.id},
          \ })
    return s:update_cell(a:bufnr, l:cell.id, s:cell_close_final_update(l:cell))
  endif

  call s:update_session(a:bufnr, {
        \ 'last_action': 'close_client',
        \ 'last_error': '',
        \ 'request': {'cell_id': l:cell.id},
        \ })
  call s:update_cell(a:bufnr, l:cell.id, {
        \ 'close_requested': 1,
        \ 'client_state': 'shutting_down',
        \ })
  let l:request = {
        \ 'cell': copy(l:cell),
        \ 'client_id': get(l:cell, 'client_id', ''),
        \ 'reason': 'user_close',
        \ }
  let l:response = s:use_async_transport_shutdown(a:bufnr)
        \ ? jusi#adapter#call_async('shutdown_client', a:bufnr, l:request)
        \ : jusi#adapter#call('shutdown_client', a:bufnr, l:request)
  if get(l:response, 'ok', 0)
    if s:use_async_transport_shutdown(a:bufnr) || get(l:response, '_transport', 0)
      if l:client_bufnr > 0
        call jusi#client#detach_buffer(l:client_bufnr)
      endif
      let l:update = s:cell_close_final_update(l:cell)
      let l:update._preserve_local_buffer = l:client_bufnr > 0 ? 1 : 0
      return s:update_cell(a:bufnr, l:cell.id, l:update)
    endif
    if has_key(l:response, 'cell')
      call jusi#session#callback_response({
            \ 'session': extend({'state': 'connected', 'last_action': 'close_client'}, get(l:response, 'session', {})),
            \ 'cell': has_key(l:response, 'cell')
            \   ? get(l:response, 'cell', {})
            \   : {'id': l:cell.id},
            \ }, a:bufnr)
    endif
    let l:current = jusi#notebook#cell_by_id(l:cell.id, a:bufnr)
    return s:maybe_finalize_closed_cell(a:bufnr, l:current)
  endif

  call s:update_cell(a:bufnr, l:cell.id, {'close_requested': 0, 'client_state': 'active'})
  if s:is_transport_failure(l:response)
    return s:reject_transport_failure(a:bufnr, {
          \ 'last_action': 'close_client',
          \ }, l:response, 'Failed to close client')
  endif
  return s:fail_session(a:bufnr, {
        \ 'last_action': 'close_client',
        \ }, get(l:response, 'error', 'Failed to close client'))
endfunction

function! jusi#session#close_client_for_cell(cell_id, ...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'close client')
    return {}
  endif
  return s:close_cell_client(l:bufnr, jusi#notebook#cell_by_id(a:cell_id, l:bufnr))
endfunction

function! jusi#session#toggle_park_current_client() abort
  let l:bufnr = s:normalize_bufnr(bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'toggle parked client')
    return {}
  endif

  let l:cell = jusi#notebook#cell_at_line(l:bufnr, line('.'))
  if empty(l:cell) || get(l:cell, 'client_bufnr', -1) < 0
    return s:reject_action(l:bufnr, {'last_action': 'toggle_park'}, 'Cannot toggle parked state without an attached client buffer')
  endif
  if index(['busy', 'follow-up'], get(l:cell, 'status', '')) >= 0
    return s:reject_action(l:bufnr, {'last_action': 'toggle_park'}, 'Cannot park a busy or follow-up client')
  endif

  call s:update_session(l:bufnr, {
        \ 'last_action': 'toggle_park',
        \ 'last_error': '',
        \ 'request': {'cell_id': l:cell.id},
        \ })
  if get(l:cell, 'status', '') ==# 'parked'
    return s:update_cell(l:bufnr, l:cell.id, {
          \ 'status': empty(get(l:cell, 'parked_status', '')) ? 'done' : l:cell.parked_status,
          \ 'parked_status': '',
          \ })
  endif
  return s:update_cell(l:bufnr, l:cell.id, {
        \ 'status': 'parked',
        \ 'parked_status': get(l:cell, 'status', 'done'),
        \ })
endfunction

function! jusi#session#shutdown_cell_client(cell_id, reason, ...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'shutdown client')
    return {}
  endif

  let l:state = s:notebook_state(l:bufnr)
  let l:idx = s:find_cell_index(l:state, a:cell_id)
  if l:idx < 0
    return {}
  endif
  let l:cell = l:state.cells[l:idx]
  if empty(get(l:cell, 'client_id', '')) && get(l:cell, 'client_bufnr', -1) < 0
    return {}
  endif

  if s:can_shutdown_client(get(l:state, 'session', {}))
    call s:request_shutdown_client(
          \ l:bufnr,
          \ get(l:state, 'session', {}),
          \ a:cell_id,
          \ get(l:cell, 'client_id', ''),
          \ a:reason)
  endif

  if get(l:cell, 'client_bufnr', -1) > 0
    call jusi#client#destroy_buffer(l:cell.client_bufnr)
  endif
  return s:update_cell(l:bufnr, a:cell_id, {
        \ 'client_state': 'shutdown',
        \ 'client_bufnr': -1,
        \ 'close_requested': 0,
        \ })
endfunction

function! jusi#session#shutdown_all_clients(reason, ...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'shutdown clients')
    return {}
  endif

  let l:state = s:notebook_state(l:bufnr)
  for l:cell in copy(get(l:state, 'cells', []))
    call jusi#session#shutdown_cell_client(l:cell.id, a:reason, l:bufnr)
  endfor
  for l:info in getbufinfo()
    let l:managed_bufnr = get(l:info, 'bufnr', 0)
    if l:managed_bufnr <= 0
      continue
    endif
    if !getbufvar(l:managed_bufnr, 'jusi_client_managed', 0)
      continue
    endif
    if getbufvar(l:managed_bufnr, 'jusi_client_notebook_bufnr', -1) != l:bufnr
      continue
    endif
    call jusi#client#destroy_buffer(l:managed_bufnr)
  endfor
  return jusi#notebook#state(l:bufnr)
endfunction

function! jusi#session#disconnect(...) abort
  let l:bufnr = s:normalize_bufnr(bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'disconnect')
    return {}
  endif

  let l:session = jusi#session#state(l:bufnr)
  if get(l:session, 'state', 'idle') !=# 'connected'
    return s:fail_session(l:bufnr, {'last_action': 'disconnect'}, 'Cannot disconnect unless the session is connected')
  endif

  let l:reason = a:0 >= 1 && !empty(a:1) ? a:1 : 'user_requested'
  call s:update_session(l:bufnr, {
        \ 'last_action': 'disconnect',
        \ 'expires_at': '',
        \ 'last_error': '',
        \ 'last_error_code': '',
        \ 'request': {'reason': l:reason},
        \ })

  let l:response = jusi#adapter#call('disconnect', l:bufnr, {
        \ 'reason': l:reason,
        \ 'session': copy(l:session),
        \ })
  call s:debug_log(l:bufnr, 'disconnect-response', l:response)
  if get(l:response, 'ok', 0)
    if get(l:response, '_transport', 0) && !s:response_has_state_updates(l:response)
      return jusi#notebook#state(l:bufnr)
    endif
    return s:apply_response(l:bufnr, l:response, {
          \ 'state': 'disconnected',
          \ 'expires_at': '',
          \ 'last_error': l:reason,
          \ 'last_error_code': '',
          \ 'request': {},
          \ }, {})
  endif

  return s:fail_session(l:bufnr, {
        \ 'last_action': 'disconnect',
        \ 'last_error_code': get(l:response, 'error_code', ''),
        \ }, get(l:response, 'error', 'Failed to disconnect session'))
endfunction

function! jusi#session#reconnect() abort
  let l:bufnr = s:normalize_bufnr(bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'reconnect')
    return {}
  endif

  let l:session = jusi#session#state(l:bufnr)
  if get(l:session, 'state', 'idle') !=# 'disconnected'
    return s:fail_session(l:bufnr, {'last_action': 'reconnect'}, 'Can only reconnect a disconnected session')
  endif

  call s:update_session(l:bufnr, {
        \ 'state': 'starting',
        \ 'expires_at': '',
        \ 'last_action': 'reconnect',
        \ 'last_error': '',
        \ 'last_error_code': '',
        \ 'request': {'session_id': get(l:session, 'id', '')},
        \ })
  let l:request_session = copy(jusi#session#state(l:bufnr))
  let l:response = jusi#adapter#call('reconnect', l:bufnr, {'session': l:request_session})
  call s:debug_log(l:bufnr, 'reconnect-response', l:response)
  if get(l:response, 'ok', 0)
    if get(l:response, '_transport', 0) && !s:response_has_state_updates(l:response)
      return jusi#notebook#state(l:bufnr)
    endif
    return s:apply_response(l:bufnr, l:response, {'state': 'connected'}, {})
  endif

  if index(['session_not_found', 'session_stopped', 'session_expired'], get(l:response, 'error_code', '')) >= 0
    call s:remove_attach_registry_session(l:session)
  endif
  if s:is_transport_failure(l:response)
    return s:reject_transport_failure(l:bufnr, {
          \ 'state': 'disconnected',
          \ 'last_action': 'reconnect',
          \ 'last_error_code': get(l:response, 'error_code', ''),
          \ }, l:response, 'Failed to reconnect session')
  endif
  return s:fail_session(l:bufnr, {
        \ 'last_action': 'reconnect',
        \ 'last_error_code': get(l:response, 'error_code', ''),
        \ }, get(l:response, 'error', 'Failed to reconnect session'))
endfunction

function! jusi#session#restart() abort
  let l:bufnr = s:normalize_bufnr(bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'restart')
    return {}
  endif

  let l:session = jusi#session#state(l:bufnr)
  let l:state = get(l:session, 'state', 'idle')
  if index(['connected', 'stopped'], l:state) < 0
    if l:state ==# 'disconnected'
      return s:fail_session(l:bufnr, {'last_action': 'restart'}, 'Cannot restart while the session is disconnected; reconnect or start a new session instead')
    endif
    return s:fail_session(l:bufnr, {'last_action': 'restart'}, 'Cannot restart a session that is not restartable')
  endif
  if !s:is_restartable_session(l:session)
    return s:fail_session(l:bufnr, {'last_action': 'restart'}, 'Can only restart sessions started by JusiStartKernel')
  endif

  let l:kernel_name = get(l:session, 'kernel_name', '')
  let l:target = copy(get(l:session, 'target', jusi#session#default_target()))
  if empty(l:kernel_name)
    return s:fail_session(l:bufnr, {'last_action': 'restart'}, 'Cannot restart without a tracked kernel name')
  endif

  if l:state ==# 'connected'
    call s:update_session(l:bufnr, {
          \ 'restart_request': {
          \   'kernel_name': l:kernel_name,
          \   'target': copy(l:target),
          \   },
          \ })
    let l:stop_result = jusi#session#stop()
    let l:stopped_session = jusi#session#state(l:bufnr)
    if get(l:stopped_session, 'state', 'idle') ==# 'stopping'
      return l:stop_result
    endif
    if get(l:stopped_session, 'state', 'idle') !=# 'stopped'
      call s:update_session(l:bufnr, {'restart_request': {}})
      return l:stop_result
    endif
    call s:update_session(l:bufnr, {'restart_request': {}})
  endif

  call s:clear_all_cell_runtime(l:bufnr)
  return s:start_kernel_session(l:bufnr, l:kernel_name, l:target, 'restart')
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

  call jusi#session#shutdown_all_clients('session_stop', l:bufnr)
  call s:update_session(l:bufnr, {
        \ 'state': 'stopping',
        \ 'last_action': 'stop',
        \ 'last_error': '',
        \ })
  let l:response = jusi#adapter#call('stop', l:bufnr, {'session': copy(l:session)})
  if get(l:response, 'ok', 0)
    if get(l:response, '_transport', 0)
      return jusi#notebook#state(l:bufnr)
    endif
    return s:apply_response(l:bufnr, l:response, {'state': 'stopped', 'request': {}})
  endif
  return s:fail_session(l:bufnr, {
        \ 'last_action': 'stop',
        \ }, get(l:response, 'error', 'Failed to stop kernel session'))
endfunction
