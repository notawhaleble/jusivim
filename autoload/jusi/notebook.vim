let s:delimiter_pattern = '^##\s*$'

function! s:normalize_bufnr(bufnr) abort
  if a:bufnr is# 0 || a:bufnr is# ''
    return bufnr('%')
  endif
  return str2nr(a:bufnr)
endfunction

function! s:is_notebook_buffer(bufnr) abort
  return bufexists(a:bufnr) && getbufvar(a:bufnr, '&filetype') ==# 'jusinb'
endfunction

function! s:ensure_state(bufnr) abort
  if !has_key(getbufvar(a:bufnr, ''), 'jusi_nb')
    call setbufvar(a:bufnr, 'jusi_nb', {
          \ 'bufnr': a:bufnr,
          \ 'changedtick': -1,
          \ 'next_cell_id': 1,
          \ 'cells': [],
          \ })
  endif
  return getbufvar(a:bufnr, 'jusi_nb')
endfunction

function! s:max_cell_id(cells) abort
  let l:max_id = 0
  for l:cell in a:cells
    let l:max_id = max([l:max_id, get(l:cell, 'id', 0)])
  endfor
  return l:max_id
endfunction

function! s:new_cell_id(state) abort
  let l:id = a:state.next_cell_id
  let a:state.next_cell_id += 1
  return l:id
endfunction

function! s:default_cell(raw, state) abort
  return {
        \ 'id': s:new_cell_id(a:state),
        \ 'start': a:raw.start,
        \ 'end': a:raw.end,
        \ 'kind': a:raw.kind,
        \ 'magic': a:raw.magic,
        \ 'syntax': a:raw.syntax,
        \ 'status': 'initial',
        \ 'sign_id': 0,
        \ 'client_bufnr': -1,
        \ }
endfunction

function! s:assign_sign_id(cell) abort
  let a:cell.sign_id = 1000 + a:cell.id
endfunction

function! s:first_content_line(lines, start_idx, end_idx) abort
  let l:i = a:start_idx
  while l:i <= a:end_idx
    let l:line = a:lines[l:i - 1]
    if l:line !~# '^\s*$'
      return l:line
    endif
    let l:i += 1
  endwhile
  return ''
endfunction

function! s:derive_cell_type(lines, start_lnum, end_lnum) abort
  if a:start_lnum + 1 > a:end_lnum
    let l:first = ''
  else
    let l:first = s:first_content_line(a:lines, a:start_lnum + 1, a:end_lnum)
  endif
  if l:first =~# '^%%\(\k\+\)'
    let l:magic = matchstr(l:first, '^%%\zs\k\+')
    return {
          \ 'kind': 'magic',
          \ 'magic': l:magic,
          \ 'syntax': l:magic,
          \ }
  endif
  return {
        \ 'kind': 'code',
        \ 'magic': '',
        \ 'syntax': 'python',
        \ }
endfunction

function! s:parse_raw_cells(lines) abort
  let l:cells = []
  let l:line_count = len(a:lines)
  let l:start = -1
  let l:lnum = 1

  while l:lnum <= l:line_count
    let l:line = a:lines[l:lnum - 1]
    if l:line =~# s:delimiter_pattern
      if l:start != -1
        let l:type_info = s:derive_cell_type(a:lines, l:start, l:lnum - 1)
        call add(l:cells, {
              \ 'start': l:start,
              \ 'end': l:lnum - 1,
              \ 'kind': l:type_info.kind,
              \ 'magic': l:type_info.magic,
              \ 'syntax': l:type_info.syntax,
              \ })
      endif
      let l:start = l:lnum
    endif
    let l:lnum += 1
  endwhile

  if l:start != -1
    let l:type_info = s:derive_cell_type(a:lines, l:start, l:line_count)
    call add(l:cells, {
          \ 'start': l:start,
          \ 'end': l:line_count,
          \ 'kind': l:type_info.kind,
          \ 'magic': l:type_info.magic,
          \ 'syntax': l:type_info.syntax,
          \ })
  endif

  return l:cells
endfunction

function! s:interval_overlap(a_start, a_end, b_start, b_end) abort
  let l:start = max([a:a_start, a:b_start])
  let l:end = min([a:a_end, a:b_end])
  return max([0, l:end - l:start + 1])
endfunction

function! s:preserve_cell_state(raw_cells, prev_cells, state) abort
  let l:cells = []
  let l:used_prev = {}

  for l:raw in a:raw_cells
    let l:best_idx = -1
    let l:best_overlap = -1
    let l:i = 0
    while l:i < len(a:prev_cells)
      if has_key(l:used_prev, l:i)
        let l:i += 1
        continue
      endif
      let l:prev = a:prev_cells[l:i]
      let l:overlap = s:interval_overlap(l:raw.start, l:raw.end, l:prev.start, l:prev.end)
      if l:overlap > l:best_overlap
        let l:best_overlap = l:overlap
        let l:best_idx = l:i
      endif
      let l:i += 1
    endwhile

    if l:best_idx >= 0 && l:best_overlap > 0
      let l:prev = copy(a:prev_cells[l:best_idx])
      let l:prev.start = l:raw.start
      let l:prev.end = l:raw.end
      let l:prev.kind = l:raw.kind
      let l:prev.magic = l:raw.magic
      if !has_key(l:prev, 'syntax') || empty(l:prev.syntax)
        let l:prev.syntax = l:raw.syntax
      endif
      call s:assign_sign_id(l:prev)
      let l:used_prev[l:best_idx] = 1
      call add(l:cells, l:prev)
    else
      let l:cell = s:default_cell(l:raw, a:state)
      call s:assign_sign_id(l:cell)
      call add(l:cells, l:cell)
    endif
  endfor

  return l:cells
endfunction

function! jusi#notebook#parse_lines(lines, ...) abort
  let l:prev_state = a:0 >= 1 ? a:1 : {}
  let l:prev_cells = get(l:prev_state, 'cells', [])
  let l:next_cell_id = get(l:prev_state, 'next_cell_id', s:max_cell_id(l:prev_cells) + 1)
  let l:state = {'next_cell_id': l:next_cell_id}
  let l:raw_cells = s:parse_raw_cells(a:lines)
  let l:cells = s:preserve_cell_state(l:raw_cells, l:prev_cells, l:state)
  return {
        \ 'next_cell_id': l:state.next_cell_id,
        \ 'cells': l:cells,
        \ }
endfunction

function! jusi#notebook#rebuild(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  if !s:is_notebook_buffer(l:bufnr)
    return {}
  endif

  let l:state = s:ensure_state(l:bufnr)
  let l:tick = getbufvar(l:bufnr, 'changedtick')
  if l:state.changedtick ==# l:tick
    return l:state
  endif

  let l:lines = getbufline(l:bufnr, 1, '$')
  let l:parsed = jusi#notebook#parse_lines(l:lines, l:state)
  let l:state.cells = l:parsed.cells
  let l:state.next_cell_id = max([l:state.next_cell_id, l:parsed.next_cell_id])
  let l:state.changedtick = l:tick

  call setbufvar(l:bufnr, 'jusi_nb', l:state)
  call jusi#render#sync_signs(l:bufnr, l:state.cells)
  call jusi#syntax#sync(l:bufnr, l:state.cells)
  return l:state
endfunction

function! jusi#notebook#state(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  return s:ensure_state(l:bufnr)
endfunction

function! jusi#notebook#cells(...) abort
  let l:state = jusi#notebook#rebuild(a:0 >= 1 ? a:1 : bufnr('%'))
  return get(l:state, 'cells', [])
endfunction

function! jusi#notebook#cell_at_line(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  let l:lnum = a:0 >= 2 ? a:2 : line('.')
  let l:state = jusi#notebook#rebuild(l:bufnr)
  if empty(l:state)
    return {}
  endif
  let l:idx = s:cell_index_at_line(l:state, l:lnum)
  if l:idx < 0
    return {}
  endif
  return l:state.cells[l:idx]
endfunction

function! s:cell_index_at_line(state, lnum) abort
  let l:low = 0
  let l:high = len(a:state.cells) - 1

  while l:low <= l:high
    let l:mid = (l:low + l:high) / 2
    let l:cell = a:state.cells[l:mid]
    if a:lnum < l:cell.start
      let l:high = l:mid - 1
    elseif a:lnum > l:cell.end
      let l:low = l:mid + 1
    else
      return l:mid
    endif
  endwhile

  return -1
endfunction

function! s:goto_cell_line(target_line) abort
  call cursor(a:target_line, 1)
  normal! zv
endfunction

function! s:cell_entry_line(cell) abort
  if empty(a:cell)
    return line('.')
  endif
  if a:cell.start < a:cell.end
    return a:cell.start + 1
  endif
  return a:cell.start
endfunction

function! s:goto_cell(cell) abort
  call s:goto_cell_line(s:cell_entry_line(a:cell))
endfunction

function! jusi#notebook#goto_next() abort
  let l:state = jusi#notebook#rebuild()
  let l:idx = s:cell_index_at_line(l:state, line('.'))
  if l:idx >= 0 && l:idx + 1 < len(l:state.cells)
    let l:cell = l:state.cells[l:idx + 1]
    call s:goto_cell(l:cell)
    return l:cell
  endif
  return {}
endfunction

function! jusi#notebook#goto_prev() abort
  let l:state = jusi#notebook#rebuild()
  let l:idx = s:cell_index_at_line(l:state, line('.'))
  if l:idx > 0
    let l:cell = l:state.cells[l:idx - 1]
    call s:goto_cell(l:cell)
    return l:cell
  endif
  return {}
endfunction

function! s:insert_cell_at(lnum) abort
  let l:line_count = line('$')
  if l:line_count == 1 && getline(1) ==# ''
    call setline(1, ['##', ''])
  else
    call append(a:lnum - 1, ['##', ''])
  endif
  call jusi#notebook#rebuild()
endfunction

function! s:enter_insert_at_cell(cell) abort
  call s:goto_cell(a:cell)
  startinsert
endfunction

function! jusi#notebook#insert_above() abort
  let l:cell = jusi#notebook#cell_at_line(bufnr('%'), line('.'))
  let l:target = empty(l:cell) ? line('.') : l:cell.start
  call s:insert_cell_at(l:target)
  let l:new_cell = jusi#notebook#cell_at_line(bufnr('%'), l:target)
  call s:enter_insert_at_cell(l:new_cell)
endfunction

function! jusi#notebook#insert_below() abort
  let l:cell = jusi#notebook#cell_at_line(bufnr('%'), line('.'))
  let l:target = empty(l:cell) ? line('$') + 1 : l:cell.end + 1
  call s:insert_cell_at(l:target)
  let l:new_cell = jusi#notebook#cell_at_line(bufnr('%'), l:target)
  call s:enter_insert_at_cell(l:new_cell)
endfunction
