function! s:escape(text) abort
  let l:text = type(a:text) == type('') ? a:text : string(a:text)
  return substitute(l:text, '%', '%%', 'g')
endfunction

function! s:notebook_name(bufnr) abort
  let l:name = bufname(a:bufnr)
  if empty(l:name)
    return '[No Name]'
  endif
  return fnamemodify(l:name, ':t')
endfunction

function! s:statusline_context() abort
  let l:winid = get(g:, 'statusline_winid', 0)
  if type(l:winid) != type(0) || l:winid <= 0
    let l:winid = exists('*win_getid') ? win_getid() : 0
  endif
  let l:bufnr = l:winid > 0 ? winbufnr(l:winid) : bufnr('%')
  return {'winid': l:winid, 'bufnr': l:bufnr}
endfunction

function! s:notebook_label(bufnr) abort
  let l:name = bufname(a:bufnr)
  if empty(l:name)
    return 'notebook'
  endif
  return fnamemodify(l:name, ':t:r')
endfunction

function! s:session_target_label(session) abort
  let l:attach_name = get(a:session, 'attach_name', '')
  if !empty(l:attach_name)
    return l:attach_name
  endif
  let l:target = get(a:session, 'target', {})
  let l:alias = get(l:target, 'alias', '')
  if !empty(l:alias)
    return l:alias
  endif
  let l:kind = get(l:target, 'kind', '')
  let l:value = get(l:target, 'value', '')
  if !empty(l:kind) && !empty(l:value)
    return l:kind . ':' . fnamemodify(l:value, ':t')
  endif
  if !empty(l:kind)
    return l:kind
  endif
  let l:kernel = get(a:session, 'kernel_name', '')
  if !empty(l:kernel)
    return l:kernel
  endif
  return ''
endfunction

function! s:notebook_state(bufnr) abort
  let l:state = getbufvar(a:bufnr, 'jusi_nb', {})
  return type(l:state) == type({}) ? l:state : {}
endfunction

function! s:cell_at_line_from_state(state, lnum) abort
  for l:cell in get(a:state, 'cells', [])
    if get(l:cell, 'start', 0) <= a:lnum && get(l:cell, 'end', 0) >= a:lnum
      return l:cell
    endif
  endfor
  return {}
endfunction

function! s:cell_by_id_from_state(state, cell_id) abort
  for l:cell in get(a:state, 'cells', [])
    if get(l:cell, 'id', 0) == a:cell_id
      return l:cell
    endif
  endfor
  return {}
endfunction

function! s:session_state_group(state) abort
  if a:state ==# 'connected'
    return 'JusiStatusSessionConnected'
  endif
  if a:state ==# 'disconnected'
    return 'JusiStatusSessionDisconnected'
  endif
  if a:state ==# 'failed'
    return 'JusiStatusSessionFailed'
  endif
  if index(['starting', 'stopping'], a:state) >= 0
    return 'JusiStatusSessionTransition'
  endif
  return 'JusiStatusSessionIdle'
endfunction

function! s:client_count_label(client_id) abort
  let l:match = matchlist(a:client_id, '\v(\d+)$')
  return len(l:match) > 1 ? l:match[1] : ''
endfunction

function! s:client_terminal_mode(bufnr) abort
  let l:ctx = s:statusline_context()
  if !getbufvar(a:bufnr, 'jusi_client_managed', 0)
        \ && getbufvar(a:bufnr, 'jusi_client_notebook_bufnr', 0) <= 0
    return ''
  endif
  if has('nvim')
    return l:ctx.bufnr == a:bufnr && mode() =~# '^t' ? 'job' : 'normal'
  endif
  if getbufvar(a:bufnr, '&buftype') ==# 'terminal'
    return l:ctx.bufnr == a:bufnr && mode() =~# '^[ti]' ? 'job' : 'normal'
  endif
  return ''
endfunction

function! s:notebook_mode_label(bufnr) abort
  if exists('*jusi#cellmode#mode') && jusi#cellmode#mode(a:bufnr) ==# 'cell'
    return 'cell'
  endif
  return ''
endfunction

function! s:statusline_prefix(group) abort
  return '%#' . a:group . '#'
endfunction

function! jusi#statusline#setup_notebook(...) abort
  let l:expr = '%!jusi#statusline#render_notebook()'
  if a:0 >= 1 && a:1 > 0
    if exists('*win_execute')
      call win_execute(a:1, 'setlocal statusline=' . l:expr, 'silent!')
      return
    endif
    if exists('*setwinvar')
      call setwinvar(a:1, '&statusline', l:expr)
      return
    endif
    return
  endif
  let &l:statusline = l:expr
endfunction

function! jusi#statusline#setup_client(...) abort
  let l:expr = '%!jusi#statusline#render_client()'
  if a:0 >= 1 && a:1 > 0
    if exists('*win_execute')
      call win_execute(a:1, 'setlocal statusline=' . l:expr, 'silent!')
      return
    endif
    if exists('*setwinvar')
      call setwinvar(a:1, '&statusline', l:expr)
      return
    endif
    return
  endif
  let &l:statusline = l:expr
endfunction

function! jusi#statusline#render_notebook() abort
  let l:ctx = s:statusline_context()
  let l:bufnr = l:ctx.bufnr
  let l:session = jusi#session#state(l:bufnr)
  let l:state = get(l:session, 'state', 'idle')
  let l:target = s:session_target_label(l:session)
  let l:notebook_mode = s:notebook_mode_label(l:bufnr)
  let l:parts = []

  call add(l:parts, s:statusline_prefix('StatusLine'))
  call add(l:parts, ' Jusi ')
  call add(l:parts, s:escape(s:notebook_name(l:bufnr)))
  if getbufvar(l:bufnr, '&modified')
    call add(l:parts, ' [+]')
  endif

  call add(l:parts, s:statusline_prefix(s:session_state_group(l:state)))
  call add(l:parts, ' ' . s:escape(l:state) . ' ')
  call add(l:parts, s:statusline_prefix('StatusLine'))

  if !empty(l:target)
    call add(l:parts, ' target:' . s:escape(l:target))
  endif
  if !empty(l:notebook_mode)
    call add(l:parts, s:statusline_prefix('JusiStatusNotebookMode'))
    call add(l:parts, ' mode:' . s:escape(l:notebook_mode))
    call add(l:parts, s:statusline_prefix('StatusLine'))
  endif

  return join(l:parts, '')
endfunction

function! jusi#statusline#render_client() abort
  let l:ctx = s:statusline_context()
  let l:bufnr = l:ctx.bufnr
  let l:notebook_bufnr = getbufvar(l:bufnr, 'jusi_client_notebook_bufnr', 0)
  let l:client_id = getbufvar(l:bufnr, 'jusi_client_id', '')
  let l:role = getbufvar(l:bufnr, 'jusi_client_role', 'cell')
  let l:mode = s:client_terminal_mode(l:bufnr)
  let l:group = l:mode ==# 'job'
        \ ? 'JusiStatusClientInteractive'
        \ : 'StatusLine'
  let l:parts = [s:statusline_prefix(l:group), ' Jusi ']

  call add(l:parts, !empty(l:client_id) ? s:escape(l:client_id) : 'client')
  if l:notebook_bufnr > 0
    call add(l:parts, ' nb:' . s:escape(s:notebook_label(l:notebook_bufnr)))
  endif
  if !empty(l:role) && l:role !=# 'cell'
    call add(l:parts, ' role:' . s:escape(l:role))
  endif
  return join(l:parts, '')
endfunction
