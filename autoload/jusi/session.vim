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

function! s:debug_log(bufnr, message, ...) abort
  if !s:debug_log_enabled()
    return
  endif
  let l:path = get(g:, 'jusi_session_debug_log', '')
  let l:parts = [strftime('%Y-%m-%d %H:%M:%S'), 'bufnr=' . a:bufnr, a:message]
  for l:item in a:000
    call add(l:parts, s:debug_string(l:item))
  endfor
  call writefile([join(l:parts, ' | ')], l:path, 'a')
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

function! s:update_session(bufnr, update) abort
  let l:state = s:notebook_state(a:bufnr)
  if empty(l:state)
    return {}
  endif
  call s:debug_log(a:bufnr, 'update-session-begin', a:update, get(l:state, 'session', {}))
  let l:update = copy(a:update)
  let l:prepared_update = {}
  if has_key(l:update, 'prepared')
    let l:prepared = remove(l:update, 'prepared')
    if type(l:prepared) == type({})
      let l:prepared_update = s:normalize_prepared_update(l:prepared)
    endif
  endif
  let l:state.session = s:copy_update(l:state.session, l:update)
  call s:update_state(a:bufnr, l:state)
  if !empty(l:prepared_update)
    let l:result = s:update_prepared(a:bufnr, l:prepared_update)
    call s:debug_log(a:bufnr, 'update-session-end-with-prepared', get(l:result, 'session', {}))
    return l:result
  endif
  call s:debug_log(a:bufnr, 'update-session-end', get(l:state, 'session', {}))
  return l:state
endfunction

function! s:update_prepared(bufnr, update) abort
  let l:state = s:notebook_state(a:bufnr)
  if empty(l:state)
    return {}
  endif
  call s:debug_log(a:bufnr, 'update-prepared-begin', a:update, get(get(l:state, 'session', {}), 'prepared', {}))
  let l:update = copy(a:update)
  let l:preserve_local_buffer = get(l:update, '_preserve_local_buffer', 0)
  if has_key(l:update, '_preserve_local_buffer')
    call remove(l:update, '_preserve_local_buffer')
  endif
  let l:prepared = get(l:state.session, 'prepared', jusi#session#default_prepared_state())
  let l:state.session.prepared = s:copy_update(l:prepared, l:update)
  if has_key(l:state.session.prepared, 'client_id') && !has_key(l:state.session.prepared, 'id')
    let l:state.session.prepared.id = l:state.session.prepared.client_id
  endif
  if has_key(l:state.session.prepared, 'client_bufnr') && !has_key(l:state.session.prepared, 'bufnr')
    let l:state.session.prepared.bufnr = l:state.session.prepared.client_bufnr
  endif
  if get(l:prepared, 'bufnr', -1) > 0
        \ && get(l:state.session.prepared, 'bufnr', -1) < 0
        \ && !l:preserve_local_buffer
    call jusi#client#destroy_buffer(l:prepared.bufnr)
  endif
  call s:debug_log(a:bufnr, 'update-prepared-end', l:state.session.prepared)
  return s:update_state(a:bufnr, l:state)
endfunction

function! s:normalize_prepared_update(update) abort
  let l:update = copy(a:update)
  if has_key(l:update, 'client_id') && !has_key(l:update, 'id')
    let l:update.id = l:update.client_id
  endif
  if has_key(l:update, 'client_bufnr') && !has_key(l:update, 'bufnr')
    let l:update.bufnr = l:update.client_bufnr
  endif
  if !has_key(l:update, 'client_state') && has_key(l:update, 'state')
    let l:update.client_state = l:update.state ==# 'missing' ? 'shutdown' : 'active'
  endif
  return l:update
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
  let l:previous_bufnr = get(l:state.cells[l:idx], 'client_bufnr', -1)
  let l:update = copy(a:update)
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

  if get(l:state.cells[l:idx], 'client_bufnr', -1) > 0
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
  return l:state.cells[l:idx]
endfunction

function! s:cell_close_reset_update() abort
  return {
        \ 'client_state': 'shutdown',
        \ 'client_bufnr': -1,
        \ 'close_requested': 0,
        \ 'pending_input': {},
        \ 'parked_status': '',
        \ }
endfunction

function! s:cell_runtime_reset_update(cell) abort
  let l:update = extend(copy(s:cell_close_reset_update()), {
        \ 'client_id': '',
        \ 'owner': {'kind': ''},
        \ })
  let l:status = get(a:cell, 'status', 'initial')
  if index(['busy', 'parked', 'follow-up'], l:status) >= 0
    let l:update.status = 'initial'
  endif
  return l:update
endfunction

function! s:prepared_shutdown_update() abort
  return {
        \ 'state': 'missing',
        \ 'client_state': 'shutdown',
        \ 'bufnr': -1,
        \ }
endfunction

function! s:execute_consumed_prepared_update(prepared) abort
  return {
        \ 'id': '',
        \ 'state': 'missing',
        \ 'client_state': 'shutdown',
        \ 'bufnr': -1,
        \ '_preserve_local_buffer': 1,
        \ }
endfunction

function! s:execute_cell_start_update(cell, prepared) abort
  return {
        \ 'status': 'busy',
        \ 'pending_input': {},
        \ 'client_id': get(a:prepared, 'id', ''),
        \ 'client_state': 'active',
        \ 'client_bufnr': get(a:prepared, 'bufnr', -1),
        \ }
endfunction

function! s:restore_prepared_update(prepared) abort
  return {
        \ 'id': get(a:prepared, 'id', ''),
        \ 'state': get(a:prepared, 'state', 'missing'),
        \ 'client_state': get(a:prepared, 'client_state', 'shutdown'),
        \ 'bufnr': get(a:prepared, 'bufnr', -1),
        \ '_preserve_local_buffer': get(a:prepared, 'bufnr', -1) > 0 ? 1 : 0,
        \ }
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
  return s:update_cell(a:bufnr, a:cell.id, s:cell_close_reset_update())
endfunction

function! s:refresh_stale_prepared(bufnr) abort
  let l:session = jusi#session#state(a:bufnr)
  let l:prepared = get(l:session, 'prepared', jusi#session#default_prepared_state())
  call s:debug_log(a:bufnr, 'refresh-stale-prepared-begin', l:prepared)
  if get(l:prepared, 'bufnr', -1) < 0
    call s:debug_log(a:bufnr, 'refresh-stale-prepared-skip-no-buf', l:prepared)
    return l:prepared
  endif
  let l:missing_locally = !bufexists(l:prepared.bufnr)

  let l:validation = jusi#client#validate_prepared_binding(
        \ a:bufnr,
        \ get(l:prepared, 'id', ''),
        \ l:prepared.bufnr)
  if get(l:validation, 'ok', 0)
    call s:debug_log(a:bufnr, 'refresh-stale-prepared-valid', l:prepared)
    return l:prepared
  endif

  call s:debug_log(a:bufnr, 'refresh-stale-prepared-invalid', l:prepared, l:validation)
  if s:has_trustworthy_client_identity(l:session, get(l:prepared, 'id', ''))
    call s:request_shutdown_client(a:bufnr, l:session, 0, get(l:prepared, 'id', ''), 'healthcheck')
  endif
  let l:update = s:prepared_shutdown_update()
  if !l:missing_locally
    let l:update._preserve_local_buffer = 1
  endif
  call s:update_prepared(a:bufnr, l:update)
  call s:update_session(a:bufnr, {
        \ 'last_action': s:has_trustworthy_client_identity(l:session, get(l:prepared, 'id', ''))
        \   ? 'shutdown_client'
        \   : 'clear_client_binding',
        \ 'last_error': get(l:validation, 'message', 'Prepared client binding became inconsistent locally'),
        \ })
  call s:debug_log(a:bufnr, 'refresh-stale-prepared-cleared', jusi#session#prepared(a:bufnr))
  return jusi#session#prepared(a:bufnr)
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
  let l:session_update.last_error_code = get(l:session_update, 'last_error_code', '')
  call s:update_session(a:bufnr, l:session_update)
  let l:session = jusi#session#state(a:bufnr)
  if get(l:session, 'state', '') ==# 'stopped'
    call s:remove_attach_registry_session(l:session)
  else
    call s:sync_attach_registry(a:bufnr, l:session)
  endif

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

function! s:response_has_state_updates(response) abort
  return (has_key(a:response, 'session') && type(a:response.session) == type({}) && !empty(a:response.session))
        \ || (has_key(a:response, 'prepared') && type(a:response.prepared) == type({}) && !empty(a:response.prepared))
        \ || (has_key(a:response, 'cell') && type(a:response.cell) == type({}) && !empty(a:response.cell))
endfunction

function! jusi#session#default_prepared_state() abort
  return {
        \ 'id': '',
        \ 'state': 'missing',
        \ 'client_state': 'shutdown',
        \ 'bufnr': -1,
        \ }
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

function! jusi#session#target(...) abort
  let l:session = jusi#session#state(a:0 >= 1 ? a:1 : bufnr('%'))
  if empty(l:session)
    return {}
  endif
  return get(l:session, 'target', jusi#session#default_target())
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
  return s:update_session(l:bufnr, l:update)
endfunction

function! jusi#session#apply_prepared(...) abort
  if a:0 >= 1 && type(a:1) == type({})
    let l:bufnr = bufnr('%')
    let l:update = s:normalize_prepared_update(a:1)
  else
    let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
    let l:update = a:0 >= 2 ? s:normalize_prepared_update(a:2) : {}
  endif
  return s:update_prepared(l:bufnr, l:update)
endfunction

function! jusi#session#apply_cell(cell_id, update, ...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  return s:update_cell(l:bufnr, a:cell_id, a:update)
endfunction

function! jusi#session#callback_session(update, ...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  let l:state = s:update_session(l:bufnr, a:update)
  let l:session = get(l:state, 'session', {})
  if get(l:session, 'state', '') ==# 'stopped'
    call s:remove_attach_registry_session(l:session)
  else
    call s:sync_attach_registry(l:bufnr, l:session)
  endif
  return l:state
endfunction

function! jusi#session#callback_prepared(update, ...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  call s:debug_log(l:bufnr, 'callback-prepared-begin', a:update, jusi#session#prepared(l:bufnr))
  call s:refresh_stale_prepared(l:bufnr)
  let l:update = s:normalize_prepared_update(a:update)
  let l:state = s:update_prepared(l:bufnr, l:update)
  if empty(l:state)
    return {}
  endif
  if get(l:state.session.prepared, 'bufnr', -1) > 0
    call jusi#client#mark_prepared_buffer(
          \ l:bufnr,
          \ get(l:state.session.prepared, 'id', ''),
          \ l:state.session.prepared.bufnr)
  endif
  if get(l:state.session.prepared, 'state', '') ==# 'binding'
        \ && get(l:state.session.prepared, 'bufnr', -1) < 0
        \ && !empty(get(l:state.session.prepared, 'id', ''))
    call jusi#session#bind_prepared_client(l:bufnr)
    return jusi#notebook#state(l:bufnr)
  endif
  call s:debug_log(l:bufnr, 'callback-prepared-end', get(l:state, 'session', {}))
  return l:state
endfunction

function! jusi#session#callback_cell(cell_id, update, ...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  call s:refresh_stale_cells(l:bufnr)
  let l:cell = s:update_cell(l:bufnr, a:cell_id, a:update)
  return s:maybe_finalize_closed_cell(l:bufnr, l:cell)
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

function! jusi#session#set_disconnected(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  return s:update_session(l:bufnr, {
        \ 'state': 'disconnected',
        \ 'expires_at': '',
        \ 'last_error': '',
        \ 'last_error_code': '',
        \ 'request': {},
        \ 'prepared': jusi#session#default_prepared_state(),
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
        \ 'prepared': jusi#session#default_prepared_state(),
        \ })
endfunction

function! jusi#session#start(...) abort
  let l:bufnr = s:normalize_bufnr(bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'start')
    return {}
  endif

  let l:kernel_name = a:0 >= 1 && !empty(a:1) ? a:1 : 'python3'
  let l:target = s:resolve_start_target(l:kernel_name)
  let l:session = jusi#session#state(l:bufnr)
  if s:connected_session_state(l:session)
    return s:fail_session(l:bufnr, {'last_action': 'start'}, 'Kernel session is already active for this notebook')
  endif

  call s:clear_all_cell_runtime(l:bufnr)

  let l:request = {
        \ 'kernel_name': l:kernel_name,
        \ 'target': copy(l:target),
        \ }
  call s:update_session(l:bufnr, {
        \ 'state': 'starting',
        \ 'kernel_name': l:kernel_name,
        \ 'target': l:target,
        \ 'expires_at': '',
        \ 'last_action': 'start',
        \ 'last_error': '',
        \ 'last_error_code': '',
        \ 'request': l:request,
        \ 'prepared': jusi#session#default_prepared_state(),
        \ })
  let l:response = jusi#adapter#call('start', l:bufnr, l:request)
  call s:debug_log(l:bufnr, 'start-response', l:response)
  if get(l:response, 'ok', 0)
    if get(l:response, '_transport', 0) && !s:response_has_state_updates(l:response)
      return jusi#notebook#state(l:bufnr)
    endif
    return s:apply_response(l:bufnr, l:response, {'state': 'connected'}, jusi#session#default_prepared_state())
  endif
  return s:fail_session(l:bufnr, {
        \ 'last_action': 'start',
        \ 'kernel_name': l:kernel_name,
        \ 'target': l:target,
        \ 'expires_at': '',
        \ 'last_error_code': get(l:response, 'error_code', ''),
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

  call s:clear_all_cell_runtime(l:bufnr)

  let l:registry_entry = type(a:target) == type('') ? s:attach_registry_entry(a:target) : {}
  if !empty(l:registry_entry) && !empty(get(l:registry_entry, 'session_id', ''))
    let l:reconnect_target = s:resolve_attach_target(a:target)
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
          \ 'prepared': jusi#session#default_prepared_state(),
          \ })
    let l:response = jusi#adapter#call('reconnect', l:bufnr, {'session': copy(jusi#session#state(l:bufnr))})
    if get(l:response, 'ok', 0)
      if get(l:response, '_transport', 0) && !s:response_has_state_updates(l:response)
        return jusi#notebook#state(l:bufnr)
      endif
      return s:apply_response(
            \ l:bufnr,
            \ l:response,
            \ {'state': 'connected', 'target': l:reconnect_target, 'attach_name': a:target},
            \ jusi#session#default_prepared_state())
    endif
    if index(['session_not_found', 'session_stopped', 'session_expired'], get(l:response, 'error_code', '')) >= 0
      call s:remove_attach_registry_session({'id': get(l:registry_entry, 'session_id', '')})
    endif
    return s:fail_session(l:bufnr, {
          \ 'last_action': 'attach',
          \ 'id': get(l:registry_entry, 'session_id', ''),
          \ 'attach_name': a:target,
          \ 'target': l:reconnect_target,
          \ 'last_error_code': get(l:response, 'error_code', ''),
          \ 'prepared': jusi#session#default_prepared_state(),
          \ }, get(l:response, 'error', 'Failed to attach session'))
  endif

  let l:resolved_target = s:resolve_attach_target(a:target)
  let l:request = {'target': copy(l:resolved_target)}
  call s:update_session(l:bufnr, {
        \ 'state': 'starting',
        \ 'attach_name': '',
        \ 'target': l:resolved_target,
        \ 'expires_at': '',
        \ 'last_action': 'attach',
        \ 'last_error': '',
        \ 'last_error_code': '',
        \ 'request': l:request,
        \ 'prepared': jusi#session#default_prepared_state(),
        \ })
  let l:response = jusi#adapter#call('attach', l:bufnr, l:request)
  if get(l:response, 'ok', 0)
    if get(l:response, '_transport', 0) && !s:response_has_state_updates(l:response)
      call s:update_session(l:bufnr, {'target': l:resolved_target})
      return jusi#notebook#state(l:bufnr)
    endif
    return s:apply_response(
          \ l:bufnr,
          \ l:response,
          \ {'state': 'connected', 'connection': a:target, 'target': l:resolved_target},
          \ jusi#session#default_prepared_state())
  endif
  return s:fail_session(l:bufnr, {
        \ 'last_action': 'attach',
        \ 'target': l:resolved_target,
        \ 'expires_at': '',
        \ 'last_error_code': get(l:response, 'error_code', ''),
        \ 'request': l:request,
        \ 'prepared': jusi#session#default_prepared_state(),
        \ }, get(l:response, 'error', 'Failed to attach kernel session'))
endfunction

function! jusi#session#execute_current() abort
  let l:bufnr = s:normalize_bufnr(bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'execute')
    return {}
  endif

  call s:debug_log(l:bufnr, 'execute-begin', jusi#session#state(l:bufnr))

  call s:refresh_stale_prepared(l:bufnr)
  call s:refresh_stale_cells(l:bufnr)

  let l:session = jusi#session#state(l:bufnr)
  call s:debug_log(l:bufnr, 'execute-after-refresh', l:session)
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
  let l:previous_cell = copy(l:cell)

  call s:update_session(l:bufnr, {
        \ 'state': 'connected',
        \ 'last_action': 'execute',
        \ 'last_error': '',
        \ 'request': {'cell_id': l:cell.id},
        \ })
  call s:release_disposable_cell_clients(l:bufnr, l:cell.id)
  let l:cell = jusi#notebook#cell_at_line(l:bufnr, line('.'))
  let l:cell_start = s:execute_cell_start_update(l:cell, l:prepared)
  call s:update_prepared(l:bufnr, s:execute_consumed_prepared_update(l:prepared))
  call s:update_cell(l:bufnr, l:cell.id, l:cell_start)

  let l:response = jusi#adapter#call('execute', l:bufnr, {
        \ 'cell': {
        \   'id': l:cell.id,
        \   'kind': l:cell.kind,
        \   'syntax': l:cell.syntax,
        \   'main_lines': jusi#notebook#cell_main_lines(l:cell),
        \   },
        \ 'prepared': copy(l:prepared),
        \ })
  if get(l:response, 'ok', 0)
    if get(l:response, '_transport', 0)
      return jusi#notebook#state(l:bufnr)
    endif
    return s:apply_response(
          \ l:bufnr,
          \ l:response,
          \ {'state': 'connected', 'request': {'cell_id': l:cell.id}},
          \ jusi#session#default_prepared_state(),
          \ l:cell_start,
          \ l:cell.id)
  endif

  call s:update_prepared(l:bufnr, s:restore_prepared_update(l:prepared))
  call s:update_cell(l:bufnr, l:cell.id, s:restore_cell_update(l:previous_cell))

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
  if empty(l:cell) || index(['busy', 'follow-up'], get(l:cell, 'status', '')) < 0
    return s:fail_session(l:bufnr, {'last_action': 'interrupt'}, 'Cannot interrupt the current cell unless it is busy or in follow-up')
  endif

  let l:response = jusi#adapter#call('interrupt', l:bufnr, {'cell': copy(l:cell)})
  if get(l:response, 'ok', 0)
    if get(l:response, '_transport', 0)
      return jusi#notebook#state(l:bufnr)
    endif
    return s:apply_response(l:bufnr, l:response, {'state': 'connected'}, get(l:session, 'prepared', jusi#session#default_prepared_state()))
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
      call jusi#client#schedule_attached_refresh(
            \ l:bufnr,
            \ l:cell.id,
            \ get(l:cell, 'client_id', ''),
            \ l:cell.client_bufnr)
    endif
    return jusi#notebook#state(l:bufnr)
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
  if empty(l:cell) || get(l:cell, 'client_bufnr', -1) < 0
    return s:fail_session(l:bufnr, {'last_action': 'close_client'}, 'Cannot close client without an attached client buffer')
  endif

  let l:session = jusi#session#state(l:bufnr)
  if get(l:session, 'state', 'idle') !=# 'connected'
        \ || !jusi#adapter#has('shutdown_client')
    if index(['busy', 'follow-up'], get(l:cell, 'status', '')) >= 0
      return s:fail_session(l:bufnr, {'last_action': 'close_client'}, 'Cannot close an active client without shutdown support')
    endif
    call jusi#client#destroy_buffer(l:cell.client_bufnr)
    call s:update_session(l:bufnr, {
          \ 'last_action': 'close_client',
          \ 'last_error': '',
          \ 'request': {'cell_id': l:cell.id},
          \ })
    return s:update_cell(l:bufnr, l:cell.id, s:cell_close_reset_update())
  endif

  call s:update_session(l:bufnr, {
        \ 'last_action': 'close_client',
        \ 'last_error': '',
        \ 'request': {'cell_id': l:cell.id},
        \ })
  call s:update_cell(l:bufnr, l:cell.id, {
        \ 'close_requested': 1,
        \ 'client_state': 'shutting_down',
        \ })
  let l:response = jusi#adapter#call('shutdown_client', l:bufnr, {
        \ 'cell': copy(l:cell),
        \ 'client_id': get(l:cell, 'client_id', ''),
        \ 'reason': 'user_close',
        \ })
  if get(l:response, 'ok', 0)
    if get(l:response, '_transport', 0)
      return jusi#notebook#state(l:bufnr)
    endif
    if has_key(l:response, 'cell') || has_key(l:response, 'prepared')
      call jusi#session#callback_response({
            \ 'session': extend({'state': 'connected', 'last_action': 'close_client'}, get(l:response, 'session', {})),
            \ 'prepared': has_key(l:response, 'prepared')
            \   ? get(l:response, 'prepared', {})
            \   : get(l:session, 'prepared', jusi#session#default_prepared_state()),
            \ 'cell': has_key(l:response, 'cell')
            \   ? get(l:response, 'cell', {})
            \   : {'id': l:cell.id},
            \ }, l:bufnr)
    endif
    let l:current = jusi#notebook#cell_at_line(l:bufnr, line('.'))
    return s:maybe_finalize_closed_cell(l:bufnr, l:current)
  endif

  call s:update_cell(l:bufnr, l:cell.id, {'close_requested': 0, 'client_state': 'active'})
  return s:fail_session(l:bufnr, {
        \ 'last_action': 'close_client',
        \ }, get(l:response, 'error', 'Failed to close client'))
endfunction

function! jusi#session#toggle_park_current_client() abort
  let l:bufnr = s:normalize_bufnr(bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'toggle parked client')
    return {}
  endif

  let l:cell = jusi#notebook#cell_at_line(l:bufnr, line('.'))
  if empty(l:cell) || get(l:cell, 'client_bufnr', -1) < 0
    return s:fail_session(l:bufnr, {'last_action': 'toggle_park'}, 'Cannot toggle parked state without an attached client buffer')
  endif
  if index(['busy', 'follow-up'], get(l:cell, 'status', '')) >= 0
    return s:fail_session(l:bufnr, {'last_action': 'toggle_park'}, 'Cannot park a busy or follow-up client')
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

function! jusi#session#shutdown_prepared_client(reason, ...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'shutdown prepared client')
    return {}
  endif

  let l:session = jusi#session#state(l:bufnr)
  let l:prepared = get(l:session, 'prepared', jusi#session#default_prepared_state())
  if empty(get(l:prepared, 'id', '')) && get(l:prepared, 'bufnr', -1) < 0
    return {}
  endif

  if s:can_shutdown_client(l:session)
    call s:request_shutdown_client(
          \ l:bufnr,
          \ l:session,
          \ 0,
          \ get(l:prepared, 'id', ''),
          \ a:reason)
  endif

  if get(l:prepared, 'bufnr', -1) > 0
    call jusi#client#destroy_buffer(l:prepared.bufnr)
  endif
  return s:update_prepared(l:bufnr, s:prepared_shutdown_update())
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
  call jusi#session#shutdown_prepared_client(a:reason, l:bufnr)
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
  call s:update_prepared(l:bufnr, jusi#session#default_prepared_state())

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
          \ }, jusi#session#default_prepared_state())
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
        \ 'prepared': jusi#session#default_prepared_state(),
        \ })
  let l:request_session = copy(jusi#session#state(l:bufnr))
  let l:response = jusi#adapter#call('reconnect', l:bufnr, {'session': l:request_session})
  call s:debug_log(l:bufnr, 'reconnect-response', l:response)
  if get(l:response, 'ok', 0)
    if get(l:response, '_transport', 0) && !s:response_has_state_updates(l:response)
      return jusi#notebook#state(l:bufnr)
    endif
    return s:apply_response(l:bufnr, l:response, {'state': 'connected'}, jusi#session#default_prepared_state())
  endif

  if index(['session_not_found', 'session_stopped', 'session_expired'], get(l:response, 'error_code', '')) >= 0
    call s:remove_attach_registry_session(l:session)
  endif
  return s:fail_session(l:bufnr, {
        \ 'last_action': 'reconnect',
        \ 'last_error_code': get(l:response, 'error_code', ''),
        \ 'prepared': jusi#session#default_prepared_state(),
        \ }, get(l:response, 'error', 'Failed to reconnect session'))
endfunction

function! jusi#session#bind_prepared_client(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  if !s:require_notebook_buffer(l:bufnr, 'bind prepared client')
    return {}
  endif

  let l:session = jusi#session#state(l:bufnr)
  let l:prepared = get(l:session, 'prepared', jusi#session#default_prepared_state())
  if get(l:prepared, 'state', '') !=# 'binding'
    return l:session
  endif
  if empty(get(l:prepared, 'id', ''))
    return s:fail_session(l:bufnr, {'last_action': 'bind_prepared_client'}, 'Cannot bind a prepared client without a backend client id')
  endif

  let l:client_bufnr = get(l:prepared, 'bufnr', -1)
  if l:client_bufnr < 0
    let l:client_bufnr = jusi#client#create_prepared_buffer(l:bufnr, l:prepared.id)
    call s:debug_log(l:bufnr, 'bind-prepared-created-buffer', {'client_id': l:prepared.id, 'bufnr': l:client_bufnr})
    call s:update_prepared(l:bufnr, {'state': 'binding', 'bufnr': l:client_bufnr})
    let l:prepared = get(jusi#session#state(l:bufnr), 'prepared', l:prepared)
  endif

  if !jusi#adapter#has('bind_prepared_client')
    return jusi#notebook#state(l:bufnr)
  endif

  let l:response = jusi#adapter#call_async('bind_prepared_client', l:bufnr, {
        \ 'client_id': l:prepared.id,
        \ 'client_bufnr': l:client_bufnr,
        \ 'prepared': copy(l:prepared),
        \ 'session': copy(l:session),
        \ })
  call s:debug_log(l:bufnr, 'bind-prepared-response', l:response)
  if get(l:response, 'ok', 0)
    return jusi#notebook#state(l:bufnr)
  endif

  return s:fail_session(l:bufnr, {
        \ 'last_action': 'bind_prepared_client',
        \ }, get(l:response, 'error', 'Failed to bind prepared client'))
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
  call s:update_prepared(l:bufnr, {'state': 'missing', 'client_state': 'shutdown', 'bufnr': -1})
  let l:response = jusi#adapter#call('stop', l:bufnr, {'session': copy(l:session)})
  if get(l:response, 'ok', 0)
    if get(l:response, '_transport', 0)
      return jusi#notebook#state(l:bufnr)
    endif
    return s:apply_response(l:bufnr, l:response, {'state': 'stopped', 'request': {}}, jusi#session#default_prepared_state())
  endif
  return s:fail_session(l:bufnr, {
        \ 'last_action': 'stop',
        \ }, get(l:response, 'error', 'Failed to stop kernel session'))
endfunction
