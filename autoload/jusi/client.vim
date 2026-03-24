function! jusi#client#prepared_name(notebook_bufnr, client_id) abort
  return '!jusi-prepared-client:' . a:notebook_bufnr . ':' . a:client_id
endfunction

function! s:is_valid_bufnr(bufnr) abort
  return type(a:bufnr) == type(0) && a:bufnr > 0 && bufexists(a:bufnr)
endfunction

function! s:set_managed_vars(bufnr, notebook_bufnr, client_id, role, ...) abort
  if !s:is_valid_bufnr(a:bufnr)
    return
  endif
  call setbufvar(a:bufnr, 'jusi_client_managed', 1)
  call setbufvar(a:bufnr, 'jusi_client_notebook_bufnr', a:notebook_bufnr)
  call setbufvar(a:bufnr, 'jusi_client_id', a:client_id)
  call setbufvar(a:bufnr, 'jusi_client_role', a:role)
  if a:0 >= 1
    call setbufvar(a:bufnr, 'jusi_client_cell_id', a:1)
  elseif getbufvar(a:bufnr, 'jusi_client_cell_id', 0) != 0
    call setbufvar(a:bufnr, 'jusi_client_cell_id', 0)
  endif
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
  call s:set_managed_vars(l:bufnr, a:notebook_bufnr, a:client_id, 'prepared')
  return l:bufnr
endfunction

function! jusi#client#mark_prepared_buffer(notebook_bufnr, client_id, bufnr) abort
  call s:set_managed_vars(a:bufnr, a:notebook_bufnr, a:client_id, 'prepared')
  return a:bufnr
endfunction

function! jusi#client#mark_attached_buffer(notebook_bufnr, cell_id, client_id, bufnr) abort
  call s:set_managed_vars(a:bufnr, a:notebook_bufnr, a:client_id, 'cell', a:cell_id)
  return a:bufnr
endfunction

function! jusi#client#destroy_buffer(bufnr) abort
  if !s:is_valid_bufnr(a:bufnr)
    return 0
  endif
  if !getbufvar(a:bufnr, 'jusi_client_managed', 0)
    return 0
  endif
  execute 'silent! bwipeout! ' . a:bufnr
  return bufexists(a:bufnr) ? 0 : 1
endfunction

function! jusi#client#is_managed_buffer(bufnr) abort
  return s:is_valid_bufnr(a:bufnr) && getbufvar(a:bufnr, 'jusi_client_managed', 0)
endfunction

function! s:binding_mismatch(message) abort
  return {'ok': 0, 'message': a:message}
endfunction

function! jusi#client#validate_prepared_binding(notebook_bufnr, client_id, bufnr) abort
  if !s:is_valid_bufnr(a:bufnr)
    return s:binding_mismatch('Prepared client buffer is missing locally')
  endif
  if getbufvar(a:bufnr, 'jusi_client_notebook_bufnr', -1) != a:notebook_bufnr
    return s:binding_mismatch('Prepared client buffer belongs to another notebook')
  endif
  if getbufvar(a:bufnr, 'jusi_client_role', '') !=# 'prepared'
    return s:binding_mismatch('Prepared client buffer has inconsistent role metadata')
  endif
  if !empty(a:client_id) && getbufvar(a:bufnr, 'jusi_client_id', '') !=# a:client_id
    return s:binding_mismatch('Prepared client buffer has inconsistent client metadata')
  endif
  return {'ok': 1}
endfunction

function! jusi#client#validate_attached_binding(notebook_bufnr, cell_id, client_id, bufnr) abort
  if !s:is_valid_bufnr(a:bufnr)
    return s:binding_mismatch('Client buffer is missing locally')
  endif
  if getbufvar(a:bufnr, 'jusi_client_notebook_bufnr', -1) != a:notebook_bufnr
    return s:binding_mismatch('Client buffer belongs to another notebook')
  endif
  if getbufvar(a:bufnr, 'jusi_client_role', '') !=# 'cell'
    return s:binding_mismatch('Client buffer has inconsistent role metadata')
  endif
  if !empty(a:client_id) && getbufvar(a:bufnr, 'jusi_client_id', '') !=# a:client_id
    return s:binding_mismatch('Client buffer has inconsistent client metadata')
  endif
  if getbufvar(a:bufnr, 'jusi_client_cell_id', 0) != a:cell_id
    return s:binding_mismatch('Client buffer belongs to another cell')
  endif
  return {'ok': 1}
endfunction
