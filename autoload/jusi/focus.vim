function! s:apply_client_window_options() abort
  if !getbufvar(bufnr('%'), 'jusi_client_managed', 0)
        \ && getbufvar(bufnr('%'), 'jusi_client_notebook_bufnr', 0) <= 0
    return 0
  endif
  call jusi#client#allow_editor_close(bufnr('%'))
  setlocal nonumber norelativenumber
  call jusi#statusline#setup_client()
  nnoremap <silent> <buffer> <C-\><C-\> :JusiToggleFocus<CR>
  inoremap <silent> <buffer> <C-\><C-\> <C-R>=jusi#focus#toggle()<CR>
  if exists(':tnoremap')
    tnoremap <silent> <buffer> <C-\><C-\> <C-\><C-n>:call jusi#focus#toggle_from_terminal()<CR>
  endif
  call jusi#client#ensure_terminal_focus_mode(bufnr('%'))
  call jusi#client#follow_terminal_output(bufnr('%'))
  return 1
endfunction

function! jusi#focus#refresh_client_window(...) abort
  let l:bufnr = a:0 >= 1 ? str2nr(a:1) : bufnr('%')
  if l:bufnr != bufnr('%')
    return 0
  endif
  return s:apply_client_window_options()
endfunction

function! s:prime_visible_client_window(winid) abort
  if a:winid <= 0 || !exists('*win_execute')
    return 0
  endif
  call win_execute(a:winid, 'setlocal nonumber norelativenumber', 'silent!')
  call jusi#statusline#setup_client(a:winid)
  call jusi#client#follow_terminal_output(winbufnr(a:winid))
  return 1
endfunction

function! jusi#focus#prime_client_windows_for_buffer(bufnr) abort
  if !jusi#buffer#is_valid_bufnr(a:bufnr)
    return 0
  endif
  let l:primed = 0
  for l:info in filter(copy(getwininfo()), {_, v -> get(v, 'bufnr', 0) == a:bufnr})
    let l:primed += s:prime_visible_client_window(get(l:info, 'winid', 0))
  endfor
  return l:primed
endfunction

function! s:restore_terminal_job_mode_if_visible(winid, bufnr) abort
  if has('nvim') || a:winid <= 0 || !exists('*win_execute') || !exists('*win_id2win')
    return 0
  endif
  if win_id2win(a:winid) <= 0 || winbufnr(a:winid) != a:bufnr
    return 0
  endif
  return jusi#client#restore_terminal_job_mode(a:winid, a:bufnr)
endfunction

function! s:find_window_for_buffer(bufnr) abort
  for l:tab in gettabinfo()
    for l:win in get(l:tab, 'windows', [])
      if winbufnr(l:win) == a:bufnr
        return {'tabnr': l:tab.tabnr, 'winnr': bufwinnr(a:bufnr)}
      endif
    endfor
  endfor
  return {}
endfunction

function! s:jump_to_buffer(bufnr) abort
  if !jusi#buffer#is_valid_bufnr(a:bufnr)
    echohl ErrorMsg
    echom 'Attached client buffer is missing locally'
    echohl None
    return 0
  endif
  let l:wininfo = filter(copy(getwininfo()), {_, v -> v.bufnr == a:bufnr})
  if !empty(l:wininfo)
    let l:info = l:wininfo[0]
    execute 'tabnext ' . l:info.tabnr
    execute l:info.winnr . 'wincmd w'
    call s:apply_client_window_options()
    return a:bufnr
  endif
  execute 'sbuffer ' . a:bufnr
  call s:apply_client_window_options()
  return a:bufnr
endfunction

function! jusi#focus#place_client_buffer(bufnr, ...) abort
  if !jusi#buffer#is_valid_bufnr(a:bufnr)
    return 0
  endif
  let l:layout = a:0 >= 1 ? a:1 : get(g:, 'jusi_client_layout', 'bsplit')
  let l:return_focus = a:0 >= 2 ? a:2 : 1
  let l:source_bufnr = bufnr('%')
  let l:source_winid = win_getid()
  let l:wininfo = filter(copy(getwininfo()), {_, v -> v.bufnr == a:bufnr})
  if l:return_focus && !empty(l:wininfo) && l:source_bufnr != a:bufnr
    call s:prime_visible_client_window(l:wininfo[0].winid)
    return a:bufnr
  endif
  if empty(l:wininfo)
    execute jusi#window#client_layout_command(l:layout) . ' | buffer ' . a:bufnr
  else
    let l:info = l:wininfo[0]
    execute 'tabnext ' . l:info.tabnr
    execute l:info.winnr . 'wincmd w'
  endif
  call s:apply_client_window_options()
  if l:return_focus && win_gotoid(l:source_winid)
    return a:bufnr
  endif
  return a:bufnr
endfunction

function! s:first_notebook_buffer() abort
  for l:info in getbufinfo({'buflisted': 1})
    if getbufvar(l:info.bufnr, '&filetype') ==# 'jusinb'
      return l:info.bufnr
    endif
  endfor
  for l:info in getbufinfo()
    if getbufvar(l:info.bufnr, '&filetype') ==# 'jusinb'
      return l:info.bufnr
    endif
  endfor
  return 0
endfunction

function! s:focus_current_cell_client() abort
  let l:notebook_bufnr = bufnr('%')
  let l:cell = jusi#notebook#cell_at_line(bufnr('%'), line('.'))
  if empty(l:cell) || get(l:cell, 'client_bufnr', -1) < 0
    echohl ErrorMsg
    echom 'No attached client for the current cell'
    echohl None
    return 0
  endif
  let l:binding = jusi#client#validate_attached_binding(
        \ l:notebook_bufnr,
        \ get(l:cell, 'id', 0),
        \ get(l:cell, 'client_id', ''),
        \ get(l:cell, 'client_bufnr', -1))
  if !get(l:binding, 'ok', 0)
    let l:recovered = jusi#client#recover_attached_buffer(
          \ l:notebook_bufnr,
          \ get(l:cell, 'id', 0),
          \ get(l:cell, 'client_id', ''))
    if l:recovered > 0
      call jusi#session#repair_local_client_binding(
            \ l:cell.id,
            \ get(l:cell, 'client_id', ''),
            \ l:recovered,
            \ l:notebook_bufnr)
      let l:cell = jusi#notebook#cell_at_line(l:notebook_bufnr, line('.'))
    else
      echohl ErrorMsg
      echom 'Attached client buffer is missing locally'
      echohl None
      return 0
    endif
  endif
  return s:jump_to_buffer(l:cell.client_bufnr)
endfunction

function! s:focus_client_cell() abort
  let l:notebook_bufnr = getbufvar(bufnr('%'), 'jusi_client_notebook_bufnr', 0)
  let l:cell_id = getbufvar(bufnr('%'), 'jusi_client_cell_id', 0)
  if l:notebook_bufnr <= 0 || !bufexists(l:notebook_bufnr)
    echohl ErrorMsg
    echom 'No notebook found for the current client buffer'
    echohl None
    return 0
  endif
  call s:jump_to_buffer(l:notebook_bufnr)
  if l:cell_id > 0
    call jusi#notebook#goto_cell_id(l:cell_id, l:notebook_bufnr)
  endif
  return l:notebook_bufnr
endfunction

function! s:focus_first_notebook() abort
  let l:bufnr = s:first_notebook_buffer()
  if l:bufnr <= 0
    echohl ErrorMsg
    echom 'No Jusivim notebook buffer found'
    echohl None
    return 0
  endif
  return s:jump_to_buffer(l:bufnr)
endfunction

function! jusi#focus#toggle() abort
  let l:bufnr = bufnr('%')
  if getbufvar(l:bufnr, '&filetype') ==# 'jusinb'
    return s:focus_current_cell_client()
  endif
  if getbufvar(l:bufnr, 'jusi_client_managed', 0)
        \ || getbufvar(l:bufnr, 'jusi_client_notebook_bufnr', 0) > 0
    return s:focus_client_cell()
  endif
  return s:focus_first_notebook()
endfunction

function! jusi#focus#toggle_from_terminal() abort
  let l:client_bufnr = bufnr('%')
  let l:client_winid = exists('*win_getid') ? win_getid() : 0
  call jusi#client#debug_terminal_focus('toggle-from-terminal-begin', {
        \ 'client_bufnr': l:client_bufnr,
        \ 'client_winid': l:client_winid,
        \ 'mode': mode(),
        \ 'notebook_bufnr': getbufvar(l:client_bufnr, 'jusi_client_notebook_bufnr', 0),
        \ 'cell_id': getbufvar(l:client_bufnr, 'jusi_client_cell_id', 0),
        \ })
  let l:result = jusi#focus#toggle()
  call jusi#client#debug_terminal_focus('toggle-from-terminal-after-toggle', {
        \ 'client_bufnr': l:client_bufnr,
        \ 'client_winid': l:client_winid,
        \ 'result': l:result,
        \ 'current_bufnr': bufnr('%'),
        \ 'current_winid': exists('*win_getid') ? win_getid() : 0,
        \ 'mode': mode(),
        \ })
  call s:restore_terminal_job_mode_if_visible(l:client_winid, l:client_bufnr)
  return l:result
endfunction
