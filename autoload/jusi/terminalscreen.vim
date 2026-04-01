function! s:is_valid_bufnr(bufnr) abort
  return type(a:bufnr) == type(0) && a:bufnr > 0 && bufexists(a:bufnr)
endfunction

function! s:blank_line(cols) abort
  return repeat(' ', max([1, a:cols]))
endfunction

function! s:default_state(bufnr) abort
  let l:rows = max([1, getbufvar(a:bufnr, 'jusi_terminal_rows', 24)])
  let l:cols = max([1, getbufvar(a:bufnr, 'jusi_terminal_cols', 80)])
  return {
        \ 'rows': l:rows,
        \ 'cols': l:cols,
        \ 'cursor_row': 0,
        \ 'cursor_col': 0,
        \ 'saved_cursor_row': 0,
        \ 'saved_cursor_col': 0,
        \ 'scroll_top': 0,
        \ 'scroll_bottom': l:rows - 1,
        \ 'cursor_visible': 1,
        \ 'lines': [s:blank_line(l:cols)],
        \ 'esc_state': '',
        \ 'csi': '',
        \ 'osc': '',
        \ 'last_printable': ' ',
        \ 'alt_screen': {},
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
  if type(get(l:state, 'lines', [])) != type([])
    let l:state.lines = []
  endif
  if empty(l:state.lines)
    let l:state.lines = [s:blank_line(l:state.cols)]
  endif
  let l:state.esc_state = get(l:state, 'esc_state', '')
  let l:state.csi = get(l:state, 'csi', '')
  let l:state.osc = get(l:state, 'osc', '')
  let l:state.last_printable = get(l:state, 'last_printable', ' ')
  let l:state.alt_screen = type(get(l:state, 'alt_screen', {})) == type({}) ? get(l:state, 'alt_screen', {}) : {}
  return l:state
endfunction

function! s:save_state(bufnr, state) abort
  call setbufvar(a:bufnr, 'jusi_terminal_screen', a:state)
  call setbufvar(a:bufnr, 'jusi_terminal_rows', a:state.rows)
  call setbufvar(a:bufnr, 'jusi_terminal_cols', a:state.cols)
  return a:state
endfunction

function! s:ensure_line(state, row) abort
  while len(a:state.lines) <= a:row
    call add(a:state.lines, s:blank_line(a:state.cols))
  endwhile
endfunction

function! s:render(bufnr, state) abort
  if !s:is_valid_bufnr(a:bufnr)
    return 0
  endif
  let l:lines = copy(a:state.lines)
  while len(l:lines) < a:state.rows
    call add(l:lines, s:blank_line(a:state.cols))
  endwhile
  if len(l:lines) > a:state.rows
    call remove(l:lines, a:state.rows, -1)
  endif
  let l:existing = len(getbufline(a:bufnr, 1, '$'))
  call setbufvar(a:bufnr, '&modifiable', 1)
  call setbufline(a:bufnr, 1, l:lines)
  if l:existing > len(l:lines)
    call deletebufline(a:bufnr, len(l:lines) + 1, '$')
  endif
  call setbufvar(a:bufnr, '&modified', 0)
  call setbufvar(a:bufnr, '&modifiable', 0)
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
  let l:chars = s:line_chars(a:state.lines[a:row], a:state.cols)
  let l:chars[a:col] = a:ch
  let a:state.lines[a:row] = join(l:chars, '')
endfunction

function! s:erase_line_segment(state, row, start_col, end_col) abort
  call s:ensure_line(a:state, a:row)
  let l:chars = s:line_chars(a:state.lines[a:row], a:state.cols)
  let l:start = max([0, a:start_col])
  let l:end = min([a:state.cols - 1, a:end_col])
  if l:end < l:start
    return
  endif
  for l:i in range(l:start, l:end)
    let l:chars[l:i] = ' '
  endfor
  let a:state.lines[a:row] = join(l:chars, '')
endfunction

function! s:insert_blank_chars(state, row, col, count) abort
  call s:ensure_line(a:state, a:row)
  let l:chars = s:line_chars(a:state.lines[a:row], a:state.cols)
  let l:count = max([1, a:count])
  let l:col = min([a:state.cols - 1, max([0, a:col])])
  call extend(l:chars, repeat([' '], l:count), l:col)
  call s:truncate_chars(l:chars, a:state.cols)
  let a:state.lines[a:row] = join(l:chars, '')
endfunction

function! s:delete_chars(state, row, col, count) abort
  call s:ensure_line(a:state, a:row)
  let l:chars = s:line_chars(a:state.lines[a:row], a:state.cols)
  let l:count = max([1, a:count])
  let l:col = min([a:state.cols - 1, max([0, a:col])])
  if l:col < len(l:chars)
    call remove(l:chars, l:col, min([len(l:chars) - 1, l:col + l:count - 1]))
  endif
  call extend(l:chars, repeat([' '], l:count))
  call s:truncate_chars(l:chars, a:state.cols)
  let a:state.lines[a:row] = join(l:chars, '')
endfunction

function! s:scroll_region(state) abort
  let l:top = min([a:state.rows - 1, max([0, get(a:state, 'scroll_top', 0)])])
  let l:bottom = min([a:state.rows - 1, max([l:top, get(a:state, 'scroll_bottom', a:state.rows - 1)])])
  return {'top': l:top, 'bottom': l:bottom}
endfunction

function! s:insert_lines(state, row, count) abort
  let l:count = max([1, a:count])
  let l:region = s:scroll_region(a:state)
  let l:row = min([l:region.bottom, max([l:region.top, a:row])])
  let l:i = 0
  while l:i < l:count
    call insert(a:state.lines, s:blank_line(a:state.cols), l:row)
    if len(a:state.lines) > l:region.bottom + 1
      call remove(a:state.lines, l:region.bottom + 1)
    endif
    let l:i += 1
  endwhile
  while len(a:state.lines) > a:state.rows
    call remove(a:state.lines, -1)
  endwhile
endfunction

function! s:delete_lines(state, row, count) abort
  let l:count = max([1, a:count])
  let l:region = s:scroll_region(a:state)
  let l:row = min([l:region.bottom, max([l:region.top, a:row])])
  let l:i = 0
  while l:i < l:count && l:row <= l:region.bottom && l:row < len(a:state.lines)
    call remove(a:state.lines, l:row)
    call insert(a:state.lines, s:blank_line(a:state.cols), l:region.bottom)
    let l:i += 1
  endwhile
  while len(a:state.lines) > a:state.rows
    call remove(a:state.lines, -1)
  endwhile
endfunction

function! s:clear_screen(state) abort
  let a:state.lines = repeat([s:blank_line(a:state.cols)], a:state.rows)
endfunction

function! s:newline(state) abort
  let l:top = min([a:state.rows - 1, max([0, get(a:state, 'scroll_top', 0)])])
  let l:bottom = min([a:state.rows - 1, max([l:top, get(a:state, 'scroll_bottom', a:state.rows - 1)])])
  if a:state.cursor_row ==# l:bottom
    if l:top < len(a:state.lines)
      call remove(a:state.lines, l:top)
      call insert(a:state.lines, s:blank_line(a:state.cols), l:bottom)
    endif
  else
    let a:state.cursor_row = min([a:state.rows - 1, a:state.cursor_row + 1])
  endif
  let a:state.cursor_col = 0
  call s:ensure_line(a:state, a:state.cursor_row)
endfunction

function! s:index(state) abort
  let a:state.cursor_row = min([a:state.rows - 1, a:state.cursor_row + 1])
  let l:top = min([a:state.rows - 1, max([0, get(a:state, 'scroll_top', 0)])])
  let l:bottom = min([a:state.rows - 1, max([l:top, get(a:state, 'scroll_bottom', a:state.rows - 1)])])
  if a:state.cursor_row > l:bottom
    let a:state.cursor_row = l:bottom
    if l:top < len(a:state.lines)
      call remove(a:state.lines, l:top)
      call insert(a:state.lines, s:blank_line(a:state.cols), l:bottom)
    endif
  endif
  call s:ensure_line(a:state, a:state.cursor_row)
endfunction

function! s:reverse_index(state) abort
  let l:top = min([a:state.rows - 1, max([0, get(a:state, 'scroll_top', 0)])])
  let l:bottom = min([a:state.rows - 1, max([l:top, get(a:state, 'scroll_bottom', a:state.rows - 1)])])
  if a:state.cursor_row ==# l:top
    call insert(a:state.lines, s:blank_line(a:state.cols), l:top)
    call remove(a:state.lines, l:bottom + 1)
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
    call s:newline(a:state)
  endif
endfunction

function! s:param(params, idx, default) abort
  if a:idx >= len(a:params)
    return a:default
  endif
  let l:value = a:params[a:idx]
  return empty(l:value) ? a:default : str2nr(l:value)
endfunction

function! s:handle_csi(state, seq) abort
  if empty(a:seq)
    return
  endif
  let l:final = strpart(a:seq, len(a:seq) - 1, 1)
  let l:body = strpart(a:seq, 0, len(a:seq) - 1)
  let l:private = !empty(l:body) && l:body[0] ==# '?'
  if l:private
    let l:body = strpart(l:body, 1)
  endif
  let l:params = split(l:body, ';')
  if l:final ==# 'A'
    let a:state.cursor_row = max([0, a:state.cursor_row - s:param(l:params, 0, 1)])
    return
  endif
  if l:final ==# 'B'
    let a:state.cursor_row = min([a:state.rows - 1, a:state.cursor_row + s:param(l:params, 0, 1)])
    call s:ensure_line(a:state, a:state.cursor_row)
    return
  endif
  if l:final ==# 'C'
    let a:state.cursor_col = min([a:state.cols - 1, a:state.cursor_col + s:param(l:params, 0, 1)])
    return
  endif
  if l:final ==# 'D'
    let a:state.cursor_col = max([0, a:state.cursor_col - s:param(l:params, 0, 1)])
    return
  endif
  if l:final ==# 'G'
    let a:state.cursor_col = min([a:state.cols - 1, max([0, s:param(l:params, 0, 1) - 1])])
    return
  endif
  if l:final ==# '`'
    let a:state.cursor_col = min([a:state.cols - 1, max([0, s:param(l:params, 0, 1) - 1])])
    return
  endif
  if l:final ==# 'd'
    let a:state.cursor_row = min([a:state.rows - 1, max([0, s:param(l:params, 0, 1) - 1])])
    call s:ensure_line(a:state, a:state.cursor_row)
    return
  endif
  if l:final ==# 'H' || l:final ==# 'f'
    let a:state.cursor_row = min([a:state.rows - 1, max([0, s:param(l:params, 0, 1) - 1])])
    let a:state.cursor_col = min([a:state.cols - 1, max([0, s:param(l:params, 1, 1) - 1])])
    call s:ensure_line(a:state, a:state.cursor_row)
    return
  endif
  if l:final ==# 'E'
    let a:state.cursor_row = min([a:state.rows - 1, a:state.cursor_row + s:param(l:params, 0, 1)])
    let a:state.cursor_col = 0
    call s:ensure_line(a:state, a:state.cursor_row)
    return
  endif
  if l:final ==# 'e'
    let a:state.cursor_row = min([a:state.rows - 1, a:state.cursor_row + s:param(l:params, 0, 1)])
    call s:ensure_line(a:state, a:state.cursor_row)
    return
  endif
  if l:final ==# 'F'
    let a:state.cursor_row = max([0, a:state.cursor_row - s:param(l:params, 0, 1)])
    let a:state.cursor_col = 0
    call s:ensure_line(a:state, a:state.cursor_row)
    return
  endif
  if l:final ==# 'a'
    let a:state.cursor_col = min([a:state.cols - 1, a:state.cursor_col + s:param(l:params, 0, 1)])
    return
  endif
  if l:final ==# 'r'
    let l:top = max([1, s:param(l:params, 0, 1)]) - 1
    let l:bottom = max([1, s:param(l:params, 1, a:state.rows)]) - 1
    let a:state.scroll_top = min([a:state.rows - 1, max([0, l:top])])
    let a:state.scroll_bottom = min([a:state.rows - 1, max([a:state.scroll_top, l:bottom])])
    let a:state.cursor_row = a:state.scroll_top
    let a:state.cursor_col = 0
    return
  endif
  if l:final ==# 'J'
    let l:mode = s:param(l:params, 0, 0)
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
        let l:row += 1
      endwhile
      return
    endif
    if l:mode ==# 1
      call s:erase_line_segment(a:state, a:state.cursor_row, 0, a:state.cursor_col)
      let l:row = 0
      while l:row < a:state.cursor_row
        let a:state.lines[l:row] = s:blank_line(a:state.cols)
        let l:row += 1
      endwhile
    endif
    return
  endif
  if l:final ==# 'K'
    let l:mode = s:param(l:params, 0, 0)
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
    call s:insert_blank_chars(a:state, a:state.cursor_row, a:state.cursor_col, s:param(l:params, 0, 1))
    return
  endif
  if l:final ==# 'P'
    call s:delete_chars(a:state, a:state.cursor_row, a:state.cursor_col, s:param(l:params, 0, 1))
    return
  endif
  if l:final ==# 'b'
    let l:count = s:param(l:params, 0, 1)
    let l:i = 0
    while l:i < l:count
      call s:put_char(a:state, get(a:state, 'last_printable', ' '))
      let l:i += 1
    endwhile
    return
  endif
  if l:final ==# 'I'
    let l:count = s:param(l:params, 0, 1)
    let a:state.cursor_col = min([a:state.cols - 1, ((a:state.cursor_col / 8) + l:count) * 8])
    return
  endif
  if l:final ==# 'Z'
    let l:count = s:param(l:params, 0, 1)
    let a:state.cursor_col = max([0, (((a:state.cursor_col / 8) + 1) - l:count) * 8])
    return
  endif
  if l:final ==# 'X'
    call s:erase_line_segment(a:state, a:state.cursor_row, a:state.cursor_col, a:state.cursor_col + s:param(l:params, 0, 1) - 1)
    return
  endif
  if l:final ==# 'L'
    call s:insert_lines(a:state, a:state.cursor_row, s:param(l:params, 0, 1))
    return
  endif
  if l:final ==# 'M'
    call s:delete_lines(a:state, a:state.cursor_row, s:param(l:params, 0, 1))
    return
  endif
  if l:final ==# 'S'
    call s:delete_lines(a:state, get(a:state, 'scroll_top', 0), s:param(l:params, 0, 1))
    return
  endif
  if l:final ==# 'T'
    call s:insert_lines(a:state, get(a:state, 'scroll_top', 0), s:param(l:params, 0, 1))
    return
  endif
  if l:final ==# 'm'
    return
  endif
  if index(['n', 'q', 'p'], l:final) >= 0
    return
  endif
  if l:final ==# 'h' || l:final ==# 'l'
    if l:private
      let l:enable = l:final ==# 'h'
      for l:param in l:params
        let l:mode = empty(l:param) ? 0 : str2nr(l:param)
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
                  \ 'lines': copy(a:state.lines),
                  \ 'cursor_row': a:state.cursor_row,
                  \ 'cursor_col': a:state.cursor_col,
                  \ 'saved_cursor_row': a:state.saved_cursor_row,
                  \ 'saved_cursor_col': a:state.saved_cursor_col,
                  \ 'scroll_top': a:state.scroll_top,
                  \ 'scroll_bottom': a:state.scroll_bottom,
                  \ }
            let a:state.lines = repeat([s:blank_line(a:state.cols)], a:state.rows)
            let a:state.cursor_row = 0
            let a:state.cursor_col = 0
            let a:state.scroll_top = 0
            let a:state.scroll_bottom = a:state.rows - 1
          elseif !empty(a:state.alt_screen)
            let a:state.lines = copy(get(a:state.alt_screen, 'lines', [s:blank_line(a:state.cols)]))
            let a:state.cursor_row = get(a:state.alt_screen, 'cursor_row', 0)
            let a:state.cursor_col = get(a:state.alt_screen, 'cursor_col', 0)
            let a:state.saved_cursor_row = get(a:state.alt_screen, 'saved_cursor_row', 0)
            let a:state.saved_cursor_col = get(a:state.alt_screen, 'saved_cursor_col', 0)
            let a:state.scroll_top = get(a:state.alt_screen, 'scroll_top', 0)
            let a:state.scroll_bottom = get(a:state.alt_screen, 'scroll_bottom', a:state.rows - 1)
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
  let l:i = 0
  while l:i < len(l:state.lines)
    let l:chars = s:line_chars(l:state.lines[l:i], l:cols)
    let l:state.lines[l:i] = join(l:chars, '')
    let l:i += 1
  endwhile
  let l:state.cursor_row = min([l:state.cursor_row, l:rows - 1])
  let l:state.cursor_col = min([l:state.cursor_col, l:cols - 1])
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
    if l:state.esc_state ==# 'esc'
      if l:byte ==# 0x5b
        let l:state.esc_state = 'csi'
        let l:state.csi = ''
      elseif l:byte ==# 0x5d
        let l:state.esc_state = 'osc'
        let l:state.osc = ''
      elseif l:byte ==# 0x28 || l:byte ==# 0x29 || l:byte ==# 0x2a || l:byte ==# 0x2b
        let l:state.esc_state = 'charset'
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
      call s:newline(l:state)
      continue
    endif
    if l:byte ==# 0x08
      let l:state.cursor_col = max([0, l:state.cursor_col - 1])
      continue
    endif
    if l:byte ==# 0x09
      let l:state.cursor_col = min([l:state.cols - 1, ((l:state.cursor_col / 8) + 1) * 8])
      continue
    endif
    if l:byte < 0x20 || l:byte ==# 0x7f
      continue
    endif
    if l:byte > 0x7e
      call s:put_char(l:state, '?')
      continue
    endif
    call s:put_char(l:state, nr2char(l:byte))
  endfor
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
        \ 'cursor_row': get(l:state, 'cursor_row', 0),
        \ 'cursor_col': get(l:state, 'cursor_col', 0),
        \ 'scroll_top': get(l:state, 'scroll_top', 0),
        \ 'scroll_bottom': get(l:state, 'scroll_bottom', 0),
        \ 'esc_state': get(l:state, 'esc_state', ''),
        \ 'csi': get(l:state, 'csi', ''),
        \ 'lines': l:lines,
        \ }
endfunction
