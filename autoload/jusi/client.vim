function! jusi#client#prepared_name(notebook_bufnr, client_id) abort
  return '!jusi-prepared-client:' . a:notebook_bufnr . ':' . a:client_id
endfunction

function! s:is_valid_bufnr(bufnr) abort
  return type(a:bufnr) == type(0) && a:bufnr > 0 && bufexists(a:bufnr)
endfunction

function! s:native_terminal_debug_enabled() abort
  return type(get(g:, 'jusi_native_terminal_debug_log', 0)) == type('')
        \ && !empty(get(g:, 'jusi_native_terminal_debug_log', ''))
endfunction

function! s:native_terminal_debug(message, payload) abort
  if !s:native_terminal_debug_enabled()
    return
  endif
  let l:path = get(g:, 'jusi_native_terminal_debug_log', '')
  let l:parts = [strftime('%Y-%m-%d %H:%M:%S'), a:message, string(a:payload)]
  call writefile([join(l:parts, ' | ')], l:path, 'a')
endfunction

function! s:layout_command(layout) abort
  let l:layout = empty(a:layout) ? get(g:, 'jusi_client_layout', 'bsplit') : a:layout
  let l:map = {
        \ 'asplit': 'aboveleft split',
        \ 'Asplit': 'topleft split',
        \ 'bsplit': 'belowright split',
        \ 'Bsplit': 'botright split',
        \ 'rsplit': 'vertical belowright split',
        \ 'lsplit': 'vertical topleft split',
        \ 'tab': 'tab split',
        \ }
  return get(l:map, l:layout, l:map['bsplit'])
endfunction

function! s:native_terminal_transport(view) abort
  let l:transport = get(a:view, 'transport', {})
  return type(l:transport) == type({}) ? l:transport : {}
endfunction

function! s:is_native_terminal_view(view) abort
  let l:transport = s:native_terminal_transport(a:view)
  return get(l:transport, 'kind', '') ==# 'native_terminal'
endfunction

function! s:sanitize_terminal_env(env) abort
  if type(a:env) != type({})
    return {}
  endif
  let l:env = copy(a:env)
  for l:key in ['ROWS', 'COLUMNS', 'LINES']
    if has_key(l:env, l:key)
      call remove(l:env, l:key)
    endif
  endfor
  return l:env
endfunction

function! s:sanitize_native_terminal_transport(transport) abort
  if type(a:transport) != type({})
    return {}
  endif
  let l:transport = copy(a:transport)
  let l:attach_env = s:sanitize_terminal_env(get(l:transport, 'attach_env', {}))
  if has_key(l:attach_env, 'JUSI_TERMINAL_ENV_JSON')
    try
      let l:nested = json_decode(l:attach_env.JUSI_TERMINAL_ENV_JSON)
      let l:nested = s:sanitize_terminal_env(l:nested)
      let l:attach_env.JUSI_TERMINAL_ENV_JSON = json_encode(l:nested)
    catch
    endtry
  endif
  let l:transport.attach_env = l:attach_env
  return l:transport
endfunction

function! s:native_terminal_launcher() abort
  let l:launcher = get(g:, 'jusi_native_terminal_launcher', 0)
  return type(l:launcher) == type(function('tr')) ? l:launcher : function('s:launch_native_terminal_default')
endfunction

function! s:launch_native_terminal_default(notebook_bufnr, cell_id, client_id, transport) abort
  let l:cmd = get(a:transport, 'attach_cmd', [])
  let l:env = get(a:transport, 'attach_env', {})
  call s:native_terminal_debug('launch-default-begin', {
        \ 'notebook_bufnr': a:notebook_bufnr,
        \ 'cell_id': a:cell_id,
        \ 'client_id': a:client_id,
        \ 'cmd': l:cmd,
        \ 'env': l:env,
        \ })
  if !(type(l:cmd) == type([]) && !empty(l:cmd)) && !(type(l:cmd) == type('') && !empty(l:cmd))
    call s:native_terminal_debug('launch-default-invalid-cmd', l:cmd)
    return 0
  endif
  let l:source_winid = exists('*win_getid') ? win_getid() : 0
  execute s:layout_command(get(g:, 'jusi_client_layout', 'bsplit'))
  if has('nvim') && exists('*termopen')
    enew
    call termopen(l:cmd, {'env': type(l:env) == type({}) ? l:env : {}})
    let l:bufnr = bufnr('%')
  elseif exists('*term_start')
    let l:options = {'curwin': 1, 'term_finish': 'close'}
    if type(l:env) == type({})
      let l:options.env = l:env
    endif
    call term_start(l:cmd, l:options)
    let l:bufnr = bufnr('%')
  else
    let l:bufnr = 0
  endif
  if l:bufnr > 0
    call setbufvar(l:bufnr, '&bufhidden', 'hide')
  endif
  call s:native_terminal_debug('launch-default-end', {
        \ 'bufnr': l:bufnr,
        \ 'cmd': l:cmd,
        \ 'env': l:env,
        \ })
  if l:source_winid > 0
    call win_gotoid(l:source_winid)
  endif
  return l:bufnr
endfunction

function! s:ensure_native_terminal_buffer(notebook_bufnr, cell_id, client_id, client_bufnr, transport) abort
  let l:transport = s:sanitize_native_terminal_transport(a:transport)
  if s:is_valid_bufnr(a:client_bufnr)
        \ && getbufvar(a:client_bufnr, 'jusi_client_transport_kind', '') ==# 'native_terminal'
        \ && getbufvar(a:client_bufnr, 'jusi_client_id', '') ==# a:client_id
    call setbufvar(a:client_bufnr, 'jusi_client_transport', copy(l:transport))
    return a:client_bufnr
  endif
  let l:Launcher = s:native_terminal_launcher()
  let l:new_bufnr = call(l:Launcher, [a:notebook_bufnr, a:cell_id, a:client_id, l:transport])
  call s:native_terminal_debug('ensure-native-terminal-buffer', {
        \ 'notebook_bufnr': a:notebook_bufnr,
        \ 'cell_id': a:cell_id,
        \ 'client_id': a:client_id,
        \ 'old_bufnr': a:client_bufnr,
        \ 'new_bufnr': l:new_bufnr,
        \ 'transport': l:transport,
        \ })
  if type(l:new_bufnr) != type(0) || l:new_bufnr <= 0 || !bufexists(l:new_bufnr)
    return 0
  endif
  call jusi#client#mark_attached_buffer(a:notebook_bufnr, a:cell_id, a:client_id, l:new_bufnr)
  call setbufvar(l:new_bufnr, 'jusi_client_transport_kind', 'native_terminal')
  call setbufvar(l:new_bufnr, 'jusi_client_transport', copy(l:transport))
  call jusi#session#callback_cell(a:cell_id, {
        \ 'client_bufnr': l:new_bufnr,
        \ 'client_state': 'active',
        \ }, a:notebook_bufnr)
  if s:is_valid_bufnr(a:client_bufnr) && a:client_bufnr != l:new_bufnr
    call jusi#client#destroy_buffer(a:client_bufnr)
  endif
  return l:new_bufnr
endfunction

function! s:stop_refresh_timer(bufnr) abort
  if !s:is_valid_bufnr(a:bufnr)
    return
  endif
  let l:timer = getbufvar(a:bufnr, 'jusi_client_refresh_timer', -1)
  if type(l:timer) == type(0) && l:timer > 0 && exists('*timer_stop')
    call timer_stop(l:timer)
  endif
  call setbufvar(a:bufnr, 'jusi_client_refresh_timer', -1)
endfunction

function! s:terminal_render_delay_ms() abort
  return max([0, get(g:, 'jusi_terminal_render_delay_ms', 15)])
endfunction

function! s:terminal_sync_render() abort
  return get(g:, 'jusi_terminal_sync_render', 0) ? 1 : 0
endfunction

function! s:stop_terminal_render_timer(bufnr) abort
  if !s:is_valid_bufnr(a:bufnr)
    return
  endif
  let l:timer = getbufvar(a:bufnr, 'jusi_terminal_render_timer', -1)
  if type(l:timer) == type(0) && l:timer > 0 && exists('*timer_stop')
    call timer_stop(l:timer)
  endif
  call setbufvar(a:bufnr, 'jusi_terminal_render_timer', -1)
endfunction

function! s:flush_terminal_bytes(bufnr, ...) abort
  if !s:is_valid_bufnr(a:bufnr)
    return 0
  endif
  call setbufvar(a:bufnr, 'jusi_terminal_render_timer', -1)
  let l:hex = getbufvar(a:bufnr, 'jusi_terminal_pending_hex', '')
  if type(l:hex) != type('') || empty(l:hex)
    call setbufvar(a:bufnr, 'jusi_terminal_pending_hex', '')
    return 0
  endif
  call setbufvar(a:bufnr, 'jusi_terminal_pending_hex', '')
  return jusi#terminalscreen#apply_bytes(a:bufnr, l:hex)
endfunction

function! s:queue_terminal_bytes(bufnr, hex) abort
  if !s:is_valid_bufnr(a:bufnr)
    return 0
  endif
  let l:pending = getbufvar(a:bufnr, 'jusi_terminal_pending_hex', '')
  if type(l:pending) != type('')
    let l:pending = ''
  endif
  call setbufvar(a:bufnr, 'jusi_terminal_pending_hex', l:pending . a:hex)
  if s:terminal_sync_render() || !exists('*timer_start') || s:terminal_render_delay_ms() <= 0
    return s:flush_terminal_bytes(a:bufnr)
  endif
  let l:timer = getbufvar(a:bufnr, 'jusi_terminal_render_timer', -1)
  if type(l:timer) == type(0) && l:timer > 0
    return 1
  endif
  let l:timer = timer_start(s:terminal_render_delay_ms(), function('s:flush_terminal_bytes', [a:bufnr]))
  call setbufvar(a:bufnr, 'jusi_terminal_render_timer', l:timer)
  return 1
endfunction

function! jusi#client#stop_refresh(bufnr) abort
  call s:stop_refresh_timer(a:bufnr)
  return getbufvar(a:bufnr, 'jusi_client_refresh_timer', -1)
endfunction

function! s:set_managed_vars(bufnr, notebook_bufnr, client_id, role, ...) abort
  if !s:is_valid_bufnr(a:bufnr)
    return
  endif
  call setbufvar(a:bufnr, 'jusi_client_managed', 1)
  call setbufvar(a:bufnr, 'jusi_client_notebook_bufnr', a:notebook_bufnr)
  call setbufvar(a:bufnr, 'jusi_client_id', a:client_id)
  call setbufvar(a:bufnr, 'jusi_client_role', a:role)
  if a:0 >= 1
    call setbufvar(a:bufnr, 'jusi_client_cell_id', a:1)
  elseif getbufvar(a:bufnr, 'jusi_client_cell_id', 0) != 0
    call setbufvar(a:bufnr, 'jusi_client_cell_id', 0)
  endif
endfunction

function! jusi#client#create_prepared_buffer(notebook_bufnr, client_id) abort
  let l:name = jusi#client#prepared_name(a:notebook_bufnr, a:client_id)
  let l:bufnr = bufadd(l:name)
  call bufload(l:bufnr)
  call setbufvar(l:bufnr, '&buftype', 'nofile')
  call setbufvar(l:bufnr, '&bufhidden', 'hide')
  call setbufvar(l:bufnr, '&swapfile', 0)
  call setbufvar(l:bufnr, '&modifiable', 1)
  call setbufline(l:bufnr, 1, [''])
  call setbufvar(l:bufnr, '&modified', 0)
  call setbufvar(l:bufnr, 'jusi_client_refresh_timer', -1)
  call setbufvar(l:bufnr, 'jusi_terminal_render_timer', -1)
  call setbufvar(l:bufnr, 'jusi_terminal_pending_hex', '')
  call setbufvar(l:bufnr, 'jusi_client_revision', -1)
  call setbufvar(l:bufnr, 'jusi_client_title', '')
  call setbufvar(l:bufnr, 'jusi_client_execution_status', '')
  call setbufvar(l:bufnr, 'jusi_client_pending_input', {})
  call s:set_managed_vars(l:bufnr, a:notebook_bufnr, a:client_id, 'prepared')
  return l:bufnr
endfunction

function! jusi#client#mark_prepared_buffer(notebook_bufnr, client_id, bufnr) abort
  call s:set_managed_vars(a:bufnr, a:notebook_bufnr, a:client_id, 'prepared')
  return a:bufnr
endfunction

function! jusi#client#mark_attached_buffer(notebook_bufnr, cell_id, client_id, bufnr) abort
  call s:set_managed_vars(a:bufnr, a:notebook_bufnr, a:client_id, 'cell', a:cell_id)
  return a:bufnr
endfunction

function! jusi#client#record_handler_message(bufnr, handler_id, message_type, payload) abort
  if !s:is_valid_bufnr(a:bufnr)
    return 0
  endif
  call setbufvar(a:bufnr, 'jusi_handler_id', a:handler_id)
  call setbufvar(a:bufnr, 'jusi_handler_last_message_type', a:message_type)
  call setbufvar(a:bufnr, 'jusi_handler_last_payload', type(a:payload) == type({}) ? copy(a:payload) : a:payload)
  if a:message_type ==# 'handler_snapshot' && type(a:payload) == type({})
    call setbufvar(a:bufnr, 'jusi_handler_snapshot', copy(a:payload))
  endif
  return 1
endfunction

function! s:append_buffer_line(bufnr, line) abort
  if !s:is_valid_bufnr(a:bufnr)
    return 0
  endif
  let l:lines = getbufline(a:bufnr, 1, '$')
  if empty(l:lines)
    let l:lines = ['']
  endif
  if len(l:lines) == 1 && empty(l:lines[0])
    call setbufvar(a:bufnr, '&modifiable', 1)
    call setbufline(a:bufnr, 1, [a:line])
    call setbufvar(a:bufnr, '&modified', 0)
    call setbufvar(a:bufnr, '&modifiable', 0)
    return 1
  endif
  call setbufvar(a:bufnr, '&modifiable', 1)
  call appendbufline(a:bufnr, '$', [a:line])
  call setbufvar(a:bufnr, '&modified', 0)
  call setbufvar(a:bufnr, '&modifiable', 0)
  return 1
endfunction

function! s:set_last_buffer_line(bufnr, line) abort
  if !s:is_valid_bufnr(a:bufnr)
    return 0
  endif
  call setbufvar(a:bufnr, '&modifiable', 1)
  call setbufline(a:bufnr, '$', [a:line])
  call setbufvar(a:bufnr, '&modified', 0)
  call setbufvar(a:bufnr, '&modifiable', 0)
  return 1
endfunction

function! jusi#client#apply_handler_terminal_message(bufnr, message_type, payload) abort
  if !s:is_valid_bufnr(a:bufnr) || type(a:payload) != type({})
    return 0
  endif
  if getbufvar(a:bufnr, 'jusi_client_transport_kind', '') ==# 'native_terminal'
    return 0
  endif
  if a:message_type ==# 'terminal_bytes'
    return s:queue_terminal_bytes(a:bufnr, get(a:payload, 'hex', ''))
  endif
  let l:text = str2nr(0) is# 0 ? get(a:payload, 'text', '') : ''
  let l:text = type(l:text) == type('') ? l:text : ''
  if a:message_type ==# 'terminal_prompt'
    if empty(l:text)
      return 0
    endif
    let l:lines = getbufline(a:bufnr, 1, '$')
    if len(l:lines) == 1 && empty(l:lines[0])
      call s:set_last_buffer_line(a:bufnr, l:text)
    elseif empty(l:lines) || l:lines[-1] !=# l:text
      call s:append_buffer_line(a:bufnr, l:text)
    endif
    call setbufvar(a:bufnr, 'jusi_handler_terminal_prompt', l:text)
    return 1
  endif
  if a:message_type ==# 'terminal_input'
    if !get(g:, 'jusi_terminal_echo_input', 0)
      call setbufvar(a:bufnr, 'jusi_handler_terminal_prompt', '')
      return 1
    endif
    let l:prompt = getbufvar(a:bufnr, 'jusi_handler_terminal_prompt', '')
    if !empty(l:prompt) && getbufline(a:bufnr, '$')[0] ==# l:prompt
      call s:set_last_buffer_line(a:bufnr, l:prompt . l:text)
    elseif !empty(l:text)
      call s:append_buffer_line(a:bufnr, l:text)
    endif
    call setbufvar(a:bufnr, 'jusi_handler_terminal_prompt', '')
    return 1
  endif
  if a:message_type ==# 'terminal_output'
    if !empty(l:text)
      call s:append_buffer_line(a:bufnr, l:text)
    endif
    return 1
  endif
  return 0
endfunction

function! jusi#client#destroy_buffer(bufnr) abort
  if !s:is_valid_bufnr(a:bufnr)
    return 0
  endif
  if !getbufvar(a:bufnr, 'jusi_client_managed', 0)
    return 0
  endif
  call s:stop_refresh_timer(a:bufnr)
  call s:stop_terminal_render_timer(a:bufnr)
  execute 'silent! bwipeout! ' . a:bufnr
  return bufexists(a:bufnr) ? 0 : 1
endfunction

function! jusi#client#is_managed_buffer(bufnr) abort
  return s:is_valid_bufnr(a:bufnr) && getbufvar(a:bufnr, 'jusi_client_managed', 0)
endfunction

function! s:binding_mismatch(message) abort
  return {'ok': 0, 'message': a:message}
endfunction

function! jusi#client#validate_prepared_binding(notebook_bufnr, client_id, bufnr) abort
  if !s:is_valid_bufnr(a:bufnr)
    return s:binding_mismatch('Prepared client buffer is missing locally')
  endif
  if getbufvar(a:bufnr, 'jusi_client_notebook_bufnr', -1) != a:notebook_bufnr
    return s:binding_mismatch('Prepared client buffer belongs to another notebook')
  endif
  if getbufvar(a:bufnr, 'jusi_client_role', '') !=# 'prepared'
    return s:binding_mismatch('Prepared client buffer has inconsistent role metadata')
  endif
  if !empty(a:client_id) && getbufvar(a:bufnr, 'jusi_client_id', '') !=# a:client_id
    return s:binding_mismatch('Prepared client buffer has inconsistent client metadata')
  endif
  return {'ok': 1}
endfunction

function! jusi#client#validate_attached_binding(notebook_bufnr, cell_id, client_id, bufnr) abort
  if !s:is_valid_bufnr(a:bufnr)
    return s:binding_mismatch('Client buffer is missing locally')
  endif
  if getbufvar(a:bufnr, 'jusi_client_notebook_bufnr', -1) != a:notebook_bufnr
    return s:binding_mismatch('Client buffer belongs to another notebook')
  endif
  if getbufvar(a:bufnr, 'jusi_client_role', '') !=# 'cell'
    return s:binding_mismatch('Client buffer has inconsistent role metadata')
  endif
  if !empty(a:client_id) && getbufvar(a:bufnr, 'jusi_client_id', '') !=# a:client_id
    return s:binding_mismatch('Client buffer has inconsistent client metadata')
  endif
  if getbufvar(a:bufnr, 'jusi_client_cell_id', 0) != a:cell_id
    return s:binding_mismatch('Client buffer belongs to another cell')
  endif
  return {'ok': 1}
endfunction

function! jusi#client#recover_attached_buffer(notebook_bufnr, cell_id, client_id) abort
  for l:info in getbufinfo()
    let l:bufnr = get(l:info, 'bufnr', 0)
    if !s:is_valid_bufnr(l:bufnr)
      continue
    endif
    if getbufvar(l:bufnr, 'jusi_client_notebook_bufnr', -1) != a:notebook_bufnr
      continue
    endif
    if getbufvar(l:bufnr, 'jusi_client_role', '') !=# 'cell'
      continue
    endif
    if getbufvar(l:bufnr, 'jusi_client_cell_id', 0) == a:cell_id
      return l:bufnr
    endif
    if !empty(a:client_id) && getbufvar(l:bufnr, 'jusi_client_id', '') ==# a:client_id
      return l:bufnr
    endif
  endfor
  return 0
endfunction

function! s:notebook_cell(notebook_bufnr, cell_id) abort
  let l:state = getbufvar(a:notebook_bufnr, 'jusi_nb', {})
  for l:cell in get(l:state, 'cells', [])
    if get(l:cell, 'id', 0) == a:cell_id
      return l:cell
    endif
  endfor
  return {}
endfunction

function! s:normalize_client_view(response) abort
  if type(a:response) != type({})
    return {}
  endif
  if has_key(a:response, 'payload') && type(a:response.payload) == type({})
    return get(a:response.payload, 'client', {})
  endif
  return get(a:response, 'client', {})
endfunction

function! s:pending_input_from_view(view) abort
  if get(a:view, 'execution_status', '') !=# 'busy'
    return {}
  endif
  let l:lines = get(a:view, 'lines', [])
  let l:idx = len(l:lines) - 1
  while l:idx >= 0
    let l:line = l:lines[l:idx]
    if empty(l:line)
      let l:idx -= 1
      continue
    endif
    if l:line =~# '^input>\s*'
      return {
            \ 'prompt': matchstr(l:line, '^input>\s*\zs.*$'),
            \ 'password': 0,
            \ }
    endif
    if l:line =~# '^password>\s*'
      return {
            \ 'prompt': matchstr(l:line, '^password>\s*\zs.*$'),
            \ 'password': 1,
            \ }
    endif
    return {}
  endwhile
  return {}
endfunction

function! s:replace_buffer_lines(bufnr, lines) abort
  if !s:is_valid_bufnr(a:bufnr)
    return 0
  endif
  let l:lines = empty(a:lines) ? [''] : copy(a:lines)
  call setbufvar(a:bufnr, '&modifiable', 1)
  call setbufline(a:bufnr, 1, l:lines)
  let l:last = len(l:lines)
  if len(getbufline(a:bufnr, 1, '$')) > l:last
    if exists('*deletebufline')
      call deletebufline(a:bufnr, l:last + 1, '$')
    else
      let l:current = bufnr('%')
      execute 'noautocmd keepalt keepjumps sbuffer ' . a:bufnr
      execute (l:last + 1) . ',$delete _'
      if l:current > 0 && bufexists(l:current)
        execute 'noautocmd keepalt keepjumps buffer ' . l:current
      endif
    endif
  endif
  call setbufvar(a:bufnr, '&modified', 0)
  call setbufvar(a:bufnr, '&modifiable', 0)
  return 1
endfunction

function! s:client_should_poll(cell) abort
  if get(get(a:cell, 'owner', {}), 'kind', '') ==# 'handler'
    return 0
  endif
  return index(['busy', 'follow-up'], get(a:cell, 'status', '')) >= 0
        \ && get(a:cell, 'client_state', '') ==# 'active'
endfunction

function! s:refresh_delay_ms() abort
  return get(g:, 'jusi_client_poll_ms', 150)
endfunction

function! s:refresh_context(notebook_bufnr, cell_id, client_id, client_bufnr) abort
  if !bufexists(a:notebook_bufnr) || !s:is_valid_bufnr(a:client_bufnr)
    return {}
  endif
  let l:cell = s:notebook_cell(a:notebook_bufnr, a:cell_id)
  if empty(l:cell)
    return {}
  endif
  if get(l:cell, 'client_bufnr', -1) != a:client_bufnr
        \ || get(l:cell, 'client_id', '') !=# a:client_id
        \ || get(l:cell, 'client_state', '') !=# 'active'
    return {}
  endif
  let l:session = get(getbufvar(a:notebook_bufnr, 'jusi_nb', {}), 'session', {})
  if empty(get(l:session, 'id', '')) || get(l:session, 'state', 'idle') !=# 'connected'
    return {}
  endif
  return {'cell': l:cell, 'session': l:session}
endfunction

function! s:refresh_attached_now(notebook_bufnr, cell_id, client_id, client_bufnr) abort
  let l:ctx = s:refresh_context(a:notebook_bufnr, a:cell_id, a:client_id, a:client_bufnr)
  if empty(l:ctx)
    call s:stop_refresh_timer(a:client_bufnr)
    return {}
  endif

  let l:response = jusi#adapter#call('inspect_client', a:notebook_bufnr, {
        \ 'client_id': a:client_id,
        \ })
  if !get(l:response, 'ok', 0)
    return {}
  endif

  let l:view = s:normalize_client_view(l:response)
  if s:is_native_terminal_view(l:view)
    let l:transport = s:native_terminal_transport(l:view)
    let l:terminal_bufnr = s:ensure_native_terminal_buffer(a:notebook_bufnr, a:cell_id, a:client_id, a:client_bufnr, l:transport)
    if l:terminal_bufnr > 0
      call jusi#session#maybe_autobootstrap_cell(a:cell_id, a:notebook_bufnr)
      return l:view
    endif
  endif
  let l:revision = get(l:view, 'revision', -1)
  if l:revision != getbufvar(a:client_bufnr, 'jusi_client_revision', -1)
    let l:lines = get(l:view, 'lines', [])
    if empty(l:lines) && !empty(get(l:view, 'title', ''))
      let l:lines = [l:view.title]
    endif
    call s:replace_buffer_lines(a:client_bufnr, l:lines)
    call setbufvar(a:client_bufnr, 'jusi_client_revision', l:revision)
    call setbufvar(a:client_bufnr, 'jusi_client_title', get(l:view, 'title', ''))
    call setbufvar(a:client_bufnr, 'jusi_client_execution_status', get(l:view, 'execution_status', ''))
  endif
  call setbufvar(a:client_bufnr, 'jusi_client_pending_input', s:pending_input_from_view(l:view))
  call jusi#session#sync_client_view(a:notebook_bufnr, a:cell_id, a:client_id, l:view)

  if s:client_should_poll(l:ctx.cell) && exists('*timer_start')
    let l:timer = timer_start(s:refresh_delay_ms(), function('s:refresh_timer', [a:notebook_bufnr, a:cell_id, a:client_id, a:client_bufnr]))
    call setbufvar(a:client_bufnr, 'jusi_client_refresh_timer', l:timer)
  else
    call setbufvar(a:client_bufnr, 'jusi_client_refresh_timer', -1)
  endif
  return l:view
endfunction

function! s:refresh_timer(notebook_bufnr, cell_id, client_id, client_bufnr, timer) abort
  if s:is_valid_bufnr(a:client_bufnr) && getbufvar(a:client_bufnr, 'jusi_client_refresh_timer', -1) == a:timer
    call setbufvar(a:client_bufnr, 'jusi_client_refresh_timer', -1)
  endif
  call s:refresh_attached_now(a:notebook_bufnr, a:cell_id, a:client_id, a:client_bufnr)
endfunction

function! jusi#client#refresh_attached_view(notebook_bufnr, cell_id, client_id, client_bufnr) abort
  return s:refresh_attached_now(a:notebook_bufnr, a:cell_id, a:client_id, a:client_bufnr)
endfunction

function! jusi#client#schedule_attached_refresh(notebook_bufnr, cell_id, client_id, client_bufnr) abort
  if !s:is_valid_bufnr(a:client_bufnr)
    return 0
  endif
  call s:stop_refresh_timer(a:client_bufnr)
  if exists('*timer_start')
    let l:timer = timer_start(0, function('s:refresh_timer', [a:notebook_bufnr, a:cell_id, a:client_id, a:client_bufnr]))
    call setbufvar(a:client_bufnr, 'jusi_client_refresh_timer', l:timer)
    return l:timer
  endif
  call s:refresh_attached_now(a:notebook_bufnr, a:cell_id, a:client_id, a:client_bufnr)
  return 0
endfunction
