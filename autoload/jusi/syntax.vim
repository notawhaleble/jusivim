function! s:normalize_bufnr(bufnr) abort
  if a:bufnr is# 0 || a:bufnr is# ''
    return bufnr('%')
  endif
  return str2nr(a:bufnr)
endfunction

function! s:clear_dynamic() abort
  let l:groups = get(b:, 'jusi_dynamic_syntax_groups', [])
  for l:group in l:groups
    execute 'syntax clear ' . l:group
  endfor
  let b:jusi_dynamic_syntax_groups = []
  syntax sync clear
endfunction

function! jusi#syntax#define_base() abort
  syntax match jusiDelimiter '^##\s*$'
  syntax match jusiMagicHeader '^%%\k\+.*$'
  highlight default link jusiDelimiter Comment
  highlight default link jusiMagicHeader PreProc
endfunction

function! jusi#syntax#sync(bufnr, cells) abort
  let l:bufnr = s:normalize_bufnr(a:bufnr)
  if l:bufnr != bufnr('%')
    return
  endif
  call jusi#syntax#define_base()
  call s:clear_dynamic()
endfunction

function! jusi#syntax#sync_from(bufnr, cells, start_idx) abort
  call jusi#syntax#sync(a:bufnr, a:cells)
endfunction

function! jusi#syntax#suspend(bufnr) abort
  call jusi#syntax#sync(a:bufnr, [])
endfunction

function! jusi#syntax#schedule(bufnr, ...) abort
  call jusi#syntax#sync(a:bufnr, [])
endfunction

function! jusi#syntax#cleanup(bufnr) abort
endfunction
