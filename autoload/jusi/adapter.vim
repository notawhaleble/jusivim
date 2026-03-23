function! s:default_response(op) abort
  return {'ok': 0, 'error': 'Session adapter not configured for ' . a:op}
endfunction

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

function! jusi#adapter#call(op, bufnr, payload) abort
  let l:Handler = s:adapter_funcref(a:op)
  if type(l:Handler) != type(function('tr'))
    return s:default_response(a:op)
  endif
  let l:result = call(l:Handler, [a:bufnr, a:payload])
  if type(l:result) != type({})
    return {'ok': 0, 'error': 'Session adapter returned invalid response for ' . a:op}
  endif
  if !has_key(l:result, 'ok')
    let l:result.ok = 0
  endif
  return l:result
endfunction

function! jusi#adapter#has(op) abort
  return type(s:adapter_funcref(a:op)) == type(function('tr'))
endfunction
