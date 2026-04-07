let s:delimiter_pattern = '^##\s*$'
let s:history_start_pattern = '^##<<\s*$'
let s:history_end_pattern = '^##>>\s*$'
let s:history_entry_pattern = '^###\s*$'

let s:buffer_cache = {}
let s:buffer_listener = {}
let s:bypass_quit_guard = 0
let s:bypass_wipeout_guard = {}

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

function! s:normalize_bufnr(bufnr) abort
  if a:bufnr is# 0 || a:bufnr is# ''
    return bufnr('%')
  endif
  return str2nr(a:bufnr)
endfunction

function! s:echo_error(message) abort
  echohl ErrorMsg
  echom a:message
  echohl None
endfunction

function! s:is_notebook_buffer(bufnr) abort
  return bufexists(a:bufnr) && getbufvar(a:bufnr, '&filetype') ==# 'jusinb'
endfunction

function! s:is_valid_cell_range(cell) abort
  if get(a:cell, 'start', 0) <= 0 || get(a:cell, 'end', 0) < get(a:cell, 'start', 0)
    return 0
  endif
  let l:body_end = get(a:cell, 'body_end', get(a:cell, 'end', 0))
  if l:body_end < get(a:cell, 'start', 0) || l:body_end > get(a:cell, 'end', 0)
    return 0
  endif
  let l:history_start = get(a:cell, 'history_start', 0)
  let l:history_end = get(a:cell, 'history_end', 0)
  if l:history_start > 0
    if l:history_start < get(a:cell, 'start', 0) || l:history_start > get(a:cell, 'end', 0)
      return 0
    endif
  endif
  if l:history_end > 0
    if l:history_end < get(a:cell, 'start', 0) || l:history_end > get(a:cell, 'end', 0)
      return 0
    endif
  endif
  return 1
endfunction

function! s:state_consistent(bufnr, state) abort
  let l:cells = get(a:state, 'cells', [])
  if empty(l:cells)
    return 0
  endif
  let l:line_count = line('$')
  if get(l:cells[0], 'start', 0) != 1
    return 0
  endif
  if get(l:cells[-1], 'end', 0) != l:line_count
    return 0
  endif

  let l:prev_end = 0
  for l:cell in l:cells
    if !s:is_valid_cell_range(l:cell)
      return 0
    endif
    if get(l:cell, 'start', 0) != l:prev_end + 1
      return 0
    endif
    if getline(l:cell.start) !~# s:delimiter_pattern
      return 0
    endif
    let l:prev_end = l:cell.end
  endfor
  return 1
endfunction

function! s:ensure_initial_delimiter(bufnr) abort
  let l:lines = getbufline(a:bufnr, 1, '$')
  if len(l:lines) == 1 && l:lines[0] ==# ''
    call setbufline(a:bufnr, 1, ['##'])
  endif
endfunction

function! s:ensure_state(bufnr) abort
  if !has_key(getbufvar(a:bufnr, ''), 'jusi_nb')
    call setbufvar(a:bufnr, 'jusi_nb', {
      \ 'bufnr': a:bufnr,
      \ 'changedtick': -1,
      \ 'next_cell_id': 1,
      \ 'cells': [],
      \ 'session': jusi#session#default_state(),
      \ 'dirty_insert': 0,
      \ 'inserted_cell_hint': {},
      \ 'syntax_dirty': 0,
      \ 'syntax_dirty_from': 0,
      \ 'consistency_check_pending': 0,
          \ })
  elseif !has_key(getbufvar(a:bufnr, 'jusi_nb'), 'session')
    let l:state = getbufvar(a:bufnr, 'jusi_nb')
    let l:state.session = jusi#session#default_state()
    call setbufvar(a:bufnr, 'jusi_nb', l:state)
  endif
  return getbufvar(a:bufnr, 'jusi_nb')
endfunction

function! s:ensure_buffer_tracking(bufnr) abort
  if !has_key(s:buffer_cache, a:bufnr)
    let s:buffer_cache[a:bufnr] = {
          \ 'lines': getbufline(a:bufnr, 1, '$'),
          \ 'change': {},
          \ }
  endif
  if exists('*listener_add') && !has_key(s:buffer_listener, a:bufnr)
    let s:buffer_listener[a:bufnr] = listener_add(function('s:on_buffer_change'), a:bufnr)
  endif
endfunction

function! s:is_inserted_cell_hint(cell, hint) abort
  return type(a:hint) == type({})
        \ && get(a:hint, 'start', 0) ==# get(a:cell, 'start', -1)
        \ && get(a:hint, 'end', 0) ==# get(a:cell, 'end', -1)
endfunction

function! s:find_prev_cell_by_id(prev_cells, used_prev, cell_id) abort
  if a:cell_id <= 0
    return -1
  endif
  let l:idx = 0
  while l:idx < len(a:prev_cells)
    if has_key(a:used_prev, l:idx)
      let l:idx += 1
      continue
    endif
    if get(a:prev_cells[l:idx], 'id', 0) == a:cell_id
      return l:idx
    endif
    let l:idx += 1
  endwhile
  return -1
endfunction

function! s:on_buffer_change(bufnr, start, end, added, changes) abort
  let s:buffer_cache[a:bufnr] = get(s:buffer_cache, a:bufnr, {'lines': [], 'change': {}})
  let s:buffer_cache[a:bufnr].change = {
        \ 'start': a:start,
        \ 'end': a:end,
        \ 'added': a:added,
        \ 'changes': copy(a:changes),
        \ }
endfunction

function! s:update_buffer_cache_lines(bufnr, lines) abort
  call s:ensure_buffer_tracking(a:bufnr)
  let s:buffer_cache[a:bufnr].lines = copy(a:lines)
  let s:buffer_cache[a:bufnr].change = {}
endfunction

function! s:buffer_cache_lines(bufnr) abort
  call s:ensure_buffer_tracking(a:bufnr)
  return get(s:buffer_cache[a:bufnr], 'lines', [])
endfunction

function! s:last_change(bufnr) abort
  call s:ensure_buffer_tracking(a:bufnr)
  return get(s:buffer_cache[a:bufnr], 'change', {})
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

function! s:assign_sign_id(cell) abort
  let a:cell.sign_id = 1000 + a:cell.id
endfunction

function! s:first_content_line(lines, start_idx, end_idx) abort
  let l:line_count = len(a:lines)
  if l:line_count == 0
    return ''
  endif
  let l:i = max([1, a:start_idx])
  let l:last = min([a:end_idx, l:line_count])
  while l:i <= l:last
    let l:line = a:lines[l:i - 1]
    if l:line !~# '^\s*$'
      return l:line
    endif
    let l:i += 1
  endwhile
  return ''
endfunction

function! s:default_syntax(kind, magic) abort
  if a:kind ==# 'magic'
    return a:magic
  endif
  return 'python'
endfunction

function! s:cell_signature(lines, start_lnum, end_lnum) abort
  let l:text = join(a:lines[a:start_lnum - 1 : a:end_lnum - 1], "\n")
  if exists('*sha256')
    return sha256(l:text)
  endif
  return l:text
endfunction

function! s:is_default_syntax(cell) abort
  return get(a:cell, 'syntax', '') ==# s:default_syntax(get(a:cell, 'kind', ''), get(a:cell, 'magic', ''))
endfunction

function! s:make_parsed_cell(start, end_, kind, magic, signature) abort
  return {
        \ 'start': a:start,
        \ 'end': a:end_,
        \ 'body_end': a:end_,
        \ 'history_start': 0,
        \ 'history_end': 0,
        \ 'kind': a:kind,
        \ 'magic': a:magic,
        \ 'syntax': s:default_syntax(a:kind, a:magic),
        \ 'signature': a:signature,
        \ }
endfunction

function! s:find_history_region(lines, start_lnum, end_lnum) abort
  let l:history_start = 0
  let l:history_end = 0
  let l:lnum = a:start_lnum + 1

  while l:lnum <= a:end_lnum
    let l:line = a:lines[l:lnum - 1]
    if l:line =~# s:history_start_pattern
      let l:history_start = l:lnum
      break
    endif
    let l:lnum += 1
  endwhile

  if l:history_start > 0
    let l:lnum = l:history_start + 1
    while l:lnum <= a:end_lnum
      if a:lines[l:lnum - 1] =~# s:history_end_pattern
        let l:history_end = l:lnum
        break
      endif
      let l:lnum += 1
    endwhile
  endif

  return {
        \ 'history_start': l:history_start,
        \ 'history_end': l:history_end,
        \ 'body_end': l:history_start > 0 ? l:history_start - 1 : a:end_lnum,
        \ }
endfunction

function! s:decorate_parsed_cell(lines, cell) abort
  let l:history = s:find_history_region(a:lines, a:cell.start, a:cell.end)
  let a:cell.body_end = l:history.body_end
  let a:cell.history_start = l:history.history_start
  let a:cell.history_end = l:history.history_end
  return a:cell
endfunction

function! s:init_runtime_cell(parsed, state) abort
  let l:cell = copy(a:parsed)
  let l:cell.id = s:new_cell_id(a:state)
  let l:cell.status = 'initial'
  let l:cell.pending_input = {}
  let l:cell.handler = {'id': '', 'last_message_type': '', 'payload': {}, 'snapshot': {}}
  let l:cell.parked_status = ''
  let l:cell.sign_id = 0
  let l:cell.client_id = ''
  let l:cell.client_state = 'shutdown'
  let l:cell.client_bufnr = -1
  let l:cell.owner = {'kind': ''}
  let l:cell.close_requested = 0
  call s:assign_sign_id(l:cell)
  return l:cell
endfunction

function! s:merge_runtime_cell(prev, parsed) abort
  let l:cell = copy(a:parsed)
  let l:cell.id = get(a:prev, 'id', 0)
  let l:cell.status = get(a:prev, 'status', 'initial')
  let l:cell.pending_input = copy(get(a:prev, 'pending_input', {}))
  let l:cell.handler = copy(get(a:prev, 'handler', {'id': '', 'last_message_type': '', 'payload': {}, 'snapshot': {}}))
  let l:cell.parked_status = get(a:prev, 'parked_status', '')
  let l:cell.sign_id = get(a:prev, 'sign_id', 0)
  let l:cell.client_id = get(a:prev, 'client_id', '')
  let l:cell.client_state = get(a:prev, 'client_state', 'shutdown')
  let l:cell.client_bufnr = get(a:prev, 'client_bufnr', -1)
  let l:cell.owner = copy(get(a:prev, 'owner', {'kind': ''}))
  let l:cell.close_requested = get(a:prev, 'close_requested', 0)

  if has_key(a:prev, 'syntax') && !empty(a:prev.syntax) && !s:is_default_syntax(a:prev)
    let l:cell.syntax = a:prev.syntax
  endif

  call s:assign_sign_id(l:cell)
  return l:cell
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
          \ 'syntax': s:default_syntax('magic', l:magic),
          \ }
  endif
  return {
        \ 'kind': 'code',
        \ 'magic': '',
        \ 'syntax': s:default_syntax('code', ''),
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
        let l:cell = s:make_parsed_cell(
              \ l:start,
              \ l:lnum - 1,
              \ l:type_info.kind,
              \ l:type_info.magic,
              \ s:cell_signature(a:lines, l:start, l:lnum - 1))
        call add(l:cells, s:decorate_parsed_cell(a:lines, l:cell))
      endif
      let l:start = l:lnum
    endif
    let l:lnum += 1
  endwhile

  if l:start != -1
    let l:type_info = s:derive_cell_type(a:lines, l:start, l:line_count)
    let l:cell = s:make_parsed_cell(
          \ l:start,
          \ l:line_count,
          \ l:type_info.kind,
          \ l:type_info.magic,
          \ s:cell_signature(a:lines, l:start, l:line_count))
    call add(l:cells, s:decorate_parsed_cell(a:lines, l:cell))
  endif

  return l:cells
endfunction

function! s:interval_overlap(a_start, a_end, b_start, b_end) abort
  let l:start = max([a:a_start, a:b_start])
  let l:end = min([a:a_end, a:b_end])
  return max([0, l:end - l:start + 1])
endfunction

function! s:match_score(parsed, prev) abort
  let l:score = s:interval_overlap(a:parsed.start, a:parsed.end, a:prev.start, a:prev.end)
  if get(a:parsed, 'signature', '') !=# '' && get(a:parsed, 'signature', '') ==# get(a:prev, 'signature', '')
    let l:score += 1000000
  endif
  return l:score
endfunction

function! s:add_signature_index(map, cell, idx) abort
  let l:signature = get(a:cell, 'signature', '')
  if empty(l:signature)
    return
  endif
  if !has_key(a:map, l:signature)
    let a:map[l:signature] = []
  endif
  call add(a:map[l:signature], a:idx)
endfunction

function! s:take_signature_match(map, prev_cells, used_prev, signature, parsed) abort
  if empty(a:signature) || !has_key(a:map, a:signature)
    return -1
  endif
  let l:had_multiple = len(a:map[a:signature]) > 1
  let l:best_idx = -1
  let l:best_score = -1
  let l:best_overlap = -1
  let l:keep = []
  while !empty(a:map[a:signature])
    let l:idx = remove(a:map[a:signature], 0)
    if has_key(a:used_prev, l:idx)
      continue
    endif
    let l:score = s:match_score(a:parsed, a:prev_cells[l:idx])
    let l:overlap = s:interval_overlap(a:parsed.start, a:parsed.end, a:prev_cells[l:idx].start, a:prev_cells[l:idx].end)
    if l:score > l:best_score
      if l:best_idx >= 0
        call add(l:keep, l:best_idx)
      endif
      let l:best_idx = l:idx
      let l:best_score = l:score
      let l:best_overlap = l:overlap
    else
      call add(l:keep, l:idx)
    endif
  endwhile
  let a:map[a:signature] = l:keep
  if l:had_multiple && l:best_overlap <= 0
    if l:best_idx >= 0
      call insert(a:map[a:signature], l:best_idx, 0)
    endif
    return -1
  endif
  if l:best_idx >= 0
    return l:best_idx
  endif
  return -1
endfunction

function! s:take_local_overlap_match(prev_cells, used_prev, parsed, parsed_idx) abort
  let l:candidates = [a:parsed_idx, a:parsed_idx - 1, a:parsed_idx + 1]
  let l:best_idx = -1
  let l:best_score = -1

  for l:idx in l:candidates
    if l:idx < 0 || l:idx >= len(a:prev_cells) || has_key(a:used_prev, l:idx)
      continue
    endif
    let l:score = s:interval_overlap(a:parsed.start, a:parsed.end, a:prev_cells[l:idx].start, a:prev_cells[l:idx].end)
    if l:score > l:best_score
      let l:best_score = l:score
      let l:best_idx = l:idx
    endif
  endfor

  if l:best_score > 0
    return l:best_idx
  endif
  return -1
endfunction

function! s:reconcile_cells(parsed_cells, prev_cells, state) abort
  let l:cells = repeat([{}], len(a:parsed_cells))
  let l:used_prev = {}
  let l:signature_map = {}
  let l:inserted_hint = get(a:state, 'inserted_cell_hint', {})
  let l:unmatched = []
  let l:i = 0

  while l:i < len(a:prev_cells)
    call s:add_signature_index(l:signature_map, a:prev_cells[l:i], l:i)
    let l:i += 1
  endwhile

  let l:parsed_idx = 0
  for l:parsed in a:parsed_cells
    if s:is_inserted_cell_hint(l:parsed, l:inserted_hint)
      let l:hint_idx = s:find_prev_cell_by_id(a:prev_cells, l:used_prev, get(l:inserted_hint, 'id', 0))
      if l:hint_idx >= 0
        let l:used_prev[l:hint_idx] = 1
        let l:cells[l:parsed_idx] = s:merge_runtime_cell(a:prev_cells[l:hint_idx], l:parsed)
      else
        let l:cells[l:parsed_idx] = s:init_runtime_cell(l:parsed, a:state)
      endif
      let l:parsed_idx += 1
      continue
    endif
    let l:best_idx = s:take_signature_match(l:signature_map, a:prev_cells, l:used_prev, get(l:parsed, 'signature', ''), l:parsed)
    if l:best_idx >= 0
      let l:used_prev[l:best_idx] = 1
      let l:cells[l:parsed_idx] = s:merge_runtime_cell(a:prev_cells[l:best_idx], l:parsed)
    else
      call add(l:unmatched, {'idx': l:parsed_idx, 'parsed': l:parsed})
    endif
    let l:parsed_idx += 1
  endfor

  for l:item in l:unmatched
    let l:best_idx = s:take_local_overlap_match(a:prev_cells, l:used_prev, l:item.parsed, l:item.idx)
    if l:best_idx >= 0
      let l:used_prev[l:best_idx] = 1
      let l:cells[l:item.idx] = s:merge_runtime_cell(a:prev_cells[l:best_idx], l:item.parsed)
    else
      let l:cells[l:item.idx] = s:init_runtime_cell(l:item.parsed, a:state)
    endif
  endfor

  return l:cells
endfunction

function! s:shutdown_lost_cells(bufnr, prev_cells, next_cells, reason) abort
  let l:next_ids = {}
  for l:cell in a:next_cells
    let l:next_ids[get(l:cell, 'id', 0)] = 1
  endfor

  for l:cell in a:prev_cells
    let l:cell_id = get(l:cell, 'id', 0)
    if l:cell_id <= 0 || has_key(l:next_ids, l:cell_id)
      continue
    endif
    if empty(get(l:cell, 'client_id', '')) && get(l:cell, 'client_bufnr', -1) < 0
      continue
    endif
    call jusi#session#shutdown_cell_client(l:cell_id, a:reason, a:bufnr)
  endfor
endfunction

function! jusi#notebook#parse_lines(lines, ...) abort
  let l:prev_state = a:0 >= 1 ? a:1 : {}
  let l:prev_cells = get(l:prev_state, 'cells', [])
  let l:next_cell_id = get(l:prev_state, 'next_cell_id', s:max_cell_id(l:prev_cells) + 1)
  let l:state = {
        \ 'next_cell_id': l:next_cell_id,
        \ 'inserted_cell_hint': copy(get(l:prev_state, 'inserted_cell_hint', {})),
        \ }
  let l:parsed_cells = s:parse_raw_cells(a:lines)
  let l:cells = s:reconcile_cells(l:parsed_cells, l:prev_cells, l:state)
  return {
        \ 'next_cell_id': l:state.next_cell_id,
        \ 'cells': l:cells,
        \ }
endfunction

function! s:parse_cell_at(lines, cell) abort
  let l:type_info = s:derive_cell_type(a:lines, a:cell.start, a:cell.end)
  return s:make_parsed_cell(
        \ a:cell.start,
        \ a:cell.end,
        \ l:type_info.kind,
        \ l:type_info.magic,
        \ s:cell_signature(a:lines, a:cell.start, a:cell.end))
endfunction

function! s:lines_have_delimiter(lines) abort
  for l:line in a:lines
    if l:line =~# s:delimiter_pattern
      return 1
    endif
  endfor
  return 0
endfunction

function! s:sync_from_index(bufnr, state, start_idx) abort
  let l:i = a:start_idx
  while l:i < len(a:state.cells)
    let l:cell = a:state.cells[l:i]
    execute 'sign unplace ' . l:cell.sign_id
          \ . ' group=' . jusi#render#sign_group()
          \ . ' buffer=' . a:bufnr
    execute 'sign place ' . l:cell.sign_id
          \ . ' line=' . jusi#render#sign_lnum(l:cell)
          \ . ' name=' . jusi#render#sign_name(l:cell.status)
          \ . ' group=' . jusi#render#sign_group()
          \ . ' buffer=' . a:bufnr
    let l:i += 1
  endwhile
endfunction

function! s:mark_syntax_dirty(bufnr, state, start_idx) abort
  let a:state.syntax_dirty = 1
  if get(a:state, 'syntax_dirty_from', 0) == 0
    let a:state.syntax_dirty_from = a:start_idx
  else
    let a:state.syntax_dirty_from = min([a:state.syntax_dirty_from, a:start_idx])
  endif
  call setbufvar(a:bufnr, 'jusi_nb', a:state)
endfunction

function! s:mark_consistency_check_pending(bufnr, state) abort
  let a:state.consistency_check_pending = 1
  call setbufvar(a:bufnr, 'jusi_nb', a:state)
endfunction

function! s:shift_cell_lines(cell, delta) abort
  let a:cell.start += a:delta
  let a:cell.end += a:delta
  let a:cell.body_end += a:delta
  if get(a:cell, 'history_start', 0) > 0
    let a:cell.history_start += a:delta
  endif
  if get(a:cell, 'history_end', 0) > 0
    let a:cell.history_end += a:delta
  endif
  return a:cell
endfunction

function! s:maybe_resize_cell(bufnr, state) abort
  let l:change = s:last_change(a:bufnr)
  if empty(l:change)
    return {}
  endif
  if get(l:change, 'added', 0) == 0
    return {}
  endif
  let l:changes = get(l:change, 'changes', [])
  if len(l:changes) != 1
    return {}
  endif
  let l:item = l:changes[0]
  let l:delta = get(l:item, 'added', 0)
  if l:delta == 0
    return {}
  endif

  let l:start = get(l:item, 'lnum', 0)
  let l:end = get(l:item, 'end', 0)
  if l:start <= 0
    return {}
  endif

  let l:old_lines = s:buffer_cache_lines(a:bufnr)
  let l:new_lines = getbufline(a:bufnr, 1, '$')
  let l:old_slice_start = max([1, l:start])
  let l:old_slice_end = min([len(l:old_lines), max([l:start, l:end - 1])])
  let l:new_slice_end = min([len(l:new_lines), l:old_slice_end + l:delta])
  let l:old_slice = l:old_slice_end >= l:old_slice_start ? l:old_lines[l:old_slice_start - 1 : l:old_slice_end - 1] : []
  let l:new_slice = l:new_slice_end >= l:old_slice_start ? l:new_lines[l:old_slice_start - 1 : l:new_slice_end - 1] : []

  if s:lines_have_delimiter(l:old_slice) || s:lines_have_delimiter(l:new_slice)
    return {}
  endif

  let l:idx = s:cell_index_at_line(a:state, l:start)
  if l:idx >= 0 && l:delta > 0
    let l:cell_at_start = a:state.cells[l:idx]
    if l:start == l:cell_at_start.start && l:idx > 0
      let l:prev = a:state.cells[l:idx - 1]
      if l:prev.end + 1 == l:start
        let l:idx -= 1
      endif
    endif
  endif
  if l:idx < 0
    return {}
  endif
  let l:cell = a:state.cells[l:idx]
  if l:start <= l:cell.start && !(l:delta > 0 && l:start == l:cell.end + 1)
    return {}
  endif

  let l:updated_cell = copy(l:cell)
  let l:updated_cell.end += l:delta
  if l:updated_cell.end < l:updated_cell.start
    return {}
  endif

  let l:parsed = s:parse_cell_at(l:new_lines, l:updated_cell)
  let l:updated = s:merge_runtime_cell(l:cell, l:parsed)
  let a:state.cells[l:idx] = l:updated

  let l:i = l:idx + 1
  while l:i < len(a:state.cells)
    call s:shift_cell_lines(a:state.cells[l:i], l:delta)
    let l:i += 1
  endwhile

  let a:state.changedtick = getbufvar(a:bufnr, 'changedtick')
  let a:state.dirty_insert = 0
  let a:state.consistency_check_pending = 1
  call setbufvar(a:bufnr, 'jusi_nb', a:state)
  call s:update_buffer_cache_lines(a:bufnr, l:new_lines)
  call s:mark_syntax_dirty(a:bufnr, a:state, l:idx)

  let l:i = l:idx
  while l:i < len(a:state.cells)
    let l:cell = a:state.cells[l:i]
    execute 'sign unplace ' . l:cell.sign_id
          \ . ' group=' . jusi#render#sign_group()
          \ . ' buffer=' . a:bufnr
    execute 'sign place ' . l:cell.sign_id
          \ . ' line=' . jusi#render#sign_lnum(l:cell)
          \ . ' name=' . jusi#render#sign_name(l:cell.status)
          \ . ' group=' . jusi#render#sign_group()
          \ . ' buffer=' . a:bufnr
    let l:i += 1
  endwhile
  return a:state
endfunction

function! s:maybe_fast_update(bufnr, state) abort
  let l:change = s:last_change(a:bufnr)
  if empty(l:change)
    return {}
  endif
  if get(l:change, 'added', 0) != 0
    return {}
  endif
  let l:changes = get(l:change, 'changes', [])
  if len(l:changes) != 1
    return {}
  endif
  let l:item = l:changes[0]
  if get(l:item, 'added', 0) != 0
    return {}
  endif
  let l:start = get(l:item, 'lnum', 0)
  let l:end = get(l:item, 'end', 0)
  if l:start <= 0 || l:end != l:start + 1
    return {}
  endif

  let l:old_lines = s:buffer_cache_lines(a:bufnr)
  if len(l:old_lines) != line('$')
    return {}
  endif

  let l:old_line = get(l:old_lines, l:start - 1, '')
  let l:new_line = getbufline(a:bufnr, l:start, l:start)[0]
  if l:old_line =~# s:delimiter_pattern || l:new_line =~# s:delimiter_pattern
    return {}
  endif

  let l:idx = s:cell_index_at_line(a:state, l:start)
  if l:idx < 0
    return {}
  endif
  let l:cell = a:state.cells[l:idx]
  let l:lines = copy(l:old_lines)
  let l:lines[l:start - 1] = l:new_line
  let l:parsed = s:parse_cell_at(l:lines, l:cell)
  let l:updated = s:merge_runtime_cell(l:cell, l:parsed)
  let a:state.cells[l:idx] = l:updated
  let a:state.changedtick = getbufvar(a:bufnr, 'changedtick')
  let a:state.dirty_insert = 0
  let a:state.consistency_check_pending = 1
  call setbufvar(a:bufnr, 'jusi_nb', a:state)
  call s:update_buffer_cache_lines(a:bufnr, l:lines)

  if l:cell.kind !=# l:updated.kind || l:cell.magic !=# l:updated.magic || l:cell.syntax !=# l:updated.syntax
    call jusi#syntax#sync(a:bufnr, a:state.cells)
  endif
  return a:state
endfunction

function! jusi#notebook#rebuild(...) abort
  let l:perf_start = reltime()
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  if !s:is_notebook_buffer(l:bufnr)
    return {}
  endif

  call s:ensure_initial_delimiter(l:bufnr)
  let l:state = s:ensure_state(l:bufnr)
  let l:prev_cells = copy(get(l:state, 'cells', []))
  call s:ensure_buffer_tracking(l:bufnr)
  let l:tick = getbufvar(l:bufnr, 'changedtick')
  if l:state.changedtick ==# l:tick && s:state_consistent(l:bufnr, l:state)
    call s:perf_log('rebuild-skip', l:perf_start, 'buf=' . l:bufnr)
    return l:state
  endif

  let l:lines = getbufline(l:bufnr, 1, '$')
  let l:parsed = jusi#notebook#parse_lines(l:lines, l:state)
  call s:shutdown_lost_cells(l:bufnr, l:prev_cells, l:parsed.cells, 'cell_deleted')
  let l:state.cells = l:parsed.cells
  let l:state.next_cell_id = max([l:state.next_cell_id, l:parsed.next_cell_id])
  let l:state.changedtick = l:tick
  let l:state.dirty_insert = 0
  let l:state.syntax_dirty = 0
  let l:state.syntax_dirty_from = 0
  let l:state.consistency_check_pending = 0

  call setbufvar(l:bufnr, 'jusi_nb', l:state)
  call s:update_buffer_cache_lines(l:bufnr, l:lines)
  call jusi#render#sync_signs(l:bufnr, l:state.cells)
  call jusi#syntax#sync(l:bufnr, l:state.cells)
  call s:perf_log('rebuild', l:perf_start, 'buf=' . l:bufnr . ' cells=' . len(l:state.cells))
  return l:state
endfunction

function! jusi#notebook#handle_text_changed(...) abort
  let l:perf_start = reltime()
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  if !s:is_notebook_buffer(l:bufnr)
    return {}
  endif
  let l:state = s:ensure_state(l:bufnr)
  if !empty(l:state.cells)
    let l:fast = s:maybe_fast_update(l:bufnr, l:state)
    if !empty(l:fast)
      call s:perf_log('handle_text_changed-fast', l:perf_start, 'buf=' . l:bufnr)
      return l:fast
    endif
    let l:resize = s:maybe_resize_cell(l:bufnr, l:state)
    if !empty(l:resize)
      call s:perf_log('handle_text_changed-resize', l:perf_start, 'buf=' . l:bufnr)
      return l:resize
    endif
  endif
  let l:result = jusi#notebook#rebuild(l:bufnr)
  call s:perf_log('handle_text_changed-rebuild', l:perf_start, 'buf=' . l:bufnr)
  return l:result
endfunction

function! jusi#notebook#handle_text_changed_insert(...) abort
  let l:perf_start = reltime()
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  if !s:is_notebook_buffer(l:bufnr)
    return {}
  endif
  let l:state = s:ensure_state(l:bufnr)
  if !empty(l:state.cells)
    let l:fast = s:maybe_fast_update(l:bufnr, l:state)
    if !empty(l:fast)
      call s:perf_log('handle_text_changed_insert-fast', l:perf_start, 'buf=' . l:bufnr)
      return l:fast
    endif
    let l:resize = s:maybe_resize_cell(l:bufnr, l:state)
    if !empty(l:resize)
      call s:perf_log('handle_text_changed_insert-resize', l:perf_start, 'buf=' . l:bufnr)
      return l:resize
    endif
  endif
  call jusi#notebook#invalidate(l:bufnr)
  call s:perf_log('handle_text_changed_insert-invalidate', l:perf_start, 'buf=' . l:bufnr)
  return l:state
endfunction

function! jusi#notebook#invalidate(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  if !s:is_notebook_buffer(l:bufnr)
    return
  endif
  let l:state = s:ensure_state(l:bufnr)
  let l:state.dirty_insert = 1
  call setbufvar(l:bufnr, 'jusi_nb', l:state)
endfunction

function! jusi#notebook#handle_insert_exit(...) abort
  let l:perf_start = reltime()
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  if !s:is_notebook_buffer(l:bufnr)
    return {}
  endif
  let l:state = s:ensure_state(l:bufnr)
  let l:tick = getbufvar(l:bufnr, 'changedtick')
  if get(l:state, 'dirty_insert', 0) || get(l:state, 'changedtick', -1) !=# l:tick
    let l:result = jusi#notebook#rebuild(l:bufnr)
    let l:result.inserted_cell_hint = {}
    call setbufvar(l:bufnr, 'jusi_nb', l:result)
    call s:perf_log('handle_insert_exit-rebuild', l:perf_start, 'buf=' . l:bufnr)
    return l:result
  endif
  if !empty(get(l:state, 'inserted_cell_hint', {}))
    let l:state.inserted_cell_hint = {}
    call setbufvar(l:bufnr, 'jusi_nb', l:state)
  endif
  call s:perf_log('handle_insert_exit-clean', l:perf_start, 'buf=' . l:bufnr)
  return l:state
endfunction

function! jusi#notebook#flush_deferred(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  if !s:is_notebook_buffer(l:bufnr)
    return {}
  endif
  let l:state = s:ensure_state(l:bufnr)
  if !get(l:state, 'syntax_dirty', 0)
    return l:state
  endif
  let l:state.syntax_dirty = 0
  let l:state.syntax_dirty_from = 0
  call setbufvar(l:bufnr, 'jusi_nb', l:state)
  return l:state
endfunction

function! jusi#notebook#refresh_if_changed(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  if !s:is_notebook_buffer(l:bufnr)
    return {}
  endif
  if exists('*jusi#cellmode#mode') && jusi#cellmode#mode(l:bufnr) ==# 'terminal'
    return s:ensure_state(l:bufnr)
  endif
  let l:state = s:ensure_state(l:bufnr)
  let l:tick = getbufvar(l:bufnr, 'changedtick')
  if get(l:state, 'changedtick', -1) !=# l:tick
    return jusi#notebook#rebuild(l:bufnr)
  endif
  if !get(l:state, 'consistency_check_pending', 0)
    return l:state
  endif
  if s:state_consistent(l:bufnr, l:state)
    let l:state.consistency_check_pending = 0
    call setbufvar(l:bufnr, 'jusi_nb', l:state)
    return l:state
  endif
  return jusi#notebook#rebuild(l:bufnr)
endfunction

function! s:notebook_has_active_session(bufnr) abort
  if !s:is_notebook_buffer(a:bufnr)
    return 0
  endif
  return jusi#session#is_active(get(getbufvar(a:bufnr, 'jusi_nb', {}), 'session', {}))
endfunction

function! s:active_notebook_buffers() abort
  let l:bufnrs = []
  for l:info in getbufinfo()
    if s:notebook_has_active_session(l:info.bufnr)
      call add(l:bufnrs, l:info.bufnr)
    endif
  endfor
  return l:bufnrs
endfunction

function! s:visible_window_count_for_buffer(bufnr) abort
  return len(filter(copy(getwininfo()), {_, v -> get(v, 'bufnr', 0) == a:bufnr}))
endfunction

function! s:mark_skip_cleanup(bufnrs) abort
  for l:bufnr in a:bufnrs
    call setbufvar(l:bufnr, 'jusi_skip_cleanup_once', 1)
  endfor
endfunction

function! s:forced_close() abort
  return exists('v:cmdbang') && v:cmdbang
endfunction

function! jusi#notebook#guard_quit(...) abort
  if s:bypass_quit_guard
    let s:bypass_quit_guard = 0
    return 1
  endif
  let l:forced = a:0 >= 1 ? a:1 : s:forced_close()
  let l:bufnr = bufnr('%')
  if getbufvar(l:bufnr, 'jusi_client_managed', 0)
        \ || getbufvar(l:bufnr, 'jusi_client_notebook_bufnr', 0) > 0
    return 1
  endif
  if !s:notebook_has_active_session(l:bufnr)
    return 1
  endif
  if s:visible_window_count_for_buffer(l:bufnr) > 1
    return 1
  endif
  if l:forced
    call s:mark_skip_cleanup([l:bufnr])
    return 1
  endif
  call s:echo_error('Cannot quit while a Jusi session is active; use :q! or stop/disconnect it first')
  throw 'jusi-quit-blocked'
endfunction

function! jusi#notebook#guard_wipeout(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  if has_key(s:bypass_wipeout_guard, l:bufnr)
    call remove(s:bypass_wipeout_guard, l:bufnr)
    return 1
  endif
  let l:forced = a:0 >= 2 ? a:2 : s:forced_close()
  if !s:notebook_has_active_session(l:bufnr)
    return 1
  endif
  if l:forced
    call s:mark_skip_cleanup([l:bufnr])
    return 1
  endif
  call s:echo_error('Cannot wipe a notebook buffer while a Jusi session is active; use :bwipeout! or stop/disconnect it first')
  throw 'jusi-wipeout-blocked'
endfunction

function! jusi#notebook#prepare_forced_exit() abort
  call s:mark_skip_cleanup(s:active_notebook_buffers())
  return 1
endfunction

function! s:run_quit_command(cmd) abort
  let s:bypass_quit_guard = 1
  execute a:cmd
  return 1
endfunction

function! s:run_window_close(force) abort
  if tabpagenr('$') > 1 || len(getwininfo()) > 1
    execute a:force ? 'close!' : 'close'
    return 1
  endif
  return s:run_quit_command(a:force ? 'quit!' : 'quit')
endfunction

function! s:run_client_close(bufnr, force) abort
  let l:notebook_bufnr = getbufvar(a:bufnr, 'jusi_client_notebook_bufnr', 0)
  if l:notebook_bufnr > 0 && bufexists(l:notebook_bufnr)
    if s:visible_window_count_for_buffer(l:notebook_bufnr) > 0
      if tabpagenr('$') > 1 || len(getwininfo()) > 1
        execute a:force ? 'close!' : 'close'
        return 1
      endif
    endif
    execute 'buffer ' . l:notebook_bufnr
    return 1
  endif
  return s:run_window_close(a:force)
endfunction

function! s:run_wipeout_command(bufnr, cmd) abort
  let s:bypass_wipeout_guard[a:bufnr] = 1
  execute a:cmd
  return 1
endfunction

function! jusi#notebook#command_abbrev(lhs, replacement) abort
  return getcmdtype() ==# ':' && getcmdline() ==# a:lhs ? a:replacement : a:lhs
endfunction

function! jusi#notebook#command_quit(force, all) abort
  if a:all
    let l:active = s:active_notebook_buffers()
    if empty(l:active)
      return s:run_quit_command(a:force ? 'qall!' : 'qall')
    endif
    if a:force
      call s:mark_skip_cleanup(l:active)
      return s:run_quit_command('qall!')
    endif
    call s:echo_error('Cannot quit while a Jusi session is active; use :q! or stop/disconnect it first')
    return 0
  endif

  let l:bufnr = bufnr('%')
  if getbufvar(l:bufnr, 'jusi_client_managed', 0)
        \ || getbufvar(l:bufnr, 'jusi_client_notebook_bufnr', 0) > 0
    call jusi#client#handle_editor_close(l:bufnr)
    return s:run_client_close(l:bufnr, a:force)
  endif

  if !s:notebook_has_active_session(l:bufnr) || s:visible_window_count_for_buffer(l:bufnr) > 1
    return s:run_window_close(a:force)
  endif

  if a:force
    call s:mark_skip_cleanup([l:bufnr])
    return s:run_window_close(1)
  endif

  call s:echo_error('Cannot quit while a Jusi session is active; use :q! or stop/disconnect it first')
  return 0
endfunction

function! jusi#notebook#command_wipeout(force) abort
  let l:bufnr = bufnr('%')
  if getbufvar(l:bufnr, 'jusi_client_managed', 0)
        \ || getbufvar(l:bufnr, 'jusi_client_notebook_bufnr', 0) > 0
    call jusi#client#handle_editor_close(l:bufnr)
    return s:run_wipeout_command(l:bufnr, a:force ? 'bwipeout!' : 'bwipeout')
  endif

  if !s:notebook_has_active_session(l:bufnr)
    return s:run_wipeout_command(l:bufnr, a:force ? 'bwipeout!' : 'bwipeout')
  endif

  if a:force
    call s:mark_skip_cleanup([l:bufnr])
    return s:run_wipeout_command(l:bufnr, 'bwipeout!')
  endif

  call s:echo_error('Cannot wipe a notebook buffer while a Jusi session is active; use :bwipeout! or stop/disconnect it first')
  return 0
endfunction

function! jusi#notebook#cleanup(...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  if has_key(s:buffer_listener, l:bufnr)
    call listener_remove(s:buffer_listener[l:bufnr])
    call remove(s:buffer_listener, l:bufnr)
  endif
  if has_key(s:buffer_cache, l:bufnr)
    call remove(s:buffer_cache, l:bufnr)
  endif
  let l:skip_cleanup = getbufvar(l:bufnr, 'jusi_skip_cleanup_once', 0)
  if l:skip_cleanup
    call setbufvar(l:bufnr, 'jusi_skip_cleanup_once', 0)
  endif
  if s:is_notebook_buffer(l:bufnr) && !l:skip_cleanup
    call jusi#session#shutdown_all_clients('frontend_unload', l:bufnr)
    let l:state = getbufvar(l:bufnr, 'jusi_nb', {})
    for l:cell in get(l:state, 'cells', [])
      if get(l:cell, 'client_bufnr', -1) > 0
        call jusi#client#destroy_buffer(l:cell.client_bufnr)
      endif
    endfor
  endif
  if !l:skip_cleanup
    call jusi#transport#stop(l:bufnr)
  endif
  call jusi#syntax#cleanup(l:bufnr)
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

function! jusi#notebook#cell_by_id(cell_id, ...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  let l:state = jusi#notebook#rebuild(l:bufnr)
  if empty(l:state)
    return {}
  endif
  for l:cell in get(l:state, 'cells', [])
    if get(l:cell, 'id', 0) == a:cell_id
      return l:cell
    endif
  endfor
  return {}
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
  if a:cell.start < a:cell.body_end
    return a:cell.start + 1
  endif
  return a:cell.start
endfunction

function! s:insertion_index_for_line(state, lnum) abort
  let l:idx = 0
  while l:idx < len(a:state.cells)
    if get(a:state.cells[l:idx], 'start', 0) >= a:lnum
      return l:idx
    endif
    let l:idx += 1
  endwhile
  return len(a:state.cells)
endfunction

function! s:blank_inserted_parsed_cell(lnum) abort
  return s:make_parsed_cell(
        \ a:lnum,
        \ a:lnum + 1,
        \ 'code',
        \ '',
        \ s:cell_signature(['##', ''], 1, 2))
endfunction

function! s:prepare_state_for_explicit_insert(bufnr, lnum) abort
  let l:state = s:ensure_state(a:bufnr)
  let l:idx = s:insertion_index_for_line(l:state, a:lnum)
  let l:i = l:idx
  while l:i < len(l:state.cells)
    call s:shift_cell_lines(l:state.cells[l:i], 2)
    let l:i += 1
  endwhile
  let l:new_cell = s:init_runtime_cell(s:blank_inserted_parsed_cell(a:lnum), l:state)
  call insert(l:state.cells, l:new_cell, l:idx)
  let l:state.inserted_cell_hint = {'id': l:new_cell.id, 'start': a:lnum, 'end': a:lnum + 1}
  let l:state.changedtick = -1
  call setbufvar(a:bufnr, 'jusi_nb', l:state)
  return l:state
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

function! jusi#notebook#goto_cell_id(cell_id, ...) abort
  let l:bufnr = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  let l:cell = jusi#notebook#cell_by_id(a:cell_id, l:bufnr)
  if empty(l:cell)
    return {}
  endif
  if l:bufnr != bufnr('%')
    execute 'buffer ' . l:bufnr
  endif
  call s:goto_cell(l:cell)
  return l:cell
endfunction

function! s:insert_cell_at(lnum) abort
  let l:bufnr = bufnr('%')
  call s:prepare_state_for_explicit_insert(l:bufnr, a:lnum)
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

function! s:delete_range(start_lnum, end_lnum) abort
  execute a:start_lnum . ',' . a:end_lnum . 'delete _'
endfunction

function! s:cell_lines(cell) abort
  return getline(a:cell.start, a:cell.end)
endfunction

function! s:cell_main_lines(cell) abort
  let l:start = a:cell.start + 1
  let l:end = get(a:cell, 'body_end', a:cell.end)
  if l:start > l:end
    return []
  endif
  return getline(l:start, l:end)
endfunction

function! s:cell_history_lines(cell) abort
  if get(a:cell, 'history_start', 0) == 0
    return []
  endif
  return getline(a:cell.history_start, a:cell.end)
endfunction

function! s:replacement_index_after_delete(state, deleted_idx) abort
  if len(a:state.cells) <= 1
    return -1
  endif
  if a:deleted_idx < len(a:state.cells) - 1
    return a:deleted_idx
  endif
  return a:deleted_idx - 1
endfunction

function! jusi#notebook#delete_current() abort
  let l:state = jusi#notebook#rebuild()
  let l:idx = s:cell_index_at_line(l:state, line('.'))
  if l:idx < 0
    return {}
  endif

  let l:cell = l:state.cells[l:idx]
  let l:target_idx = s:replacement_index_after_delete(l:state, l:idx)

  if len(l:state.cells) <= 1
    call setline(1, ['##'])
    if line('$') > 1
      execute '2,$delete _'
    endif
    call jusi#notebook#rebuild()
    let l:new_cell = jusi#notebook#cell_at_line(bufnr('%'), 1)
    call s:enter_insert_at_cell(l:new_cell)
    return l:new_cell
  endif

  call s:delete_range(l:cell.start, l:cell.end)
  let l:new_state = jusi#notebook#rebuild()
  let l:new_cell = l:target_idx >= 0 ? l:new_state.cells[l:target_idx] : {}
  call s:goto_cell(l:new_cell)
  return l:new_cell
endfunction

function! jusi#notebook#edit_current() abort
  let l:cell = jusi#notebook#cell_at_line(bufnr('%'), line('.'))
  if empty(l:cell)
    return {}
  endif

  let l:body_end = get(l:cell, 'body_end', l:cell.end)
  if l:cell.start < l:body_end
    call s:delete_range(l:cell.start + 1, l:body_end)
  endif
  call append(l:cell.start, '')
  call jusi#notebook#rebuild()
  let l:new_cell = jusi#notebook#cell_at_line(bufnr('%'), l:cell.start)
  call s:enter_insert_at_cell(l:new_cell)
  return l:new_cell
endfunction

function! jusi#notebook#copy_current() abort
  let l:cell = jusi#notebook#cell_at_line(bufnr('%'), line('.'))
  if empty(l:cell)
    let g:jusi_cell_clipboard = []
    return []
  endif
  let g:jusi_cell_clipboard = copy(s:cell_lines(l:cell))
  return g:jusi_cell_clipboard
endfunction

function! jusi#notebook#cell_main_lines(...) abort
  let l:cell = a:0 >= 1 ? a:1 : jusi#notebook#cell_at_line(bufnr('%'), line('.'))
  if empty(l:cell)
    return []
  endif
  return s:cell_main_lines(l:cell)
endfunction

function! jusi#notebook#cell_history_lines(...) abort
  let l:cell = a:0 >= 1 ? a:1 : jusi#notebook#cell_at_line(bufnr('%'), line('.'))
  if empty(l:cell)
    return []
  endif
  return s:cell_history_lines(l:cell)
endfunction

function! jusi#notebook#paste_below() abort
  if empty(get(g:, 'jusi_cell_clipboard', []))
    return {}
  endif

  let l:cell = jusi#notebook#cell_at_line(bufnr('%'), line('.'))
  let l:target = empty(l:cell) ? line('$') : l:cell.end
  call append(l:target, copy(g:jusi_cell_clipboard))
  call jusi#notebook#rebuild()
  let l:new_cell = jusi#notebook#cell_at_line(bufnr('%'), l:target + 1)
  call s:goto_cell(l:new_cell)
  return l:new_cell
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
