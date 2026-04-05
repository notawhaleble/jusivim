function! s:apply_client_window_options() abort
  if !getbufvar(bufnr('%'), 'jusi_client_managed', 0)
        \ && getbufvar(bufnr('%'), 'jusi_client_notebook_bufnr', 0) <= 0
    return 0
  endif
  setlocal nonumber norelativenumber
  nnoremap <silent> <buffer> <C-\><C-\> :JusiToggleFocus<CR>
  inoremap <silent> <buffer> <C-\><C-\> <C-R>=jusi#focus#toggle()<CR>
  return 1
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
  let l:source_winid = win_getid()
  let l:wininfo = filter(copy(getwininfo()), {_, v -> v.bufnr == a:bufnr})
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
  if !bufexists(l:cell.client_bufnr)
    let l:recovered = jusi#client#recover_attached_buffer(
          \ l:notebook_bufnr,
          \ get(l:cell, 'id', 0),
          \ get(l:cell, 'client_id', ''))
    if l:recovered > 0
      call jusi#session#callback_cell(l:cell.id, {'client_bufnr': l:recovered, 'client_state': 'active'}, l:notebook_bufnr)
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
