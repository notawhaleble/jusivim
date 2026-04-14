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

if !exists('g:jusi_cellmode_indicator_text')
  let g:jusi_cellmode_indicator_text = ''
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

if !exists('g:jusi_kernel_targets')
  let g:jusi_kernel_targets = {}
endif

if !exists('g:jusi_backend_cmd')
  let g:jusi_backend_cmd = jusi#transport#default_backend_cmd()
endif

if !exists('g:jusi_transport_timeout_ms')
  let g:jusi_transport_timeout_ms = 5000
endif

if !exists('g:jusi_client_layout')
  let g:jusi_client_layout = 'bsplit'
endif

if !exists('g:jusi_terminal_echo_input')
  let g:jusi_terminal_echo_input = 0
endif

if !exists('g:jusi_sign_texts')
  let g:jusi_sign_texts = {
        \ 'initial': '#',
        \ 'follow-up': '#>',
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
command! -nargs=? JusiReplyInput call jusi#session#reply_input_current(<q-args>)
command! JusiInterruptKernel call jusi#session#interrupt()
command! JusiCloseClient call jusi#session#close_current_client()
command! JusiTogglePark call jusi#session#toggle_park_current_client()
command! JusiToggleFocus call jusi#focus#toggle()
command! -nargs=? JusiHandlerInput call jusi#session#send_handler_input_current(<q-args>)
command! JusiHandlerFollowup call jusi#session#send_handler_followup_current()
command! JusiHandlerComplete call jusi#session#request_handler_completion_current()
command! -nargs=? JusiDisconnect call jusi#session#disconnect(<q-args>)
command! JusiReconnect call jusi#session#reconnect()
command! JusiStopKernel call jusi#session#stop()
command! JusiCellModeEnable call jusi#cellmode#enable()
command! JusiCellModeDisable call jusi#cellmode#disable()
command! JusiCellModeToggle call jusi#cellmode#toggle()
command! -bang JusiInternalQuit call jusi#notebook#command_quit(<bang>0, 0)
command! -bang JusiInternalQuitAll call jusi#notebook#command_quit(<bang>0, 1)
command! -bang JusiInternalBwipeout call jusi#notebook#command_wipeout(<bang>0)

cnoreabbrev <expr> q jusi#notebook#command_abbrev('q', 'JusiInternalQuit')
cnoreabbrev <expr> q! jusi#notebook#command_abbrev('q!', 'JusiInternalQuit!')
cnoreabbrev <expr> quit jusi#notebook#command_abbrev('quit', 'JusiInternalQuit')
cnoreabbrev <expr> quit! jusi#notebook#command_abbrev('quit!', 'JusiInternalQuit!')
cnoreabbrev <expr> qa jusi#notebook#command_abbrev('qa', 'JusiInternalQuitAll')
cnoreabbrev <expr> qa! jusi#notebook#command_abbrev('qa!', 'JusiInternalQuitAll!')
cnoreabbrev <expr> qall jusi#notebook#command_abbrev('qall', 'JusiInternalQuitAll')
cnoreabbrev <expr> qall! jusi#notebook#command_abbrev('qall!', 'JusiInternalQuitAll!')
cnoreabbrev <expr> bw jusi#notebook#command_abbrev('bw', 'JusiInternalBwipeout')
cnoreabbrev <expr> bw! jusi#notebook#command_abbrev('bw!', 'JusiInternalBwipeout!')
cnoreabbrev <expr> bwipeout jusi#notebook#command_abbrev('bwipeout', 'JusiInternalBwipeout')
cnoreabbrev <expr> bwipeout! jusi#notebook#command_abbrev('bwipeout!', 'JusiInternalBwipeout!')

augroup jusi_notebook
  au!
  au FileType jusinb runtime! ftplugin/jusinb.vim | call jusi#cellmode#refresh(expand('<abuf>'))
  au VimLeavePre * call jusi#notebook#prepare_forced_exit()
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
  au BufHidden * call jusi#client#handle_editor_close(expand('<abuf>'))
  au BufUnload * call jusi#client#handle_editor_close(expand('<abuf>'))
  au BufWipeout * call jusi#client#handle_editor_close(expand('<abuf>'))
  au BufWipeout *.vipynb call jusi#notebook#guard_wipeout(expand('<abuf>'))
  au BufUnload *.vipynb call jusi#notebook#cleanup(expand('<abuf>'))
  au BufEnter,InsertEnter,InsertLeave *.vipynb call jusi#cellmode#update_indicator()
  au BufLeave *.vipynb call jusi#cellmode#update_indicator(v:true)
  if exists('##ModeChanged')
    au ModeChanged *.vipynb call jusi#cellmode#update_indicator()
  endif
augroup END
