let s:levels = {
      \ 'off': 0,
      \ 'error': 1,
      \ 'warn': 2,
      \ 'info': 3,
      \ 'debug': 4,
      \ }

function! s:level_name(level) abort
  let l:level = tolower(type(a:level) == type('') ? a:level : string(a:level))
  return has_key(s:levels, l:level) ? l:level : ''
endfunction

function! jusi#log#path() abort
  let l:path = get(g:, 'jusi_log_file', '')
  if type(l:path) != type('') || empty(l:path)
    let l:path = '~/.jusi/jusivim.log'
  endif
  return fnamemodify(expand(l:path), ':p')
endfunction

function! jusi#log#level() abort
  let l:level = s:level_name(get(g:, 'jusi_log_level', 'off'))
  return empty(l:level) ? 'off' : l:level
endfunction

function! jusi#log#enabled(level) abort
  let l:configured = get(s:levels, jusi#log#level(), 0)
  let l:requested = get(s:levels, s:level_name(a:level), 999)
  return l:configured > 0 && l:requested <= l:configured
endfunction

function! s:sensitive_key(key) abort
  return tolower(a:key) =~# '\v(password|passwd|token|secret|authorization|cookie|api[_-]?key|private[_-]?key)'
endfunction

function! s:omitted_key(key) abort
  return index(['cell_text', 'code', 'content', 'lines', 'visidatarc', 'attach_env'], tolower(a:key)) >= 0
endfunction

function! s:sanitize(value, depth, key) abort
  if s:sensitive_key(a:key)
    return '<redacted>'
  endif
  if s:omitted_key(a:key)
    return '<omitted>'
  endif
  if a:depth >= 6
    return '<max-depth>'
  endif
  if type(a:value) == type({})
    let l:result = {}
    let l:keys = sort(keys(a:value))
    for l:key in l:keys[0 : 49]
      let l:result[l:key] = s:sanitize(a:value[l:key], a:depth + 1, l:key)
    endfor
    if len(l:keys) > 50
      let l:result._omitted_keys = len(l:keys) - 50
    endif
    return l:result
  endif
  if type(a:value) == type([])
    let l:result = []
    for l:item in a:value[0 : 19]
      call add(l:result, s:sanitize(l:item, a:depth + 1, ''))
    endfor
    if len(a:value) > 20
      call add(l:result, '<' . (len(a:value) - 20) . ' more items>')
    endif
    return l:result
  endif
  if type(a:value) == type('') && strlen(a:value) > 500
    return strpart(a:value, 0, 500) . '<truncated>'
  endif
  if type(a:value) == type(function('tr'))
    return '<function>'
  endif
  return a:value
endfunction

function! s:encode(value) abort
  let l:value = s:sanitize(a:value, 0, '')
  try
    return json_encode(l:value)
  catch
    try
      return string(l:value)
    catch
      return '<unprintable>'
    endtry
  endtry
endfunction

function! s:ensure_parent(path) abort
  let l:parent = fnamemodify(a:path, ':h')
  if !isdirectory(l:parent)
    call mkdir(l:parent, 'p')
  endif
endfunction

function! s:rotate(path) abort
  let l:max_bytes = get(g:, 'jusi_log_max_bytes', 1048576)
  if type(l:max_bytes) != type(0) || l:max_bytes <= 0 || getfsize(a:path) < l:max_bytes
    return
  endif
  let l:previous = a:path . '.1'
  if filereadable(l:previous)
    call delete(l:previous)
  endif
  call rename(a:path, l:previous)
endfunction

function! jusi#log#write(level, component, event, ...) abort
  let l:level = s:level_name(a:level)
  if empty(l:level) || !jusi#log#enabled(l:level)
    return 0
  endif
  let l:context = a:0 >= 1 ? a:1 : {}
  let l:bufnr = a:0 >= 2 ? str2nr(a:2) : 0
  let l:path = jusi#log#path()
  try
    call s:ensure_parent(l:path)
    call s:rotate(l:path)
    let l:parts = [
          \ strftime('%Y-%m-%dT%H:%M:%S%z'),
          \ toupper(l:level),
          \ type(a:component) == type('') ? a:component : string(a:component),
          \ type(a:event) == type('') ? a:event : string(a:event),
          \ ]
    if l:bufnr > 0
      call add(l:parts, 'bufnr=' . l:bufnr)
    endif
    if type(l:context) == type({}) ? !empty(l:context) : 1
      call add(l:parts, s:encode(l:context))
    endif
    call writefile([join(l:parts, ' | ')], l:path, 'a')
    return 1
  catch
    return 0
  endtry
endfunction

function! jusi#log#enable(...) abort
  let l:level = a:0 >= 1 && !empty(a:1) ? s:level_name(a:1) : 'debug'
  if empty(l:level) || l:level ==# 'off'
    echohl ErrorMsg
    echom 'Jusi log level must be error, warn, info, or debug'
    echohl None
    return 0
  endif
  let g:jusi_log_level = l:level
  let l:written = jusi#log#write(l:level, 'log', 'enabled', {
        \ 'level': l:level,
        \ 'editor': has('nvim') ? 'nvim' : 'vim',
        \ })
  if !l:written
    let g:jusi_log_level = 'off'
    echohl ErrorMsg
    echom 'Cannot write Jusi log: ' . jusi#log#path()
    echohl None
    return 0
  endif
  echom 'Jusi logging enabled at ' . l:level . ': ' . jusi#log#path()
  return 1
endfunction

function! jusi#log#disable() abort
  call jusi#log#write('info', 'log', 'disabled', {})
  let g:jusi_log_level = 'off'
  echom 'Jusi logging disabled'
  return 1
endfunction

function! jusi#log#open() abort
  let l:path = jusi#log#path()
  call s:ensure_parent(l:path)
  execute 'keepalt edit ' . fnameescape(l:path)
  return l:path
endfunction

function! jusi#log#complete_levels(arglead, cmdline, cursorpos) abort
  return filter(['error', 'warn', 'info', 'debug'], 'v:val =~# ''^'' . escape(a:arglead, ''\.^$~[]*'')')
endfunction
