let s:transport = {}
let s:debug_clock = {'sec': localtime(), 'rel': reltime()}

function! s:debug_log_enabled() abort
  return type(get(g:, 'jusi_transport_debug_log', 0)) == type('')
        \ && !empty(get(g:, 'jusi_transport_debug_log', ''))
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
  let l:path = get(g:, 'jusi_transport_debug_log', '')
  let l:parts = [s:debug_timestamp(), 'bufnr=' . a:bufnr, a:message]
  for l:item in a:000
    call add(l:parts, s:debug_string(l:item))
  endfor
  call writefile([join(l:parts, ' | ')], l:path, 'a')
endfunction

function! s:envelope_log_summary(envelope) abort
  let l:payload = get(a:envelope, 'payload', {})
  let l:session = get(l:payload, 'session', {})
  let l:cell = get(l:payload, 'cell', {})
  let l:error = get(a:envelope, 'error', {})
  return {
        \ 'kind': get(a:envelope, 'kind', ''),
        \ 'type': get(a:envelope, 'type', ''),
        \ 'request_id': get(a:envelope, 'request_id', ''),
        \ 'ok': get(a:envelope, 'ok', ''),
        \ 'session_id': get(l:payload, 'session_id', get(l:session, 'id', '')),
        \ 'session_state': get(l:session, 'state', ''),
        \ 'cell_id': get(l:payload, 'cell_id', get(l:cell, 'id', '')),
        \ 'client_id': get(l:payload, 'client_id', get(l:cell, 'client_id', '')),
        \ 'handler_id': get(l:payload, 'handler_id', ''),
        \ 'message_type': get(l:payload, 'message_type', ''),
        \ 'error_code': type(l:error) == type({}) ? get(l:error, 'code', '') : '',
        \ 'error': type(l:error) == type({}) ? get(l:error, 'message', '') : l:error,
        \ }
endfunction

function! s:normalize_bufnr(bufnr) abort
  if a:bufnr is# 0 || a:bufnr is# ''
    return bufnr('%')
  endif
  return str2nr(a:bufnr)
endfunction

function! s:handler_funcref() abort
  let l:Handler = get(g:, 'jusi_transport_handler', 0)
  if type(l:Handler) == type(function('tr'))
    return l:Handler
  endif
  if type(l:Handler) == type('')
    try
      return function(l:Handler)
    catch
      return 0
    endtry
  endif
  return 0
endfunction

function! s:backend_cmd() abort
  return get(g:, 'jusi_backend_cmd', [])
endfunction

function! s:copy_cmd(cmd) abort
  if type(a:cmd) == type([])
    return copy(a:cmd)
  endif
  return a:cmd
endfunction

function! s:has_cmd(cmd) abort
  return (type(a:cmd) == type([]) && !empty(a:cmd))
        \ || (type(a:cmd) == type('') && !empty(a:cmd))
endfunction

function! s:same_cmd(left, right) abort
  return type(a:left) == type(a:right) && string(a:left) ==# string(a:right)
endfunction

function! s:has_backend_cmd() abort
  let l:cmd = s:backend_cmd()
  return s:has_cmd(l:cmd)
endfunction

function! s:default_python() abort
  if executable('python3')
    return 'python3'
  endif
  if executable('python')
    return 'python'
  endif
  return ''
endfunction

function! jusi#transport#default_backend_cmd() abort
  let l:python = s:default_python()
  let l:backend_src = fnamemodify(getcwd() . '/../jusi/src', ':p')
  if empty(l:python)
    return []
  endif
  if isdirectory(l:backend_src)
    return 'PYTHONPATH=' . shellescape(l:backend_src) . ' ' . l:python . ' -m jusi'
  endif
  return [l:python, '-m', 'jusi']
endfunction

function! s:target_value_body(value) abort
  if type(a:value) != type('')
    return ''
  endif
  return substitute(a:value, '^[A-Za-z0-9_+-]\+://', '', '')
endfunction

function! s:target_config(target) abort
  let l:config = get(a:target, 'config', {})
  return type(l:config) == type({}) ? l:config : {}
endfunction

function! s:target_config_string(target, ...) abort
  let l:config = s:target_config(a:target)
  for l:key in a:000
    let l:value = get(l:config, l:key, '')
    if type(l:value) == type('') && !empty(l:value)
      return l:value
    endif
  endfor
  return ''
endfunction

function! s:target_config_number(target, ...) abort
  let l:config = s:target_config(a:target)
  for l:key in a:000
    let l:value = get(l:config, l:key, '')
    if type(l:value) == type(0) && l:value > 0
      return l:value
    endif
    if type(l:value) == type('') && l:value =~# '^[1-9][0-9]*$'
      return str2nr(l:value)
    endif
  endfor
  return 0
endfunction

function! s:venv_python_path(venv_path) abort
  if empty(a:venv_path)
    return ''
  endif
  if has('win32') || has('win64')
    return fnamemodify(a:venv_path . '/Scripts/python.exe', ':p')
  endif
  return fnamemodify(a:venv_path . '/bin/python', ':p')
endfunction

function! s:target_python_cmd(target) abort
  let l:python = s:target_config_string(a:target, 'python')
  if empty(l:python)
    let l:python = 'python3'
  endif
  return [l:python, '-m', 'jusi']
endfunction

function! s:target_python_program(target) abort
  let l:kind = get(a:target, 'kind', '')
  if l:kind ==# 'venv'
    return s:venv_python_path(s:target_value_body(get(a:target, 'value', '')))
  endif
  let l:python = s:target_config_string(a:target, 'python')
  return empty(l:python) ? 'python3' : l:python
endfunction

function! s:ssh_host(target) abort
  let l:host = s:target_config_string(a:target, 'host')
  if empty(l:host)
    let l:value = s:target_value_body(get(a:target, 'value', ''))
    let l:host = split(l:value, '/', 1)[0]
  endif
  let l:user = s:target_config_string(a:target, 'user')
  if !empty(l:user) && l:host !~# '@'
    let l:host = l:user . '@' . l:host
  endif
  return l:host
endfunction

function! s:docker_container(target) abort
  let l:container = s:target_config_string(a:target, 'container', 'container_name')
  if !empty(l:container)
    return l:container
  endif
  let l:value = s:target_value_body(get(a:target, 'value', ''))
  if get(a:target, 'kind', '') ==# 'docker+ssh'
    let l:parts = split(l:value, '/', 1)
    return len(l:parts) >= 2 ? l:parts[1] : ''
  endif
  return l:value
endfunction

function! s:ssh_prefix(target) abort
  let l:host = s:ssh_host(a:target)
  if empty(l:host)
    return []
  endif
  let l:cmd = []
  let l:password = s:target_config_string(a:target, 'password')
  if !empty(l:password)
    call extend(l:cmd, ['sshpass', '-p', l:password])
  endif
  call add(l:cmd, 'ssh')
  let l:key_path = s:target_config_string(a:target, 'key_path', 'identity_file')
  if !empty(l:key_path)
    call extend(l:cmd, ['-i', l:key_path])
  endif
  let l:port = s:target_config_number(a:target, 'port')
  if l:port > 0
    call extend(l:cmd, ['-p', string(l:port)])
  endif
  call add(l:cmd, l:host)
  return l:cmd
endfunction

function! s:ssh_attach_prefix(target) abort
  let l:host = s:ssh_host(a:target)
  if empty(l:host)
    return []
  endif
  let l:cmd = []
  let l:password = s:target_config_string(a:target, 'password')
  if !empty(l:password)
    call extend(l:cmd, ['sshpass', '-p', l:password])
  endif
  call add(l:cmd, 'ssh')
  call add(l:cmd, '-tt')
  let l:key_path = s:target_config_string(a:target, 'key_path', 'identity_file')
  if !empty(l:key_path)
    call extend(l:cmd, ['-i', l:key_path])
  endif
  let l:port = s:target_config_number(a:target, 'port')
  if l:port > 0
    call extend(l:cmd, ['-p', string(l:port)])
  endif
  call add(l:cmd, l:host)
  return l:cmd
endfunction

function! s:attach_cmd_list(cmd) abort
  if type(a:cmd) == type([])
    return copy(a:cmd)
  endif
  return []
endfunction

function! s:attach_env_assignments(env) abort
  if type(a:env) != type({})
    return []
  endif
  let l:pairs = []
  for l:key in sort(keys(a:env))
    call add(l:pairs, l:key . '=' . get(a:env, l:key, ''))
  endfor
  return l:pairs
endfunction

function! s:host_terminal_env() abort
  let l:env = {}
  for l:key in ['TERM', 'COLORTERM']
    let l:value = exists('$' . l:key) ? eval('$' . l:key) : ''
    if type(l:value) == type('') && !empty(l:value)
      let l:env[l:key] = l:value
    endif
  endfor
  return l:env
endfunction

function! s:host_env_value(key) abort
  let l:value = exists('$' . a:key) ? eval('$' . a:key) : ''
  return type(l:value) == type('') ? l:value : ''
endfunction

function! s:venv_target_root(target) abort
  return s:target_value_body(get(a:target, 'value', ''))
endfunction

function! s:rewrite_exec_attach_child_env_for_target(target, child_env) abort
  let l:target = type(a:target) == type({}) ? a:target : {}
  let l:kind = get(l:target, 'kind', '')
  let l:child_env = type(a:child_env) == type({}) ? copy(a:child_env) : {}
  if index(['', 'kernel', 'local', 'connection_file', 'venv'], l:kind) < 0
    return l:child_env
  endif

  let l:rewritten = {}
  for [l:key, l:value] in items(l:child_env)
    if l:key =~# '^JUSI_'
      let l:rewritten[l:key] = l:value
    endif
  endfor
  for l:key in ['TERM', 'COLORTERM', 'LANG', 'LC_ALL', 'LC_CTYPE', 'HOME', 'PYTHONPATH']
    let l:value = s:host_env_value(l:key)
    if !empty(l:value)
      let l:rewritten[l:key] = l:value
    endif
  endfor
  let l:path = s:host_env_value('PATH')
  if l:kind ==# 'venv'
    let l:venv_root = s:venv_target_root(l:target)
    let l:venv_bin = fnamemodify(s:venv_python_path(l:venv_root), ':h')
    if !empty(l:venv_root)
      let l:rewritten.VIRTUAL_ENV = l:venv_root
    endif
    if !empty(l:venv_bin)
      let l:rewritten.PATH = empty(l:path) ? l:venv_bin : l:venv_bin . ':' . l:path
    elseif !empty(l:path)
      let l:rewritten.PATH = l:path
    endif
  elseif !empty(l:path)
    let l:rewritten.PATH = l:path
  endif
  return l:rewritten
endfunction

function! s:docker_attach_env(env) abort
  let l:env = type(a:env) == type({}) ? copy(a:env) : {}
  for [l:key, l:value] in items(s:host_terminal_env())
    if !has_key(l:env, l:key)
      let l:env[l:key] = l:value
    endif
  endfor
  return l:env
endfunction

function! s:terminal_attach_cmd_for_venv(target, attach_cmd) abort
  let l:cmd = s:attach_cmd_list(a:attach_cmd)
  if empty(l:cmd)
    return []
  endif
  let l:python = s:target_python_program(a:target)
  if empty(l:python)
    return []
  endif
  let l:cmd[0] = l:python
  return l:cmd
endfunction

function! jusi#transport#terminal_attach_spec_for_target(target, attach_cmd, attach_env) abort
  let l:target = type(a:target) == type({}) ? a:target : {}
  let l:kind = get(l:target, 'kind', '')
  let l:attach_cmd = s:attach_cmd_list(a:attach_cmd)
  let l:attach_env = type(a:attach_env) == type({}) ? copy(a:attach_env) : {}

  if empty(l:attach_cmd)
    return {'cmd': [], 'env': {}}
  endif

  if empty(l:kind) || index(['kernel', 'local', 'connection_file'], l:kind) >= 0
    return {'cmd': l:attach_cmd, 'env': l:attach_env}
  endif

  if l:kind ==# 'venv'
    return {'cmd': s:terminal_attach_cmd_for_venv(l:target, l:attach_cmd), 'env': l:attach_env}
  endif

  if l:kind ==# 'ssh'
    let l:prefix = s:ssh_attach_prefix(l:target)
    if empty(l:prefix)
      return {'cmd': [], 'env': {}}
    endif
    return {'cmd': l:prefix + ['env'] + s:attach_env_assignments(l:attach_env) + l:attach_cmd, 'env': {}}
  endif

  if l:kind ==# 'docker'
    let l:container = s:docker_container(l:target)
    if empty(l:container)
      return {'cmd': [], 'env': {}}
    endif
    let l:attach_env = s:docker_attach_env(l:attach_env)
    let l:cmd = ['docker', 'exec', '-it']
    for l:pair in s:attach_env_assignments(l:attach_env)
      call extend(l:cmd, ['-e', l:pair])
    endfor
    call add(l:cmd, l:container)
    call extend(l:cmd, l:attach_cmd)
    return {'cmd': l:cmd, 'env': {}}
  endif

  if l:kind ==# 'docker+ssh'
    let l:prefix = s:ssh_attach_prefix(l:target)
    let l:container = s:docker_container(l:target)
    if empty(l:prefix) || empty(l:container)
      return {'cmd': [], 'env': {}}
    endif
    let l:attach_env = s:docker_attach_env(l:attach_env)
    let l:cmd = l:prefix + ['docker', 'exec', '-it']
    for l:pair in s:attach_env_assignments(l:attach_env)
      call extend(l:cmd, ['-e', l:pair])
    endfor
    call add(l:cmd, l:container)
    call extend(l:cmd, l:attach_cmd)
    return {'cmd': l:cmd, 'env': {}}
  endif

  return {'cmd': l:attach_cmd, 'env': l:attach_env}
endfunction

function! jusi#transport#rewrite_native_terminal_attach_env_for_target(target, attach_env) abort
  let l:target = type(a:target) == type({}) ? a:target : {}
  let l:kind = get(l:target, 'kind', '')
  let l:attach_env = type(a:attach_env) == type({}) ? copy(a:attach_env) : {}

  if has_key(l:attach_env, 'JUSI_TERMINAL_CMD_JSON')
    try
      let l:command = json_decode(l:attach_env.JUSI_TERMINAL_CMD_JSON)
      if type(l:command) == type([])
        if l:kind ==# 'venv'
          let l:command = s:terminal_attach_cmd_for_venv(l:target, l:command)
        endif
        let l:attach_env.JUSI_TERMINAL_CMD_JSON = json_encode(l:command)
      endif
    catch
    endtry
  endif

  if has_key(l:attach_env, 'JUSI_TERMINAL_ENV_JSON')
    try
      let l:child_env = json_decode(l:attach_env.JUSI_TERMINAL_ENV_JSON)
      let l:child_env = s:rewrite_exec_attach_child_env_for_target(l:target, l:child_env)
      let l:attach_env.JUSI_TERMINAL_ENV_JSON = json_encode(l:child_env)
    catch
    endtry
  endif

  return l:attach_env
endfunction

function! jusi#transport#backend_cmd_for_target(target) abort
  let l:target = type(a:target) == type({}) ? a:target : {}
  let l:kind = get(l:target, 'kind', '')

  if l:kind ==# 'local'
    return jusi#transport#default_backend_cmd()
  endif

  if l:kind ==# 'venv'
    let l:python = s:venv_python_path(s:target_value_body(get(l:target, 'value', '')))
    return empty(l:python) ? [] : [l:python, '-m', 'jusi']
  endif

  if l:kind ==# 'ssh'
    let l:cmd = s:ssh_prefix(l:target)
    return empty(l:cmd) ? [] : l:cmd + s:target_python_cmd(l:target)
  endif

  if l:kind ==# 'docker'
    let l:container = s:docker_container(l:target)
    return empty(l:container) ? [] : ['docker', 'exec', '-i', l:container] + s:target_python_cmd(l:target)
  endif

  if l:kind ==# 'docker+ssh'
    let l:cmd = s:ssh_prefix(l:target)
    let l:container = s:docker_container(l:target)
    return empty(l:cmd) || empty(l:container)
          \ ? []
          \ : l:cmd + ['docker', 'exec', '-i', l:container] + s:target_python_cmd(l:target)
  endif

  return s:copy_cmd(s:backend_cmd())
endfunction

function! s:backend_cmd_for_envelope(bufnr, envelope) abort
  let l:type = get(a:envelope, 'type', '')
  if l:type ==# 'start_session'
    let l:payload = get(a:envelope, 'payload', {})
    let l:cmd = jusi#transport#backend_cmd_for_target(get(l:payload, 'target', {}))
    if (type(l:cmd) == type([]) && !empty(l:cmd)) || (type(l:cmd) == type('') && !empty(l:cmd))
      return l:cmd
    endif
  endif
  return s:copy_cmd(s:backend_cmd())
endfunction

function! s:ensure_state(bufnr) abort
  if !has_key(s:transport, a:bufnr)
    let s:transport[a:bufnr] = {
          \ 'job': 0,
          \ 'channel': 0,
          \ 'pending': {},
          \ 'stdout_tail': '',
          \ }
  endif
  return s:transport[a:bufnr]
endfunction

function! s:set_state(bufnr, state) abort
  let s:transport[a:bufnr] = a:state
  return a:state
endfunction

function! s:clear_state(bufnr) abort
  if has_key(s:transport, a:bufnr)
    call remove(s:transport, a:bufnr)
  endif
endfunction

function! s:channel_send(bufnr, text) abort
  let l:state = s:ensure_state(a:bufnr)
  try
    if has('nvim')
      call chansend(l:state.job, a:text)
      return 1
    endif
    call ch_sendraw(l:state.channel, a:text)
    return 1
  catch
    call s:debug_log(a:bufnr, 'channel-send-failed', v:exception)
    call s:stop_job(a:bufnr)
    return 0
  endtry
endfunction

function! s:job_is_running(bufnr) abort
  if !has_key(s:transport, a:bufnr)
    return 0
  endif
  let l:state = s:transport[a:bufnr]
  if has('nvim')
    return get(l:state, 'job', 0) > 0
  endif
  let l:job = get(l:state, 'job', 0)
  if type(l:job) == type(0)
    return l:job > 0 && job_status(l:job) ==# 'run'
  endif
  return !empty(l:job) && job_status(l:job) ==# 'run'
endfunction

function! s:matches_current_job(bufnr, job) abort
  if !has_key(s:transport, a:bufnr)
    return 0
  endif
  return string(get(s:transport[a:bufnr], 'job', 0)) ==# string(a:job)
endfunction

function! s:matches_current_channel(bufnr, channel) abort
  if !has_key(s:transport, a:bufnr)
    return 0
  endif
  return string(get(s:transport[a:bufnr], 'channel', 0)) ==# string(a:channel)
endfunction

function! s:stop_job(bufnr) abort
  if !has_key(s:transport, a:bufnr)
    return
  endif
  let l:state = s:transport[a:bufnr]
  if has('nvim')
    if get(l:state, 'job', 0) > 0
      call jobstop(l:state.job)
    endif
  else
    let l:job = get(l:state, 'job', 0)
    if type(l:job) == type(0)
      if l:job > 0
        call job_stop(l:job)
      endif
    elseif !empty(l:job)
      call job_stop(l:job)
    endif
  endif
  call s:clear_state(a:bufnr)
endfunction

function! s:on_message(bufnr, envelope) abort
  call s:debug_log(a:bufnr, 'parsed-envelope', a:envelope)
  if type(a:envelope) != type({})
    return
  endif
  call jusi#log#write('debug', 'transport', 'received',
        \ s:envelope_log_summary(a:envelope), a:bufnr)

  if get(a:envelope, 'kind', '') ==# 'response'
    let l:request_id = get(a:envelope, 'request_id', '')
    let l:state = s:ensure_state(a:bufnr)
    if has_key(l:state.pending, l:request_id)
      let l:state.pending[l:request_id] = {
            \ 'done': 1,
            \ 'response': {
            \   'ok': get(a:envelope, 'ok', v:false) ? 1 : 0,
            \   'payload': get(a:envelope, 'payload', {}),
            \   'error_code': has_key(a:envelope, 'error')
            \     ? (type(a:envelope.error) == type({}) ? get(a:envelope.error, 'code', '') : '')
            \     : '',
            \   'error': has_key(a:envelope, 'error')
            \     ? (type(a:envelope.error) == type({}) ? get(a:envelope.error, 'message', '') : a:envelope.error)
            \     : '',
            \   },
            \ }
      call s:debug_log(a:bufnr, 'response-matched', l:request_id, l:state.pending[l:request_id])
      call s:set_state(a:bufnr, l:state)
    else
      call s:debug_log(a:bufnr, 'response-unmatched', l:request_id)
    endif
    return
  endif

  if get(a:envelope, 'kind', '') !=# 'event'
    return
  endif

  let l:payload = get(a:envelope, 'payload', {})
  let l:type = get(a:envelope, 'type', '')
  if l:type ==# 'session_updated'
    call jusi#session#callback_session(get(l:payload, 'session', {}), a:bufnr)
    return
  endif
  if l:type ==# 'cell_updated'
    let l:cell = get(l:payload, 'cell', {})
    call jusi#session#callback_cell(get(l:cell, 'id', 0), l:cell, a:bufnr)
    return
  endif
  if l:type ==# 'client_updated'
    call jusi#session#callback_client_updated(l:payload, a:bufnr)
    return
  endif
  if l:type ==# 'handler_message'
    call jusi#session#callback_handler_message(l:payload, a:bufnr)
    return
  endif
  if l:type ==# 'healthcheck'
    call jusi#session#callback_healthcheck(l:payload, a:bufnr)
    return
  endif
endfunction

function! s:parse_lines(bufnr, lines) abort
  for l:line in a:lines
    if empty(l:line)
      continue
    endif
    call s:debug_log(a:bufnr, 'raw-line', l:line)
    try
      let l:envelope = json_decode(l:line)
    catch
      call s:debug_log(a:bufnr, 'json-decode-failed', l:line)
      continue
    endtry
    call s:on_message(a:bufnr, l:envelope)
  endfor
endfunction

function! s:parse_nvim_chunks(bufnr, chunks) abort
  if empty(a:chunks)
    return
  endif
  call s:debug_log(a:bufnr, 'nvim-chunks', a:chunks)
  let l:state = s:ensure_state(a:bufnr)
  let l:parts = copy(a:chunks)
  let l:parts[0] = get(l:state, 'stdout_tail', '') . l:parts[0]

  if l:parts[-1] ==# ''
    let l:state.stdout_tail = ''
    call s:set_state(a:bufnr, l:state)
    call s:parse_lines(a:bufnr, l:parts[0 : len(l:parts) - 2])
    return
  endif

  let l:state.stdout_tail = remove(l:parts, -1)
  call s:set_state(a:bufnr, l:state)
  call s:parse_lines(a:bufnr, l:parts)
endfunction

function! s:parse_vim_chunk(bufnr, msg) abort
  call s:debug_log(a:bufnr, 'vim-chunk', a:msg)
  let l:state = s:ensure_state(a:bufnr)
  let l:text = get(l:state, 'stdout_tail', '') . a:msg
  let l:parts = split(l:text, "\n", 1)
  if l:text =~# "\n$"
    let l:state.stdout_tail = ''
  else
    let l:state.stdout_tail = remove(l:parts, -1)
  endif
  call s:set_state(a:bufnr, l:state)
  call s:parse_lines(a:bufnr, l:parts)
endfunction

function! s:nvim_stdout(bufnr, jobid, data, event) abort
  if !s:matches_current_job(a:bufnr, a:jobid)
    call s:debug_log(a:bufnr, 'nvim-stdout-ignored-stale-job', 'job=' . a:jobid)
    return
  endif
  call s:parse_nvim_chunks(a:bufnr, a:data)
endfunction

function! s:nvim_exit(bufnr, jobid, code, event) abort
  if !s:matches_current_job(a:bufnr, a:jobid)
    call s:debug_log(a:bufnr, 'nvim-exit-ignored-stale-job', 'job=' . a:jobid, 'code=' . a:code)
    return
  endif
  call s:debug_log(a:bufnr, 'nvim-exit', 'job=' . a:jobid, 'code=' . a:code)
  call jusi#log#write(a:code == 0 ? 'info' : 'error', 'transport', 'backend_exited', {
        \ 'job': a:jobid,
        \ 'exit_code': a:code,
        \ }, a:bufnr)
  let l:state = s:ensure_state(a:bufnr)
  let l:state.job = 0
  call s:set_state(a:bufnr, l:state)
endfunction

function! s:vim_out(bufnr, channel, msg) abort
  if !s:matches_current_channel(a:bufnr, a:channel)
    call s:debug_log(a:bufnr, 'vim-out-ignored-stale-channel', 'channel=' . string(a:channel))
    return
  endif
  call s:parse_vim_chunk(a:bufnr, a:msg)
endfunction

function! s:vim_exit(bufnr, job, status) abort
  if !s:matches_current_job(a:bufnr, a:job)
    call s:debug_log(a:bufnr, 'vim-exit-ignored-stale-job', 'job=' . string(a:job), 'status=' . a:status)
    return
  endif
  call s:debug_log(a:bufnr, 'vim-exit', 'status=' . a:status)
  call jusi#log#write(a:status == 0 ? 'info' : 'error', 'transport', 'backend_exited', {
        \ 'exit_status': a:status,
        \ }, a:bufnr)
  let l:state = s:ensure_state(a:bufnr)
  let l:state.job = 0
  let l:state.channel = 0
  call s:set_state(a:bufnr, l:state)
endfunction

function! s:start_job(bufnr, envelope) abort
  let l:cmd = s:backend_cmd_for_envelope(a:bufnr, a:envelope)
  if s:job_is_running(a:bufnr)
    let l:state = s:ensure_state(a:bufnr)
    let l:current_cmd = get(l:state, 'cmd', [])
    if get(a:envelope, 'type', '') ==# 'start_session'
          \ && s:has_cmd(l:cmd)
          \ && !s:same_cmd(l:current_cmd, l:cmd)
      call s:debug_log(a:bufnr, 'start-job-restart-command-changed', l:current_cmd, l:cmd)
      call s:stop_job(a:bufnr)
    else
      call s:debug_log(a:bufnr, 'start-job-skip-already-running', l:current_cmd)
      return 1
    endif
  endif
  if !s:has_cmd(l:cmd)
    call s:debug_log(a:bufnr, 'start-job-no-backend-cmd')
    return 0
  endif

  let l:state = s:ensure_state(a:bufnr)
  let l:state.cmd = s:copy_cmd(l:cmd)
  call s:set_state(a:bufnr, l:state)
  call s:debug_log(a:bufnr, 'start-job', l:cmd)
  call jusi#log#write('info', 'transport', 'backend_starting', {
        \ 'request_type': get(a:envelope, 'type', ''),
        \ }, a:bufnr)
  if has('nvim')
    let l:job = jobstart(l:cmd, {
          \ 'on_stdout': function('s:nvim_stdout', [a:bufnr]),
          \ 'on_stderr': function('s:nvim_stdout', [a:bufnr]),
          \ 'on_exit': function('s:nvim_exit', [a:bufnr]),
          \ 'stdout_buffered': v:false,
          \ 'stderr_buffered': v:false,
          \ })
    if l:job <= 0
      call s:debug_log(a:bufnr, 'start-job-failed', l:job)
      call jusi#log#write('error', 'transport', 'backend_start_failed', {
            \ 'result': l:job,
            \ }, a:bufnr)
      return 0
    endif
    let l:state.job = l:job
    call s:set_state(a:bufnr, l:state)
    call s:debug_log(a:bufnr, 'start-job-ok', 'job=' . l:job)
    call jusi#log#write('info', 'transport', 'backend_started', {'job': l:job}, a:bufnr)
    return 1
  endif

  let l:job = job_start(l:cmd, {
        \ 'in_io': 'pipe',
        \ 'out_io': 'pipe',
        \ 'err_io': 'pipe',
        \ 'out_mode': 'raw',
        \ 'err_mode': 'raw',
        \ 'out_cb': function('s:vim_out', [a:bufnr]),
        \ 'err_cb': function('s:vim_out', [a:bufnr]),
        \ 'exit_cb': function('s:vim_exit', [a:bufnr]),
        \ })
  if type(l:job) == type(0) && (l:job == 0 || l:job == -1)
    call s:debug_log(a:bufnr, 'start-job-failed', l:job)
    call jusi#log#write('error', 'transport', 'backend_start_failed', {
          \ 'result': l:job,
          \ }, a:bufnr)
    return 0
  endif
  let l:state.job = l:job
  let l:state.channel = job_getchannel(l:job)
  call s:set_state(a:bufnr, l:state)
  call s:debug_log(a:bufnr, 'start-job-ok', 'channel=' . string(l:state.channel))
  call jusi#log#write('info', 'transport', 'backend_started', {}, a:bufnr)
  return 1
endfunction

function! jusi#transport#can_request(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  let l:envelope = a:0 >= 2 && type(a:2) == type({}) ? a:2 : {}
  return type(s:handler_funcref()) == type(function('tr'))
        \ || s:job_is_running(l:bufnr)
        \ || s:has_backend_cmd()
        \ || !empty(s:backend_cmd_for_envelope(l:bufnr, l:envelope))
endfunction

function! jusi#transport#request(bufnr, envelope) abort
  let l:bufnr = s:normalize_bufnr(a:bufnr)
  call s:debug_log(l:bufnr, 'request-begin', a:envelope)
  call jusi#log#write('debug', 'transport', 'request',
        \ s:envelope_log_summary(a:envelope), l:bufnr)
  let l:Handler = s:handler_funcref()
  if type(l:Handler) == type(function('tr'))
    let l:result = call(l:Handler, [l:bufnr, a:envelope])
    call s:debug_log(l:bufnr, 'request-handler-result', l:result)
    return l:result
  endif

  if !s:start_job(l:bufnr, a:envelope)
    call s:debug_log(l:bufnr, 'request-no-transport')
    return {'ok': 0, 'error': 'Transport is not configured', 'error_code': 'transport_unreachable'}
  endif

  let l:state = s:ensure_state(l:bufnr)
  let l:request_id = get(a:envelope, 'request_id', '')
  let l:state.pending[l:request_id] = {'done': 0, 'response': {}}
  call s:set_state(l:bufnr, l:state)
  call s:debug_log(l:bufnr, 'request-pending', l:request_id, get(a:envelope, 'type', ''))
  if !s:channel_send(l:bufnr, json_encode(a:envelope) . "\n")
    let l:state = s:ensure_state(l:bufnr)
    if has_key(l:state.pending, l:request_id)
      call remove(l:state.pending, l:request_id)
      call s:set_state(l:bufnr, l:state)
    endif
    return {'ok': 0, 'error': 'Transport write failed', 'error_code': 'transport_unreachable'}
  endif
  call s:debug_log(l:bufnr, 'request-sent', l:request_id)

  let l:timeout = get(g:, 'jusi_transport_timeout_ms', 5000)
  if exists('*wait')
    call wait(l:timeout, {-> get(get(s:transport, l:bufnr, {'pending': {}}).pending, l:request_id, {'done': 0}).done})
  else
    let l:start = reltime()
    while reltimefloat(reltime(l:start)) * 1000.0 < l:timeout
      if get(get(s:transport, l:bufnr, {'pending': {}}).pending, l:request_id, {'done': 0}).done
        break
      endif
      sleep 10m
    endwhile
  endif

  let l:state = s:ensure_state(l:bufnr)
  let l:pending = get(l:state.pending, l:request_id, {'done': 0, 'response': {}})
  if has_key(l:state.pending, l:request_id)
    call remove(l:state.pending, l:request_id)
    call s:set_state(l:bufnr, l:state)
  endif
  if !get(l:pending, 'done', 0)
    call s:debug_log(l:bufnr, 'request-timeout', l:request_id, 'timeout_ms=' . l:timeout)
    call jusi#log#write('warn', 'transport', 'request_timeout', {
          \ 'request_id': l:request_id,
          \ 'request_type': get(a:envelope, 'type', ''),
          \ 'timeout_ms': l:timeout,
          \ }, l:bufnr)
    return {'ok': 0, 'error': 'Timed out waiting for backend response', 'error_code': 'transport_timeout'}
  endif
  call s:debug_log(l:bufnr, 'request-complete', l:request_id, l:pending.response)
  call jusi#log#write(get(l:pending.response, 'ok', 0) ? 'debug' : 'warn',
        \ 'transport', 'response', {
        \   'request_id': l:request_id,
        \   'request_type': get(a:envelope, 'type', ''),
        \   'ok': get(l:pending.response, 'ok', 0),
        \   'error_code': get(l:pending.response, 'error_code', ''),
        \   'error': get(l:pending.response, 'error', ''),
        \ }, l:bufnr)
  return l:pending.response
endfunction

function! jusi#transport#notify(bufnr, envelope) abort
  let l:bufnr = s:normalize_bufnr(a:bufnr)
  call s:debug_log(l:bufnr, 'notify-begin', a:envelope)
  call jusi#log#write('debug', 'transport', 'notify',
        \ s:envelope_log_summary(a:envelope), l:bufnr)
  let l:Handler = s:handler_funcref()
  if type(l:Handler) == type(function('tr'))
    let l:result = call(l:Handler, [l:bufnr, a:envelope])
    call s:debug_log(l:bufnr, 'notify-handler-result', l:result)
    return l:result
  endif

  if !s:start_job(l:bufnr, a:envelope)
    call s:debug_log(l:bufnr, 'notify-no-transport')
    return {'ok': 0, 'error': 'Transport is not configured', 'error_code': 'transport_unreachable'}
  endif

  if !s:channel_send(l:bufnr, json_encode(a:envelope) . "\n")
    return {'ok': 0, 'error': 'Transport write failed', 'error_code': 'transport_unreachable'}
  endif
  call s:debug_log(l:bufnr, 'notify-sent', get(a:envelope, 'request_id', ''), get(a:envelope, 'type', ''))
  return {'ok': 1}
endfunction

function! jusi#transport#receive(bufnr, envelope) abort
  call s:on_message(s:normalize_bufnr(a:bufnr), a:envelope)
endfunction

function! jusi#transport#stop(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  call s:stop_job(l:bufnr)
endfunction
