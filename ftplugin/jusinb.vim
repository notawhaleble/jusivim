setlocal commentstring=#\ %s
setlocal completeopt-=preview
call jusi#statusline#setup_notebook()

if !exists('b:jusi_mappings_initialized')
  let b:jusi_mappings_initialized = 1

  nnoremap <silent> <buffer> <Space> :JusiCellModeToggle<CR>
  nnoremap <silent> <buffer> <leader>r :JusiRebuild<CR>
  nnoremap <silent> <buffer> <leader>a :JusiCellNewAbove<CR>
  nnoremap <silent> <buffer> <leader>b :JusiCellNewBelow<CR>
  nnoremap <silent> <buffer> <leader>x :JusiCellDelete<CR>
  nnoremap <silent> <buffer> <leader>c :JusiCellEdit<CR>
  nnoremap <silent> <buffer> <leader>y :JusiCellCopy<CR>
  nnoremap <silent> <buffer> <leader>p :JusiCellPasteBelow<CR>
  nnoremap <silent> <buffer> <leader>h :<C-U>call jusi#notebook#toggle_history_fold_current()<CR>
  nnoremap <silent> <buffer> <leader>j :<C-U>call jusi#notebook#execute_or_apply_history()<CR>
  nnoremap <silent> <buffer> <leader>s :JusiTogglePark<CR>
  nnoremap <silent> <buffer> <leader>00 :JusiRestartKernel<CR>
  nnoremap <silent> <buffer> <leader>ii :JusiInterruptKernel<CR>
  nnoremap <silent> <buffer> <leader>q :<C-U>call jusi#cellmode#close_client(v:count)<CR>
  nnoremap <silent> <buffer> <leader>g :<C-U>call jusi#cellmode#goto_client(v:count)<CR>
  nnoremap <silent> <buffer> <C-\><C-\> :JusiToggleFocus<CR>
  inoremap <silent> <buffer> <C-\><C-\> <C-R>=jusi#focus#toggle()<CR>
  inoremap <silent> <buffer> <Tab> <C-\><C-o>:JusiComplete<CR>
  inoremap <silent> <buffer> <C-Y> <C-\><C-o>:call jusi#notebook#execute_and_edit_current()<CR>
  inoremap <silent> <buffer> <C-C> <C-\><C-n>:call jusi#notebook#handle_insert_exit()<Bar>call jusi#cellmode#update_indicator()<CR>
endif

call jusi#cellmode#refresh(bufnr('%'))
