scriptencoding utf-8

let s:sign_group = 'jusi_cells'
let s:sign_specs = {
      \ 'initial': {'text': 'JusiSignInitial', 'line': 'JusiSignLineInitial', 'fg': 'Yellow', 'guifg': '#d7af00', 'bg': '#d7af00', 'ctermfg_active': 'Black', 'guifg_active': '#000000'},
      \ 'follow-up': {'text': 'JusiSignFollowup', 'line': 'JusiSignLineFollowup', 'fg': 'LightMagenta', 'guifg': '#ff66cc', 'bg': '#ff66cc', 'ctermfg_active': 'White', 'guifg_active': '#ffffff'},
      \ 'busy': {'text': 'JusiSignBusy', 'line': 'JusiSignLineBusy', 'fg': 'Magenta', 'guifg': '#ff00ff', 'bg': '#ff00ff', 'ctermfg_active': 'White', 'guifg_active': '#ffffff'},
      \ 'done': {'text': 'JusiSignDone', 'line': 'JusiSignLineDone', 'fg': 'Green', 'guifg': '#00af00', 'bg': '#00ff00', 'ctermfg_active': 'Black', 'guifg_active': '#000000'},
      \ 'error': {'text': 'JusiSignError', 'line': 'JusiSignLineError', 'fg': 'Red', 'guifg': '#ff0000', 'bg': '#ff0000', 'ctermfg_active': 'White', 'guifg_active': '#ffffff'},
      \ 'interrupted': {'text': 'JusiSignInterrupted', 'line': 'JusiSignLineInterrupted', 'fg': 'DarkYellow', 'guifg': '#d78700', 'bg': '#d78700', 'ctermfg_active': 'Black', 'guifg_active': '#000000'},
      \ 'parked': {'text': 'JusiSignParked', 'line': 'JusiSignLineParked', 'fg': 'Blue', 'guifg': '#3b7cff', 'bg': '#3b7cff', 'ctermfg_active': 'Black', 'guifg_active': '#000000'},
      \ }

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

function! jusi#render#sign_group() abort
  return s:sign_group
endfunction

function! jusi#render#sign_name(status) abort
  return 'jusi_' . substitute(a:status, '-', '_', 'g')
endfunction

function! jusi#render#sign_lnum(cell) abort
  if a:cell.start < a:cell.end
    return a:cell.start + 1
  endif
  return a:cell.start
endfunction

function! jusi#render#set_sign_highlights(cell_mode) abort
  for [l:status, l:spec] in items(s:sign_specs)
    if a:cell_mode
      execute 'highlight ' . l:spec.text
            \ . ' ctermfg=' . l:spec.ctermfg_active
            \ . ' ctermbg=' . l:spec.fg
            \ . ' guifg=' . l:spec.guifg_active
            \ . ' guibg=' . l:spec.bg
    else
      execute 'highlight ' . l:spec.text
            \ . ' ctermfg=' . l:spec.fg
            \ . ' ctermbg=NONE'
            \ . ' guifg=' . l:spec.guifg
            \ . ' guibg=NONE'
    endif
  endfor
endfunction

function! jusi#render#define_signs() abort
  call jusi#render#set_sign_highlights(get(g:, 'jusi_cell_mode', 0))
  for [l:status, l:text] in items(g:jusi_sign_texts)
    let l:spec = s:sign_specs[l:status]
    execute 'sign define ' . jusi#render#sign_name(l:status)
          \ . ' text=' . l:text
          \ . ' texthl=' . l:spec.text
  endfor
endfunction

function! jusi#render#sync_signs(bufnr, cells) abort
  let l:perf_start = reltime()
  execute 'sign unplace * group=' . s:sign_group . ' buffer=' . a:bufnr
  for l:cell in a:cells
    execute 'sign place ' . l:cell.sign_id
          \ . ' line=' . jusi#render#sign_lnum(l:cell)
          \ . ' name=' . jusi#render#sign_name(l:cell.status)
          \ . ' group=' . s:sign_group
          \ . ' buffer=' . a:bufnr
  endfor
  call s:perf_log('sync_signs', l:perf_start, 'buf=' . a:bufnr . ' cells=' . len(a:cells))
endfunction
