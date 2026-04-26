function! s:normalize_bufnr(bufnr) abort
  if a:bufnr is# 0 || a:bufnr is# ''
    return bufnr('%')
  endif
  return str2nr(a:bufnr)
endfunction

function! s:is_notebook_buffer(bufnr) abort
  return bufexists(a:bufnr) && getbufvar(a:bufnr, '&filetype') ==# 'jusinb'
endfunction

function! s:debug_enabled() abort
  return type(get(g:, 'jusi_indent_debug_log', 0)) == type('')
        \ && !empty(get(g:, 'jusi_indent_debug_log', ''))
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

function! s:debug_log(message, ...) abort
  if !s:debug_enabled()
    return
  endif
  let l:parts = [strftime('%Y-%m-%d %H:%M:%S'), a:message]
  for l:item in a:000
    call add(l:parts, s:debug_string(l:item))
  endfor
  call writefile([join(l:parts, ' | ')], get(g:, 'jusi_indent_debug_log', ''), 'a')
endfunction

function! s:cell_key(cell) abort
  if empty(a:cell)
    return ''
  endif
  return printf('%d:%s', get(a:cell, 'id', 0), get(a:cell, 'syntax', ''))
endfunction

function! s:indent_dialect(cell) abort
  return jusi#plugins#indent_for_cell(bufnr('%'), a:cell)
endfunction

function! s:runtime_indent_exists(name) abort
  return !empty(globpath(&runtimepath, 'indent/' . a:name . '.vim'))
endfunction

function! s:apply_indent_file(dialect) abort
  if s:runtime_indent_exists(a:dialect)
    execute 'runtime indent/' . a:dialect . '.vim'
    return 1
  endif

  return 0
endfunction

function! s:active_indent_matches(dialect) abort
  return !empty(a:dialect)
        \ && get(b:, 'jusi_indent_loaded_dialect', '') ==# a:dialect
        \ && &l:indentexpr ==# 'jusi#indent#expr(v:lnum)'
endfunction

function! s:apply_python_style_options() abort
  if !exists('g:python_recommended_style') || g:python_recommended_style != 0
    setlocal expandtab tabstop=4 softtabstop=4 shiftwidth=4
  endif
endfunction

function! s:clear_indent_settings() abort
  call s:debug_log('clear-before', {
        \ 'indentexpr': &l:indentexpr,
        \ 'autoindent': &l:autoindent,
        \ 'smartindent': &l:smartindent,
        \ 'cindent': &l:cindent,
        \ 'expandtab': &l:expandtab,
        \ 'tabstop': &l:tabstop,
        \ 'softtabstop': &l:softtabstop,
        \ 'shiftwidth': &l:shiftwidth,
        \ 'did_indent': exists('b:did_indent') ? b:did_indent : '<unset>',
        \ 'undo_indent': exists('b:undo_indent') ? b:undo_indent : '<unset>',
        \ })
  if exists('b:undo_indent')
    silent! execute b:undo_indent
    unlet! b:undo_indent
  endif
  unlet! b:jusi_indent_delegate_expr
  unlet! b:did_indent
  setlocal indentexpr<
  setlocal indentkeys<
  setlocal autoindent<
  setlocal smartindent<
  setlocal cindent<
  setlocal lisp<
  call s:debug_log('clear-after', {
        \ 'indentexpr': &l:indentexpr,
        \ 'autoindent': &l:autoindent,
        \ 'smartindent': &l:smartindent,
        \ 'cindent': &l:cindent,
        \ 'expandtab': &l:expandtab,
        \ 'tabstop': &l:tabstop,
        \ 'softtabstop': &l:softtabstop,
        \ 'shiftwidth': &l:shiftwidth,
        \ 'did_indent': exists('b:did_indent') ? b:did_indent : '<unset>',
        \ })
endfunction

function! s:set_notebook_indentexpr(dialect) abort
  let b:jusi_indent_delegate_expr = &l:indentexpr
  let b:jusi_indent_loaded_dialect = a:dialect
  setlocal indentexpr=jusi#indent#expr(v:lnum)
endfunction

function! s:set_python_notebook_indentexpr() abort
  let b:jusi_indent_delegate_expr = "python#GetIndent(v:lnum, function('jusi#indent#python_barrier'))"
  let b:jusi_indent_loaded_dialect = 'python'
  setlocal indentexpr=jusi#indent#expr(v:lnum)
endfunction

function! s:delegate_indent(lnum) abort
  let l:expr = get(b:, 'jusi_indent_delegate_expr', '')
  if empty(l:expr)
    call s:debug_log('expr-no-delegate', {'lnum': a:lnum})
    return -1
  endif
  let l:expr = substitute(l:expr, '\Cv:lnum', string(a:lnum), 'g')
  try
    let l:result = eval(l:expr)
    call s:debug_log('expr-delegate', {
          \ 'lnum': a:lnum,
          \ 'expr': l:expr,
          \ 'result': l:result,
          \ 'line': getline(a:lnum),
          \ 'prevnonblank': prevnonblank(a:lnum - 1),
          \ 'prevline': getline(prevnonblank(a:lnum - 1)),
          \ })
    return l:result
  catch
    call s:debug_log('expr-error', {
          \ 'lnum': a:lnum,
          \ 'expr': l:expr,
          \ 'exception': v:exception,
          \ })
    return -1
  endtry
endfunction

function! jusi#indent#expr(lnum) abort
  let l:bufnr = bufnr('%')
  if !s:is_notebook_buffer(l:bufnr)
    return s:delegate_indent(a:lnum)
  endif

  let l:cell = jusi#notebook#cell_at_line(l:bufnr, a:lnum)
  if empty(l:cell)
    return 0
  endif

  let l:start = get(l:cell, 'start', 0)
  if a:lnum <= l:start || prevnonblank(a:lnum - 1) <= l:start
    call s:debug_log('expr-cell-boundary', {
          \ 'lnum': a:lnum,
          \ 'cell_id': get(l:cell, 'id', 0),
          \ 'cell_start': l:start,
          \ 'line': getline(a:lnum),
          \ 'prevnonblank': prevnonblank(a:lnum - 1),
          \ 'prevline': getline(prevnonblank(a:lnum - 1)),
          \ })
    return 0
  endif

  let b:jusi_indent_eval_cell_start = l:start
  try
    return s:delegate_indent(a:lnum)
  finally
    unlet! b:jusi_indent_eval_cell_start
  endtry
endfunction

function! jusi#indent#python_barrier(lnum) abort
  return a:lnum <= get(b:, 'jusi_indent_eval_cell_start', 0)
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
  let l:session = get(getbufvar(l:bufnr, 'jusi_nb', {}), 'session', {})
  let l:spec = get(get(l:session, 'plugin_specs', {}), get(l:cell, 'magic', ''), {})
  call s:debug_log('refresh-begin', {
        \ 'bufnr': l:bufnr,
        \ 'line': line('.'),
        \ 'cell_id': get(l:cell, 'id', 0),
        \ 'kind': get(l:cell, 'kind', ''),
        \ 'magic': get(l:cell, 'magic', ''),
        \ 'syntax': get(l:cell, 'syntax', ''),
        \ 'presentation': get(l:cell, 'presentation', {}),
        \ 'session_spec': l:spec,
        \ 'resolved_dialect': l:dialect,
        \ 'prev_key': get(b:, 'jusi_indent_cell_key', ''),
        \ 'next_key': l:key,
        \ 'prev_dialect': get(b:, 'jusi_indent_dialect', ''),
        \ 'loaded_dialect': get(b:, 'jusi_indent_loaded_dialect', ''),
        \ 'indentexpr': &l:indentexpr,
        \ 'line_text': getline('.'),
        \ 'line_indent': indent('.'),
        \ 'prev_lnum': prevnonblank(line('.') - 1),
        \ 'prev_text': getline(prevnonblank(line('.') - 1)),
        \ 'prev_indent': prevnonblank(line('.') - 1) > 0 ? indent(prevnonblank(line('.') - 1)) : -1,
        \ 'col': col('.'),
        \ 'mode': mode(),
        \ 'paste': &paste,
        \ 'formatoptions': &l:formatoptions,
        \ })

  if l:key ==# get(b:, 'jusi_indent_cell_key', '')
        \ && l:dialect ==# get(b:, 'jusi_indent_dialect', '')
        \ && s:active_indent_matches(l:dialect)
    call s:debug_log('refresh-skip-cache', {
          \ 'dialect': l:dialect,
          \ 'indentexpr': &l:indentexpr,
          \ 'loaded_dialect': get(b:, 'jusi_indent_loaded_dialect', ''),
          \ })
    return
  endif

  call s:clear_indent_settings()
  runtime indent/python.vim
  call s:apply_python_style_options()
  call s:set_python_notebook_indentexpr()
  call s:debug_log('loaded-python', {
        \ 'indentexpr': &l:indentexpr,
        \ 'delegate': get(b:, 'jusi_indent_delegate_expr', ''),
        \ 'autoindent': &l:autoindent,
        \ 'smartindent': &l:smartindent,
        \ 'cindent': &l:cindent,
        \ 'expandtab': &l:expandtab,
        \ 'tabstop': &l:tabstop,
        \ 'softtabstop': &l:softtabstop,
        \ 'shiftwidth': &l:shiftwidth,
        \ })

  if l:dialect !=# 'python'
    call s:clear_indent_settings()
    if !s:apply_indent_file(l:dialect)
      call s:clear_indent_settings()
      runtime indent/python.vim
      call s:apply_python_style_options()
      let l:dialect = 'python'
      call s:set_python_notebook_indentexpr()
    else
      call s:set_notebook_indentexpr(l:dialect)
    endif
    call s:debug_log('loaded-dialect', {
          \ 'dialect': l:dialect,
          \ 'indentexpr': &l:indentexpr,
          \ 'delegate': get(b:, 'jusi_indent_delegate_expr', ''),
          \ 'autoindent': &l:autoindent,
          \ 'smartindent': &l:smartindent,
          \ 'cindent': &l:cindent,
          \ 'expandtab': &l:expandtab,
          \ 'tabstop': &l:tabstop,
          \ 'softtabstop': &l:softtabstop,
          \ 'shiftwidth': &l:shiftwidth,
          \ })
  endif

  let b:jusi_indent_cell_key = l:key
  let b:jusi_indent_dialect = l:dialect
  call s:debug_log('refresh-end', {
        \ 'dialect': l:dialect,
        \ 'loaded_dialect': get(b:, 'jusi_indent_loaded_dialect', ''),
        \ 'indentexpr': &l:indentexpr,
        \ 'autoindent': &l:autoindent,
        \ 'smartindent': &l:smartindent,
        \ 'cindent': &l:cindent,
        \ 'expandtab': &l:expandtab,
        \ 'tabstop': &l:tabstop,
        \ 'softtabstop': &l:softtabstop,
        \ 'shiftwidth': &l:shiftwidth,
        \ 'indentkeys': &l:indentkeys,
        \ })
endfunction
