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

if !exists('g:jusi_indent_map')
  let g:jusi_indent_map = {}
endif

if !exists('g:jusi_syntax_map')
  let g:jusi_syntax_map = {}
endif

if !exists('g:jusi_ext_api_names')
  let g:jusi_ext_api_names = {}
endif

if !exists('g:jusi_session_adapter')
  let g:jusi_session_adapter = {}
endif

if !exists('g:jusi_backend_cmd')
  let g:jusi_backend_cmd = jusi#transport#default_backend_cmd()
endif

if !exists('g:jusi_client_layout')
  let g:jusi_client_layout = 'bsplit'
endif

if !exists('g:jusi_sign_texts')
  let g:jusi_sign_texts = {
        \ 'initial': '#',
        \ 'follow-up': '#+',
        \ 'busy': '#*',
        \ 'done': '#✔',
        \ 'error': '#✖',
        \ 'interrupted': '#!',
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
command! -nargs=? JusiStartKernel call jusi#session#start(<q-args>)
command! -nargs=1 JusiAttach call jusi#session#attach(<q-args>)
command! JusiExecute call jusi#session#execute_current()
command! JusiInterruptKernel call jusi#session#interrupt()
command! JusiCloseClient call jusi#session#close_current_client()
command! JusiTogglePark call jusi#session#toggle_park_current_client()
command! JusiToggleFocus call jusi#focus#toggle()
command! -nargs=? JusiDisconnect call jusi#session#disconnect(<q-args>)
command! JusiReconnect call jusi#session#reconnect()
command! JusiStopKernel call jusi#session#stop()
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
  au BufEnter,CursorMoved *.vipynb call jusi#notebook#refresh_if_changed(expand('<abuf>'))
  au BufEnter,InsertEnter,InsertLeave,TextChanged *.vipynb call jusi#indent#refresh(expand('<abuf>'))
  au BufEnter,CursorMoved,CursorMovedI *.vipynb call jusi#syntax#request_refresh(expand('<abuf>'))
  if exists('##WinScrolled')
    au WinScrolled *.vipynb call jusi#syntax#request_refresh(expand('<abuf>'))
  endif
  au VimResized *.vipynb call jusi#syntax#request_refresh(expand('<abuf>'))
  au BufUnload *.vipynb call jusi#notebook#cleanup(expand('<abuf>'))
  au BufEnter,InsertEnter,InsertLeave *.vipynb call jusi#cellmode#update_indicator()
  au BufLeave *.vipynb call jusi#cellmode#update_indicator(v:true)
  if exists('##ModeChanged')
    au ModeChanged *.vipynb call jusi#cellmode#update_indicator()
  endif
augroup END
