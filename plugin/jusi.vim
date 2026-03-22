scriptencoding utf-8

if exists('g:loaded_jusi')
  finish
endif
let g:loaded_jusi = 1

if !exists('g:jusi_cell_mode')
  let g:jusi_cell_mode = 0
endif

if !exists('g:jusi_cellmode_indicator')
  let g:jusi_cellmode_indicator = 0
endif

if !exists('g:jusi_cell_clipboard')
  let g:jusi_cell_clipboard = []
endif

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
command! JusiCellDelete call jusi#notebook#delete_current()
command! JusiCellEdit call jusi#notebook#edit_current()
command! JusiCellCopy call jusi#notebook#copy_current()
command! JusiCellPasteBelow call jusi#notebook#paste_below()
command! JusiCellModeEnable call jusi#cellmode#enable()
command! JusiCellModeDisable call jusi#cellmode#disable()
command! JusiCellModeToggle call jusi#cellmode#toggle()

augroup jusi_notebook
  au!
  au BufReadPost,BufNewFile *.vipynb call jusi#notebook#rebuild(expand('<abuf>'))
  au TextChanged *.vipynb call jusi#notebook#handle_text_changed(expand('<abuf>'))
  au TextChangedI *.vipynb call jusi#notebook#handle_text_changed_insert(expand('<abuf>'))
  au InsertLeave *.vipynb call jusi#notebook#handle_insert_exit(expand('<abuf>'))
  au BufEnter *.vipynb call jusi#notebook#rebuild(expand('<abuf>'))
  au BufEnter,CursorMoved,CursorMovedI *.vipynb call jusi#syntax#request_refresh(expand('<abuf>'))
  au BufUnload *.vipynb call jusi#notebook#cleanup(expand('<abuf>'))
  au BufEnter,CursorMoved,InsertEnter,InsertLeave *.vipynb call jusi#cellmode#update_indicator()
  au BufLeave *.vipynb call jusi#cellmode#update_indicator(v:true)
  if exists('##ModeChanged')
    au ModeChanged *.vipynb call jusi#cellmode#update_indicator()
  endif
augroup END
