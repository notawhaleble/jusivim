function! Test_open_scratch(lines) abort
  for l:info in getbufinfo()
    if getbufvar(l:info.bufnr, '&filetype') ==# 'jusinb'
          \ || getbufvar(l:info.bufnr, 'jusi_client_managed', 0)
          \ || getbufvar(l:info.bufnr, 'jusi_client_notebook_bufnr', 0) > 0
      call setbufvar(l:info.bufnr, 'jusi_skip_cleanup_once', 1)
    endif
  endfor
  silent! noautocmd tabonly!
  silent! noautocmd only!
  for l:info in getbufinfo()
    if getbufvar(l:info.bufnr, '&filetype') ==# 'jusinb'
          \ || getbufvar(l:info.bufnr, 'jusi_client_managed', 0)
          \ || getbufvar(l:info.bufnr, 'jusi_client_notebook_bufnr', 0) > 0
      call jusi#transport#stop(l:info.bufnr)
      call setbufvar(l:info.bufnr, 'jusi_skip_cleanup_once', 1)
      execute 'silent! noautocmd bwipeout! ' . l:info.bufnr
    endif
  endfor
  enew!
  setlocal buftype=
  setlocal bufhidden=wipe
  setlocal swapfile&
  file test.vipynb
  setlocal filetype=jusinb
  setlocal syntax=jusinb
  runtime! ftplugin/jusinb.vim
  runtime! syntax/jusinb.vim
  if empty(a:lines)
    call setline(1, [''])
  else
    call setline(1, a:lines)
  endif
  if line('$') > len(a:lines)
    execute (len(a:lines) + 1) . ',$delete _'
  endif
  call jusi#notebook#rebuild()
endfunction

function! Test_syn_name(lnum, col) abort
  return synIDattr(synID(a:lnum, a:col, 1), 'name')
endfunction

function! Test_sign_lines(bufnr) abort
  let l:result = []
  for l:item in sign_getplaced(a:bufnr, {'group': jusi#render#sign_group()})[0].signs
    call add(l:result, [l:item.id, l:item.lnum, l:item.name])
  endfor
  return l:result
endfunction

function! Test_wait_until(Fn, timeout_ms) abort
  if exists('*wait')
    return wait(a:timeout_ms, a:Fn)
  endif
  let l:start = reltime()
  while reltimefloat(reltime(l:start)) * 1000.0 < a:timeout_ms
    if call(a:Fn, [])
      return 0
    endif
    sleep 10m
  endwhile
  return -1
endfunction
