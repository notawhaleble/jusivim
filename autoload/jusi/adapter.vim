function! s:default_response(op) abort
  return {'ok': 0, 'error': 'Session adapter not configured for ' . a:op}
endfunction

let s:next_request_id = 1

function! s:adapter_registry() abort
  return get(g:, 'jusi_session_adapter', {})
endfunction

function! s:adapter_funcref(op) abort
  let l:adapter = s:adapter_registry()
  if type(l:adapter) != type({})
    return 0
  endif
  let l:Handler = get(l:adapter, a:op, 0)
  if type(l:Handler) == type(function('tr'))
    return l:Handler
  endif
  return 0
endfunction

function! s:request_funcref() abort
  let l:adapter = s:adapter_registry()
  if type(l:adapter) != type({})
    return 0
  endif
  let l:Handler = get(l:adapter, 'request', 0)
  if type(l:Handler) == type(function('tr'))
    return l:Handler
  endif
  return 0
endfunction

function! s:notebook_id(bufnr) abort
  return 'nb-' . a:bufnr
endfunction

function! s:session_id(bufnr) abort
  let l:state = getbufvar(a:bufnr, 'jusi_nb', {})
  let l:session = get(l:state, 'session', {})
  return get(l:session, 'id', '')
endfunction

function! s:request_type(op) abort
  let l:map = {
        \ 'start': 'start_session',
        \ 'attach': 'attach_session',
        \ 'execute': 'execute_cell',
        \ 'inspect_client': 'inspect_client',
        \ 'healthcheck_reply': 'healthcheck_reply',
        \ 'handler_message': 'handler_message',
        \ 'interrupt': 'interrupt_cell',
        \ 'input_reply': 'input_reply',
        \ 'shutdown_client': 'shutdown_client',
        \ 'stop': 'stop_session',
        \ 'disconnect': 'disconnect_session',
        \ 'reconnect': 'reconnect_session',
        \ }
  return get(l:map, a:op, a:op)
endfunction

function! s:new_request_id() abort
  let l:id = 'req-' . s:next_request_id
  let s:next_request_id += 1
  return l:id
endfunction

function! s:normalize_result(result) abort
  let l:result = type(a:result) == type({}) ? copy(a:result) : {}
  let l:payload = get(l:result, 'payload', {})
  if type(l:payload) == type({})
    for [l:key, l:value] in items(l:payload)
      if !has_key(l:result, l:key)
        let l:result[l:key] = l:value
      endif
    endfor
  endif
  return l:result
endfunction

function! s:request_payload(op, bufnr, payload) abort
  let l:notebook_id = s:notebook_id(a:bufnr)
  let l:session_id = s:session_id(a:bufnr)

  if a:op ==# 'start'
    return {
          \ 'notebook_id': l:notebook_id,
          \ 'kernel_name': get(a:payload, 'kernel_name', ''),
          \ 'target': get(a:payload, 'target', {}),
          \ }
  endif

  if a:op ==# 'attach'
    return {
          \ 'notebook_id': l:notebook_id,
          \ 'target': get(a:payload, 'target', a:payload),
          \ }
  endif

  if a:op ==# 'execute'
    let l:cell = get(a:payload, 'cell', {})
    return {
          \ 'notebook_id': l:notebook_id,
          \ 'session_id': l:session_id,
          \ 'cell': {
          \   'id': get(l:cell, 'id', 0),
          \   'kind': get(l:cell, 'kind', ''),
          \   'syntax': get(l:cell, 'syntax', ''),
          \   'main_lines': get(l:cell, 'main_lines', []),
          \   },
          \ }
  endif

  if a:op ==# 'interrupt'
    let l:cell = get(a:payload, 'cell', {})
    return {
          \ 'notebook_id': l:notebook_id,
          \ 'session_id': l:session_id,
          \ 'cell_id': get(l:cell, 'id', 0),
          \ }
  endif

  if a:op ==# 'input_reply'
    let l:cell = get(a:payload, 'cell', {})
    return {
          \ 'notebook_id': l:notebook_id,
          \ 'session_id': l:session_id,
          \ 'cell_id': get(l:cell, 'id', 0),
          \ 'client_id': get(a:payload, 'client_id', get(l:cell, 'client_id', '')),
          \ 'value': get(a:payload, 'value', ''),
          \ }
  endif

  if a:op ==# 'inspect_client'
    return {
          \ 'notebook_id': l:notebook_id,
          \ 'session_id': l:session_id,
          \ 'client_id': get(a:payload, 'client_id', ''),
          \ }
  endif

  if a:op ==# 'healthcheck_reply'
    return {
          \ 'notebook_id': l:notebook_id,
          \ 'session_id': get(a:payload, 'session_id', l:session_id),
          \ 'healthcheck_id': get(a:payload, 'healthcheck_id', ''),
          \ }
  endif

  if a:op ==# 'handler_message'
    return {
          \ 'notebook_id': l:notebook_id,
          \ 'session_id': get(a:payload, 'session_id', l:session_id),
          \ 'client_id': get(a:payload, 'client_id', ''),
          \ 'handler_id': get(a:payload, 'handler_id', ''),
          \ 'message_type': get(a:payload, 'message_type', ''),
          \ 'payload': get(a:payload, 'payload', {}),
          \ }
  endif

  if a:op ==# 'stop'
    return {
          \ 'notebook_id': l:notebook_id,
          \ 'session_id': l:session_id,
          \ }
  endif

  if a:op ==# 'shutdown_client'
    let l:cell = get(a:payload, 'cell', {})
    return {
          \ 'notebook_id': l:notebook_id,
          \ 'session_id': l:session_id,
          \ 'cell_id': get(l:cell, 'id', 0),
          \ 'client_id': get(a:payload, 'client_id', get(l:cell, 'client_id', '')),
          \ 'reason': get(a:payload, 'reason', ''),
          \ }
  endif

  if a:op ==# 'disconnect'
    return {
          \ 'notebook_id': l:notebook_id,
          \ 'session_id': l:session_id,
          \ 'reason': get(a:payload, 'reason', ''),
          \ }
  endif

  if a:op ==# 'reconnect'
    return {
          \ 'notebook_id': l:notebook_id,
          \ 'session_id': l:session_id,
          \ }
  endif

  return copy(a:payload)
endfunction

function! jusi#adapter#build_request(op, bufnr, payload) abort
  return {
        \ 'version': 1,
        \ 'kind': 'request',
        \ 'type': s:request_type(a:op),
        \ 'request_id': s:new_request_id(),
        \ 'payload': s:request_payload(a:op, a:bufnr, a:payload),
        \ }
endfunction

function! jusi#adapter#call(op, bufnr, payload) abort
  let l:Request = s:request_funcref()
  if type(l:Request) == type(function('tr'))
    let l:envelope = jusi#adapter#build_request(a:op, a:bufnr, a:payload)
    let l:result = s:normalize_result(call(l:Request, [a:bufnr, l:envelope]))
    if type(l:result) != type({})
      return {'ok': 0, 'error': 'Session adapter returned invalid response for ' . a:op}
    endif
    if !has_key(l:result, 'ok')
      let l:result.ok = 0
    endif
    return l:result
  endif

  let l:Handler = s:adapter_funcref(a:op)
  if type(l:Handler) == type(function('tr'))
    let l:result = s:normalize_result(call(l:Handler, [a:bufnr, a:payload]))
    if type(l:result) != type({})
      return {'ok': 0, 'error': 'Session adapter returned invalid response for ' . a:op}
    endif
    if !has_key(l:result, 'ok')
      let l:result.ok = 0
    endif
    return l:result
  endif

  let l:envelope = jusi#adapter#build_request(a:op, a:bufnr, a:payload)
  if jusi#transport#can_request(a:bufnr, l:envelope)
    let l:result = s:normalize_result(jusi#transport#request(a:bufnr, l:envelope))
    if type(l:result) != type({})
      return {'ok': 0, 'error': 'Transport returned invalid response for ' . a:op}
    endif
    if !has_key(l:result, 'ok')
      let l:result.ok = 0
    endif
    let l:result._transport = 1
    return l:result
  endif

  return s:default_response(a:op)
endfunction

function! jusi#adapter#call_async(op, bufnr, payload) abort
  let l:Request = s:request_funcref()
  if type(l:Request) == type(function('tr'))
    let l:envelope = jusi#adapter#build_request(a:op, a:bufnr, a:payload)
    let l:result = s:normalize_result(call(l:Request, [a:bufnr, l:envelope]))
    if type(l:result) != type({})
      return {'ok': 0, 'error': 'Session adapter returned invalid response for ' . a:op}
    endif
    if !has_key(l:result, 'ok')
      let l:result.ok = 0
    endif
    return l:result
  endif

  let l:Handler = s:adapter_funcref(a:op)
  if type(l:Handler) == type(function('tr'))
    let l:result = s:normalize_result(call(l:Handler, [a:bufnr, a:payload]))
    if type(l:result) != type({})
      return {'ok': 0, 'error': 'Session adapter returned invalid response for ' . a:op}
    endif
    if !has_key(l:result, 'ok')
      let l:result.ok = 0
    endif
    return l:result
  endif

  let l:envelope = jusi#adapter#build_request(a:op, a:bufnr, a:payload)
  if jusi#transport#can_request(a:bufnr, l:envelope)
    return jusi#transport#notify(a:bufnr, l:envelope)
  endif

  return s:default_response(a:op)
endfunction

function! jusi#adapter#has(op) abort
  return type(s:request_funcref()) == type(function('tr'))
        \ || type(s:adapter_funcref(a:op)) == type(function('tr'))
        \ || jusi#transport#can_request(bufnr('%'))
endfunction
