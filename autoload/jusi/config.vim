function! s:trim(text) abort
  return substitute(a:text, '^\s*\|\s*$', '', 'g')
endfunction

function! s:strip_comment(line) abort
  let l:out = ''
  let l:quote = ''
  let l:i = 0
  while l:i < strlen(a:line)
    let l:ch = strpart(a:line, l:i, 1)
    if empty(l:quote)
      if l:ch ==# '#'
        break
      endif
      if l:ch ==# '"' || l:ch ==# "'"
        let l:quote = l:ch
      endif
      let l:out .= l:ch
      let l:i += 1
      continue
    endif

    let l:out .= l:ch
    if l:quote ==# '"' && l:ch ==# '\\' && l:i + 1 < strlen(a:line)
      let l:i += 1
      let l:out .= a:line[l:i]
    elseif l:ch ==# l:quote
      let l:quote = ''
    endif
    let l:i += 1
  endwhile
  return l:out
endfunction

function! s:split_top_level(text, separator) abort
  let l:items = []
  let l:current = ''
  let l:quote = ''
  let l:depth = 0
  let l:i = 0
  while l:i < strlen(a:text)
    let l:ch = strpart(a:text, l:i, 1)
    if !empty(l:quote)
      let l:current .= l:ch
      if l:quote ==# '"' && l:ch ==# '\\' && l:i + 1 < strlen(a:text)
        let l:i += 1
        let l:current .= strpart(a:text, l:i, 1)
      elseif l:ch ==# l:quote
        let l:quote = ''
      endif
      let l:i += 1
      continue
    endif
    if l:ch ==# '"' || l:ch ==# "'"
      let l:quote = l:ch
      let l:current .= l:ch
    elseif l:ch ==# '['
      let l:depth += 1
      let l:current .= l:ch
    elseif l:ch ==# ']'
      let l:depth -= 1
      let l:current .= l:ch
    elseif l:ch ==# a:separator && l:depth == 0
      call add(l:items, s:trim(l:current))
      let l:current = ''
    else
      let l:current .= l:ch
    endif
    let l:i += 1
  endwhile
  call add(l:items, s:trim(l:current))
  return l:items
endfunction

function! s:parse_string(text) abort
  if strlen(a:text) < 2
    throw 'Invalid TOML string'
  endif
  let l:quote = strpart(a:text, 0, 1)
  let l:body = a:text[1 : -2]
  if l:quote ==# "'"
    return l:body
  endif
  let l:body = substitute(l:body, '\\\\"', '"', 'g')
  let l:body = substitute(l:body, '\\\\n', "\n", 'g')
  let l:body = substitute(l:body, '\\\\t', "\t", 'g')
  let l:body = substitute(l:body, '\\\\\\\\', '\\', 'g')
  return l:body
endfunction

function! s:parse_value(text) abort
  let l:text = s:trim(a:text)
  if empty(l:text)
    throw 'Missing TOML value'
  endif
  if strpart(l:text, 0, 1) ==# '['
    if l:text[-1:] !=# ']'
      throw 'Invalid TOML array'
    endif
    let l:body = s:trim(l:text[1 : -2])
    if empty(l:body)
      return []
    endif
    let l:items = []
    for l:item in s:split_top_level(l:body, ',')
      call add(l:items, s:parse_value(l:item))
    endfor
    return l:items
  endif
  if (strpart(l:text, 0, 1) ==# '"' && l:text[-1:] ==# '"')
        \ || (strpart(l:text, 0, 1) ==# "'" && l:text[-1:] ==# "'")
    return s:parse_string(l:text)
  endif
  if l:text ==# 'true'
    return v:true
  endif
  if l:text ==# 'false'
    return v:false
  endif
  if l:text =~# '^-\=[0-9]\+$'
    return str2nr(l:text)
  endif
  if l:text =~# '^-\=[0-9]\+\.[0-9]\+$'
    return str2float(l:text)
  endif
  throw 'Unsupported TOML value: ' . l:text
endfunction

function! s:set_nested(root, path, value) abort
  let l:cursor = a:root
  let l:last = len(a:path) - 1
  for l:i in range(0, l:last - 1)
    let l:key = a:path[l:i]
    if !has_key(l:cursor, l:key) || type(l:cursor[l:key]) != type({})
      let l:cursor[l:key] = {}
    endif
    let l:cursor = l:cursor[l:key]
  endfor
  let l:cursor[a:path[l:last]] = a:value
endfunction

function! s:ensure_table(root, path) abort
  let l:cursor = a:root
  for l:key in a:path
    if !has_key(l:cursor, l:key) || type(l:cursor[l:key]) != type({})
      let l:cursor[l:key] = {}
    endif
    let l:cursor = l:cursor[l:key]
  endfor
endfunction

function! s:config_default_lines() abort
  return [
        \ '# Jusi frontend-owned user config.',
        \ '# Plugin-specific settings live in nested TOML tables.',
        \ '',
        \ '[plugins]',
        \ ]
endfunction

function! jusi#config#path() abort
  let l:path = get(g:, 'jusi_config_file', '')
  if type(l:path) == type('') && !empty(l:path)
    return fnamemodify(l:path, ':p')
  endif
  return fnamemodify('~/.jusi/jusi.toml', ':p')
endfunction

function! jusi#config#visidatarc_path() abort
  let l:path = get(g:, 'jusi_visidatarc_file', '')
  if type(l:path) == type('') && !empty(l:path)
    return fnamemodify(l:path, ':p')
  endif
  return fnamemodify('~/.jusi/visidatarc', ':p')
endfunction

function! jusi#config#ensure_file() abort
  let l:path = jusi#config#path()
  let l:dir = fnamemodify(l:path, ':h')
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
  if !filereadable(l:path)
    call writefile(s:config_default_lines(), l:path)
  endif
  return l:path
endfunction

function! jusi#config#ensure_visidatarc() abort
  let l:path = jusi#config#visidatarc_path()
  let l:dir = fnamemodify(l:path, ':h')
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
  if !filereadable(l:path)
    call writefile([], l:path)
  endif
  return l:path
endfunction

function! jusi#config#load() abort
  let l:path = jusi#config#ensure_file()
  let l:config = {}
  let l:table_path = []
  try
    for l:raw in readfile(l:path)
      let l:line = s:trim(s:strip_comment(l:raw))
      if empty(l:line)
        continue
      endif
      if l:line =~# '^\[[^][]\+\]$'
        let l:header = s:trim(l:line[1 : -2])
        if empty(l:header)
          throw 'Empty TOML table header'
        endif
        let l:table_path = []
        for l:part in s:split_top_level(l:header, '.')
          if empty(l:part) || l:part !~# '^[A-Za-z0-9_-]\+$'
            throw 'Invalid TOML table name: ' . l:part
          endif
          call add(l:table_path, l:part)
        endfor
        call s:ensure_table(l:config, l:table_path)
        continue
      endif
      let l:eq = match(l:line, '=')
      if l:eq < 1
        throw 'Invalid TOML assignment: ' . l:line
      endif
      let l:key = s:trim(strpart(l:line, 0, l:eq))
      if empty(l:key) || l:key !~# '^[A-Za-z0-9_-]\+$'
        throw 'Invalid TOML key: ' . l:key
      endif
      let l:value = s:parse_value(strpart(l:line, l:eq + 1))
      call s:set_nested(l:config, l:table_path + [l:key], l:value)
    endfor
  catch
    return {
          \ 'ok': 0,
          \ 'path': l:path,
          \ 'config': {},
          \ 'error': 'Invalid Jusi config at ' . l:path . ': ' . v:exception,
          \ }
  endtry
  return {
        \ 'ok': 1,
        \ 'path': l:path,
        \ 'config': l:config,
        \ }
endfunction

function! jusi#config#load_visidatarc() abort
  let l:path = jusi#config#ensure_visidatarc()
  try
    let l:lines = readfile(l:path)
  catch
    return {
          \ 'ok': 0,
          \ 'path': l:path,
          \ 'content': '',
          \ 'error': 'Failed to read VisiData config at ' . l:path . ': ' . v:exception,
          \ }
  endtry
  let l:content = empty(l:lines) ? '' : join(l:lines, "\n")
  if !empty(l:content)
    let l:content .= "\n"
  endif
  return {
        \ 'ok': 1,
        \ 'path': l:path,
        \ 'content': l:content,
        \ }
endfunction

function! jusi#config#merge_target_config(target, session_config) abort
  let l:target = type(a:target) == type({}) ? copy(a:target) : {}
  let l:config = type(a:session_config) == type({}) ? copy(a:session_config) : {}
  let l:target_config = get(l:target, 'config', {})
  if type(l:target_config) == type({})
    call extend(l:config, l:target_config, 'force')
  endif
  let l:target.config = l:config
  return l:target
endfunction

function! jusi#config#refresh_target_config(target, session_config) abort
  let l:target = type(a:target) == type({}) ? copy(a:target) : {}
  let l:config = {}
  let l:target_config = get(l:target, 'config', {})
  if type(l:target_config) == type({})
    let l:config = copy(l:target_config)
  endif
  if type(a:session_config) == type({})
    call extend(l:config, copy(a:session_config), 'force')
  endif
  let l:target.config = l:config
  return l:target
endfunction
