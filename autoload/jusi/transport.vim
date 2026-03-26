let s:transport = {}

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

function! s:debug_log(bufnr, message, ...) abort
  if !s:debug_log_enabled()
    return
  endif
  let l:path = get(g:, 'jusi_transport_debug_log', '')
  let l:parts = [strftime('%Y-%m-%d %H:%M:%S'), 'bufnr=' . a:bufnr, a:message]
  for l:item in a:000
    call add(l:parts, s:debug_string(l:item))
  endfor
  call writefile([join(l:parts, ' | ')], l:path, 'a')
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

function! s:has_backend_cmd() abort
  let l:cmd = s:backend_cmd()
  return (type(l:cmd) == type([]) && !empty(l:cmd))
        \ || (type(l:cmd) == type('') && !empty(l:cmd))
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
  if empty(l:python) || !isdirectory(l:backend_src)
    return []
  endif
  return 'PYTHONPATH=' . shellescape(l:backend_src) . ' ' . l:python . ' -m jusi'
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
  if has('nvim')
    call chansend(l:state.job, a:text)
    return
  endif
  call ch_sendraw(l:state.channel, a:text)
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

function! s:on_message(bufnr, envelope) abort
  call s:debug_log(a:bufnr, 'parsed-envelope', a:envelope)
  if type(a:envelope) != type({})
    return
  endif

  if get(a:envelope, 'kind', '') ==# 'response'
    let l:request_id = get(a:envelope, 'request_id', '')
    let l:state = s:ensure_state(a:bufnr)
    if has_key(l:state.pending, l:request_id)
      let l:state.pending[l:request_id] = {
            \ 'done': 1,
            \ 'response': {
            \   'ok': get(a:envelope, 'ok', v:false) ? 1 : 0,
            \   'payload': get(a:envelope, 'payload', {}),
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
  if l:type ==# 'prepared_updated'
    call jusi#session#callback_prepared(get(l:payload, 'prepared', {}), a:bufnr)
    return
  endif
  if l:type ==# 'cell_updated'
    let l:cell = get(l:payload, 'cell', {})
    call jusi#session#callback_cell(get(l:cell, 'id', 0), l:cell, a:bufnr)
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
  call s:parse_nvim_chunks(a:bufnr, a:data)
endfunction

function! s:nvim_exit(bufnr, jobid, code, event) abort
  call s:debug_log(a:bufnr, 'nvim-exit', 'job=' . a:jobid, 'code=' . a:code)
  let l:state = s:ensure_state(a:bufnr)
  let l:state.job = 0
  call s:set_state(a:bufnr, l:state)
endfunction

function! s:vim_out(bufnr, channel, msg) abort
  call s:parse_vim_chunk(a:bufnr, a:msg)
endfunction

function! s:vim_exit(bufnr, job, status) abort
  call s:debug_log(a:bufnr, 'vim-exit', 'status=' . a:status)
  let l:state = s:ensure_state(a:bufnr)
  let l:state.job = 0
  let l:state.channel = 0
  call s:set_state(a:bufnr, l:state)
endfunction

function! s:start_job(bufnr) abort
  if s:job_is_running(a:bufnr)
    call s:debug_log(a:bufnr, 'start-job-skip-already-running')
    return 1
  endif
  if !s:has_backend_cmd()
    call s:debug_log(a:bufnr, 'start-job-no-backend-cmd')
    return 0
  endif

  let l:state = s:ensure_state(a:bufnr)
  call s:debug_log(a:bufnr, 'start-job', s:backend_cmd())
  if has('nvim')
    let l:job = jobstart(s:backend_cmd(), {
          \ 'on_stdout': function('s:nvim_stdout', [a:bufnr]),
          \ 'on_stderr': function('s:nvim_stdout', [a:bufnr]),
          \ 'on_exit': function('s:nvim_exit', [a:bufnr]),
          \ 'stdout_buffered': v:false,
          \ 'stderr_buffered': v:false,
          \ })
    if l:job <= 0
      call s:debug_log(a:bufnr, 'start-job-failed', l:job)
      return 0
    endif
    let l:state.job = l:job
    call s:set_state(a:bufnr, l:state)
    call s:debug_log(a:bufnr, 'start-job-ok', 'job=' . l:job)
    return 1
  endif

  let l:job = job_start(s:backend_cmd(), {
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
    return 0
  endif
  let l:state.job = l:job
  let l:state.channel = job_getchannel(l:job)
  call s:set_state(a:bufnr, l:state)
  call s:debug_log(a:bufnr, 'start-job-ok', 'channel=' . string(l:state.channel))
  return 1
endfunction

function! jusi#transport#can_request(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  return type(s:handler_funcref()) == type(function('tr'))
        \ || s:job_is_running(l:bufnr)
        \ || s:has_backend_cmd()
endfunction

function! jusi#transport#request(bufnr, envelope) abort
  let l:bufnr = s:normalize_bufnr(a:bufnr)
  call s:debug_log(l:bufnr, 'request-begin', a:envelope)
  let l:Handler = s:handler_funcref()
  if type(l:Handler) == type(function('tr'))
    let l:result = call(l:Handler, [l:bufnr, a:envelope])
    call s:debug_log(l:bufnr, 'request-handler-result', l:result)
    return l:result
  endif

  if !s:start_job(l:bufnr)
    call s:debug_log(l:bufnr, 'request-no-transport')
    return {'ok': 0, 'error': 'Transport is not configured'}
  endif

  let l:state = s:ensure_state(l:bufnr)
  let l:request_id = get(a:envelope, 'request_id', '')
  let l:state.pending[l:request_id] = {'done': 0, 'response': {}}
  call s:set_state(l:bufnr, l:state)
  call s:debug_log(l:bufnr, 'request-pending', l:request_id, get(a:envelope, 'type', ''))
  call s:channel_send(l:bufnr, json_encode(a:envelope) . "\n")
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
    return {'ok': 0, 'error': 'Timed out waiting for backend response'}
  endif
  call s:debug_log(l:bufnr, 'request-complete', l:request_id, l:pending.response)
  return l:pending.response
endfunction

function! jusi#transport#notify(bufnr, envelope) abort
  let l:bufnr = s:normalize_bufnr(a:bufnr)
  call s:debug_log(l:bufnr, 'notify-begin', a:envelope)
  let l:Handler = s:handler_funcref()
  if type(l:Handler) == type(function('tr'))
    let l:result = call(l:Handler, [l:bufnr, a:envelope])
    call s:debug_log(l:bufnr, 'notify-handler-result', l:result)
    return l:result
  endif

  if !s:start_job(l:bufnr)
    call s:debug_log(l:bufnr, 'notify-no-transport')
    return {'ok': 0, 'error': 'Transport is not configured'}
  endif

  call s:channel_send(l:bufnr, json_encode(a:envelope) . "\n")
  call s:debug_log(l:bufnr, 'notify-sent', get(a:envelope, 'request_id', ''), get(a:envelope, 'type', ''))
  return {'ok': 1}
endfunction

function! jusi#transport#receive(bufnr, envelope) abort
  call s:on_message(s:normalize_bufnr(a:bufnr), a:envelope)
endfunction

function! jusi#transport#stop(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  if !has_key(s:transport, l:bufnr)
    return
  endif
  let l:state = s:transport[l:bufnr]
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
  call s:clear_state(l:bufnr)
endfunction
