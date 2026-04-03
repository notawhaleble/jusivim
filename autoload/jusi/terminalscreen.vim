function! s:is_valid_bufnr(bufnr) abort
  return type(a:bufnr) == type(0) && a:bufnr > 0 && bufexists(a:bufnr)
endfunction

function! s:is_visible_bufnr(bufnr) abort
  if !s:is_valid_bufnr(a:bufnr)
    return 0
  endif
  for l:info in getwininfo()
    if get(l:info, 'bufnr', 0) == a:bufnr
      return 1
    endif
  endfor
  return 0
endfunction

function! s:blank_line(cols) abort
  return repeat(' ', max([1, a:cols]))
endfunction

function! s:scrollback_limit() abort
  return max([0, get(g:, 'jusi_terminal_scrollback_lines', 1000)])
endfunction

function! s:default_style() abort
  return {'fg': '', 'bg': '', 'bold': 0, 'reverse': 0}
endfunction

function! s:canonical_style(style) abort
  if !exists('s:style_cache')
    let s:style_cache = {}
  endif
  let l:key = s:style_key(a:style)
  if !has_key(s:style_cache, l:key)
    let s:style_cache[l:key] = {
          \ 'fg': get(a:style, 'fg', ''),
          \ 'bg': get(a:style, 'bg', ''),
          \ 'bold': get(a:style, 'bold', 0) ? 1 : 0,
          \ 'reverse': get(a:style, 'reverse', 0) ? 1 : 0,
          \ }
  endif
  return s:style_cache[l:key]
endfunction

function! s:blank_attr_row(cols) abort
  let l:blank = s:canonical_style(s:default_style())
  let l:row = []
  let l:i = 0
  while l:i < max([1, a:cols])
    call add(l:row, l:blank)
    let l:i += 1
  endwhile
  return l:row
endfunction

function! s:normalize_attr_row(row, cols) abort
  let l:normalized = type(a:row) == type([]) ? copy(a:row) : []
  let l:i = 0
  while l:i < len(l:normalized)
    let l:normalized[l:i] = s:canonical_style(l:normalized[l:i])
    let l:i += 1
  endwhile
  while len(l:normalized) < max([1, a:cols])
    call add(l:normalized, s:canonical_style(s:default_style()))
  endwhile
  if len(l:normalized) > a:cols
    call remove(l:normalized, a:cols, -1)
  endif
  return l:normalized
endfunction

function! s:style_copy(style) abort
  return {
        \ 'fg': get(a:style, 'fg', ''),
        \ 'bg': get(a:style, 'bg', ''),
        \ 'bold': get(a:style, 'bold', 0) ? 1 : 0,
        \ 'reverse': get(a:style, 'reverse', 0) ? 1 : 0,
        \ }
endfunction

function! s:is_default_style(style) abort
  return get(a:style, 'fg', '') ==# ''
        \ && get(a:style, 'bg', '') ==# ''
        \ && !get(a:style, 'bold', 0)
        \ && !get(a:style, 'reverse', 0)
endfunction

function! s:style_key(style) abort
  return join([
        \ get(a:style, 'fg', ''),
        \ get(a:style, 'bg', ''),
        \ get(a:style, 'bold', 0) ? '1' : '0',
        \ get(a:style, 'reverse', 0) ? '1' : '0',
        \ ], ':')
endfunction

function! s:ansi_color_spec(name) abort
  let l:map = {
        \ 'black': {'cterm': '0', 'gui': '#000000'},
        \ 'red': {'cterm': '1', 'gui': '#cd3131'},
        \ 'green': {'cterm': '2', 'gui': '#0dbc79'},
        \ 'yellow': {'cterm': '3', 'gui': '#949800'},
        \ 'blue': {'cterm': '4', 'gui': '#0451a5'},
        \ 'magenta': {'cterm': '5', 'gui': '#bc05bc'},
        \ 'cyan': {'cterm': '6', 'gui': '#0598bc'},
        \ 'white': {'cterm': '7', 'gui': '#555555'},
        \ 'bright_black': {'cterm': '8', 'gui': '#666666'},
        \ 'bright_red': {'cterm': '9', 'gui': '#f14c4c'},
        \ 'bright_green': {'cterm': '10', 'gui': '#23d18b'},
        \ 'bright_yellow': {'cterm': '11', 'gui': '#f5f543'},
        \ 'bright_blue': {'cterm': '12', 'gui': '#3b8eea'},
        \ 'bright_magenta': {'cterm': '13', 'gui': '#d670d6'},
        \ 'bright_cyan': {'cterm': '14', 'gui': '#29b8db'},
        \ 'bright_white': {'cterm': '15', 'gui': '#e5e5e5'},
        \ }
  return get(l:map, a:name, {})
endfunction

function! s:ensure_style_group(style) abort
  if s:is_default_style(a:style)
    return ''
  endif
  if !exists('s:sgr_groups')
    let s:sgr_groups = {}
  endif
  let l:key = s:style_key(a:style)
  if has_key(s:sgr_groups, l:key)
    return s:sgr_groups[l:key]
  endif
  let l:name = 'JusiTerminalSgr' . (len(keys(s:sgr_groups)) + 1)
  let l:terms = []
  let l:guiterms = []
  if get(a:style, 'bold', 0)
    call add(l:terms, 'bold')
    call add(l:guiterms, 'bold')
  endif
  if get(a:style, 'reverse', 0)
    call add(l:terms, 'reverse')
    call add(l:guiterms, 'reverse')
  endif
  let l:cmd = 'highlight ' . l:name
  let l:fg = s:ansi_color_spec(get(a:style, 'fg', ''))
  let l:bg = s:ansi_color_spec(get(a:style, 'bg', ''))
  if !empty(l:fg)
    let l:cmd .= ' ctermfg=' . l:fg.cterm . ' guifg=' . l:fg.gui
  endif
  if !empty(l:bg)
    let l:cmd .= ' ctermbg=' . l:bg.cterm . ' guibg=' . l:bg.gui
  endif
  let l:cmd .= ' cterm=' . (empty(l:terms) ? 'NONE' : join(l:terms, ','))
  let l:cmd .= ' gui=' . (empty(l:guiterms) ? 'NONE' : join(l:guiterms, ','))
  execute l:cmd
  let s:sgr_groups[l:key] = l:name
  return l:name
endfunction

function! s:clear_window_style_matches(winid) abort
  let l:ids = getwinvar(a:winid, 'jusi_terminal_style_matches', [])
  for l:id in l:ids
    call matchdelete(l:id, a:winid)
  endfor
  call setwinvar(a:winid, 'jusi_terminal_style_matches', [])
  call setwinvar(a:winid, 'jusi_terminal_reverse_rows', [])
endfunction

function! s:ensure_reverse_row_group() abort
  if !hlexists('JusiTerminalReverseRow')
    execute 'highlight default JusiTerminalReverseRow term=reverse cterm=reverse gui=reverse'
  endif
  return 'JusiTerminalReverseRow'
endfunction

function! s:row_has_reverse(attr_row) abort
  if type(a:attr_row) != type([])
    return 0
  endif
  for l:style in a:attr_row
    if get(l:style, 'reverse', 0)
      return 1
    endif
  endfor
  return 0
endfunction

function! s:reverse_row_positions(attr_rows) abort
  let l:positions = []
  let l:row_idx = 0
  while l:row_idx < len(a:attr_rows)
    let l:row = get(a:attr_rows, l:row_idx, [])
    if s:row_has_reverse(l:row)
      call add(l:positions, [l:row_idx + 1, 1, max([1, len(l:row)])])
    endif
    let l:row_idx += 1
  endwhile
  return l:positions
endfunction

function! s:apply_reverse_row_matches(winid, positions) abort
  let l:previous = getwinvar(a:winid, 'jusi_terminal_reverse_rows', [])
  let l:existing_ids = getwinvar(a:winid, 'jusi_terminal_style_matches', [])
  if string(l:previous) ==# string(a:positions)
    return l:existing_ids
  endif
  for l:id in l:existing_ids
    call matchdelete(l:id, a:winid)
  endfor
  let l:ids = []
  if !empty(a:positions)
    let l:group = s:ensure_reverse_row_group()
    for l:pos in a:positions
      call add(l:ids, matchaddpos(l:group, [l:pos], 5, -1, {'window': a:winid}))
    endfor
  endif
  call setwinvar(a:winid, 'jusi_terminal_style_matches', l:ids)
  call setwinvar(a:winid, 'jusi_terminal_reverse_rows', copy(a:positions))
  return l:ids
endfunction

function! s:style_span_limit() abort
  return max([0, get(g:, 'jusi_terminal_style_span_limit', 128)])
endfunction

function! s:styles_enabled() abort
  return get(g:, 'jusi_terminal_enable_styles', 0) ? 1 : 0
endfunction

function! s:default_state(bufnr) abort
  let l:rows = max([1, getbufvar(a:bufnr, 'jusi_terminal_rows', 24)])
  let l:cols = max([1, getbufvar(a:bufnr, 'jusi_terminal_cols', 80)])
  return {
        \ '_internal': 1,
        \ 'rows': l:rows,
        \ 'cols': l:cols,
        \ 'cursor_row': 0,
        \ 'cursor_col': 0,
        \ 'saved_cursor_row': 0,
        \ 'saved_cursor_col': 0,
        \ 'scroll_top': 0,
        \ 'scroll_bottom': l:rows - 1,
        \ 'cursor_visible': 1,
        \ 'scrollback': [],
        \ 'scrollback_attr_rows': [],
        \ 'alt_active': 0,
        \ 'charset_g0': 'ascii',
        \ 'charset_g1': 'ascii',
        \ 'charset_active': 'g0',
        \ 'charset_target': '',
        \ 'lines': [s:blank_line(l:cols)],
        \ 'attr_rows': [s:blank_attr_row(l:cols)],
        \ 'esc_state': '',
        \ 'csi': '',
        \ 'osc': '',
        \ 'utf8': [],
        \ 'last_printable': ' ',
        \ 'current_style': s:default_style(),
        \ 'alt_screen': {},
        \ 'line_cache': {},
        \ }
endfunction

function! s:state(bufnr) abort
  let l:state = getbufvar(a:bufnr, 'jusi_terminal_screen', {})
  if type(l:state) != type({})
    let l:state = {}
  endif
  if empty(l:state)
    let l:state = s:default_state(a:bufnr)
  endif
  let l:state.rows = max([1, get(l:state, 'rows', 24)])
  let l:state.cols = max([1, get(l:state, 'cols', 80)])
  let l:state.cursor_row = max([0, get(l:state, 'cursor_row', 0)])
  let l:state.cursor_col = max([0, get(l:state, 'cursor_col', 0)])
  let l:state.saved_cursor_row = max([0, get(l:state, 'saved_cursor_row', 0)])
  let l:state.saved_cursor_col = max([0, get(l:state, 'saved_cursor_col', 0)])
  let l:state.scroll_top = max([0, get(l:state, 'scroll_top', 0)])
  let l:state.scroll_bottom = min([l:state.rows - 1, max([l:state.scroll_top, get(l:state, 'scroll_bottom', l:state.rows - 1)])])
  let l:state.cursor_visible = get(l:state, 'cursor_visible', 1) ? 1 : 0
  let l:state.scrollback = type(get(l:state, 'scrollback', [])) == type([]) ? get(l:state, 'scrollback', []) : []
  let l:state.scrollback_attr_rows = type(get(l:state, 'scrollback_attr_rows', [])) == type([]) ? get(l:state, 'scrollback_attr_rows', []) : []
  let l:state.alt_active = get(l:state, 'alt_active', 0) ? 1 : 0
  let l:state.charset_g0 = get(l:state, 'charset_g0', 'ascii')
  let l:state.charset_g1 = get(l:state, 'charset_g1', 'ascii')
  let l:state.charset_active = get(l:state, 'charset_active', 'g0') ==# 'g1' ? 'g1' : 'g0'
  let l:state.charset_target = get(l:state, 'charset_target', '')
  if type(get(l:state, 'lines', [])) != type([])
    let l:state.lines = []
  endif
  if empty(l:state.lines)
    let l:state.lines = [s:blank_line(l:state.cols)]
  endif
  let l:state.attr_rows = type(get(l:state, 'attr_rows', [])) == type([]) ? get(l:state, 'attr_rows', []) : []
  let l:fast_path = get(l:state, '_internal', 0) ? 1 : 0
  while len(l:state.attr_rows) < len(l:state.lines)
    call add(l:state.attr_rows, s:blank_attr_row(l:state.cols))
  endwhile
  if len(l:state.attr_rows) > len(l:state.lines)
    call remove(l:state.attr_rows, len(l:state.lines), -1)
  endif
  if !l:fast_path
    let l:i = 0
    while l:i < len(l:state.attr_rows)
      let l:state.attr_rows[l:i] = s:normalize_attr_row(l:state.attr_rows[l:i], l:state.cols)
      let l:i += 1
    endwhile
    let l:scroll_i = 0
    while l:scroll_i < len(l:state.scrollback_attr_rows)
      let l:state.scrollback_attr_rows[l:scroll_i] = s:normalize_attr_row(l:state.scrollback_attr_rows[l:scroll_i], l:state.cols)
      let l:scroll_i += 1
    endwhile
  endif
  let l:state.esc_state = get(l:state, 'esc_state', '')
  let l:state.csi = get(l:state, 'csi', '')
  let l:state.osc = get(l:state, 'osc', '')
  let l:state.utf8 = type(get(l:state, 'utf8', [])) == type([]) ? get(l:state, 'utf8', []) : []
  let l:state.last_printable = get(l:state, 'last_printable', ' ')
  let l:state.current_style = l:fast_path
        \ ? get(l:state, 'current_style', s:default_style())
        \ : s:style_copy(get(l:state, 'current_style', s:default_style()))
  let l:state.alt_screen = type(get(l:state, 'alt_screen', {})) == type({}) ? get(l:state, 'alt_screen', {}) : {}
  let l:state.line_cache = l:fast_path && type(get(l:state, 'line_cache', {})) == type({})
        \ ? get(l:state, 'line_cache', {})
        \ : {}
  let l:state._internal = 1
  return l:state
endfunction

function! s:save_state(bufnr, state) abort
  let a:state._internal = 1
  call setbufvar(a:bufnr, 'jusi_terminal_screen', a:state)
  call setbufvar(a:bufnr, 'jusi_terminal_rows', a:state.rows)
  call setbufvar(a:bufnr, 'jusi_terminal_cols', a:state.cols)
  return a:state
endfunction

function! s:ensure_line(state, row) abort
  while len(a:state.lines) <= a:row
    call add(a:state.lines, s:blank_line(a:state.cols))
    call add(a:state.attr_rows, s:blank_attr_row(a:state.cols))
  endwhile
endfunction

function! s:invalidate_line_cache(state) abort
  let a:state.line_cache = {}
endfunction

function! s:get_cached_chars(state, row) abort
  call s:ensure_line(a:state, a:row)
  let l:key = string(a:row)
  if !has_key(a:state.line_cache, l:key)
    let a:state.line_cache[l:key] = s:line_chars(a:state.lines[a:row], a:state.cols)
  endif
  return a:state.line_cache[l:key]
endfunction

function! s:flush_line_cache(state) abort
  if type(get(a:state, 'line_cache', {})) != type({}) || empty(a:state.line_cache)
    return
  endif
  for [l:key, l:chars] in items(a:state.line_cache)
    let l:row = str2nr(l:key)
    if l:row >= 0 && l:row < len(a:state.lines)
      let a:state.lines[l:row] = join(l:chars, '')
    endif
  endfor
  let a:state.line_cache = {}
endfunction

function! s:append_scrollback(state, line, attr_row) abort
  if get(a:state, 'alt_active', 0)
    return
  endif
  let l:limit = s:scrollback_limit()
  if l:limit <= 0
    return
  endif
  call add(a:state.scrollback, a:line)
  call add(a:state.scrollback_attr_rows, s:normalize_attr_row(a:attr_row, a:state.cols))
  if len(a:state.scrollback) > l:limit
    call remove(a:state.scrollback, 0, len(a:state.scrollback) - l:limit - 1)
    call remove(a:state.scrollback_attr_rows, 0, len(a:state.scrollback_attr_rows) - l:limit - 1)
  endif
endfunction

function! s:charset_name(final) abort
  if a:final ==# '0'
    return 'dec_special'
  endif
  return 'ascii'
endfunction

function! s:translate_dec_special(ch) abort
  let l:map = {
        \ '`': '◆',
        \ 'a': '▒',
        \ 'f': '°',
        \ 'g': '±',
        \ 'h': '␤',
        \ 'i': '␋',
        \ 'j': '┘',
        \ 'k': '┐',
        \ 'l': '┌',
        \ 'm': '└',
        \ 'n': '┼',
        \ 'o': '⎺',
        \ 'p': '⎻',
        \ 'q': '─',
        \ 'r': '⎼',
        \ 's': '⎽',
        \ 't': '├',
        \ 'u': '┤',
        \ 'v': '┴',
        \ 'w': '┬',
        \ 'x': '│',
        \ 'y': '≤',
        \ 'z': '≥',
        \ '{': 'π',
        \ '|': '≠',
        \ '}': '£',
        \ '~': '·',
        \ }
  return get(l:map, a:ch, a:ch)
endfunction

function! s:translate_char(state, ch) abort
  if strlen(a:ch) != 1 || char2nr(a:ch) > 0x7e
    return a:ch
  endif
  let l:charset = get(a:state, get(a:state, 'charset_active', 'g0') ==# 'g1' ? 'charset_g1' : 'charset_g0', 'ascii')
  if l:charset ==# 'dec_special'
    return s:translate_dec_special(a:ch)
  endif
  return a:ch
endfunction

function! s:visible_window_views(bufnr, line_count) abort
  let l:current = win_getid()
  let l:views = []
  for l:info in getwininfo()
    if get(l:info, 'bufnr', 0) != a:bufnr
      continue
    endif
    if !win_gotoid(get(l:info, 'winid', 0))
      continue
    endif
    let l:view = winsaveview()
    let l:follow_tail = line('w$') >= max([1, a:line_count]) ? 1 : 0
    call setwinvar(win_getid(), 'jusi_terminal_follow_tail', l:follow_tail)
    call add(l:views, {
          \ 'winid': win_getid(),
          \ 'view': l:view,
          \ 'follow_tail': l:follow_tail,
          \ })
  endfor
  if l:current > 0
    call win_gotoid(l:current)
  endif
  return l:views
endfunction

function! s:restore_visible_window_views(bufnr, views, line_count, follow_tail, alt_active) abort
  let l:current = win_getid()
  for l:item in a:views
    if !win_gotoid(get(l:item, 'winid', 0))
      continue
    endif
    if a:alt_active
      let l:view = {
            \ 'lnum': 1,
            \ 'col': 1,
            \ 'curswant': 1,
            \ 'leftcol': 0,
            \ 'topline': 1,
            \ }
      call winrestview(l:view)
      call setwinvar(win_getid(), 'jusi_terminal_follow_tail', 0)
    elseif a:follow_tail && get(l:item, 'follow_tail', 0)
      let l:view = {
            \ 'lnum': a:line_count,
            \ 'col': 1,
            \ 'curswant': 1,
            \ 'leftcol': 0,
            \ 'topline': max([1, a:line_count - winheight(0) + 1]),
            \ }
      call winrestview(l:view)
      call setwinvar(win_getid(), 'jusi_terminal_follow_tail', 1)
    else
      call winrestview(get(l:item, 'view', {}))
      call setwinvar(win_getid(), 'jusi_terminal_follow_tail', 0)
    endif
  endfor
  if l:current > 0
    call win_gotoid(l:current)
  endif
endfunction

function! s:visible_attr_rows(state, screen_lines) abort
  let l:rows = copy(get(a:state, 'attr_rows', []))
  while len(l:rows) < len(a:screen_lines)
    call add(l:rows, s:blank_attr_row(a:state.cols))
  endwhile
  if len(l:rows) > len(a:screen_lines)
    call remove(l:rows, len(a:screen_lines), -1)
  endif
  return !get(a:state, 'alt_active', 0)
        \ ? copy(get(a:state, 'scrollback_attr_rows', [])) + l:rows
        \ : l:rows
endfunction

function! s:apply_window_style_matches(winid, attr_rows) abort
  let l:reverse_positions = s:reverse_row_positions(a:attr_rows)
  let l:ids = s:apply_reverse_row_matches(a:winid, l:reverse_positions)
  if !s:styles_enabled()
    return
  endif
  call s:clear_window_style_matches(a:winid)
  let l:ids = []
  if !empty(l:reverse_positions)
    let l:reverse_group = s:ensure_reverse_row_group()
    for l:pos in l:reverse_positions
      call add(l:ids, matchaddpos(l:reverse_group, [l:pos], 5, -1, {'window': a:winid}))
    endfor
  endif
  let l:limit = s:style_span_limit()
  if l:limit <= 0
    call setwinvar(a:winid, 'jusi_terminal_style_matches', l:ids)
    call setwinvar(a:winid, 'jusi_terminal_reverse_rows', copy(l:reverse_positions))
    return
  endif
  let l:span_count = 0
  let l:row_idx = 0
  while l:row_idx < len(a:attr_rows)
    let l:row = s:normalize_attr_row(get(a:attr_rows, l:row_idx, []), len(get(a:attr_rows, l:row_idx, [])))
    let l:col = 0
    while l:col < len(l:row)
      let l:style = get(l:row, l:col, s:default_style())
      if s:is_default_style(l:style)
        let l:col += 1
        continue
      endif
      let l:run_end = l:col
      while l:run_end + 1 < len(l:row) && s:style_key(get(l:row, l:run_end + 1, s:default_style())) ==# s:style_key(l:style)
        let l:run_end += 1
      endwhile
      let l:group = s:ensure_style_group(l:style)
      if !empty(l:group)
        let l:span_count += 1
        if l:span_count > l:limit
          call s:clear_window_style_matches(a:winid)
          return
        endif
        call add(l:ids, matchaddpos(l:group, [[l:row_idx + 1, l:col + 1, l:run_end - l:col + 1]], 10, -1, {'window': a:winid}))
      endif
      let l:col = l:run_end + 1
    endwhile
    let l:row_idx += 1
  endwhile
  call setwinvar(a:winid, 'jusi_terminal_style_matches', l:ids)
  call setwinvar(a:winid, 'jusi_terminal_reverse_rows', copy(l:reverse_positions))
endfunction

function! s:update_buffer_lines(bufnr, existing_lines, new_lines) abort
  let l:existing_len = len(a:existing_lines)
  let l:new_len = len(a:new_lines)
  let l:overlap = min([l:existing_len, l:new_len])
  let l:start = -1
  let l:i = 0
  while l:i < l:overlap
    if get(a:existing_lines, l:i, '') !=# get(a:new_lines, l:i, '')
      if l:start < 0
        let l:start = l:i + 1
      endif
    elseif l:start > 0
      call setbufline(a:bufnr, l:start, a:new_lines[l:start - 1 : l:i - 1])
      let l:start = -1
    endif
    let l:i += 1
  endwhile
  if l:start > 0
    call setbufline(a:bufnr, l:start, a:new_lines[l:start - 1 : l:overlap - 1])
  endif
  if l:new_len > l:existing_len
    if exists('*appendbufline')
      call appendbufline(a:bufnr, l:existing_len, a:new_lines[l:existing_len : -1])
    else
      call setbufline(a:bufnr, 1, a:new_lines)
      return
    endif
  elseif l:existing_len > l:new_len
    call deletebufline(a:bufnr, l:new_len + 1, '$')
  endif
endfunction

function! s:render(bufnr, state) abort
  if !s:is_valid_bufnr(a:bufnr)
    return 0
  endif
  call s:flush_line_cache(a:state)
  let l:existing_lines = getbufline(a:bufnr, 1, '$')
  let l:existing = len(l:existing_lines)
  let l:window_views = s:is_visible_bufnr(a:bufnr)
        \ ? s:visible_window_views(a:bufnr, l:existing)
        \ : []
  let l:screen_lines = copy(a:state.lines)
  while len(l:screen_lines) < a:state.rows
    call add(l:screen_lines, s:blank_line(a:state.cols))
  endwhile
  if len(l:screen_lines) > a:state.rows
    call remove(l:screen_lines, a:state.rows, -1)
  endif
  let l:visible = s:is_visible_bufnr(a:bufnr)
  let l:lines = l:visible && !get(a:state, 'alt_active', 0)
        \ ? copy(get(a:state, 'scrollback', [])) + l:screen_lines
        \ : copy(l:screen_lines)
  let l:attr_rows = s:visible_attr_rows(a:state, l:screen_lines)
  if get(a:state, 'cursor_visible', 1) && l:visible
    let l:cursor_offset = l:visible && !get(a:state, 'alt_active', 0) ? len(get(a:state, 'scrollback', [])) : 0
    let l:cursor_row = min([len(l:lines) - 1, l:cursor_offset + max([0, get(a:state, 'cursor_row', 0)])])
    let l:cursor_col = min([a:state.cols - 1, max([0, get(a:state, 'cursor_col', 0)])])
    let l:chars = s:line_chars(l:lines[l:cursor_row], a:state.cols)
    let l:chars[l:cursor_col] = '█'
    let l:lines[l:cursor_row] = join(l:chars, '')
  endif
  call setbufvar(a:bufnr, '&modifiable', 1)
  call s:update_buffer_lines(a:bufnr, l:existing_lines, l:lines)
  call setbufvar(a:bufnr, '&modified', 0)
  call setbufvar(a:bufnr, '&modifiable', 0)
  if !empty(l:window_views)
    for l:item in l:window_views
      call s:apply_window_style_matches(get(l:item, 'winid', 0), l:attr_rows)
    endfor
    call s:restore_visible_window_views(
          \ a:bufnr,
          \ l:window_views,
          \ len(l:lines),
          \ !get(a:state, 'alt_active', 0),
          \ get(a:state, 'alt_active', 0))
  endif
  return 1
endfunction

function! s:line_chars(line, cols) abort
  let l:chars = split(a:line, '\zs')
  while len(l:chars) < a:cols
    call add(l:chars, ' ')
  endwhile
  call s:truncate_chars(l:chars, a:cols)
  return l:chars
endfunction

function! s:truncate_chars(chars, cols) abort
  if len(a:chars) > a:cols
    call remove(a:chars, a:cols, -1)
  endif
endfunction

function! s:set_char(state, row, col, ch) abort
  call s:ensure_line(a:state, a:row)
  let l:chars = s:get_cached_chars(a:state, a:row)
  let l:chars[a:col] = a:ch
  let a:state.attr_rows[a:row][a:col] = s:canonical_style(get(a:state, 'current_style', s:default_style()))
endfunction

function! s:erase_line_segment(state, row, start_col, end_col) abort
  call s:ensure_line(a:state, a:row)
  let l:chars = s:get_cached_chars(a:state, a:row)
  let l:start = max([0, a:start_col])
  let l:end = min([a:state.cols - 1, a:end_col])
  if l:end < l:start
    return
  endif
  for l:i in range(l:start, l:end)
    let l:chars[l:i] = ' '
    let a:state.attr_rows[a:row][l:i] = s:canonical_style(s:default_style())
  endfor
endfunction

function! s:insert_blank_chars(state, row, col, count) abort
  call s:ensure_line(a:state, a:row)
  let l:chars = s:get_cached_chars(a:state, a:row)
  let l:attrs = s:normalize_attr_row(a:state.attr_rows[a:row], a:state.cols)
  let l:count = max([1, a:count])
  let l:col = min([a:state.cols - 1, max([0, a:col])])
  call extend(l:chars, repeat([' '], l:count), l:col)
  call extend(l:attrs, repeat([s:canonical_style(s:default_style())], l:count), l:col)
  call s:truncate_chars(l:chars, a:state.cols)
  call s:truncate_chars(l:attrs, a:state.cols)
  let a:state.attr_rows[a:row] = l:attrs
endfunction

function! s:delete_chars(state, row, col, count) abort
  call s:ensure_line(a:state, a:row)
  let l:chars = s:get_cached_chars(a:state, a:row)
  let l:attrs = s:normalize_attr_row(a:state.attr_rows[a:row], a:state.cols)
  let l:count = max([1, a:count])
  let l:col = min([a:state.cols - 1, max([0, a:col])])
  if l:col < len(l:chars)
    call remove(l:chars, l:col, min([len(l:chars) - 1, l:col + l:count - 1]))
    call remove(l:attrs, l:col, min([len(l:attrs) - 1, l:col + l:count - 1]))
  endif
  call extend(l:chars, repeat([' '], l:count))
  call extend(l:attrs, repeat([s:canonical_style(s:default_style())], l:count))
  call s:truncate_chars(l:chars, a:state.cols)
  call s:truncate_chars(l:attrs, a:state.cols)
  let a:state.attr_rows[a:row] = l:attrs
endfunction

function! s:scroll_region(state) abort
  let l:top = min([a:state.rows - 1, max([0, get(a:state, 'scroll_top', 0)])])
  let l:bottom = min([a:state.rows - 1, max([l:top, get(a:state, 'scroll_bottom', a:state.rows - 1)])])
  return {'top': l:top, 'bottom': l:bottom}
endfunction

function! s:insert_lines(state, row, count) abort
  call s:flush_line_cache(a:state)
  let l:count = max([1, a:count])
  let l:region = s:scroll_region(a:state)
  let l:row = min([l:region.bottom, max([l:region.top, a:row])])
  let l:i = 0
  while l:i < l:count
    call insert(a:state.lines, s:blank_line(a:state.cols), l:row)
    call insert(a:state.attr_rows, s:blank_attr_row(a:state.cols), l:row)
    if len(a:state.lines) > l:region.bottom + 1
      call remove(a:state.lines, l:region.bottom + 1)
      call remove(a:state.attr_rows, l:region.bottom + 1)
    endif
    let l:i += 1
  endwhile
  while len(a:state.lines) > a:state.rows
    call remove(a:state.lines, -1)
    call remove(a:state.attr_rows, -1)
  endwhile
endfunction

function! s:delete_lines(state, row, count) abort
  call s:flush_line_cache(a:state)
  let l:count = max([1, a:count])
  let l:region = s:scroll_region(a:state)
  let l:row = min([l:region.bottom, max([l:region.top, a:row])])
  let l:i = 0
  while l:i < l:count && l:row <= l:region.bottom && l:row < len(a:state.lines)
    let l:deleted_line = a:state.lines[l:row]
    let l:deleted_attr = a:state.attr_rows[l:row]
    if l:region.top ==# 0 && l:region.bottom ==# a:state.rows - 1
      call s:append_scrollback(a:state, l:deleted_line, l:deleted_attr)
    endif
    call remove(a:state.lines, l:row)
    call remove(a:state.attr_rows, l:row)
    call insert(a:state.lines, s:blank_line(a:state.cols), l:region.bottom)
    call insert(a:state.attr_rows, s:blank_attr_row(a:state.cols), l:region.bottom)
    let l:i += 1
  endwhile
  while len(a:state.lines) > a:state.rows
    call remove(a:state.lines, -1)
    call remove(a:state.attr_rows, -1)
  endwhile
endfunction

function! s:clear_screen(state) abort
  call s:invalidate_line_cache(a:state)
  let a:state.lines = []
  let a:state.attr_rows = []
  let l:i = 0
  while l:i < a:state.rows
    call add(a:state.lines, s:blank_line(a:state.cols))
    call add(a:state.attr_rows, s:blank_attr_row(a:state.cols))
    let l:i += 1
  endwhile
endfunction

function! s:linefeed(state) abort
  call s:flush_line_cache(a:state)
  let l:top = min([a:state.rows - 1, max([0, get(a:state, 'scroll_top', 0)])])
  let l:bottom = min([a:state.rows - 1, max([l:top, get(a:state, 'scroll_bottom', a:state.rows - 1)])])
  if a:state.cursor_row ==# l:bottom
    if l:top < len(a:state.lines)
      if l:top ==# 0 && l:bottom ==# a:state.rows - 1
        call s:append_scrollback(a:state, a:state.lines[l:top], a:state.attr_rows[l:top])
      endif
      call remove(a:state.lines, l:top)
      call remove(a:state.attr_rows, l:top)
      call insert(a:state.lines, s:blank_line(a:state.cols), l:bottom)
      call insert(a:state.attr_rows, s:blank_attr_row(a:state.cols), l:bottom)
    endif
  else
    let a:state.cursor_row = min([a:state.rows - 1, a:state.cursor_row + 1])
  endif
  call s:ensure_line(a:state, a:state.cursor_row)
endfunction

function! s:index(state) abort
  call s:flush_line_cache(a:state)
  let a:state.cursor_row = min([a:state.rows - 1, a:state.cursor_row + 1])
  let l:top = min([a:state.rows - 1, max([0, get(a:state, 'scroll_top', 0)])])
  let l:bottom = min([a:state.rows - 1, max([l:top, get(a:state, 'scroll_bottom', a:state.rows - 1)])])
  if a:state.cursor_row > l:bottom
    let a:state.cursor_row = l:bottom
    if l:top < len(a:state.lines)
      if l:top ==# 0 && l:bottom ==# a:state.rows - 1
        call s:append_scrollback(a:state, a:state.lines[l:top], a:state.attr_rows[l:top])
      endif
      call remove(a:state.lines, l:top)
      call remove(a:state.attr_rows, l:top)
      call insert(a:state.lines, s:blank_line(a:state.cols), l:bottom)
      call insert(a:state.attr_rows, s:blank_attr_row(a:state.cols), l:bottom)
    endif
  endif
  call s:ensure_line(a:state, a:state.cursor_row)
endfunction

function! s:reverse_index(state) abort
  call s:flush_line_cache(a:state)
  let l:top = min([a:state.rows - 1, max([0, get(a:state, 'scroll_top', 0)])])
  let l:bottom = min([a:state.rows - 1, max([l:top, get(a:state, 'scroll_bottom', a:state.rows - 1)])])
  if a:state.cursor_row ==# l:top
    call insert(a:state.lines, s:blank_line(a:state.cols), l:top)
    call insert(a:state.attr_rows, s:blank_attr_row(a:state.cols), l:top)
    call remove(a:state.lines, l:bottom + 1)
    call remove(a:state.attr_rows, l:bottom + 1)
  else
    let a:state.cursor_row = max([0, a:state.cursor_row - 1])
  endif
  call s:ensure_line(a:state, a:state.cursor_row)
endfunction

function! s:put_char(state, ch) abort
  call s:ensure_line(a:state, a:state.cursor_row)
  call s:set_char(a:state, a:state.cursor_row, a:state.cursor_col, a:ch)
  let a:state.last_printable = a:ch
  let a:state.cursor_col += 1
  if a:state.cursor_col >= a:state.cols
    let a:state.cursor_col = 0
    call s:linefeed(a:state)
  endif
endfunction

function! s:param(params, idx, default) abort
  if a:idx >= len(a:params)
    return a:default
  endif
  let l:value = a:params[a:idx]
  return empty(l:value) ? a:default : str2nr(l:value)
endfunction

function! s:param_num(params, idx, default) abort
  if a:idx >= len(a:params)
    return a:default
  endif
  let l:value = a:params[a:idx]
  return l:value < 0 ? a:default : l:value
endfunction

function! s:parse_csi(seq) abort
  if !exists('s:csi_parse_cache')
    let s:csi_parse_cache = {}
  endif
  if has_key(s:csi_parse_cache, a:seq)
    return s:csi_parse_cache[a:seq]
  endif
  let l:final = strpart(a:seq, len(a:seq) - 1, 1)
  let l:body = strpart(a:seq, 0, len(a:seq) - 1)
  let l:private = !empty(l:body) && l:body[0] ==# '?'
  if l:private
    let l:body = strpart(l:body, 1)
  endif
  let l:params = []
  if !empty(l:body)
    for l:item in split(l:body, ';')
      call add(l:params, empty(l:item) ? -1 : str2nr(l:item))
    endfor
  endif
  let l:parsed = {
        \ 'final': l:final,
        \ 'private': l:private ? 1 : 0,
        \ 'params': l:params,
        \ }
  let s:csi_parse_cache[a:seq] = l:parsed
  return l:parsed
endfunction

function! s:ansi_color_name(code, bright) abort
  let l:names = ['black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white']
  if a:code < 0 || a:code > 7
    return ''
  endif
  return a:bright ? 'bright_' . l:names[a:code] : l:names[a:code]
endfunction

function! s:apply_sgr_params(state, params) abort
  let l:params = empty(a:params) ? ['0'] : a:params
  for l:param in l:params
    let l:code = empty(l:param) ? 0 : str2nr(l:param)
    if l:code ==# 0
      let a:state.current_style = s:default_style()
    elseif l:code ==# 1
      let a:state.current_style.bold = 1
    elseif l:code ==# 22
      let a:state.current_style.bold = 0
    elseif l:code ==# 7
      let a:state.current_style.reverse = 1
    elseif l:code ==# 27
      let a:state.current_style.reverse = 0
    elseif l:code ==# 39
      let a:state.current_style.fg = ''
    elseif l:code ==# 49
      let a:state.current_style.bg = ''
    elseif l:code >= 30 && l:code <= 37
      let a:state.current_style.fg = s:ansi_color_name(l:code - 30, 0)
    elseif l:code >= 40 && l:code <= 47
      let a:state.current_style.bg = s:ansi_color_name(l:code - 40, 0)
    elseif l:code >= 90 && l:code <= 97
      let a:state.current_style.fg = s:ansi_color_name(l:code - 90, 1)
    elseif l:code >= 100 && l:code <= 107
      let a:state.current_style.bg = s:ansi_color_name(l:code - 100, 1)
    endif
  endfor
endfunction

function! s:utf8_expected_len(byte) abort
  if a:byte >= 0xc2 && a:byte <= 0xdf
    return 2
  endif
  if a:byte >= 0xe0 && a:byte <= 0xef
    return 3
  endif
  if a:byte >= 0xf0 && a:byte <= 0xf4
    return 4
  endif
  return 0
endfunction

function! s:utf8_codepoint(bytes) abort
  let l:len = len(a:bytes)
  if l:len == 2
    return ((a:bytes[0] - 0xc0) * 0x40) + (a:bytes[1] - 0x80)
  endif
  if l:len == 3
    return ((a:bytes[0] - 0xe0) * 0x1000)
          \ + ((a:bytes[1] - 0x80) * 0x40)
          \ + (a:bytes[2] - 0x80)
  endif
  if l:len == 4
    return ((a:bytes[0] - 0xf0) * 0x40000)
          \ + ((a:bytes[1] - 0x80) * 0x1000)
          \ + ((a:bytes[2] - 0x80) * 0x40)
          \ + (a:bytes[3] - 0x80)
  endif
  return -1
endfunction

function! s:utf8_emit_pending(state) abort
  if empty(get(a:state, 'utf8', []))
    return 0
  endif
  let l:bytes = copy(a:state.utf8)
  let a:state.utf8 = []
  let l:expected = s:utf8_expected_len(l:bytes[0])
  if l:expected == 0 || len(l:bytes) != l:expected
    call s:put_char(a:state, '?')
    return 1
  endif
  for l:i in range(1, len(l:bytes) - 1)
    if l:bytes[l:i] < 0x80 || l:bytes[l:i] > 0xbf
      call s:put_char(a:state, '?')
      return 1
    endif
  endfor
  let l:codepoint = s:utf8_codepoint(l:bytes)
  if l:codepoint < 0
        \ || (l:expected == 2 && l:codepoint < 0x80)
        \ || (l:expected == 3 && l:codepoint < 0x800)
        \ || (l:expected == 4 && l:codepoint < 0x10000)
        \ || l:codepoint > 0x10ffff
        \ || (l:codepoint >= 0xd800 && l:codepoint <= 0xdfff)
    call s:put_char(a:state, '?')
    return 1
  endif
  call s:put_char(a:state, nr2char(l:codepoint))
  return 1
endfunction

function! s:handle_csi(state, seq) abort
  if empty(a:seq)
    return
  endif
  let l:parsed = s:parse_csi(a:seq)
  let l:final = l:parsed.final
  let l:private = l:parsed.private
  let l:params = l:parsed.params
  if l:final ==# 'A'
    let a:state.cursor_row = max([0, a:state.cursor_row - s:param_num(l:params, 0, 1)])
    return
  endif
  if l:final ==# 'B'
    let a:state.cursor_row = min([a:state.rows - 1, a:state.cursor_row + s:param_num(l:params, 0, 1)])
    call s:ensure_line(a:state, a:state.cursor_row)
    return
  endif
  if l:final ==# 'C'
    let a:state.cursor_col = min([a:state.cols - 1, a:state.cursor_col + s:param_num(l:params, 0, 1)])
    return
  endif
  if l:final ==# 'D'
    let a:state.cursor_col = max([0, a:state.cursor_col - s:param_num(l:params, 0, 1)])
    return
  endif
  if l:final ==# 'G'
    let a:state.cursor_col = min([a:state.cols - 1, max([0, s:param_num(l:params, 0, 1) - 1])])
    return
  endif
  if l:final ==# '`'
    let a:state.cursor_col = min([a:state.cols - 1, max([0, s:param_num(l:params, 0, 1) - 1])])
    return
  endif
  if l:final ==# 'd'
    let a:state.cursor_row = min([a:state.rows - 1, max([0, s:param_num(l:params, 0, 1) - 1])])
    call s:ensure_line(a:state, a:state.cursor_row)
    return
  endif
  if l:final ==# 'H' || l:final ==# 'f'
    let a:state.cursor_row = min([a:state.rows - 1, max([0, s:param_num(l:params, 0, 1) - 1])])
    let a:state.cursor_col = min([a:state.cols - 1, max([0, s:param_num(l:params, 1, 1) - 1])])
    call s:ensure_line(a:state, a:state.cursor_row)
    return
  endif
  if l:final ==# 'E'
    let a:state.cursor_row = min([a:state.rows - 1, a:state.cursor_row + s:param_num(l:params, 0, 1)])
    let a:state.cursor_col = 0
    call s:ensure_line(a:state, a:state.cursor_row)
    return
  endif
  if l:final ==# 'e'
    let a:state.cursor_row = min([a:state.rows - 1, a:state.cursor_row + s:param_num(l:params, 0, 1)])
    call s:ensure_line(a:state, a:state.cursor_row)
    return
  endif
  if l:final ==# 'F'
    let a:state.cursor_row = max([0, a:state.cursor_row - s:param_num(l:params, 0, 1)])
    let a:state.cursor_col = 0
    call s:ensure_line(a:state, a:state.cursor_row)
    return
  endif
  if l:final ==# 'a'
    let a:state.cursor_col = min([a:state.cols - 1, a:state.cursor_col + s:param_num(l:params, 0, 1)])
    return
  endif
  if l:final ==# 'r'
    let l:top = max([1, s:param_num(l:params, 0, 1)]) - 1
    let l:bottom = max([1, s:param_num(l:params, 1, a:state.rows)]) - 1
    let a:state.scroll_top = min([a:state.rows - 1, max([0, l:top])])
    let a:state.scroll_bottom = min([a:state.rows - 1, max([a:state.scroll_top, l:bottom])])
    let a:state.cursor_row = a:state.scroll_top
    let a:state.cursor_col = 0
    return
  endif
  if l:final ==# 'J'
    let l:mode = s:param_num(l:params, 0, 0)
    if l:mode ==# 2
      call s:clear_screen(a:state)
      let a:state.cursor_row = 0
      let a:state.cursor_col = 0
      return
    endif
    if l:mode ==# 3
      call s:clear_screen(a:state)
      let a:state.cursor_row = 0
      let a:state.cursor_col = 0
      return
    endif
    if l:mode ==# 0
      call s:erase_line_segment(a:state, a:state.cursor_row, a:state.cursor_col, a:state.cols - 1)
      let l:row = a:state.cursor_row + 1
      while l:row < len(a:state.lines)
        let a:state.lines[l:row] = s:blank_line(a:state.cols)
        let a:state.attr_rows[l:row] = s:blank_attr_row(a:state.cols)
        let l:row += 1
      endwhile
      return
    endif
    if l:mode ==# 1
      call s:erase_line_segment(a:state, a:state.cursor_row, 0, a:state.cursor_col)
      let l:row = 0
      while l:row < a:state.cursor_row
        let a:state.lines[l:row] = s:blank_line(a:state.cols)
        let a:state.attr_rows[l:row] = s:blank_attr_row(a:state.cols)
        let l:row += 1
      endwhile
    endif
    return
  endif
  if l:final ==# 'K'
    let l:mode = s:param_num(l:params, 0, 0)
    if l:mode ==# 1
      call s:erase_line_segment(a:state, a:state.cursor_row, 0, a:state.cursor_col)
    elseif l:mode ==# 2
      call s:erase_line_segment(a:state, a:state.cursor_row, 0, a:state.cols - 1)
    else
      call s:erase_line_segment(a:state, a:state.cursor_row, a:state.cursor_col, a:state.cols - 1)
    endif
    return
  endif
  if l:final ==# '@'
    call s:insert_blank_chars(a:state, a:state.cursor_row, a:state.cursor_col, s:param_num(l:params, 0, 1))
    return
  endif
  if l:final ==# 'P'
    call s:delete_chars(a:state, a:state.cursor_row, a:state.cursor_col, s:param_num(l:params, 0, 1))
    return
  endif
  if l:final ==# 'b'
    let l:count = s:param_num(l:params, 0, 1)
    let l:i = 0
    while l:i < l:count
      call s:put_char(a:state, get(a:state, 'last_printable', ' '))
      let l:i += 1
    endwhile
    return
  endif
  if l:final ==# 'I'
    let l:count = s:param_num(l:params, 0, 1)
    let a:state.cursor_col = min([a:state.cols - 1, ((a:state.cursor_col / 8) + l:count) * 8])
    return
  endif
  if l:final ==# 'Z'
    let l:count = s:param_num(l:params, 0, 1)
    let a:state.cursor_col = max([0, (((a:state.cursor_col / 8) + 1) - l:count) * 8])
    return
  endif
  if l:final ==# 'X'
    call s:erase_line_segment(a:state, a:state.cursor_row, a:state.cursor_col, a:state.cursor_col + s:param_num(l:params, 0, 1) - 1)
    return
  endif
  if l:final ==# 'L'
    call s:insert_lines(a:state, a:state.cursor_row, s:param_num(l:params, 0, 1))
    return
  endif
  if l:final ==# 'M'
    call s:delete_lines(a:state, a:state.cursor_row, s:param_num(l:params, 0, 1))
    return
  endif
  if l:final ==# 'S'
    call s:delete_lines(a:state, get(a:state, 'scroll_top', 0), s:param_num(l:params, 0, 1))
    return
  endif
  if l:final ==# 'T'
    call s:insert_lines(a:state, get(a:state, 'scroll_top', 0), s:param_num(l:params, 0, 1))
    return
  endif
  if l:final ==# 'm'
    call s:apply_sgr_params(a:state, l:params)
    return
  endif
  if index(['n', 'q', 'p'], l:final) >= 0
    return
  endif
  if l:final ==# 'h' || l:final ==# 'l'
    if l:private
      let l:enable = l:final ==# 'h'
      for l:param in l:params
        let l:mode = l:param < 0 ? 0 : l:param
        if l:mode ==# 25
          let a:state.cursor_visible = l:enable ? 1 : 0
        elseif l:mode ==# 1048
          if l:enable
            let a:state.saved_cursor_row = a:state.cursor_row
            let a:state.saved_cursor_col = a:state.cursor_col
          else
            let a:state.cursor_row = min([a:state.rows - 1, a:state.saved_cursor_row])
            let a:state.cursor_col = min([a:state.cols - 1, a:state.saved_cursor_col])
            call s:ensure_line(a:state, a:state.cursor_row)
          endif
        elseif index([47, 1047, 1049], l:mode) >= 0
          if l:enable
            let a:state.alt_screen = {
                  \ 'scrollback': copy(get(a:state, 'scrollback', [])),
                  \ 'scrollback_attr_rows': copy(get(a:state, 'scrollback_attr_rows', [])),
                  \ 'lines': copy(a:state.lines),
                  \ 'attr_rows': copy(get(a:state, 'attr_rows', [])),
                  \ 'charset_g0': get(a:state, 'charset_g0', 'ascii'),
                  \ 'charset_g1': get(a:state, 'charset_g1', 'ascii'),
                  \ 'charset_active': get(a:state, 'charset_active', 'g0'),
                  \ 'cursor_row': a:state.cursor_row,
                  \ 'cursor_col': a:state.cursor_col,
                  \ 'saved_cursor_row': a:state.saved_cursor_row,
                  \ 'saved_cursor_col': a:state.saved_cursor_col,
                  \ 'scroll_top': a:state.scroll_top,
                  \ 'scroll_bottom': a:state.scroll_bottom,
                  \ 'current_style': s:style_copy(get(a:state, 'current_style', s:default_style())),
                  \ }
            let a:state.alt_active = 1
            let a:state.scrollback_attr_rows = []
            call s:clear_screen(a:state)
            let a:state.cursor_row = 0
            let a:state.cursor_col = 0
            let a:state.scroll_top = 0
            let a:state.scroll_bottom = a:state.rows - 1
          elseif !empty(a:state.alt_screen)
            let a:state.alt_active = 0
            let a:state.scrollback = copy(get(a:state.alt_screen, 'scrollback', []))
            let a:state.scrollback_attr_rows = copy(get(a:state.alt_screen, 'scrollback_attr_rows', []))
            let a:state.lines = copy(get(a:state.alt_screen, 'lines', [s:blank_line(a:state.cols)]))
            let a:state.attr_rows = copy(get(a:state.alt_screen, 'attr_rows', [s:blank_attr_row(a:state.cols)]))
            let a:state.charset_g0 = get(a:state.alt_screen, 'charset_g0', 'ascii')
            let a:state.charset_g1 = get(a:state.alt_screen, 'charset_g1', 'ascii')
            let a:state.charset_active = get(a:state.alt_screen, 'charset_active', 'g0')
            let a:state.cursor_row = get(a:state.alt_screen, 'cursor_row', 0)
            let a:state.cursor_col = get(a:state.alt_screen, 'cursor_col', 0)
            let a:state.saved_cursor_row = get(a:state.alt_screen, 'saved_cursor_row', 0)
            let a:state.saved_cursor_col = get(a:state.alt_screen, 'saved_cursor_col', 0)
            let a:state.scroll_top = get(a:state.alt_screen, 'scroll_top', 0)
            let a:state.scroll_bottom = get(a:state.alt_screen, 'scroll_bottom', a:state.rows - 1)
            let a:state.current_style = s:style_copy(get(a:state.alt_screen, 'current_style', s:default_style()))
            let a:state.alt_screen = {}
          endif
        endif
      endfor
    endif
    return
  endif
  if l:final ==# 's'
    let a:state.saved_cursor_row = a:state.cursor_row
    let a:state.saved_cursor_col = a:state.cursor_col
    return
  endif
  if l:final ==# 'u'
    let a:state.cursor_row = min([a:state.rows - 1, a:state.saved_cursor_row])
    let a:state.cursor_col = min([a:state.cols - 1, a:state.saved_cursor_col])
    call s:ensure_line(a:state, a:state.cursor_row)
    return
  endif
endfunction

function! s:decode_hex(hex) abort
  let l:clean = substitute(a:hex, '\s\+', '', 'g')
  let l:bytes = []
  let l:i = 0
  while l:i + 1 < len(l:clean)
    call add(l:bytes, str2nr(strpart(l:clean, l:i, 2), 16))
    let l:i += 2
  endwhile
  return l:bytes
endfunction

function! jusi#terminalscreen#resize(bufnr, rows, cols) abort
  if !s:is_valid_bufnr(a:bufnr)
    return 0
  endif
  let l:state = s:state(a:bufnr)
  let l:rows = max([1, a:rows])
  let l:cols = max([1, a:cols])
  let l:state.rows = l:rows
  let l:state.cols = l:cols
  while len(l:state.lines) > l:rows
    call remove(l:state.lines, -1)
  endwhile
  while len(l:state.lines) < l:rows
    call add(l:state.lines, s:blank_line(l:cols))
  endwhile
  while len(l:state.attr_rows) > l:rows
    call remove(l:state.attr_rows, -1)
  endwhile
  while len(l:state.attr_rows) < l:rows
    call add(l:state.attr_rows, s:blank_attr_row(l:cols))
  endwhile
  let l:i = 0
  while l:i < len(l:state.lines)
    let l:chars = s:line_chars(l:state.lines[l:i], l:cols)
    let l:state.lines[l:i] = join(l:chars, '')
    let l:state.attr_rows[l:i] = s:normalize_attr_row(get(l:state.attr_rows, l:i, []), l:cols)
    let l:i += 1
  endwhile
  let l:scroll_i = 0
  while l:scroll_i < len(l:state.scrollback_attr_rows)
    let l:state.scrollback_attr_rows[l:scroll_i] = s:normalize_attr_row(l:state.scrollback_attr_rows[l:scroll_i], l:cols)
    let l:scroll_i += 1
  endwhile
  let l:state.cursor_row = min([l:state.cursor_row, l:rows - 1])
  let l:state.cursor_col = min([l:state.cursor_col, l:cols - 1])
  call s:save_state(a:bufnr, l:state)
  return s:render(a:bufnr, l:state)
endfunction

function! jusi#terminalscreen#refresh(bufnr) abort
  if !s:is_valid_bufnr(a:bufnr)
    return 0
  endif
  let l:state = s:state(a:bufnr)
  call s:save_state(a:bufnr, l:state)
  return s:render(a:bufnr, l:state)
endfunction

function! jusi#terminalscreen#reset(bufnr, ...) abort
  if !s:is_valid_bufnr(a:bufnr)
    return 0
  endif
  let l:rows = a:0 >= 1 ? max([1, a:1]) : max([1, getbufvar(a:bufnr, 'jusi_terminal_rows', 24)])
  let l:cols = a:0 >= 2 ? max([1, a:2]) : max([1, getbufvar(a:bufnr, 'jusi_terminal_cols', 80)])
  let l:state = s:default_state(a:bufnr)
  let l:state.rows = l:rows
  let l:state.cols = l:cols
  let l:state.scrollback = []
  let l:state.alt_active = 0
  let l:state.scroll_top = 0
  let l:state.scroll_bottom = l:rows - 1
  call s:clear_screen(l:state)
  call s:save_state(a:bufnr, l:state)
  return s:render(a:bufnr, l:state)
endfunction

function! jusi#terminalscreen#apply_bytes(bufnr, hex) abort
  if !s:is_valid_bufnr(a:bufnr) || type(a:hex) != type('')
    return 0
  endif
  let l:state = s:state(a:bufnr)
  for l:byte in s:decode_hex(a:hex)
    if !empty(get(l:state, 'utf8', []))
      if l:byte >= 0x80 && l:byte <= 0xbf
        call add(l:state.utf8, l:byte)
        if len(l:state.utf8) >= s:utf8_expected_len(l:state.utf8[0])
          call s:utf8_emit_pending(l:state)
        endif
        continue
      endif
      call s:utf8_emit_pending(l:state)
    endif
    if l:state.esc_state ==# 'esc'
      if l:byte ==# 0x5b
        let l:state.esc_state = 'csi'
        let l:state.csi = ''
      elseif l:byte ==# 0x5d
        let l:state.esc_state = 'osc'
        let l:state.osc = ''
      elseif l:byte ==# 0x28 || l:byte ==# 0x29 || l:byte ==# 0x2a || l:byte ==# 0x2b
        let l:state.esc_state = 'charset'
        let l:state.charset_target = l:byte ==# 0x29 ? 'g1' : 'g0'
      elseif l:byte ==# 0x44
        call s:index(l:state)
        let l:state.esc_state = ''
      elseif l:byte ==# 0x45
        call s:index(l:state)
        let l:state.cursor_col = 0
        let l:state.esc_state = ''
      elseif l:byte ==# 0x4d
        call s:reverse_index(l:state)
        let l:state.esc_state = ''
      elseif l:byte ==# 0x37
        let l:state.saved_cursor_row = l:state.cursor_row
        let l:state.saved_cursor_col = l:state.cursor_col
        let l:state.esc_state = ''
      elseif l:byte ==# 0x38
        let l:state.cursor_row = min([l:state.rows - 1, l:state.saved_cursor_row])
        let l:state.cursor_col = min([l:state.cols - 1, l:state.saved_cursor_col])
        call s:ensure_line(l:state, l:state.cursor_row)
        let l:state.esc_state = ''
      elseif l:byte ==# 0x63
        let l:state = s:default_state(a:bufnr)
      else
        let l:state.esc_state = ''
      endif
      continue
    endif
    if l:state.esc_state ==# 'charset'
      if get(l:state, 'charset_target', 'g0') ==# 'g1'
        let l:state.charset_g1 = s:charset_name(nr2char(l:byte))
      else
        let l:state.charset_g0 = s:charset_name(nr2char(l:byte))
      endif
      let l:state.charset_target = ''
      let l:state.esc_state = ''
      continue
    endif
    if l:state.esc_state ==# 'osc'
      if l:byte ==# 0x07
        let l:state.esc_state = ''
        let l:state.osc = ''
      elseif l:byte ==# 0x1b
        let l:state.esc_state = 'osc_esc'
      else
        let l:state.osc .= nr2char(l:byte)
      endif
      continue
    endif
    if l:state.esc_state ==# 'osc_esc'
      if l:byte ==# 0x5c
        let l:state.esc_state = ''
        let l:state.osc = ''
      else
        let l:state.esc_state = 'osc'
        let l:state.osc .= nr2char(0x1b) . nr2char(l:byte)
      endif
      continue
    endif
    if l:state.esc_state ==# 'csi'
      let l:char = nr2char(l:byte)
      let l:state.csi .= l:char
      if l:char =~# '[@-~]'
        call s:handle_csi(l:state, l:state.csi)
        let l:state.esc_state = ''
        let l:state.csi = ''
      endif
      continue
    endif
    if l:byte ==# 0x1b
      let l:state.esc_state = 'esc'
      let l:state.csi = ''
      continue
    endif
    if l:byte ==# 0x0d
      let l:state.cursor_col = 0
      continue
    endif
    if l:byte ==# 0x0a
      call s:linefeed(l:state)
      continue
    endif
    if l:byte ==# 0x08
      let l:state.cursor_col = max([0, l:state.cursor_col - 1])
      continue
    endif
    if l:byte ==# 0x0e
      let l:state.charset_active = 'g1'
      continue
    endif
    if l:byte ==# 0x0f
      let l:state.charset_active = 'g0'
      continue
    endif
    if l:byte ==# 0x09
      let l:state.cursor_col = min([l:state.cols - 1, ((l:state.cursor_col / 8) + 1) * 8])
      continue
    endif
    if l:byte < 0x20 || l:byte ==# 0x7f
      continue
    endif
    let l:utf8_len = s:utf8_expected_len(l:byte)
    if l:utf8_len > 1
      let l:state.utf8 = [l:byte]
      continue
    endif
    if l:byte > 0x7e
      call s:put_char(l:state, '?')
      continue
    endif
    call s:put_char(l:state, s:translate_char(l:state, nr2char(l:byte)))
  endfor
  if !empty(get(l:state, 'utf8', []))
    call s:utf8_emit_pending(l:state)
  endif
  call s:save_state(a:bufnr, l:state)
  return s:render(a:bufnr, l:state)
endfunction

function! jusi#terminalscreen#debug_state(bufnr) abort
  if !s:is_valid_bufnr(a:bufnr)
    return {}
  endif
  let l:state = s:state(a:bufnr)
  let l:lines = copy(getbufline(a:bufnr, 1, min([max([1, get(l:state, 'rows', 1)]), 8])))
  return {
        \ 'rows': get(l:state, 'rows', 0),
        \ 'cols': get(l:state, 'cols', 0),
        \ 'scrollback_len': len(get(l:state, 'scrollback', [])),
        \ 'cursor_row': get(l:state, 'cursor_row', 0),
        \ 'cursor_col': get(l:state, 'cursor_col', 0),
        \ 'scroll_top': get(l:state, 'scroll_top', 0),
        \ 'scroll_bottom': get(l:state, 'scroll_bottom', 0),
        \ 'esc_state': get(l:state, 'esc_state', ''),
        \ 'csi': get(l:state, 'csi', ''),
        \ 'lines': l:lines,
        \ }
endfunction
