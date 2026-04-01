function! s:perf_enabled() abort
  return get(g:, 'jusi_perf_log', 0) == 1
endfunction

function! s:perf_log(event, start, ...) abort
  if !s:perf_enabled()
    return
  endif
  let l:elapsed = reltimefloat(reltime(a:start)) * 1000.0
  let l:extra = a:0 >= 1 ? a:1 : ''
  call writefile([printf('%s %.3fms %s', a:event, l:elapsed, l:extra)], '/tmp/jusivim-perf.log', 'a')
endfunction

function! s:default_mode() abort
  return get(g:, 'jusi_cell_mode', 0) ? 'cell' : 'edit'
endfunction

function! s:normalize_mode(mode) abort
  if a:mode ==# 'cell' || a:mode ==# 'terminal'
    return a:mode
  endif
  return 'edit'
endfunction

function! s:mode(bufnr) abort
  return s:normalize_mode(getbufvar(a:bufnr, 'jusi_notebook_mode', s:default_mode()))
endfunction

function! s:set_mode(bufnr, mode) abort
  let l:mode = s:normalize_mode(a:mode)
  call setbufvar(a:bufnr, 'jusi_notebook_mode', l:mode)
  call setbufvar(a:bufnr, 'jusi_cell_mode', l:mode ==# 'edit' ? 0 : 1)
endfunction

function! s:escaped_lhs(lhs) abort
  return escape(a:lhs, '\|')
endfunction

function! s:map_cell_mode() abort
  nnoremap <silent> <buffer> j :<C-U>execute "JusiCellNext"<CR>
  nnoremap <silent> <buffer> k :<C-U>execute "JusiCellPrev"<CR>
  nnoremap <silent> <buffer> J :JusiTerminalModeEnter<CR>
  nnoremap <silent> <buffer> B :JusiCellNewBelow<CR>
  nnoremap <silent> <buffer> A :JusiCellNewAbove<CR>
  nnoremap <silent> <buffer> X :JusiCellDelete<CR>
  nnoremap <silent> <buffer> C :JusiCellEdit<CR>
  nnoremap <silent> <buffer> Y :JusiCellCopy<CR>
  nnoremap <silent> <buffer> P :JusiCellPasteBelow<CR>
  nnoremap <silent> <buffer> S :JusiTogglePark<CR>
  nnoremap <silent> <buffer> Q :JusiCloseClient<CR>
  nnoremap <silent> <buffer> R :JusiRebuild<CR>
endfunction

function! s:map_terminal_mode() abort
  for l:lhs in jusi#terminalmode#text_mappings()
    execute 'nnoremap <silent> <nowait> <buffer> ' . s:escaped_lhs(l:lhs)
          \ . ' :<C-U>call jusi#terminalmode#send_lhs('
          \ . string(l:lhs)
          \ . ')<CR>'
  endfor
  for l:item in jusi#terminalmode#key_mappings()
    execute 'nnoremap <silent> <nowait> <buffer> ' . s:escaped_lhs(l:item.lhs)
          \ . ' :<C-U>call jusi#terminalmode#send_key(' . string(l:item.key) . ')<CR>'
  endfor
endfunction

function! s:clear_mode_mappings() abort
  silent! nunmap <buffer> j
  silent! nunmap <buffer> k
  silent! nunmap <buffer> J
  silent! nunmap <buffer> B
  silent! nunmap <buffer> A
  silent! nunmap <buffer> X
  silent! nunmap <buffer> C
  silent! nunmap <buffer> Y
  silent! nunmap <buffer> P
  silent! nunmap <buffer> S
  silent! nunmap <buffer> Q
  silent! nunmap <buffer> R
  for l:lhs in jusi#terminalmode#text_mappings()
    execute 'silent! nunmap <buffer> ' . s:escaped_lhs(l:lhs)
  endfor
  for l:item in jusi#terminalmode#key_mappings()
    execute 'silent! nunmap <buffer> ' . s:escaped_lhs(l:item.lhs)
  endfor
  nnoremap <silent> <buffer> <Space> :JusiCellModeToggle<CR>
endfunction

function! jusi#cellmode#mode(...) abort
  let l:bufnr = a:0 >= 1 ? str2nr(a:1) : bufnr('%')
  return s:mode(l:bufnr)
endfunction

function! jusi#cellmode#refresh(...) abort
  let l:bufnr = a:0 >= 1 ? str2nr(a:1) : bufnr('%')
  if getbufvar(l:bufnr, '&filetype') !=# 'jusinb' || l:bufnr != bufnr('%')
    return
  endif
  let l:mode = s:mode(l:bufnr)
  call s:clear_mode_mappings()
  if l:mode ==# 'cell'
    call s:map_cell_mode()
  elseif l:mode ==# 'terminal'
    call s:map_terminal_mode()
  endif
  call jusi#cellmode#update_indicator()
endfunction

function! jusi#cellmode#indicator_text(...) abort
  let l:bufnr = a:0 >= 1 ? str2nr(a:1) : bufnr('%')
  let l:mode = s:mode(l:bufnr)
  if l:mode ==# 'terminal'
    return '-- JUSI TERMINAL --'
  endif
  if l:mode ==# 'cell'
    return '-- CELL --'
  endif
  return ''
endfunction

function! jusi#cellmode#update_indicator(...) abort
  let l:perf_start = reltime()
  let l:force_clear = a:0 >= 1 ? a:1 : v:false
  let l:should_show = jusi#cellmode#should_show_indicator() && !l:force_clear

  if l:should_show
    redraw
    echo ''
    echohl ModeMsg
    echon jusi#cellmode#indicator_text()
    echohl None
    let g:jusi_cellmode_indicator = 1
    call s:perf_log('cellmode_indicator-show', l:perf_start)
    return
  endif

  if get(g:, 'jusi_cellmode_indicator', 0)
    redraw
    echo ''
    let g:jusi_cellmode_indicator = 0
    call s:perf_log('cellmode_indicator-clear', l:perf_start)
    return
  endif
  call s:perf_log('cellmode_indicator-noop', l:perf_start)
endfunction

function! jusi#cellmode#should_show_indicator() abort
  let l:is_vipynb = &filetype ==# 'jusinb'
  return l:is_vipynb && jusi#cellmode#mode() !=# 'edit' && mode() =~# '^n'
endfunction

function! jusi#cellmode#set_mode(mode, ...) abort
  let l:bufnr = a:0 >= 1 ? str2nr(a:1) : bufnr('%')
  let l:mode = s:normalize_mode(a:mode)
  call s:set_mode(l:bufnr, l:mode)
  let g:jusi_cell_mode = l:mode ==# 'edit' ? 0 : 1
  call jusi#render#set_sign_highlights(l:mode !=# 'edit')
  call jusi#cellmode#refresh(l:bufnr)
  return l:mode
endfunction

function! jusi#cellmode#enable() abort
  call jusi#cellmode#set_mode('cell', bufnr('%'))
endfunction

function! jusi#cellmode#disable() abort
  call jusi#cellmode#set_mode('edit', bufnr('%'))
endfunction

function! jusi#cellmode#toggle() abort
  if jusi#cellmode#mode() ==# 'edit'
    call jusi#cellmode#enable()
    return
  endif
  call jusi#cellmode#disable()
endfunction
