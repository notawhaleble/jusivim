setlocal commentstring=#\ %s

if !exists('b:jusi_mappings_initialized')
  let b:jusi_mappings_initialized = 1

  nnoremap <silent> <buffer> <Space> :JusiCellModeToggle<CR>
  nnoremap <silent> <buffer> <leader>r :JusiRebuild<CR>
  nnoremap <silent> <buffer> <leader>a :JusiCellNewAbove<CR>
  nnoremap <silent> <buffer> <leader>b :JusiCellNewBelow<CR>
  inoremap <silent> <buffer> <C-C> <C-\><C-n>:call jusi#cellmode#update_indicator()<CR>
endif

call jusi#cellmode#refresh(bufnr('%'))
