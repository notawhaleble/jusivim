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
  if a:mode ==# 'cell'
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

function! s:maybe_unmap_buffer(lhs) abort
  let l:map = maparg(a:lhs, 'n', 0, 1)
  if type(l:map) != type({}) || empty(l:map) || !get(l:map, 'buffer', 0)
    return
  endif
  try
    execute 'nunmap <buffer> ' . s:escaped_lhs(a:lhs)
  catch /^Vim\%((\a\+)\)\=:E31/
  endtry
endfunction

function! s:map_cell_mode() abort
  nnoremap <silent> <buffer> j :<C-U>call jusi#notebook#goto_next_cellmode_target()<CR>
  nnoremap <silent> <buffer> n :<C-U>call jusi#notebook#goto_next_cellmode_target()<CR>
  nnoremap <silent> <buffer> k :<C-U>call jusi#notebook#goto_prev_cellmode_target()<CR>
  nnoremap <silent> <buffer> <CR> :<C-U>call jusi#notebook#execute_or_apply_history()<CR>
  nnoremap <silent> <buffer> <C-P> :<C-U>call jusi#notebook#apply_history_relative(-1)<CR>
  nnoremap <silent> <buffer> <C-N> :<C-U>call jusi#notebook#apply_history_relative(1)<CR>
  nnoremap <silent> <buffer> H :<C-U>call jusi#notebook#toggle_history_fold_current()<CR>
  nnoremap <silent> <buffer> B :JusiCellNewBelow<CR>
  nnoremap <silent> <buffer> A :JusiCellNewAbove<CR>
  nnoremap <silent> <buffer> X :JusiCellDelete<CR>
  nnoremap <silent> <buffer> C :JusiCellEdit<CR>
  nnoremap <silent> <buffer> Y :JusiCellCopy<CR>
  nnoremap <silent> <buffer> P :JusiCellPasteBelow<CR>
  nnoremap <silent> <buffer> S :JusiTogglePark<CR>
  nnoremap <silent> <buffer> Q :<C-U>call jusi#cellmode#close_client(v:count)<CR>
  nnoremap <silent> <buffer> G :<C-U>call jusi#cellmode#goto_client(v:count)<CR>
  nnoremap <silent> <buffer> R :JusiRebuild<CR>
endfunction

function! s:clear_mode_mappings() abort
  call s:maybe_unmap_buffer('j')
  call s:maybe_unmap_buffer('n')
  call s:maybe_unmap_buffer('k')
  call s:maybe_unmap_buffer('<CR>')
  call s:maybe_unmap_buffer('<C-P>')
  call s:maybe_unmap_buffer('<C-N>')
  call s:maybe_unmap_buffer('H')
  call s:maybe_unmap_buffer('B')
  call s:maybe_unmap_buffer('A')
  call s:maybe_unmap_buffer('X')
  call s:maybe_unmap_buffer('C')
  call s:maybe_unmap_buffer('Y')
  call s:maybe_unmap_buffer('P')
  call s:maybe_unmap_buffer('S')
  call s:maybe_unmap_buffer('Q')
  call s:maybe_unmap_buffer('G')
  call s:maybe_unmap_buffer('R')
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
  endif
  call jusi#cellmode#update_indicator()
endfunction

function! jusi#cellmode#indicator_text(...) abort
  let l:bufnr = a:0 >= 1 ? str2nr(a:1) : bufnr('%')
  let l:mode = s:mode(l:bufnr)
  if l:mode ==# 'cell'
    return '-- CELL --'
  endif
  return ''
endfunction

function! jusi#cellmode#update_indicator(...) abort
  let l:perf_start = reltime()
  let l:force_clear = a:0 >= 1 ? a:1 : v:false
  let l:should_show = jusi#cellmode#should_show_indicator() && !l:force_clear
  let l:text = l:should_show ? jusi#cellmode#indicator_text() : ''
  let l:was_visible = get(g:, 'jusi_cellmode_indicator', 0)
  let l:was_text = get(g:, 'jusi_cellmode_indicator_text', '')

  if l:should_show
    if l:was_visible && l:was_text ==# l:text
      call s:perf_log('cellmode_indicator-noop', l:perf_start)
      return
    endif
    redraw
    echo ''
    echohl ModeMsg
    echon l:text
    echohl None
    let g:jusi_cellmode_indicator = 1
    let g:jusi_cellmode_indicator_text = l:text
    call s:perf_log('cellmode_indicator-show', l:perf_start)
    return
  endif

  if l:was_visible
    redraw
    echo ''
    let g:jusi_cellmode_indicator = 0
    let g:jusi_cellmode_indicator_text = ''
    call s:perf_log('cellmode_indicator-clear', l:perf_start)
    return
  endif
  call s:perf_log('cellmode_indicator-noop', l:perf_start)
endfunction

function! jusi#cellmode#should_show_indicator() abort
  let l:is_vipynb = &filetype ==# 'jusinb'
  return l:is_vipynb && jusi#cellmode#mode() !=# 'edit' && mode() =~# '^[nc]'
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

function! jusi#cellmode#goto_client(count) abort
  if a:count <= 0
    echohl ErrorMsg
    echom 'Client id count is required for G in cell mode'
    echohl None
    return {}
  endif
  let l:bufnr = bufnr('%')
  let l:cell = jusi#notebook#cell_by_client_number(a:count, l:bufnr)
  if empty(l:cell)
    echohl ErrorMsg
    echom 'No cell found for client-' . a:count
    echohl None
    return {}
  endif
  return jusi#notebook#goto_cell_id(l:cell.id, l:bufnr)
endfunction

function! jusi#cellmode#close_client(count) abort
  let l:bufnr = bufnr('%')
  if a:count <= 0
    return jusi#session#close_current_client()
  endif
  let l:cell = jusi#notebook#cell_by_client_number(a:count, l:bufnr)
  if empty(l:cell)
    echohl ErrorMsg
    echom 'No cell found for client-' . a:count
    echohl None
    return {}
  endif
  return jusi#session#close_client_for_cell(l:cell.id, l:bufnr)
endfunction
