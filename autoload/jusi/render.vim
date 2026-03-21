scriptencoding utf-8

let s:sign_group = 'jusi_cells'

function! jusi#render#sign_group() abort
  return s:sign_group
endfunction

function! jusi#render#sign_name(status) abort
  return 'jusi_' . substitute(a:status, '-', '_', 'g')
endfunction

function! jusi#render#define_signs() abort
  for [l:status, l:text] in items(g:jusi_sign_texts)
    execute 'sign define ' . jusi#render#sign_name(l:status)
          \ . ' text=' . l:text
          \ . ' texthl=Directory'
  endfor
endfunction

function! jusi#render#sync_signs(bufnr, cells) abort
  execute 'sign unplace * group=' . s:sign_group . ' buffer=' . a:bufnr
  for l:cell in a:cells
    execute 'sign place ' . l:cell.sign_id
          \ . ' line=' . l:cell.start
          \ . ' name=' . jusi#render#sign_name(l:cell.status)
          \ . ' group=' . s:sign_group
          \ . ' buffer=' . a:bufnr
  endfor
endfunction
