function! s:echo_error(message) abort
  echohl ErrorMsg
  echom a:message
  echohl None
endfunction

function! s:normalize_bufnr(bufnr) abort
  if a:bufnr is# 0 || a:bufnr is# ''
    return bufnr('%')
  endif
  return str2nr(a:bufnr)
endfunction

function! s:is_notebook_buffer(bufnr) abort
  return bufexists(a:bufnr) && getbufvar(a:bufnr, '&filetype') ==# 'jusinb'
endfunction

function! s:notebook_label_from_path(path, fallback) abort
  if type(a:path) != type('') || empty(a:path)
    return a:fallback
  endif
  let l:tail = fnamemodify(a:path, ':t:r')
  return empty(l:tail) ? a:fallback : l:tail
endfunction

function! s:notebook_identity_list(...) abort
  let l:current = s:normalize_bufnr(a:0 >= 1 ? a:1 : bufnr('%'))
  let l:items = []
  for l:info in getbufinfo()
    let l:bufnr = get(l:info, 'bufnr', 0)
    if !s:is_notebook_buffer(l:bufnr)
      continue
    endif
    let l:session = jusi#session#state(l:bufnr)
    if !jusi#session#is_active(l:session) && empty(get(l:session, 'palette', {}))
      continue
    endif
    let l:path = bufname(l:bufnr)
    call add(l:items, {
          \ 'bufnr': l:bufnr,
          \ 'path': l:path,
          \ 'base': s:notebook_label_from_path(l:path, 'notebook-' . l:bufnr),
          \ })
  endfor

  let l:base_counts = {}
  for l:item in l:items
    let l:base_counts[l:item.base] = get(l:base_counts, l:item.base, 0) + 1
  endfor

  let l:label_counts = {}
  for l:item in l:items
    if get(l:base_counts, l:item.base, 0) == 1
      let l:item.label = l:item.base
    else
      let l:path_label = fnamemodify(fnamemodify(l:item.path, ':~:.'), ':r')
      let l:item.label = empty(l:path_label) ? l:item.base : l:path_label
    endif
    let l:label_counts[l:item.label] = get(l:label_counts, l:item.label, 0) + 1
  endfor

  for l:item in l:items
    if get(l:label_counts, l:item.label, 0) > 1
      let l:item.label .= '#' . l:item.bufnr
    endif
  endfor

  call sort(l:items, {a, b -> a.bufnr - b.bufnr})
  let l:current_items = filter(copy(l:items), 'v:val.bufnr == l:current')
  let l:other_items = filter(copy(l:items), 'v:val.bufnr != l:current')
  return l:current_items + l:other_items
endfunction

function! s:notebook_label_map(...) abort
  let l:map = {}
  for l:item in s:notebook_identity_list(a:0 >= 1 ? a:1 : bufnr('%'))
    let l:map[l:item.label] = l:item.bufnr
  endfor
  return l:map
endfunction

function! s:palette_for_buffer(bufnr) abort
  let l:session = jusi#session#state(a:bufnr)
  let l:palette = get(l:session, 'palette', {})
  return type(l:palette) == type({}) ? l:palette : {}
endfunction

function! s:palette_sections(bufnr) abort
  let l:sections = keys(s:palette_for_buffer(a:bufnr))
  call sort(l:sections)
  return l:sections
endfunction

function! s:palette_entries(bufnr, section) abort
  let l:palette = s:palette_for_buffer(a:bufnr)
  let l:spec = get(l:palette, a:section, {})
  let l:entries = get(l:spec, 'entries', [])
  return type(l:entries) == type([]) ? copy(l:entries) : []
endfunction

function! s:parsed_command(qargs) abort
  let l:text = type(a:qargs) == type('') ? substitute(a:qargs, '^\s*\|\s*$', '', 'g') : ''
  let l:parts = split(l:text)
  return {
        \ 'raw': l:text,
        \ 'parts': l:parts,
        \ 'notebook': get(l:parts, 0, ''),
        \ }
endfunction

function! s:resolved_command(qargs, bufnr) abort
  let l:parsed = s:parsed_command(a:qargs)
  let l:parts = get(l:parsed, 'parts', [])
  let l:resolved = {
        \ 'raw': get(l:parsed, 'raw', ''),
        \ 'parts': l:parts,
        \ 'notebook': get(l:parsed, 'notebook', ''),
        \ 'section': '',
        \ 'entry': '',
        \ 'extra': '',
        \ 'plain': len(l:parts) <= 1,
        \ 'requires_entry': 0,
        \ }
  if len(l:parts) <= 1
    return l:resolved
  endif

  let l:resolved.section = get(l:parts, 1, '')
  let l:entries = s:palette_entries(a:bufnr, l:resolved.section)
  let l:resolved.requires_entry = !empty(l:entries)
  if l:resolved.requires_entry
    let l:resolved.entry = get(l:parts, 2, '')
    let l:resolved.extra = len(l:parts) > 3 ? join(l:parts[3:], ' ') : ''
  else
    let l:resolved.extra = len(l:parts) > 2 ? join(l:parts[2:], ' ') : ''
  endif
  return l:resolved
endfunction

function! s:matches(items, lead) abort
  let l:result = []
  for l:item in a:items
    if type(l:item) != type('') || l:item !~# '^' . escape(a:lead, '\.^$~[]*')
      continue
    endif
    call add(l:result, l:item)
  endfor
  return l:result
endfunction

function! s:strip_command_prefix(cmdline) abort
  return substitute(a:cmdline, '^\s*\%(''<,''>\)\?\s*J!\?\s*', '', '')
endfunction

function! s:is_palette_cmdline(cmdline) abort
  return a:cmdline =~# '^\s*\%(''<,''>\)\?\s*J!\?\%(\s\|$\)'
endfunction

function! jusi#palette#complete(arglead, cmdline, cursorpos) abort
  let l:tail = s:strip_command_prefix(a:cmdline)
  let l:parts = split(substitute(l:tail, '^\s*\|\s*$', '', 'g'))
  let l:arg_index = empty(a:arglead) ? len(l:parts) + 1 : len(l:parts)
  let l:parsed = s:parsed_command(l:tail)
  if l:arg_index == 1
    return s:matches(map(copy(s:notebook_identity_list(bufnr('%'))), 'v:val.label'), a:arglead)
  endif

  let l:label_map = s:notebook_label_map(bufnr('%'))
  let l:target_bufnr = get(l:label_map, l:parsed.notebook, 0)
  if l:target_bufnr <= 0
    return []
  endif
  let l:resolved = s:resolved_command(l:tail, l:target_bufnr)

  if l:arg_index == 2
    return s:matches(s:palette_sections(l:target_bufnr), a:arglead)
  endif
  if l:arg_index == 3
    return s:matches(s:palette_entries(l:target_bufnr, l:resolved.section), a:arglead)
  endif
  return []
endfunction

function! s:build_header(section, entry, extra) abort
  let l:header = '%%' . a:section
  if !empty(a:entry)
    let l:header .= ' ' . a:entry
  endif
  if !empty(a:extra)
    let l:header .= ' ' . a:extra
  endif
  return l:header
endfunction

function! s:cell_header(cell, bufnr) abort
  let l:lines = jusi#notebook#cell_main_lines(a:cell)
  return empty(l:lines) ? '' : l:lines[0]
endfunction

function! s:find_plain_code_cell(bufnr) abort
  return {}
endfunction

function! s:find_cell_by_header_prefix(bufnr, header) abort
  let l:pattern = '^' . escape(a:header, '\.^$~[]*') . '\%(\s\|$\)'
  for l:cell in jusi#notebook#cells(a:bufnr)
    if get(l:cell, 'kind', '') !=# 'magic'
      continue
    endif
    if s:cell_header(l:cell, a:bufnr) =~# l:pattern
      return l:cell
    endif
  endfor
  return {}
endfunction

function! s:set_cell_body(cell, body_lines) abort
  let l:start = a:cell.start + 1
  if get(a:cell, 'kind', '') ==# 'magic'
    let l:start += 1
  endif
  let l:end = get(a:cell, 'body_end', a:cell.end)
  if l:start <= l:end
    silent execute l:start . ',' . l:end . 'delete _'
  endif
  if !empty(a:body_lines)
    call append(a:cell.start + 1, copy(a:body_lines))
  endif
endfunction

function! s:enter_insert_at_cell(cell) abort
  call cursor(get(a:cell, 'start', 1) + 1, 1)
  if get(a:cell, 'kind', '') ==# 'magic'
    if get(a:cell, 'start', 0) < get(a:cell, 'body_end', get(a:cell, 'end', 0))
      call cursor(a:cell.start + 2, 1)
    endif
  elseif get(a:cell, 'start', 0) < get(a:cell, 'body_end', get(a:cell, 'end', 0))
    call cursor(a:cell.start + 1, 1)
  endif
  startinsert
endfunction

function! s:create_palette_cell(bufnr, kind, header, body_lines) abort
  execute 'buffer ' . a:bufnr
  let l:body_lines = empty(a:body_lines) ? [''] : copy(a:body_lines)
  let l:lines = ['##']
  if a:kind ==# 'magic'
    call add(l:lines, a:header)
  endif
  let l:lines += l:body_lines
  call append(line('$'), l:lines)
  call jusi#notebook#rebuild(a:bufnr)
  return jusi#notebook#cell_at_line(a:bufnr, line('$'))
endfunction

function! s:update_palette_cell(cell, kind, header, body_lines, replace_body) abort
  call cursor(a:cell.start, 1)
  if a:kind ==# 'magic'
    call setline(a:cell.start + 1, a:header)
  endif
  if a:replace_body
    call s:set_cell_body(a:cell, a:body_lines)
  endif
  call jusi#notebook#rebuild(bufnr('%'))
  return jusi#notebook#cell_at_line(bufnr('%'), a:cell.start)
endfunction

function! s:current_tab_window_for_buffer(bufnr) abort
  for l:win in getwininfo()
    if get(l:win, 'bufnr', 0) == a:bufnr
          \ && get(l:win, 'tabnr', 0) == tabpagenr()
      return get(l:win, 'winid', 0)
    endif
  endfor
  return 0
endfunction

function! s:show_target_notebook(bufnr) abort
  if a:bufnr == bufnr('%')
    return 1
  endif
  let l:winid = s:current_tab_window_for_buffer(a:bufnr)
  if l:winid > 0
    call win_gotoid(l:winid)
    return 1
  endif
  execute 'vertical sbuffer ' . a:bufnr
  return 1
endfunction

function! s:selected_text(line1, line2) abort
  let l:start = getpos("'<")
  let l:end = getpos("'>")
  let l:current = bufnr('%')
  if index([0, l:current], get(l:start, 0, 0)) < 0
        \ || index([0, l:current], get(l:end, 0, 0)) < 0
    return []
  endif
  if get(l:start, 1, 0) != a:line1 || get(l:end, 1, 0) != a:line2
    return []
  endif
  let l:lines = getline(a:line1, a:line2)
  if empty(l:lines)
    return []
  endif
  if visualmode() ==# 'V'
    return l:lines
  endif
  let l:start_col = get(l:start, 2, 1)
  let l:end_col = get(l:end, 2, 1)
  if a:line1 == a:line2
    let l:max_col = len(get(l:lines, 0, ''))
    if l:start_col <= 1 && l:end_col >= l:max_col
      return []
    endif
  endif
  if a:line1 == a:line2
    return [strpart(l:lines[0], l:start_col - 1, l:end_col - l:start_col + 1)]
  endif
  let l:lines[0] = strpart(l:lines[0], l:start_col - 1)
  let l:lines[-1] = strpart(l:lines[-1], 0, l:end_col)
  return l:lines
endfunction

function! s:resolve_target_buffer(label) abort
  let l:label_map = s:notebook_label_map(bufnr('%'))
  return get(l:label_map, a:label, 0)
endfunction

function! s:ensure_palette_args(parsed) abort
  if empty(a:parsed.notebook)
    call s:echo_error('Usage: J[!] {notebook} [section [entry]] [extra args...]')
    return 0
  endif
  return 1
endfunction

function! s:ensure_palette_entry(bufnr, section, entry) abort
  let l:entries = s:palette_entries(a:bufnr, a:section)
  return index(l:entries, a:entry) >= 0
endfunction

function! jusi#palette#command(bang, line1, line2, qargs) abort
  let l:parsed = s:parsed_command(a:qargs)
  if !s:ensure_palette_args(l:parsed)
    return {}
  endif

  let l:target_bufnr = s:resolve_target_buffer(l:parsed.notebook)
  if l:target_bufnr <= 0
    call s:echo_error('Unknown notebook alias: ' . l:parsed.notebook)
    return {}
  endif
  let l:resolved = s:resolved_command(a:qargs, l:target_bufnr)
  if !empty(l:resolved.section) && !has_key(s:palette_for_buffer(l:target_bufnr), l:resolved.section)
    call s:echo_error('Unknown palette section for notebook ' . l:parsed.notebook . ': ' . l:resolved.section)
    return {}
  endif
  if l:resolved.requires_entry && empty(l:resolved.entry)
    call s:echo_error('Palette section requires entry: ' . l:resolved.section)
    return {}
  endif
  if l:resolved.requires_entry && !s:ensure_palette_entry(l:target_bufnr, l:resolved.section, l:resolved.entry)
    call s:echo_error('Unknown palette entry for ' . l:resolved.section . ': ' . l:resolved.entry)
    return {}
  endif

  let l:body_lines = []
  let l:replace_body = 0
  if a:line1 > 0 && a:line2 > 0
    let l:body_lines = s:selected_text(a:line1, a:line2)
    let l:replace_body = !empty(l:body_lines)
  endif

  call s:show_target_notebook(l:target_bufnr)
  if l:resolved.plain
    let l:kind = 'code'
    let l:header = ''
    let l:cell = {}
  else
    let l:kind = 'magic'
    let l:header = s:build_header(l:resolved.section, l:resolved.entry, l:resolved.extra)
    let l:cell = s:find_cell_by_header_prefix(l:target_bufnr, l:header)
  endif
  let l:created = empty(l:cell)
  if l:created
    let l:cell = s:create_palette_cell(l:target_bufnr, l:kind, l:header, l:body_lines)
    let l:replace_body = 0
  else
    let l:cell = s:update_palette_cell(l:cell, l:kind, l:header, l:body_lines, l:replace_body)
  endif

  call jusi#notebook#goto_cell_id(get(l:cell, 'id', 0), l:target_bufnr)
  if a:bang
    return jusi#session#execute_current()
  endif
  if l:created
    call s:enter_insert_at_cell(l:cell)
  endif
  return l:cell
endfunction
