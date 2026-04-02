function! s:normalize_bufnr(bufnr) abort
  if a:bufnr is# 0 || a:bufnr is# ''
    return bufnr('%')
  endif
  return str2nr(a:bufnr)
endfunction

function! s:is_notebook_buffer(bufnr) abort
  return bufexists(a:bufnr) && getbufvar(a:bufnr, '&filetype') ==# 'jusinb'
endfunction

function! s:cell_key(cell) abort
  if empty(a:cell)
    return ''
  endif
  return printf('%d:%d:%d:%s', get(a:cell, 'id', 0), get(a:cell, 'start', 0), get(a:cell, 'end', 0), get(a:cell, 'syntax', ''))
endfunction

function! s:indent_dialect(cell) abort
  let l:syntax = get(a:cell, 'syntax', '')
  if !empty(l:syntax)
    return l:syntax
  endif
  return 'python'
endfunction

function! s:runtime_indent_exists(name) abort
  return !empty(globpath(&runtimepath, 'indent/' . a:name . '.vim'))
endfunction

function! s:source_indent_file(path) abort
  if filereadable(a:path)
    execute 'source ' . fnameescape(a:path)
    return 1
  endif
  if !empty(globpath(&runtimepath, a:path))
    execute 'runtime ' . a:path
    return 1
  endif
  return 0
endfunction

function! s:apply_indent_file(dialect) abort
  let l:applied = 0
  let l:map = get(g:, 'jusi_indent_map', {})

  if has_key(l:map, a:dialect)
    let l:applied = s:source_indent_file(l:map[a:dialect])
  endif

  if !l:applied && s:runtime_indent_exists(a:dialect)
    execute 'runtime indent/' . a:dialect . '.vim'
    let l:applied = 1
  endif

  return l:applied
endfunction

function! jusi#indent#refresh(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  if l:bufnr != bufnr('%') || !s:is_notebook_buffer(l:bufnr)
    return
  endif
  if exists('*jusi#cellmode#mode') && jusi#cellmode#mode(l:bufnr) ==# 'terminal'
    return
  endif

  let l:cell = jusi#notebook#cell_at_line(l:bufnr, line('.'))
  let l:key = s:cell_key(l:cell)
  let l:dialect = s:indent_dialect(l:cell)

  if l:key ==# get(b:, 'jusi_indent_cell_key', '')
        \ && l:dialect ==# get(b:, 'jusi_indent_dialect', '')
    return
  endif

  unlet! b:did_indent
  runtime indent/python.vim

  if l:dialect !=# 'python'
    unlet! b:did_indent
    if !s:apply_indent_file(l:dialect)
      unlet! b:did_indent
      runtime indent/python.vim
      let l:dialect = 'python'
    endif
  endif

  let b:jusi_indent_cell_key = l:key
  let b:jusi_indent_dialect = l:dialect
endfunction
