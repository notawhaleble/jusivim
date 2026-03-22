function! s:normalize_bufnr(bufnr) abort
  if a:bufnr is# 0 || a:bufnr is# ''
    return bufnr('%')
  endif
  return str2nr(a:bufnr)
endfunction

function! s:is_notebook_buffer(bufnr) abort
  return bufexists(a:bufnr) && getbufvar(a:bufnr, '&filetype') ==# 'jusinb'
endfunction

function! s:clear_dynamic() abort
  let l:groups = get(b:, 'jusi_dynamic_syntax_groups', [])
  for l:group in l:groups
    silent! execute 'syntax clear ' . l:group
  endfor
  let b:jusi_dynamic_syntax_groups = []
  syntax sync clear
  syntax sync minlines=1
endfunction

function! s:syntax_cluster_name(name) abort
  return 'jusiBody_' . substitute(a:name, '\W', '_', 'g')
endfunction

function! s:syntax_file_exists(name) abort
  return !empty(globpath(&runtimepath, 'syntax/' . a:name . '.vim'))
endfunction

function! s:ensure_cluster(name) abort
  if empty(a:name) || !s:syntax_file_exists(a:name)
    return ''
  endif

  let b:jusi_included_clusters = get(b:, 'jusi_included_clusters', {})
  let l:cluster = s:syntax_cluster_name(a:name)
  if !has_key(b:jusi_included_clusters, l:cluster)
    unlet! b:current_syntax
    execute 'syntax include @' . l:cluster . ' syntax/' . a:name . '.vim'
    let b:current_syntax = 'jusinb'
    let b:jusi_included_clusters[l:cluster] = 1
  endif
  return '@' . l:cluster
endfunction

function! s:cell_key(cell) abort
  if empty(a:cell)
    return ''
  endif
  return printf('%d:%d:%d:%s', get(a:cell, 'id', 0), get(a:cell, 'start', 0), get(a:cell, 'end', 0), get(a:cell, 'syntax', ''))
endfunction

function! s:visible_cells(bufnr, topline, botline) abort
  let l:state = jusi#notebook#rebuild(a:bufnr)
  let l:cells = []
  for l:cell in get(l:state, 'cells', [])
    if l:cell.end < a:topline
      continue
    endif
    if l:cell.start > a:botline
      break
    endif
    call add(l:cells, l:cell)
  endfor
  return l:cells
endfunction

function! s:visible_cells_key(cells) abort
  if empty(a:cells)
    return ''
  endif
  return join(map(copy(a:cells), 's:cell_key(v:val)'), '|')
endfunction

function! s:cell_body_start(cell) abort
  if a:cell.start < a:cell.end
    return a:cell.start + 1
  endif
  return a:cell.start
endfunction

function! s:visible_sync_start(cells) abort
  if empty(a:cells)
    return line('.')
  endif
  return s:cell_body_start(a:cells[0])
endfunction

function! s:sync_margin() abort
  return max([winheight(0), 50])
endfunction

function! jusi#syntax#define_base() abort
  syntax match jusiDelimiter '^##\s*$'
  syntax match jusiMagicHeader '^%%\k\+.*$'
  highlight default link jusiDelimiter Comment
  highlight default link jusiMagicHeader PreProc
endfunction

function! jusi#syntax#sync(bufnr, cells) abort
  let l:bufnr = s:normalize_bufnr(a:bufnr)
  if l:bufnr != bufnr('%')
    return
  endif
  call jusi#syntax#define_base()
  call s:clear_dynamic()

  let l:topline = line('w0')
  let l:botline = line('w$')
  let l:cells = a:cells
  if empty(l:cells)
    let l:cells = s:visible_cells(l:bufnr, l:topline, l:botline)
  endif
  let b:jusi_syntax_visible_key = s:visible_cells_key(l:cells)
  let b:jusi_syntax_window_top = l:topline
  let b:jusi_syntax_window_bot = l:botline
  if empty(l:cells)
    return
  endif

  let l:sync_start = s:visible_sync_start(l:cells)
  let l:sync_until = min([line('$'), l:botline + s:sync_margin()])
  let l:sync_depth = max([1, l:sync_until - l:sync_start + 1])
  let l:groups = []

  for l:cell in l:cells
    let l:body_start = s:cell_body_start(l:cell)
    let l:body_end = l:cell.end
    if l:body_start > l:body_end
      continue
    endif

    let l:contains = ['jusiMagicHeader']
    let l:cluster = s:ensure_cluster(get(l:cell, 'syntax', ''))
    if !empty(l:cluster)
      call add(l:contains, l:cluster)
    endif

    let l:group = 'jusiVisibleCellBody_' . l:cell.id
    execute 'syntax region ' . l:group
          \ . ' start=/\%' . l:body_start . 'l^/'
          \ . ' end=/\%' . l:body_end . 'l$/'
          \ . ' keepend transparent contains=' . join(l:contains, ',')
    call add(l:groups, l:group)
  endfor

  execute 'syntax sync minlines=' . l:sync_depth
  execute 'syntax sync maxlines=' . l:sync_depth
  let b:jusi_syntax_sync_start = l:sync_start
  let b:jusi_syntax_sync_until = l:sync_until
  let b:jusi_dynamic_syntax_groups = l:groups
endfunction

function! jusi#syntax#sync_from(bufnr, cells, start_idx) abort
  call jusi#syntax#sync(a:bufnr, a:cells)
endfunction

function! jusi#syntax#suspend(bufnr) abort
  call jusi#syntax#sync(a:bufnr, [])
endfunction

function! jusi#syntax#schedule(bufnr, ...) abort
  let l:bufnr = s:normalize_bufnr(a:bufnr)
  if l:bufnr != bufnr('%')
    return
  endif
  let l:topline = line('w0')
  let l:botline = line('w$')
  let l:cells = s:visible_cells(l:bufnr, l:topline, l:botline)
  let l:key = s:visible_cells_key(l:cells)
  let l:sync_start = s:visible_sync_start(l:cells)
  let l:sync_until = get(b:, 'jusi_syntax_sync_until', 0)
  let l:cached_sync_start = get(b:, 'jusi_syntax_sync_start', -1)
  if l:key ==# get(b:, 'jusi_syntax_visible_key', '')
        \ && l:topline ==# get(b:, 'jusi_syntax_window_top', -1)
        \ && l:botline ==# get(b:, 'jusi_syntax_window_bot', -1)
        \ && l:sync_start ==# l:cached_sync_start
        \ && l:botline <= l:sync_until
    return
  endif
  call jusi#syntax#sync(l:bufnr, l:cells)
  redraw
endfunction

function! s:refresh_timer(timer) abort
  let l:bufnr = getbufvar(bufnr('%'), 'jusi_syntax_refresh_bufnr', bufnr('%'))
  unlet! b:jusi_syntax_refresh_timer
  unlet! b:jusi_syntax_refresh_bufnr
  if !s:is_notebook_buffer(l:bufnr) || l:bufnr != bufnr('%')
    return
  endif
  call jusi#syntax#schedule(l:bufnr)
endfunction

function! jusi#syntax#request_refresh(bufnr) abort
  let l:bufnr = s:normalize_bufnr(a:bufnr)
  if l:bufnr != bufnr('%')
    return
  endif
  if !exists('*timer_start')
    call jusi#syntax#schedule(l:bufnr)
    return
  endif

  if exists('b:jusi_syntax_refresh_timer') && b:jusi_syntax_refresh_timer > 0
    call timer_stop(b:jusi_syntax_refresh_timer)
  endif
  let b:jusi_syntax_refresh_bufnr = l:bufnr
  let b:jusi_syntax_refresh_timer = timer_start(0, function('s:refresh_timer'))
endfunction

function! jusi#syntax#cleanup(bufnr) abort
  if a:bufnr == bufnr('%') && exists('b:jusi_syntax_refresh_timer') && b:jusi_syntax_refresh_timer > 0
    call timer_stop(b:jusi_syntax_refresh_timer)
    unlet! b:jusi_syntax_refresh_timer
    unlet! b:jusi_syntax_refresh_bufnr
  endif
  if a:bufnr == bufnr('%')
    call s:clear_dynamic()
  endif
endfunction
