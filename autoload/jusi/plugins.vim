function! s:default_specs() abort
  return {
        \ 'vd': {'syntax': 'python', 'indent': 'python'},
        \ }
endfunction

function! s:runtime_path_dialect(value, kind) abort
  if type(a:value) != type('') || empty(a:value)
    return ''
  endif
  let l:prefix = a:kind . '/'
  let l:suffix = '.vim'
  if a:value =~# '^' . l:prefix . '.\+' . l:suffix . '$'
    return fnamemodify(a:value, ':t:r')
  endif
  return a:value
endfunction

function! s:runtime_file_exists(kind, name) abort
  return type(a:name) == type('')
        \ && !empty(a:name)
        \ && !empty(globpath(&runtimepath, a:kind . '/' . a:name . '.vim'))
endfunction

function! s:warn_once(bufnr, key, message) abort
  let l:state = getbufvar(a:bufnr, 'jusi_nb', {})
  let l:warnings = get(l:state, 'plugin_warnings', {})
  if type(l:warnings) != type({})
    let l:warnings = {}
  endif
  if has_key(l:warnings, a:key)
    return
  endif
  let l:warnings[a:key] = 1
  let l:state.plugin_warnings = l:warnings
  call setbufvar(a:bufnr, 'jusi_nb', l:state)
  echohl WarningMsg
  echom a:message
  echohl None
endfunction

function! s:normalize_bufnr(bufnr) abort
  if a:bufnr is# 0 || a:bufnr is# ''
    return bufnr('%')
  endif
  return str2nr(a:bufnr)
endfunction

function! s:session_specs(bufnr) abort
  let l:state = getbufvar(a:bufnr, 'jusi_nb', {})
  let l:session = get(l:state, 'session', {})
  let l:specs = get(l:session, 'plugin_specs', {})
  return type(l:specs) == type({}) ? l:specs : {}
endfunction

function! s:spec_for_magic(bufnr, magic) abort
  if empty(a:magic)
    return {}
  endif
  let l:session_specs = s:session_specs(a:bufnr)
  if has_key(l:session_specs, a:magic) && type(l:session_specs[a:magic]) == type({})
    return l:session_specs[a:magic]
  endif
  return {}
endfunction

function! jusi#plugins#syntax_for_magic(bufnr, magic) abort
  let l:bufnr = s:normalize_bufnr(a:bufnr)
  if empty(a:magic)
    return 'python'
  endif

  let l:spec = s:spec_for_magic(l:bufnr, a:magic)
  if has_key(l:spec, 'syntax')
    let l:syntax = s:runtime_path_dialect(get(l:spec, 'syntax', ''), 'syntax')
    if s:runtime_file_exists('syntax', l:syntax)
      return l:syntax
    endif
  endif

  let l:defaults = s:default_specs()
  if has_key(l:defaults, a:magic)
    let l:syntax = s:runtime_path_dialect(get(l:defaults[a:magic], 'syntax', ''), 'syntax')
    if s:runtime_file_exists('syntax', l:syntax)
      return l:syntax
    endif
  endif

  return 'python'
endfunction

function! jusi#plugins#indent_for_cell(bufnr, cell) abort
  let l:bufnr = s:normalize_bufnr(a:bufnr)
  let l:presentation = get(a:cell, 'presentation', {})
  if type(l:presentation) == type({}) && has_key(l:presentation, 'indent')
    let l:indent = s:runtime_path_dialect(get(l:presentation, 'indent', ''), 'indent')
    if s:runtime_file_exists('indent', l:indent)
      return l:indent
    endif
  endif
  let l:syntax = get(a:cell, 'syntax', '')
  let l:magic = get(a:cell, 'magic', '')
  if !empty(l:magic)
    let l:spec = s:spec_for_magic(l:bufnr, l:magic)
    if has_key(l:spec, 'indent')
      let l:indent = s:runtime_path_dialect(get(l:spec, 'indent', ''), 'indent')
      if s:runtime_file_exists('indent', l:indent)
        return l:indent
      endif
    endif
    let l:defaults = s:default_specs()
    if has_key(l:defaults, l:magic) && has_key(l:defaults[l:magic], 'indent')
      let l:indent = s:runtime_path_dialect(get(l:defaults[l:magic], 'indent', ''), 'indent')
      if s:runtime_file_exists('indent', l:indent)
        return l:indent
      endif
    endif
  endif
  if !empty(l:syntax)
    return l:syntax
  endif
  return 'python'
endfunction

function! jusi#plugins#sanitize_cell_update(bufnr, cell, update) abort
  let l:bufnr = s:normalize_bufnr(a:bufnr)
  let l:update = type(a:update) == type({}) ? copy(a:update) : {}
  let l:presentation = get(l:update, 'presentation', {})
  if type(l:presentation) != type({})
    return l:update
  endif

  if has_key(l:presentation, 'syntax')
    let l:syntax = s:runtime_path_dialect(get(l:presentation, 'syntax', ''), 'syntax')
    if !empty(l:syntax) && !s:runtime_file_exists('syntax', l:syntax)
      call remove(l:presentation, 'syntax')
      if has_key(l:update, 'syntax')
        call remove(l:update, 'syntax')
      endif
      call s:warn_once(l:bufnr, 'syntax:' . l:syntax,
            \ 'Jusi: syntax "' . l:syntax . '" is unavailable in Vim runtime; keeping existing cell syntax')
    endif
  endif

  if has_key(l:presentation, 'indent')
    let l:indent = s:runtime_path_dialect(get(l:presentation, 'indent', ''), 'indent')
    if !empty(l:indent) && !s:runtime_file_exists('indent', l:indent)
      call remove(l:presentation, 'indent')
      call s:warn_once(l:bufnr, 'indent:' . l:indent,
            \ 'Jusi: indent "' . l:indent . '" is unavailable in Vim runtime; keeping existing cell indent')
    endif
  endif

  if empty(l:presentation)
    if has_key(l:update, 'presentation')
      call remove(l:update, 'presentation')
    endif
  else
    let l:update.presentation = l:presentation
  endif
  return l:update
endfunction
