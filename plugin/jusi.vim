scriptencoding utf-8

if exists('g:loaded_jusi')
  finish
endif
let g:loaded_jusi = 1

if !exists('g:jusi_sign_texts')
  let g:jusi_sign_texts = {
        \ 'initial': '#',
        \ 'follow-up': '#+',
        \ 'busy': '#*',
        \ 'done': '#✔',
        \ 'error': '#✖',
        \ 'parked': '#~',
        \ }
endif

call jusi#render#define_signs()

command! JusiRebuild call jusi#notebook#rebuild()
command! JusiCellNext call jusi#notebook#goto_next()
command! JusiCellPrev call jusi#notebook#goto_prev()
command! JusiCellNewAbove call jusi#notebook#insert_above()
command! JusiCellNewBelow call jusi#notebook#insert_below()

augroup jusi_notebook
  au!
  au BufReadPost,BufNewFile *.vipynb call jusi#notebook#rebuild(expand('<abuf>'))
  au TextChanged,TextChangedI *.vipynb call jusi#notebook#rebuild(expand('<abuf>'))
  au BufEnter *.vipynb call jusi#notebook#rebuild(expand('<abuf>'))
augroup END
