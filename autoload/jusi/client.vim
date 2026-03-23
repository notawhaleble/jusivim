function! jusi#client#prepared_name(notebook_bufnr, client_id) abort
  return '!jusi-prepared-client:' . a:notebook_bufnr . ':' . a:client_id
endfunction

function! jusi#client#create_prepared_buffer(notebook_bufnr, client_id) abort
  let l:name = jusi#client#prepared_name(a:notebook_bufnr, a:client_id)
  let l:bufnr = bufadd(l:name)
  call bufload(l:bufnr)
  call setbufvar(l:bufnr, '&buftype', 'nofile')
  call setbufvar(l:bufnr, '&bufhidden', 'hide')
  call setbufvar(l:bufnr, '&swapfile', 0)
  call setbufvar(l:bufnr, '&modifiable', 1)
  call setbufline(l:bufnr, 1, [''])
  call setbufvar(l:bufnr, '&modified', 0)
  return l:bufnr
endfunction
