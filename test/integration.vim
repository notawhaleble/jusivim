let s:integration_last_request_envelope = {}
let s:integration_shutdown_requests = []

function! s:integration_session_adapter_start(bufnr, payload) abort
  return {
        \ 'ok': 1,
        \ 'session': {
        \   'id': 'sess-int-1',
        \   'kernel_id': 'kernel-int-1',
        \   'state': 'connected',
        \   'backend': 'mock',
        \   'kernel_name': get(a:payload, 'kernel_name', ''),
        \   'connection': 'mock://kernel/' . get(a:payload, 'kernel_name', ''),
        \   },
        \ 'prepared': {
        \   'id': 'client-int-1',
        \   'state': 'binding',
        \   'bufnr': -1,
        \   },
        \ }
endfunction

function! s:integration_session_adapter_disconnect(bufnr, payload) abort
  return {
        \ 'ok': 1,
        \ 'session': {
        \   'state': 'disconnected',
        \   'expires_at': '2030-01-01T00:00:00Z',
        \   'last_action': 'disconnect',
        \   },
        \ 'prepared': {
        \   'state': 'missing',
        \   'bufnr': -1,
        \   },
        \ }
endfunction

function! s:integration_session_adapter_reconnect(bufnr, payload) abort
  return {
        \ 'ok': 1,
        \ 'session': {
        \   'id': 'sess-int-1',
        \   'state': 'connected',
        \   'expires_at': '',
        \   'last_action': 'reconnect',
        \   },
        \ 'prepared': {
        \   'id': 'client-int-2',
        \   'state': 'binding',
        \   'bufnr': -1,
        \   },
        \ }
endfunction

function! s:integration_session_adapter_stop(bufnr, payload) abort
  return {
        \ 'ok': 1,
        \ 'session': {
        \   'request': {},
        \   },
        \ 'prepared': {
        \   'state': 'missing',
        \   'bufnr': -1,
        \   },
        \ }
endfunction

function! s:integration_session_adapter_bind_prepared(bufnr, payload) abort
  return {'ok': 1}
endfunction

function! s:integration_session_adapter_shutdown_client_record(bufnr, payload) abort
  call add(s:integration_shutdown_requests, copy(a:payload))
  return {'ok': 1}
endfunction

function! s:integration_reset_undo_history() abort
  let l:save = &l:undolevels
  setlocal undolevels=-1
  let &l:undolevels = l:save
endfunction

function! s:integration_open_additional_notebook(lines, name) abort
  tabnew
  setlocal buftype=
  setlocal bufhidden=wipe
  setlocal swapfile&
  execute 'file ' . a:name
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
  return bufnr('%')
endfunction

function! s:integration_transport_request_adapter(bufnr, envelope) abort
  let s:integration_last_request_envelope = copy(a:envelope)
  if get(a:envelope, 'type', '') ==# 'shutdown_client'
    return {'ok': 1, '_transport': 1, 'payload': {}}
  endif
  if get(a:envelope, 'type', '') ==# 'execute_cell'
    return {'ok': 1, '_transport': 1, 'payload': {}}
  endif
  return {'ok': 1}
endfunction

function! Test_integration_close_missing_client_keeps_connected_session() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call jusi#session#set_connected(0, {
        \ 'id': 'sess-1',
        \ 'kernel_name': 'python3',
        \ 'prepared': {'id': 'client-prepared', 'state': 'ready', 'client_state': 'active', 'bufnr': -1},
        \ })

  call jusi#session#close_current_client()

  call assert_equal('connected', b:jusi_nb.session.state)
  call assert_equal('close_client', b:jusi_nb.session.last_action)
  call assert_match('Cannot close client without an attached client buffer', b:jusi_nb.session.last_error)
  call assert_equal('initial', b:jusi_nb.cells[0].status)
endfunction

function! Test_integration_toggle_park_rejection_keeps_connected_session() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ ])
  let l:client = jusi#client#create_prepared_buffer(bufnr('%'), 'client-1')
  call jusi#session#set_connected(0, {
        \ 'id': 'sess-1',
        \ 'kernel_name': 'python3',
        \ 'prepared': {'id': 'client-prepared', 'state': 'ready', 'client_state': 'active', 'bufnr': -1},
        \ })
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client

  call jusi#session#toggle_park_current_client()

  call assert_equal('connected', b:jusi_nb.session.state)
  call assert_equal('toggle_park', b:jusi_nb.session.last_action)
  call assert_match('Cannot park a busy or follow-up client', b:jusi_nb.session.last_error)
  call assert_equal('follow-up', b:jusi_nb.cells[0].status)
  call assert_equal(l:client, b:jusi_nb.cells[0].client_bufnr)
endfunction

function! Test_integration_session_roundtrip_start_disconnect_reconnect_stop() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:integration_session_adapter_start'),
          \ 'disconnect': function('s:integration_session_adapter_disconnect'),
          \ 'reconnect': function('s:integration_session_adapter_reconnect'),
          \ 'stop': function('s:integration_session_adapter_stop'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])

    call jusi#session#start('python3')
    call assert_equal('connected', b:jusi_nb.session.state)
    call assert_equal('sess-int-1', b:jusi_nb.session.id)
    call assert_equal('client-int-1', b:jusi_nb.session.prepared.id)
    call assert_equal('binding', b:jusi_nb.session.prepared.state)

    call jusi#session#disconnect()
    call assert_equal('disconnected', b:jusi_nb.session.state)
    call assert_equal('2030-01-01T00:00:00Z', b:jusi_nb.session.expires_at)
    call assert_equal('missing', b:jusi_nb.session.prepared.state)

    call jusi#session#reconnect()
    call assert_equal('connected', b:jusi_nb.session.state)
    call assert_equal('reconnect', b:jusi_nb.session.last_action)
    call assert_equal('client-int-2', b:jusi_nb.session.prepared.id)
    call assert_equal('binding', b:jusi_nb.session.prepared.state)

    call jusi#session#stop()
    call assert_equal('stopped', b:jusi_nb.session.state)
    call assert_equal('missing', b:jusi_nb.session.prepared.state)
    call assert_equal(-1, b:jusi_nb.session.prepared.bufnr)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_integration_recoverable_rejections_do_not_block_disconnect() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'disconnect': function('s:integration_session_adapter_disconnect'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#set_connected(0, {
          \ 'id': 'sess-1',
          \ 'kernel_name': 'python3',
          \ 'prepared': {'id': 'client-prepared', 'state': 'ready', 'client_state': 'active', 'bufnr': -1},
          \ })

    call jusi#session#close_current_client()
    call assert_equal('connected', b:jusi_nb.session.state)
    call assert_equal('close_client', b:jusi_nb.session.last_action)

    call jusi#session#toggle_park_current_client()
    call assert_equal('connected', b:jusi_nb.session.state)
    call assert_equal('toggle_park', b:jusi_nb.session.last_action)

    call jusi#session#disconnect()
    call assert_equal('disconnected', b:jusi_nb.session.state)
    call assert_equal('disconnect', b:jusi_nb.session.last_action)
    call assert_equal('2030-01-01T00:00:00Z', b:jusi_nb.session.expires_at)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_integration_stop_cleans_hidden_detached_client_after_transport_close() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    call Test_open_scratch([
          \ '##',
          \ '%%vd pods',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
    call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)
    call setbufvar(l:client, 'jusi_client_transport_kind', 'native_terminal')
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    call jusi#focus#place_client_buffer(l:client, 'bsplit', 1)

    let g:jusi_session_adapter = {'request': function('s:integration_transport_request_adapter')}
    let s:integration_last_request_envelope = {}
    call jusi#session#close_current_client()

    call assert_true(bufexists(l:client))
    call assert_equal('detached', getbufvar(l:client, 'jusi_client_role', ''))
    call assert_equal(0, getbufvar(l:client, 'jusi_client_cell_id', -1))
    call assert_equal(-1, bufwinid(l:client))
    call assert_equal('shutdown_client', get(s:integration_last_request_envelope, 'type', ''))
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
    call assert_equal('shutdown', b:jusi_nb.cells[0].client_state)

    let g:jusi_session_adapter = {'stop': function('s:integration_session_adapter_stop')}
    call jusi#session#stop()

    call assert_equal('stopped', b:jusi_nb.session.state)
    call assert_false(bufexists(l:client))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_integration_recoverable_close_rejection_does_not_block_execute() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'execute': function('s:integration_session_adapter_start'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#set_connected(0, {
          \ 'id': 'sess-1',
          \ 'kernel_name': 'python3',
          \ 'prepared': {'id': 'client-prepared', 'state': 'ready', 'client_state': 'active', 'bufnr': -1},
          \ })
    let l:prepared = jusi#client#create_prepared_buffer(bufnr('%'), 'client-prepared')
    call jusi#session#apply_prepared({
          \ 'id': 'client-prepared',
          \ 'state': 'ready',
          \ 'client_state': 'active',
          \ 'bufnr': l:prepared,
          \ })

    call jusi#session#close_current_client()
    call assert_equal('connected', b:jusi_nb.session.state)
    call assert_equal('close_client', b:jusi_nb.session.last_action)

    let g:jusi_session_adapter.execute = function('s:integration_session_adapter_execute')
    call jusi#session#execute_current()

    call assert_equal('connected', b:jusi_nb.session.state)
    call assert_equal('execute', b:jusi_nb.session.last_action)
    call assert_equal('busy', b:jusi_nb.cells[0].status)
    call assert_equal('client-prepared', b:jusi_nb.cells[0].client_id)
    call assert_equal(l:prepared, b:jusi_nb.cells[0].client_bufnr)
    call assert_equal('client-int-1', b:jusi_nb.session.prepared.id)
    call assert_equal('binding', b:jusi_nb.session.prepared.state)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! s:integration_session_adapter_execute(bufnr, payload) abort
  return {
        \ 'ok': 1,
        \ 'prepared': {
        \   'id': 'client-int-1',
        \   'state': 'binding',
        \   'bufnr': -1,
        \   },
        \ }
endfunction

function! Test_integration_execute_after_transport_close_uses_new_prepared_buffer() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'request': function('s:integration_transport_request_adapter')}
    call Test_open_scratch([
          \ '##',
          \ '%%vd pods',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let l:old_client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
    call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:old_client)
    call setbufvar(l:old_client, 'jusi_client_transport_kind', 'native_terminal')
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:old_client
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    call jusi#focus#place_client_buffer(l:old_client, 'bsplit', 1)

    call jusi#session#close_current_client()
    call assert_true(bufexists(l:old_client))
    call assert_equal('detached', getbufvar(l:old_client, 'jusi_client_role', ''))
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
    call assert_equal('shutdown', b:jusi_nb.cells[0].client_state)

    let l:new_prepared = jusi#client#create_prepared_buffer(l:notebook, 'client-2')
    call jusi#session#apply_prepared({
          \ 'id': 'client-2',
          \ 'state': 'ready',
          \ 'client_state': 'active',
          \ 'bufnr': l:new_prepared,
          \ })
    call jusi#session#execute_current()

    call assert_equal('execute', b:jusi_nb.session.last_action)
    call assert_equal('busy', b:jusi_nb.cells[0].status)
    call assert_equal('client-2', b:jusi_nb.cells[0].client_id)
    call assert_equal(l:new_prepared, b:jusi_nb.cells[0].client_bufnr)
    call assert_true(bufexists(l:old_client))
    call assert_equal('detached', getbufvar(l:old_client, 'jusi_client_role', ''))
    call assert_equal(0, getbufvar(l:old_client, 'jusi_client_cell_id', -1))
    call assert_equal('missing', b:jusi_nb.session.prepared.state)
    call assert_equal(-1, b:jusi_nb.session.prepared.bufnr)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_integration_cleanup_destroys_hidden_detached_client_after_transport_close() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'request': function('s:integration_transport_request_adapter')}
    call Test_open_scratch([
          \ '##',
          \ '%%vd pods',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
    call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)
    call setbufvar(l:client, 'jusi_client_transport_kind', 'native_terminal')
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}

    call jusi#session#close_current_client()
    call assert_true(bufexists(l:client))
    call assert_equal('detached', getbufvar(l:client, 'jusi_client_role', ''))

    call jusi#notebook#cleanup(l:notebook)

    call assert_false(bufexists(l:client))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_integration_execute_close_execute_across_cells_keeps_old_client_detached() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'request': function('s:integration_transport_request_adapter')}
    call Test_open_scratch([
          \ '##',
          \ '%%vd pods',
          \ '##',
          \ 'print("second")',
          \ ])
    let l:notebook = bufnr('%')
    let l:first_id = b:jusi_nb.cells[0].id
    let l:old_client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
    call jusi#client#mark_attached_buffer(l:notebook, l:first_id, 'client-1', l:old_client)
    call setbufvar(l:old_client, 'jusi_client_transport_kind', 'native_terminal')
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:old_client
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}

    call cursor(2, 1)
    call jusi#session#close_current_client()
    call assert_true(bufexists(l:old_client))
    call assert_equal('detached', getbufvar(l:old_client, 'jusi_client_role', ''))

    let l:new_prepared = jusi#client#create_prepared_buffer(l:notebook, 'client-2')
    call jusi#session#apply_prepared({
          \ 'id': 'client-2',
          \ 'state': 'ready',
          \ 'client_state': 'active',
          \ 'bufnr': l:new_prepared,
          \ })
    call cursor(4, 1)
    call jusi#session#execute_current()

    call assert_equal('shutdown', b:jusi_nb.cells[0].client_state)
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
    call assert_equal('busy', b:jusi_nb.cells[1].status)
    call assert_equal('client-2', b:jusi_nb.cells[1].client_id)
    call assert_equal(l:new_prepared, b:jusi_nb.cells[1].client_bufnr)
    call assert_equal('detached', getbufvar(l:old_client, 'jusi_client_role', ''))
    call assert_equal(0, getbufvar(l:old_client, 'jusi_client_cell_id', -1))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_integration_start_after_transport_close_clears_cell_runtime_without_rebinding_detached_buffer() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'request': function('s:integration_transport_request_adapter')}
    call Test_open_scratch([
          \ '##',
          \ '%%vd pods',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let l:old_client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
    call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:old_client)
    call setbufvar(l:old_client, 'jusi_client_transport_kind', 'native_terminal')
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:old_client
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}

    call jusi#session#close_current_client()
    call assert_true(bufexists(l:old_client))
    call assert_equal('detached', getbufvar(l:old_client, 'jusi_client_role', ''))

    call jusi#session#apply({'state': 'stopped', 'id': '', 'prepared': jusi#session#default_prepared_state()})
    let g:jusi_session_adapter = {'start': function('s:integration_session_adapter_start')}
    call jusi#session#start('python3')

    call assert_equal('connected', b:jusi_nb.session.state)
    call assert_equal('start', b:jusi_nb.session.last_action)
    call assert_equal('initial', b:jusi_nb.cells[0].status)
    call assert_equal('', b:jusi_nb.cells[0].client_id)
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
    call assert_equal('client-int-1', b:jusi_nb.session.prepared.id)
    call assert_equal('binding', b:jusi_nb.session.prepared.state)
    call assert_true(bufexists(l:old_client))
    call assert_equal('detached', getbufvar(l:old_client, 'jusi_client_role', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_integration_reconnect_allocates_new_prepared_buffer_when_detached_buffer_exists() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    call Test_open_scratch([
          \ '##',
          \ '%%vd pods',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let l:old_client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
    call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:old_client)
    call setbufvar(l:old_client, 'jusi_client_transport_kind', 'native_terminal')
    let b:jusi_nb.session.id = 'sess-int-1'
    let b:jusi_nb.session.state = 'connected'
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:old_client
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}

    let g:jusi_session_adapter = {'request': function('s:integration_transport_request_adapter')}
    call jusi#session#close_current_client()
    call assert_true(bufexists(l:old_client))
    call assert_equal('detached', getbufvar(l:old_client, 'jusi_client_role', ''))

    let g:jusi_session_adapter = {
          \ 'reconnect': function('s:integration_session_adapter_reconnect'),
          \ 'bind_prepared_client': function('s:integration_session_adapter_bind_prepared'),
          \ }
    call jusi#session#set_disconnected()
    let b:jusi_nb.session.id = 'sess-int-1'
    call jusi#session#reconnect()
    call assert_equal('connected', b:jusi_nb.session.state)
    call assert_equal('client-int-2', b:jusi_nb.session.prepared.id)
    call assert_equal('binding', b:jusi_nb.session.prepared.state)
    call assert_equal(-1, b:jusi_nb.session.prepared.bufnr)

    call jusi#session#callback_prepared({'id': 'client-int-2', 'state': 'binding', 'bufnr': -1})

    call assert_equal('connected', b:jusi_nb.session.state)
    call assert_equal('client-int-2', b:jusi_nb.session.prepared.id)
    call assert_equal('binding', b:jusi_nb.session.prepared.state)
    call assert_true(b:jusi_nb.session.prepared.bufnr > 0)
    call assert_notequal(l:old_client, b:jusi_nb.session.prepared.bufnr)
    call assert_true(bufexists(l:old_client))
    call assert_equal('detached', getbufvar(l:old_client, 'jusi_client_role', ''))
    call assert_equal('prepared', getbufvar(b:jusi_nb.session.prepared.bufnr, 'jusi_client_role', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_integration_late_prepared_callback_after_stop_does_not_rebind_clients() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:integration_session_adapter_start'),
          \ 'stop': function('s:integration_session_adapter_stop'),
          \ 'bind_prepared_client': function('s:integration_session_adapter_bind_prepared'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('python3')
    call jusi#session#stop()

    call assert_equal('stopped', b:jusi_nb.session.state)
    call assert_equal('missing', b:jusi_nb.session.prepared.state)
    call assert_equal(-1, b:jusi_nb.session.prepared.bufnr)

    call jusi#session#callback_prepared({'id': 'late-client', 'state': 'binding', 'bufnr': -1})

    call assert_equal('stopped', b:jusi_nb.session.state)
    call assert_equal('missing', b:jusi_nb.session.prepared.state)
    call assert_equal(-1, b:jusi_nb.session.prepared.bufnr)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_integration_late_cell_callback_after_stop_does_not_restore_runtime() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:integration_session_adapter_start'),
          \ 'stop': function('s:integration_session_adapter_stop'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    let l:cell_id = b:jusi_nb.cells[0].id
    call jusi#session#start('python3')
    call jusi#session#stop()

    call jusi#session#callback_cell(l:cell_id, {
          \ 'status': 'follow-up',
          \ 'client_id': 'late-client',
          \ 'client_state': 'active',
          \ 'client_bufnr': 91,
          \ 'owner': {'kind': 'handler'},
          \ })

    call assert_equal('stopped', b:jusi_nb.session.state)
    call assert_equal('initial', b:jusi_nb.cells[0].status)
    call assert_equal('', b:jusi_nb.cells[0].client_id)
    call assert_equal('shutdown', b:jusi_nb.cells[0].client_state)
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_integration_stop_in_other_notebook_does_not_destroy_detached_buffers() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'request': function('s:integration_transport_request_adapter')}
    call Test_open_scratch([
          \ '##',
          \ '%%vd pods',
          \ ])
    let l:notebook_a = bufnr('%')
    let l:cell_a = b:jusi_nb.cells[0].id
    let l:detached = jusi#client#create_prepared_buffer(l:notebook_a, 'client-a')
    call jusi#client#mark_attached_buffer(l:notebook_a, l:cell_a, 'client-a', l:detached)
    call setbufvar(l:detached, 'jusi_client_transport_kind', 'native_terminal')
    let b:jusi_nb.session.id = 'sess-a'
    let b:jusi_nb.session.state = 'connected'
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].client_id = 'client-a'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:detached
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    call jusi#session#close_current_client()
    call assert_true(bufexists(l:detached))
    call assert_equal('detached', getbufvar(l:detached, 'jusi_client_role', ''))

    let l:notebook_b = s:integration_open_additional_notebook([
          \ '##',
          \ 'print("other")',
          \ ], 'other.vipynb')
    let g:jusi_session_adapter = {
          \ 'start': function('s:integration_session_adapter_start'),
          \ 'stop': function('s:integration_session_adapter_stop'),
          \ }
    call jusi#session#start('python3')
    call jusi#session#stop()

    call assert_equal(l:notebook_b, bufnr('%'))
    call assert_false(bufexists(get(b:jusi_nb.session.prepared, 'bufnr', -1)))
    call assert_true(bufexists(l:detached))
    call assert_equal(l:notebook_a, getbufvar(l:detached, 'jusi_client_notebook_bufnr', -1))
    call assert_equal('detached', getbufvar(l:detached, 'jusi_client_role', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_integration_late_prepared_callback_while_disconnected_is_ignored() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:integration_session_adapter_start'),
          \ 'disconnect': function('s:integration_session_adapter_disconnect'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('python3')
    call jusi#session#disconnect()

    call assert_equal('disconnected', b:jusi_nb.session.state)
    call assert_equal('missing', b:jusi_nb.session.prepared.state)
    call assert_equal(-1, b:jusi_nb.session.prepared.bufnr)

    call jusi#session#callback_prepared({'id': 'late-client', 'state': 'binding', 'bufnr': -1})

    call assert_equal('disconnected', b:jusi_nb.session.state)
    call assert_equal('missing', b:jusi_nb.session.prepared.state)
    call assert_equal(-1, b:jusi_nb.session.prepared.bufnr)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_integration_late_cell_callback_while_disconnected_is_ignored() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:integration_session_adapter_start'),
          \ 'disconnect': function('s:integration_session_adapter_disconnect'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    let l:cell_id = b:jusi_nb.cells[0].id
    call jusi#session#start('python3')
    call jusi#session#disconnect()

    call jusi#session#callback_cell(l:cell_id, {
          \ 'status': 'follow-up',
          \ 'client_id': 'late-client',
          \ 'client_state': 'active',
          \ 'client_bufnr': 91,
          \ 'owner': {'kind': 'handler'},
          \ })

    call assert_equal('disconnected', b:jusi_nb.session.state)
    call assert_equal('initial', b:jusi_nb.cells[0].status)
    call assert_equal('', b:jusi_nb.cells[0].client_id)
    call assert_equal('shutdown', b:jusi_nb.cells[0].client_state)
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_integration_reconnect_in_other_notebook_does_not_touch_detached_buffers() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'request': function('s:integration_transport_request_adapter')}
    call Test_open_scratch([
          \ '##',
          \ '%%vd pods',
          \ ])
    let l:notebook_a = bufnr('%')
    let l:cell_a = b:jusi_nb.cells[0].id
    let l:detached = jusi#client#create_prepared_buffer(l:notebook_a, 'client-a')
    call jusi#client#mark_attached_buffer(l:notebook_a, l:cell_a, 'client-a', l:detached)
    call setbufvar(l:detached, 'jusi_client_transport_kind', 'native_terminal')
    let b:jusi_nb.session.id = 'sess-a'
    let b:jusi_nb.session.state = 'connected'
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].client_id = 'client-a'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:detached
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    call jusi#session#close_current_client()
    call assert_true(bufexists(l:detached))
    call assert_equal('detached', getbufvar(l:detached, 'jusi_client_role', ''))

    let l:notebook_b = s:integration_open_additional_notebook([
          \ '##',
          \ 'print("other")',
          \ ], 'reconnect-other.vipynb')
    let g:jusi_session_adapter = {
          \ 'reconnect': function('s:integration_session_adapter_reconnect'),
          \ 'bind_prepared_client': function('s:integration_session_adapter_bind_prepared'),
          \ }
    call jusi#session#set_disconnected()
    let b:jusi_nb.session.id = 'sess-b'
    call jusi#session#reconnect()
    call jusi#session#callback_prepared({'id': 'client-int-2', 'state': 'binding', 'bufnr': -1})

    call assert_equal(l:notebook_b, bufnr('%'))
    call assert_true(get(b:jusi_nb.session.prepared, 'bufnr', -1) > 0)
    call assert_true(bufexists(l:detached))
    call assert_equal(l:notebook_a, getbufvar(l:detached, 'jusi_client_notebook_bufnr', -1))
    call assert_equal('detached', getbufvar(l:detached, 'jusi_client_role', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_integration_late_session_connected_update_while_disconnected_is_ignored() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:integration_session_adapter_start'),
          \ 'disconnect': function('s:integration_session_adapter_disconnect'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('python3')
    call jusi#session#disconnect()

    call jusi#session#callback_session({
          \ 'id': 'sess-int-1',
          \ 'state': 'connected',
          \ 'backend': 'late-backend',
          \ })

    call assert_equal('disconnected', b:jusi_nb.session.state)
    call assert_equal('disconnect', b:jusi_nb.session.last_action)
    call assert_notequal('late-backend', get(b:jusi_nb.session, 'backend', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_integration_late_session_connected_update_while_stopped_is_ignored() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:integration_session_adapter_start'),
          \ 'stop': function('s:integration_session_adapter_stop'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('python3')
    call jusi#session#stop()

    call jusi#session#callback_session({
          \ 'id': 'sess-int-1',
          \ 'state': 'connected',
          \ 'backend': 'late-backend',
          \ })

    call assert_equal('stopped', b:jusi_nb.session.state)
    call assert_equal('stop', b:jusi_nb.session.last_action)
    call assert_notequal('late-backend', get(b:jusi_nb.session, 'backend', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_integration_insert_below_active_cell_keeps_runtime_on_same_cell() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd pods',
        \ '##',
        \ 'print("other")',
        \ ])
  let l:notebook = bufnr('%')
  let l:active_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  call jusi#client#mark_attached_buffer(l:notebook, l:active_id, 'client-1', l:client)

  call cursor(2, 1)
  call jusi#notebook#insert_below()
  stopinsert

  call assert_equal(3, len(b:jusi_nb.cells))
  call assert_equal(l:active_id, b:jusi_nb.cells[0].id)
  call assert_equal('follow-up', b:jusi_nb.cells[0].status)
  call assert_equal('client-1', b:jusi_nb.cells[0].client_id)
  call assert_equal(l:client, b:jusi_nb.cells[0].client_bufnr)
  call assert_equal('initial', b:jusi_nb.cells[1].status)
  call assert_equal(-1, b:jusi_nb.cells[1].client_bufnr)
endfunction

function! Test_integration_insert_above_active_cell_keeps_runtime_on_shifted_cell() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd pods',
        \ '##',
        \ 'print("other")',
        \ ])
  let l:notebook = bufnr('%')
  let l:active_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  call jusi#client#mark_attached_buffer(l:notebook, l:active_id, 'client-1', l:client)

  call cursor(2, 1)
  call jusi#notebook#insert_above()
  stopinsert

  call assert_equal(3, len(b:jusi_nb.cells))
  call assert_equal('initial', b:jusi_nb.cells[0].status)
  call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
  call assert_equal(l:active_id, b:jusi_nb.cells[1].id)
  call assert_equal('follow-up', b:jusi_nb.cells[1].status)
  call assert_equal('client-1', b:jusi_nb.cells[1].client_id)
  call assert_equal(l:client, b:jusi_nb.cells[1].client_bufnr)
endfunction

function! Test_integration_mutating_active_cell_body_keeps_runtime_binding() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd pods',
        \ '##',
        \ 'print("other")',
        \ ])
  let l:notebook = bufnr('%')
  let l:active_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  call jusi#client#mark_attached_buffer(l:notebook, l:active_id, 'client-1', l:client)

  call append(2, 'tail line')
  call jusi#notebook#handle_text_changed()

  call assert_equal(2, len(b:jusi_nb.cells))
  call assert_equal(l:active_id, b:jusi_nb.cells[0].id)
  call assert_equal('follow-up', b:jusi_nb.cells[0].status)
  call assert_equal('client-1', b:jusi_nb.cells[0].client_id)
  call assert_equal(l:client, b:jusi_nb.cells[0].client_bufnr)
  call assert_equal(['%%vd pods', 'tail line'], jusi#notebook#cell_main_lines(b:jusi_nb.cells[0]))
endfunction

function! Test_integration_delete_active_cell_then_undo_does_not_restore_client_binding() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let s:integration_shutdown_requests = []
    let g:jusi_session_adapter = {
          \ 'shutdown_client': function('s:integration_session_adapter_shutdown_client_record'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ '%%vd pods',
          \ '##',
          \ 'print("other")',
          \ ])
    call s:integration_reset_undo_history()
    let l:notebook = bufnr('%')
    let l:active_id = b:jusi_nb.cells[0].id
    let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
    call jusi#session#set_connected(0, {'id': 'sess-1'})
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    call jusi#client#mark_attached_buffer(l:notebook, l:active_id, 'client-1', l:client)

    call cursor(2, 1)
    call jusi#notebook#delete_current()
    call assert_false(bufexists(l:client))
    call assert_equal(1, len(s:integration_shutdown_requests))
    call assert_equal('client-1', get(s:integration_shutdown_requests[0], 'client_id', ''))

    silent! undo
    call jusi#notebook#refresh_if_changed()

    call assert_equal(2, len(b:jusi_nb.cells))
    call assert_equal(['##', '%%vd pods', '##', 'print("other")'], getline(1, '$'))
    call assert_equal('initial', b:jusi_nb.cells[0].status)
    call assert_equal('', b:jusi_nb.cells[0].client_id)
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_integration_deleting_region_overlapping_active_cell_clears_runtime_and_undo_does_not_restore_it() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let s:integration_shutdown_requests = []
    let g:jusi_session_adapter = {
          \ 'shutdown_client': function('s:integration_session_adapter_shutdown_client_record'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("one")',
          \ '##',
          \ '%%vd pods',
          \ '##',
          \ 'print("three")',
          \ ])
    call s:integration_reset_undo_history()
    let l:notebook = bufnr('%')
    let l:active_id = b:jusi_nb.cells[1].id
    let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-2')
    call jusi#session#set_connected(0, {'id': 'sess-1'})
    let b:jusi_nb.cells[1].status = 'follow-up'
    let b:jusi_nb.cells[1].owner = {'kind': 'handler'}
    let b:jusi_nb.cells[1].client_id = 'client-2'
    let b:jusi_nb.cells[1].client_state = 'active'
    let b:jusi_nb.cells[1].client_bufnr = l:client
    call jusi#client#mark_attached_buffer(l:notebook, l:active_id, 'client-2', l:client)

    execute '3,4delete _'
    call jusi#notebook#handle_text_changed()

    call assert_false(bufexists(l:client))
    call assert_equal(1, len(s:integration_shutdown_requests))
    call assert_equal('client-2', get(s:integration_shutdown_requests[0], 'client_id', ''))
    call assert_equal(2, len(b:jusi_nb.cells))
    call assert_equal(['##', 'print("one")', '##', 'print("three")'], getline(1, '$'))

    silent! undo
    call jusi#notebook#refresh_if_changed()

    call assert_equal(['##', 'print("one")', '##', '%%vd pods', '##', 'print("three")'], getline(1, '$'))
    for l:cell in b:jusi_nb.cells
      call assert_notequal('client-2', get(l:cell, 'client_id', ''))
      call assert_equal(-1, get(l:cell, 'client_bufnr', -1))
    endfor
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_integration_splitting_active_cell_keeps_runtime_on_original_cell() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd pods',
        \ 'echo "one"',
        \ '##',
        \ 'print("other")',
        \ ])
  let l:notebook = bufnr('%')
  let l:active_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  call jusi#client#mark_attached_buffer(l:notebook, l:active_id, 'client-1', l:client)

  call append(2, '##')
  call jusi#notebook#handle_text_changed()

  call assert_equal(3, len(b:jusi_nb.cells))
  call assert_equal(l:active_id, b:jusi_nb.cells[0].id)
  call assert_equal('follow-up', b:jusi_nb.cells[0].status)
  call assert_equal('client-1', b:jusi_nb.cells[0].client_id)
  call assert_equal(l:client, b:jusi_nb.cells[0].client_bufnr)
  call assert_equal('initial', b:jusi_nb.cells[1].status)
  call assert_equal(-1, b:jusi_nb.cells[1].client_bufnr)
  call assert_equal(['%%vd pods'], jusi#notebook#cell_main_lines(b:jusi_nb.cells[0]))
  call assert_equal(['echo "one"'], jusi#notebook#cell_main_lines(b:jusi_nb.cells[1]))
endfunction

function! Test_integration_deleting_delimiter_below_active_cell_keeps_runtime_on_merged_cell() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd pods',
        \ '##',
        \ 'echo "one"',
        \ '##',
        \ 'print("other")',
        \ ])
  let l:notebook = bufnr('%')
  let l:active_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  call jusi#client#mark_attached_buffer(l:notebook, l:active_id, 'client-1', l:client)

  execute '3delete _'
  call jusi#notebook#handle_text_changed()

  call assert_equal(2, len(b:jusi_nb.cells))
  call assert_equal(l:active_id, b:jusi_nb.cells[0].id)
  call assert_equal('follow-up', b:jusi_nb.cells[0].status)
  call assert_equal('client-1', b:jusi_nb.cells[0].client_id)
  call assert_equal(l:client, b:jusi_nb.cells[0].client_bufnr)
  call assert_equal(['%%vd pods', 'echo "one"'], jusi#notebook#cell_main_lines(b:jusi_nb.cells[0]))
endfunction

function! Test_integration_deleting_active_cell_start_delimiter_clears_runtime() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let s:integration_shutdown_requests = []
    let g:jusi_session_adapter = {
          \ 'shutdown_client': function('s:integration_session_adapter_shutdown_client_record'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("one")',
          \ '##',
          \ '%%vd pods',
          \ '##',
          \ 'print("other")',
          \ ])
    let l:notebook = bufnr('%')
    let l:active_id = b:jusi_nb.cells[1].id
    let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-2')
    call jusi#session#set_connected(0, {'id': 'sess-1'})
    let b:jusi_nb.cells[1].status = 'follow-up'
    let b:jusi_nb.cells[1].owner = {'kind': 'handler'}
    let b:jusi_nb.cells[1].client_id = 'client-2'
    let b:jusi_nb.cells[1].client_state = 'active'
    let b:jusi_nb.cells[1].client_bufnr = l:client
    call jusi#client#mark_attached_buffer(l:notebook, l:active_id, 'client-2', l:client)

    execute '3delete _'
    call jusi#notebook#handle_text_changed()

    call assert_false(bufexists(l:client))
    call assert_equal(1, len(s:integration_shutdown_requests))
    call assert_equal('client-2', get(s:integration_shutdown_requests[0], 'client_id', ''))
    call assert_equal(2, len(b:jusi_nb.cells))
    call assert_equal('initial', b:jusi_nb.cells[0].status)
    call assert_equal('', b:jusi_nb.cells[0].client_id)
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
    call assert_equal(['##', 'print("one")', '%%vd pods', '##', 'print("other")'], getline(1, '$'))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_integration_mutating_active_code_cell_header_to_magic_keeps_runtime_binding() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ '##',
        \ 'print("other")',
        \ ])
  let l:notebook = bufnr('%')
  let l:active_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
  let b:jusi_nb.cells[0].status = 'busy'
  let b:jusi_nb.cells[0].owner = {'kind': 'kernel'}
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  call jusi#client#mark_attached_buffer(l:notebook, l:active_id, 'client-1', l:client)

  call setline(2, '%%sql main')
  call jusi#notebook#handle_text_changed()

  call assert_equal(l:active_id, b:jusi_nb.cells[0].id)
  call assert_equal('magic', b:jusi_nb.cells[0].kind)
  call assert_equal('sql', b:jusi_nb.cells[0].magic)
  call assert_equal('busy', b:jusi_nb.cells[0].status)
  call assert_equal('client-1', b:jusi_nb.cells[0].client_id)
  call assert_equal(l:client, b:jusi_nb.cells[0].client_bufnr)
endfunction

function! Test_integration_mutating_active_magic_header_to_code_keeps_runtime_binding() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd pods',
        \ '##',
        \ 'print("other")',
        \ ])
  let l:notebook = bufnr('%')
  let l:active_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  call jusi#client#mark_attached_buffer(l:notebook, l:active_id, 'client-1', l:client)

  call setline(2, 'print("now code")')
  call jusi#notebook#handle_text_changed()

  call assert_equal(l:active_id, b:jusi_nb.cells[0].id)
  call assert_equal('code', b:jusi_nb.cells[0].kind)
  call assert_equal('', b:jusi_nb.cells[0].magic)
  call assert_equal('follow-up', b:jusi_nb.cells[0].status)
  call assert_equal('client-1', b:jusi_nb.cells[0].client_id)
  call assert_equal(l:client, b:jusi_nb.cells[0].client_bufnr)
endfunction

function! Test_integration_redo_after_delete_active_cell_keeps_binding_dead() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let s:integration_shutdown_requests = []
    let g:jusi_session_adapter = {
          \ 'shutdown_client': function('s:integration_session_adapter_shutdown_client_record'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ '%%vd pods',
          \ '##',
          \ 'print("other")',
          \ ])
    call s:integration_reset_undo_history()
    let l:notebook = bufnr('%')
    let l:active_id = b:jusi_nb.cells[0].id
    let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
    call jusi#session#set_connected(0, {'id': 'sess-1'})
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    call jusi#client#mark_attached_buffer(l:notebook, l:active_id, 'client-1', l:client)

    call cursor(2, 1)
    call jusi#notebook#delete_current()
    silent! undo
    call jusi#notebook#refresh_if_changed()
    silent! redo
    call jusi#notebook#refresh_if_changed()

    call assert_false(bufexists(l:client))
    call assert_equal(['##', 'print("other")'], getline(1, '$'))
    call assert_equal(1, len(b:jusi_nb.cells))
    call assert_equal('initial', b:jusi_nb.cells[0].status)
    call assert_equal('', b:jusi_nb.cells[0].client_id)
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_integration_redo_after_overlap_delete_keeps_binding_dead() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let s:integration_shutdown_requests = []
    let g:jusi_session_adapter = {
          \ 'shutdown_client': function('s:integration_session_adapter_shutdown_client_record'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("one")',
          \ '##',
          \ '%%vd pods',
          \ '##',
          \ 'print("three")',
          \ ])
    call s:integration_reset_undo_history()
    let l:notebook = bufnr('%')
    let l:active_id = b:jusi_nb.cells[1].id
    let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-2')
    call jusi#session#set_connected(0, {'id': 'sess-1'})
    let b:jusi_nb.cells[1].status = 'follow-up'
    let b:jusi_nb.cells[1].owner = {'kind': 'handler'}
    let b:jusi_nb.cells[1].client_id = 'client-2'
    let b:jusi_nb.cells[1].client_state = 'active'
    let b:jusi_nb.cells[1].client_bufnr = l:client
    call jusi#client#mark_attached_buffer(l:notebook, l:active_id, 'client-2', l:client)

    execute '3,4delete _'
    call jusi#notebook#handle_text_changed()
    silent! undo
    call jusi#notebook#refresh_if_changed()
    silent! redo
    call jusi#notebook#refresh_if_changed()

    call assert_false(bufexists(l:client))
    call assert_equal(['##', 'print("one")', '##', 'print("three")'], getline(1, '$'))
    for l:cell in b:jusi_nb.cells
      call assert_notequal('client-2', get(l:cell, 'client_id', ''))
      call assert_equal(-1, get(l:cell, 'client_bufnr', -1))
    endfor
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_integration_quit_guard_ignores_unrelated_current_buffer() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call jusi#session#set_connected()
  tabnew
  setlocal buftype=
  execute 'file ' . tempname() . '.txt'
  call assert_equal(1, jusi#notebook#guard_quit(0))
endfunction

function! Test_integration_quit_guard_allows_closing_one_of_multiple_visible_notebook_windows() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call jusi#session#set_connected()
  let l:notebook = bufnr('%')
  execute 'sbuffer ' . l:notebook
  call assert_equal(1, jusi#notebook#guard_quit(0))
endfunction

function! Test_integration_wipeout_guard_ignores_unrelated_buffer() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call jusi#session#set_connected()
  tabnew
  setlocal buftype=
  execute 'file ' . tempname() . '.txt'
  call assert_equal(1, jusi#notebook#guard_wipeout(bufnr('%'), 0))
endfunction

function! Test_integration_forced_exit_marks_all_active_notebooks_for_skip_cleanup() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("one")',
        \ ])
  call jusi#session#set_connected()
  let l:first = bufnr('%')

  let l:second = s:integration_open_additional_notebook([
        \ '##',
        \ 'print("two")',
        \ ], 'second.vipynb')
  call jusi#session#set_connected()

  call jusi#notebook#prepare_forced_exit()

  call assert_equal(1, getbufvar(l:first, 'jusi_skip_cleanup_once', 0))
  call assert_equal(1, getbufvar(l:second, 'jusi_skip_cleanup_once', 0))
endfunction

function! Test_integration_client_editor_close_clears_cell_binding_without_disconnect() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd pods',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
  call jusi#session#set_connected(0, {'id': 'sess-1'})
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)

  call assert_equal(1, jusi#client#handle_editor_close(l:client))

  call assert_equal('connected', b:jusi_nb.session.state)
  call assert_equal('follow-up', b:jusi_nb.cells[0].status)
  call assert_equal('shutdown', b:jusi_nb.cells[0].client_state)
  call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
endfunction

function! Test_integration_quit_guard_allows_closing_one_of_multiple_visible_notebook_tabs() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call jusi#session#set_connected()
  let l:notebook = bufnr('%')
  tabnew
  execute 'buffer ' . l:notebook
  call assert_equal(1, jusi#notebook#guard_quit(0))
endfunction

function! Test_integration_forced_quit_marks_only_current_active_notebook() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("one")',
        \ ])
  call jusi#session#set_connected()
  let l:first = bufnr('%')

  let l:second = s:integration_open_additional_notebook([
        \ '##',
        \ 'print("two")',
        \ ], 'forced-one.vipynb')
  call jusi#session#set_connected()

  call assert_equal(1, jusi#notebook#guard_quit(1))

  call assert_equal(0, getbufvar(l:first, 'jusi_skip_cleanup_once', 0))
  call assert_equal(1, getbufvar(l:second, 'jusi_skip_cleanup_once', 0))
endfunction

function! Test_integration_forced_wipeout_marks_only_target_notebook() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("one")',
        \ ])
  call jusi#session#set_connected()
  let l:first = bufnr('%')

  let l:second = s:integration_open_additional_notebook([
        \ '##',
        \ 'print("two")',
        \ ], 'forced-wipe.vipynb')
  call jusi#session#set_connected()

  call assert_equal(1, jusi#notebook#guard_wipeout(l:second, 1))

  call assert_equal(0, getbufvar(l:first, 'jusi_skip_cleanup_once', 0))
  call assert_equal(1, getbufvar(l:second, 'jusi_skip_cleanup_once', 0))
endfunction

function! Test_integration_client_editor_close_clears_prepared_binding_without_disconnect() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let l:notebook = bufnr('%')
  let l:prepared = jusi#client#create_prepared_buffer(l:notebook, 'client-prepared')
  call jusi#session#set_connected(0, {'id': 'sess-1'})
  call jusi#session#apply_prepared({
        \ 'id': 'client-prepared',
        \ 'state': 'ready',
        \ 'client_state': 'active',
        \ 'bufnr': l:prepared,
        \ })

  call assert_equal(1, jusi#client#handle_editor_close(l:prepared))

  call assert_equal('connected', b:jusi_nb.session.state)
  call assert_equal('missing', b:jusi_nb.session.prepared.state)
  call assert_equal('shutdown', b:jusi_nb.session.prepared.client_state)
  call assert_equal(-1, b:jusi_nb.session.prepared.bufnr)
endfunction

function! Test_integration_command_q_blocks_last_visible_active_notebook() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let l:notebook = bufnr('%')
  call jusi#session#set_connected()

  call feedkeys(":q\<CR>", 'xt')

  call assert_equal(l:notebook, bufnr('%'))
  call assert_equal('connected', b:jusi_nb.session.state)
endfunction

function! Test_integration_command_q_closes_client_and_keeps_session_connected() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd pods',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
  call jusi#session#set_connected(0, {'id': 'sess-1'})
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)
  call jusi#focus#place_client_buffer(l:client, 'bsplit', 0)

  execute 'JusiInternalQuit'

  call assert_equal(l:notebook, bufnr('%'))
  call assert_equal('connected', b:jusi_nb.session.state)
  call assert_equal('shutdown', b:jusi_nb.cells[0].client_state)
  call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
endfunction

function! Test_integration_command_q_allows_closing_unrelated_buffer() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let l:notebook = bufnr('%')
  call jusi#session#set_connected()
  tabnew
  setlocal buftype=
  execute 'file ' . tempname() . '.txt'

  execute 'JusiInternalQuit'

  call assert_equal(l:notebook, bufnr('%'))
endfunction
