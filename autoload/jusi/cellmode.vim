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

function! s:is_enabled(bufnr) abort
  return getbufvar(a:bufnr, 'jusi_cell_mode', g:jusi_cell_mode)
endfunction

function! s:set_enabled(bufnr, enabled) abort
  call setbufvar(a:bufnr, 'jusi_cell_mode', a:enabled ? 1 : 0)
endfunction

function! s:map_normal_mode() abort
  nnoremap <silent> <buffer> j :<C-U>execute "JusiCellNext"<CR>
  nnoremap <silent> <buffer> k :<C-U>execute "JusiCellPrev"<CR>
  nnoremap <silent> <buffer> B :JusiCellNewBelow<CR>
  nnoremap <silent> <buffer> A :JusiCellNewAbove<CR>
  nnoremap <silent> <buffer> X :JusiCellDelete<CR>
  nnoremap <silent> <buffer> C :JusiCellEdit<CR>
  nnoremap <silent> <buffer> Y :JusiCellCopy<CR>
  nnoremap <silent> <buffer> P :JusiCellPasteBelow<CR>
  nnoremap <silent> <buffer> R :JusiRebuild<CR>
endfunction

function! s:unmap_normal_mode() abort
  silent! nunmap <buffer> j
  silent! nunmap <buffer> k
  silent! nunmap <buffer> B
  silent! nunmap <buffer> A
  silent! nunmap <buffer> X
  silent! nunmap <buffer> C
  silent! nunmap <buffer> Y
  silent! nunmap <buffer> P
  silent! nunmap <buffer> R
endfunction

function! jusi#cellmode#refresh(...) abort
  let l:bufnr = a:0 >= 1 ? str2nr(a:1) : bufnr('%')
  if getbufvar(l:bufnr, '&filetype') !=# 'jusinb' || l:bufnr != bufnr('%')
    return
  endif
  if s:is_enabled(l:bufnr)
    call s:map_normal_mode()
  else
    call s:unmap_normal_mode()
  endif
  call jusi#cellmode#update_indicator()
endfunction

function! jusi#cellmode#update_indicator(...) abort
  let l:perf_start = reltime()
  let l:force_clear = a:0 >= 1 ? a:1 : v:false
  let l:should_show = jusi#cellmode#should_show_indicator() && !l:force_clear

  if l:should_show
    redraw
    echo ''
    echohl ModeMsg
    echon '-- CELL --'
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
  let l:enabled = get(b:, 'jusi_cell_mode', get(g:, 'jusi_cell_mode', 0))
  return l:is_vipynb && l:enabled == 1 && mode() =~# '^n'
endfunction

function! jusi#cellmode#enable() abort
  call s:set_enabled(bufnr('%'), 1)
  let g:jusi_cell_mode = 1
  call jusi#render#set_sign_highlights(v:true)
  call jusi#cellmode#refresh(bufnr('%'))
endfunction

function! jusi#cellmode#disable() abort
  call s:set_enabled(bufnr('%'), 0)
  let g:jusi_cell_mode = 0
  call jusi#render#set_sign_highlights(v:false)
  call jusi#cellmode#refresh(bufnr('%'))
endfunction

function! jusi#cellmode#toggle() abort
  if s:is_enabled(bufnr('%'))
    call jusi#cellmode#disable()
  else
    call jusi#cellmode#enable()
  endif
endfunction
