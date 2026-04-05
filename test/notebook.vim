source test/helpers.vim

function! Test_parser_detects_cells_and_magic() abort
  let l:parsed = jusi#notebook#parse_lines([
        \ '##',
        \ 'print("hello")',
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ ])
  call assert_equal(2, len(l:parsed.cells))
  call assert_equal('code', l:parsed.cells[0].kind)
  call assert_equal('magic', l:parsed.cells[1].kind)
  call assert_equal('sql', l:parsed.cells[1].magic)
  call assert_equal(1, l:parsed.cells[0].start)
  call assert_equal(2, l:parsed.cells[0].end)
  call assert_equal(3, l:parsed.cells[1].start)
  call assert_equal(5, l:parsed.cells[1].end)
  call assert_equal(1, l:parsed.cells[0].id)
  call assert_equal(2, l:parsed.cells[1].id)
  call assert_equal('python', l:parsed.cells[0].syntax)
  call assert_equal('sql', l:parsed.cells[1].syntax)
  call assert_equal(2, l:parsed.cells[0].body_end)
  call assert_equal(0, l:parsed.cells[1].history_start)
endfunction

function! Test_parser_tracks_magic_history_region() abort
  let l:parsed = jusi#notebook#parse_lines([
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ '##<<',
        \ '###',
        \ 'select 0',
        \ '##>>',
        \ ])
  call assert_equal(1, len(l:parsed.cells))
  call assert_equal('magic', l:parsed.cells[0].kind)
  call assert_equal(3, l:parsed.cells[0].body_end)
  call assert_equal(4, l:parsed.cells[0].history_start)
  call assert_equal(7, l:parsed.cells[0].history_end)
endfunction

function! Test_rebuild_places_signs_on_cell_starts() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ '##',
        \ 'print("bye")',
        \ ])
  let l:signs = Test_sign_lines(bufnr('%'))
  call assert_equal(2, len(l:signs))
  call assert_equal(2, l:signs[0][1])
  call assert_equal(4, l:signs[1][1])
  let l:state = b:jusi_nb
  call assert_equal([1, 2], map(copy(l:state.cells), 'v:val.id'))
  call assert_false(has_key(l:state, 'line_to_cell'))
endfunction

function! Test_insert_below_creates_new_cell() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call cursor(2, 1)
  call jusi#notebook#insert_below()
  call assert_equal(['##', 'print("hello")', '##', ''], getline(1, '$'))
  let l:cells = jusi#notebook#cells()
  call assert_equal(2, len(l:cells))
  call assert_equal(3, l:cells[1].start)
  call assert_equal([1, 2], map(copy(l:cells), 'v:val.id'))
  call assert_equal(4, line('.'))
endfunction

function! Test_insert_above_creates_new_cell() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call cursor(2, 1)
  call jusi#notebook#insert_above()
  call assert_equal(['##', '', '##', 'print("hello")'], getline(1, '$'))
  let l:cells = jusi#notebook#cells()
  call assert_equal(2, len(l:cells))
  call assert_equal(1, l:cells[0].start)
  call assert_equal(3, l:cells[1].start)
  call assert_equal([2, 1], map(copy(l:cells), 'v:val.id'))
  call assert_equal(2, line('.'))
endfunction

function! Test_insert_below_keeps_runtime_on_matching_duplicate_signature_cell() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd pods',
        \ '##',
        \ '%%vd pods',
        \ '##',
        \ '%%vd pods',
        \ ])
  let l:notebook = bufnr('%')
  let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
  let b:jusi_nb.cells[2].status = 'follow-up'
  let b:jusi_nb.cells[2].owner = {'kind': 'handler'}
  let b:jusi_nb.cells[2].client_id = 'client-1'
  let b:jusi_nb.cells[2].client_state = 'active'
  let b:jusi_nb.cells[2].client_bufnr = l:client
  let b:jusi_nb.cells[2].handler = {'id': 'vd', 'last_message_type': 'handler_snapshot', 'payload': {}, 'snapshot': {'transport': 'native_terminal'}}
  call jusi#client#mark_attached_buffer(l:notebook, b:jusi_nb.cells[2].id, 'client-1', l:client)

  call cursor(2, 1)
  call jusi#notebook#insert_below()
  stopinsert

  call assert_equal(4, len(b:jusi_nb.cells))
  call assert_equal('initial', b:jusi_nb.cells[1].status)
  call assert_equal(-1, b:jusi_nb.cells[1].client_bufnr)
  call assert_equal('initial', b:jusi_nb.cells[2].status)
  call assert_equal(-1, b:jusi_nb.cells[2].client_bufnr)
  call assert_equal('follow-up', b:jusi_nb.cells[3].status)
  call assert_equal('client-1', b:jusi_nb.cells[3].client_id)
  call assert_equal(l:client, b:jusi_nb.cells[3].client_bufnr)
endfunction

function! Test_delete_middle_cell_keeps_neighbors() abort
  call Test_open_scratch([
        \ '##',
        \ 'one',
        \ '##',
        \ 'two',
        \ '##',
        \ 'three',
        \ ])
  call cursor(4, 1)
  call jusi#notebook#delete_current()
  call assert_equal(['##', 'one', '##', 'three'], getline(1, '$'))
  let l:cells = jusi#notebook#cells()
  call assert_equal(2, len(l:cells))
  call assert_equal([1, 3], map(copy(l:cells), 'v:val.id'))
  call assert_equal(4, line('.'))
endfunction

function! Test_delete_only_cell_resets_to_single_empty_cell() abort
  call Test_open_scratch([
        \ '##',
        \ 'one',
        \ ])
  call cursor(2, 1)
  call jusi#notebook#delete_current()
  call assert_equal(['##'], getline(1, '$'))
  let l:cells = jusi#notebook#cells()
  call assert_equal(1, len(l:cells))
  call assert_equal(1, l:cells[0].start)
  call assert_equal(1, l:cells[0].end)
  call assert_equal(1, line('.'))
endfunction

function! Test_delete_last_cell_moves_to_previous_cell() abort
  call Test_open_scratch([
        \ '##',
        \ 'one',
        \ '##',
        \ 'two',
        \ ])
  call cursor(4, 1)
  call jusi#notebook#delete_current()
  call assert_equal(['##', 'one'], getline(1, '$'))
  let l:cells = jusi#notebook#cells()
  call assert_equal(1, len(l:cells))
  call assert_equal(2, line('.'))
endfunction

function! Test_edit_current_clears_cell_body_and_enters_insert_target() abort
  call Test_open_scratch([
        \ '##',
        \ 'one',
        \ 'two',
        \ '##',
        \ 'three',
        \ ])
  call cursor(3, 1)
  call jusi#notebook#edit_current()
  call assert_equal(['##', '', '##', 'three'], getline(1, '$'))
  let l:cells = jusi#notebook#cells()
  call assert_equal(2, len(l:cells))
  call assert_equal(2, line('.'))
endfunction

function! Test_edit_current_preserves_magic_history_region() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ '##<<',
        \ '###',
        \ 'select 0',
        \ '##>>',
        \ ])
  call cursor(3, 1)
  call jusi#notebook#edit_current()
  call assert_equal(['##', '', '##<<', '###', 'select 0', '##>>'], getline(1, '$'))
  call assert_equal([''], jusi#notebook#cell_main_lines())
  call assert_equal(['##<<', '###', 'select 0', '##>>'], jusi#notebook#cell_history_lines())
endfunction

function! Test_copy_current_stores_cell_lines() abort
  call Test_open_scratch([
        \ '##',
        \ 'one',
        \ 'two',
        \ '##',
        \ 'three',
        \ ])
  call cursor(2, 1)
  call jusi#notebook#copy_current()
  call assert_equal(['##', 'one', 'two'], g:jusi_cell_clipboard)
endfunction

function! Test_paste_below_inserts_copied_cell() abort
  call Test_open_scratch([
        \ '##',
        \ 'one',
        \ '##',
        \ 'two',
        \ ])
  call cursor(2, 1)
  call jusi#notebook#copy_current()
  call cursor(4, 1)
  call jusi#notebook#paste_below()
  call assert_equal(['##', 'one', '##', 'two', '##', 'one'], getline(1, '$'))
  let l:cells = jusi#notebook#cells()
  call assert_equal(3, len(l:cells))
  call assert_equal(5, l:cells[2].start)
  call assert_equal(6, line('.'))
endfunction

function! Test_paste_below_without_clipboard_is_noop() abort
  let g:jusi_cell_clipboard = []
  call Test_open_scratch([
        \ '##',
        \ 'one',
        \ ])
  call jusi#notebook#paste_below()
  call assert_equal(['##', 'one'], getline(1, '$'))
endfunction

function! Test_navigation_moves_to_cell_boundaries() abort
  call Test_open_scratch([
        \ '##',
        \ 'one',
        \ '##',
        \ 'two',
        \ '##',
        \ 'three',
        \ ])
  call cursor(2, 1)
  call jusi#notebook#goto_next()
  call assert_equal(4, line('.'))
  call jusi#notebook#goto_prev()
  call assert_equal(2, line('.'))
endfunction

function! Test_existing_cell_ids_are_preserved_across_rebuilds() abort
  call Test_open_scratch([
        \ '##',
        \ 'one',
        \ '##',
        \ 'two',
        \ ])
  let l:before = map(copy(jusi#notebook#cells()), 'v:val.id')
  call setline(2, 'ONE')
  call jusi#notebook#rebuild()
  let l:after = map(copy(jusi#notebook#cells()), 'v:val.id')
  call assert_equal(l:before, l:after)
endfunction

function! Test_cell_lookup_works_inside_long_cell_without_line_map() abort
  let l:lines = ['##']
  for l:num in range(1, 800)
    call add(l:lines, 'line ' . l:num)
  endfor
  call add(l:lines, '##')
  call add(l:lines, 'tail')

  call Test_open_scratch(l:lines)

  let l:cell = jusi#notebook#cell_at_line(bufnr('%'), 500)
  call assert_equal(1, l:cell.id)
  call assert_equal(1, l:cell.start)
  call assert_equal(801, l:cell.end)
endfunction

function! Test_existing_syntax_override_survives_rebuild() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ ])
  let b:jusi_nb.cells[0].syntax = 'sqloracle'
  let l:tick_before = b:jusi_nb.changedtick
  call setline(3, 'select 2')
  call jusi#notebook#rebuild()
  call assert_notequal(l:tick_before, b:jusi_nb.changedtick)
  call assert_equal('sqloracle', b:jusi_nb.cells[0].syntax)
endfunction

function! Test_default_runtime_state_is_initialized_for_new_cells() abort
  let l:parsed = jusi#notebook#parse_lines([
        \ '##',
        \ 'print("hello")',
        \ ])
  call assert_equal(1, len(l:parsed.cells))
  call assert_equal('initial', l:parsed.cells[0].status)
  call assert_equal('', l:parsed.cells[0].client_id)
  call assert_equal('shutdown', l:parsed.cells[0].client_state)
  call assert_equal(-1, l:parsed.cells[0].client_bufnr)
  call assert_equal('', get(get(l:parsed.cells[0], 'owner', {}), 'kind', ''))
  call assert_true(l:parsed.cells[0].sign_id > 0)
endfunction

function! Test_non_default_runtime_state_is_preserved_for_surviving_cells() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let b:jusi_nb.cells[0].status = 'busy'
  let b:jusi_nb.cells[0].client_bufnr = 42
  call setline(2, 'print("HELLO")')
  call jusi#notebook#rebuild()
  call assert_equal('busy', b:jusi_nb.cells[0].status)
  call assert_equal(42, b:jusi_nb.cells[0].client_bufnr)
endfunction

function! Test_backend_runtime_cell_fields_are_preserved_for_surviving_cells() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].client_id = 'client-9'
  let b:jusi_nb.cells[0].client_bufnr = 42
  let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
  call setline(2, 'print("HELLO")')
  call jusi#notebook#rebuild()
  call assert_equal('follow-up', b:jusi_nb.cells[0].status)
  call assert_equal('client-9', b:jusi_nb.cells[0].client_id)
  call assert_equal(42, b:jusi_nb.cells[0].client_bufnr)
  call assert_equal('handler', get(get(b:jusi_nb.cells[0], 'owner', {}), 'kind', ''))
endfunction

function! s:test_session_adapter_start(bufnr, payload) abort
  return {
        \ 'ok': 1,
        \ 'session': {
        \   'id': 'sess-start-1',
        \   'kernel_id': 'kernel-start-1',
        \   'state': 'connected',
        \   'backend': 'mock',
        \   'kernel_name': get(a:payload, 'kernel_name', ''),
        \   'connection': 'mock://kernel/' . get(a:payload, 'kernel_name', ''),
        \   },
        \ 'prepared': {
        \   'id': 'client-1',
        \   'state': 'binding',
        \   'bufnr': -1,
        \   },
        \ }
endfunction

function! s:test_session_adapter_attach(bufnr, payload) abort
  let l:target = get(a:payload, 'target', {})
  return {
        \ 'ok': 1,
        \ 'session': {
        \   'id': 'sess-attach-1',
        \   'kernel_id': 'kernel-attach-1',
        \   'state': 'connected',
        \   'backend': 'mock',
        \   'connection': type(l:target) == type({}) ? get(l:target, 'value', '') : l:target,
        \   },
        \ 'prepared': {
        \   'id': 'client-1',
        \   'state': 'binding',
        \   'bufnr': -1,
        \   },
        \ }
endfunction

function! s:test_session_adapter_attach_without_ids(bufnr, payload) abort
  let l:target = get(a:payload, 'target', {})
  return {
        \ 'ok': 1,
        \ 'session': {
        \   'state': 'connected',
        \   'backend': 'mock',
        \   'connection': type(l:target) == type({}) ? get(l:target, 'value', '') : l:target,
        \   },
        \ 'prepared': {
        \   'id': 'client-1',
        \   'state': 'binding',
        \   'bufnr': -1,
        \   },
        \ }
endfunction

let s:last_bound_prepared = {}
let s:shutdown_requests = []
let s:inspect_client_response = {}
let s:inspect_client_calls = 0
let s:inspect_client_sequence = []
let s:native_terminal_launches = []

function! s:test_session_adapter_bind_prepared(bufnr, payload) abort
  let s:last_bound_prepared = copy(a:payload)
  return {'ok': 1}
endfunction

function! s:test_session_adapter_shutdown_client_record(bufnr, payload) abort
  call add(s:shutdown_requests, copy(a:payload))
  return {'ok': 1}
endfunction

function! s:test_session_adapter_inspect_client(bufnr, payload) abort
  let s:inspect_client_calls += 1
  if !empty(s:inspect_client_sequence)
    let l:view = remove(s:inspect_client_sequence, 0)
  else
    let l:view = copy(s:inspect_client_response)
  endif
  return {
        \ 'ok': 1,
        \ 'payload': {
        \   'client': l:view,
        \   },
        \ }
endfunction

function! s:test_native_terminal_launcher(notebook_bufnr, cell_id, client_id, transport) abort
  let l:bufnr = bufadd('!jusi-native-terminal:' . a:notebook_bufnr . ':' . a:client_id)
  call bufload(l:bufnr)
  call setbufvar(l:bufnr, '&buftype', 'terminal')
  call setbufvar(l:bufnr, '&bufhidden', 'hide')
  call setbufvar(l:bufnr, '&swapfile', 0)
  call setbufline(l:bufnr, 1, ['terminal attached'])
  call add(s:native_terminal_launches, {
        \ 'notebook_bufnr': a:notebook_bufnr,
        \ 'cell_id': a:cell_id,
        \ 'client_id': a:client_id,
        \ 'transport': copy(a:transport),
        \ 'bufnr': l:bufnr,
        \ })
  return l:bufnr
endfunction

let s:last_request_envelope = {}
let s:request_envelopes = []

function! s:test_request_adapter(bufnr, envelope) abort
  let s:last_request_envelope = copy(a:envelope)
  call add(s:request_envelopes, copy(a:envelope))
  return {'ok': 1}
endfunction

function! s:test_transport_like_request_adapter(bufnr, envelope) abort
  let s:last_request_envelope = copy(a:envelope)
  if get(a:envelope, 'type', '') ==# 'start_session'
    return {
          \ 'ok': 1,
          \ '_transport': 1,
          \ 'payload': {
          \   'session': {
          \     'id': 'sess-1',
          \     'state': 'connected',
          \     'backend': 'mock',
          \     'kernel_name': get(get(a:envelope, 'payload', {}), 'kernel_name', ''),
          \     'connection': 'mock://kernel/' . get(get(a:envelope, 'payload', {}), 'kernel_name', ''),
          \     },
          \   'prepared': {
          \     'id': 'client-1',
          \     'state': 'binding',
          \     'bufnr': -1,
          \     },
          \   },
          \ }
  endif
  if get(a:envelope, 'type', '') ==# 'disconnect_session'
    return {
          \ 'ok': 1,
          \ '_transport': 1,
          \ 'payload': {
          \   'session': {
          \     'state': 'disconnected',
          \     'expires_at': '2030-01-01T00:00:00Z',
          \     'last_action': 'disconnect',
          \     },
          \   'prepared': {
          \     'state': 'missing',
          \     'bufnr': -1,
          \     },
          \   },
          \ }
  endif
  if get(a:envelope, 'type', '') ==# 'reconnect_session'
    return {
          \ 'ok': 1,
          \ '_transport': 1,
          \ 'payload': {
          \   'session': {
          \     'state': 'connected',
          \     'last_action': 'reconnect',
          \     'expires_at': '',
          \     },
          \   'prepared': {
          \     'id': 'client-2',
          \     'state': 'binding',
          \     'bufnr': -1,
          \     },
          \   },
          \ }
  endif
  return {'ok': 1, '_transport': 1, 'payload': {}}
endfunction

function! s:test_transport_handler(bufnr, envelope) abort
  let s:last_request_envelope = copy(a:envelope)
  return {'ok': 1}
endfunction

function! TestTransportHandler(bufnr, envelope) abort
  return s:test_transport_handler(a:bufnr, a:envelope)
endfunction

function! s:test_session_adapter_execute(bufnr, payload) abort
  return {
        \ 'ok': 1,
        \ 'prepared': {
        \   'id': 'client-2',
        \   'state': 'binding',
        \   'bufnr': -1,
        \   },
        \ }
endfunction

function! s:test_session_adapter_execute_failure(bufnr, payload) abort
  return {'ok': 0, 'error': 'mock execute failure'}
endfunction

function! s:test_session_adapter_interrupt(bufnr, payload) abort
  return {
        \ 'ok': 1,
        \ 'cell': {
        \   'id': get(get(a:payload, 'cell', {}), 'id', 0),
        \   'status': 'interrupted',
        \   'owner': {'kind': get(get(get(a:payload, 'cell', {}), 'owner', {}), 'kind', '')},
        \   },
        \ }
endfunction

function! s:test_session_adapter_input_reply(bufnr, payload) abort
  let s:last_input_reply_payload = copy(a:payload)
  return {'ok': 1}
endfunction

function! s:test_session_adapter_shutdown_client(bufnr, payload) abort
  return {
        \ 'ok': 1,
        \ 'cell': {
        \   'id': get(get(a:payload, 'cell', {}), 'id', 0),
        \   'status': get(get(a:payload, 'cell', {}), 'status', ''),
        \   'client_id': get(a:payload, 'client_id', ''),
        \   'client_state': 'shutdown',
        \   'client_bufnr': -1,
        \   'owner': get(get(a:payload, 'cell', {}), 'owner', {'kind': ''}),
        \   },
        \ }
endfunction

function! s:test_session_adapter_stop(bufnr, payload) abort
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

function! s:test_session_adapter_disconnect(bufnr, payload) abort
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

function! s:test_session_adapter_reconnect(bufnr, payload) abort
  return {
        \ 'ok': 1,
        \ 'session': {
        \   'state': 'connected',
        \   'expires_at': '',
        \   'last_action': 'reconnect',
        \   },
        \ 'prepared': {
        \   'id': 'client-2',
        \   'state': 'binding',
        \   'bufnr': -1,
        \   },
        \ }
endfunction

function! s:test_session_adapter_reconnect_error(bufnr, payload) abort
  return {'ok': 0, 'error': 'Session expired', 'error_code': 'session_expired'}
endfunction

function! Test_default_session_state_is_initialized_for_notebook() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let l:session = jusi#session#state()
  call assert_equal('idle', l:session.state)
  call assert_equal('', l:session.backend)
  call assert_equal('', l:session.last_error)
  call assert_false(has_key(l:session, 'attachable'))
  call assert_false(has_key(l:session, 'link'))
  call assert_equal('', get(l:session, 'expires_at', ''))
  call assert_equal('', get(l:session, 'last_error_code', ''))
  call assert_equal('', get(l:session.target, 'source', ''))
  call assert_equal('', get(l:session.target, 'alias', ''))
  call assert_equal('', l:session.prepared.id)
  call assert_equal('missing', l:session.prepared.state)
  call assert_equal('shutdown', l:session.prepared.client_state)
  call assert_equal(-1, l:session.prepared.bufnr)
endfunction

function! Test_adapter_builds_start_session_request_envelope() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let l:request = jusi#adapter#build_request('start', bufnr('%'), {
        \ 'kernel_name': 'python3',
        \ 'target': {
        \   'source': 'start',
        \   'alias': 'python3',
        \   'kind': 'kernel',
        \   'value': '',
        \   'config': {},
        \   },
        \ })
  call assert_equal(1, l:request.version)
  call assert_equal('request', l:request.kind)
  call assert_equal('start_session', l:request.type)
  call assert_match('^req-', l:request.request_id)
  call assert_equal('nb-' . bufnr('%'), l:request.payload.notebook_id)
  call assert_equal('python3', l:request.payload.kernel_name)
  call assert_equal('start', l:request.payload.target.source)
  call assert_equal('python3', l:request.payload.target.alias)
  call assert_equal('kernel', l:request.payload.target.kind)
endfunction

function! Test_adapter_builds_execute_cell_request_without_history_lines() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ '##<<',
        \ '###',
        \ 'select 0',
        \ '##>>',
        \ ])
  let b:jusi_nb.session.id = 'sess-1'
  let l:cell = jusi#notebook#cell_at_line(bufnr('%'), 3)
  let l:request = jusi#adapter#build_request('execute', bufnr('%'), {
        \ 'cell': {
        \   'id': l:cell.id,
        \   'kind': l:cell.kind,
        \   'syntax': l:cell.syntax,
        \   'main_lines': jusi#notebook#cell_main_lines(l:cell),
        \   },
        \ })
  call assert_equal('execute_cell', l:request.type)
  call assert_equal('nb-' . bufnr('%'), l:request.payload.notebook_id)
  call assert_equal('sess-1', l:request.payload.session_id)
  call assert_equal(l:cell.id, l:request.payload.cell.id)
  call assert_equal(['%%sql main', 'select 1'], l:request.payload.cell.main_lines)
  call assert_false(has_key(l:request.payload.cell, 'history_lines'))
endfunction

function! Test_cell_main_lines_excludes_opening_delimiter() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let l:cell = jusi#notebook#cell_at_line(bufnr('%'), 2)
  call assert_equal(['print("hello")'], jusi#notebook#cell_main_lines(l:cell))
endfunction

function! Test_adapter_builds_shutdown_client_request_envelope() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let b:jusi_nb.session.id = 'sess-1'
  let l:cell = b:jusi_nb.cells[0]
  let l:request = jusi#adapter#build_request('shutdown_client', bufnr('%'), {
        \ 'cell': l:cell,
        \ 'client_id': 'client-1',
        \ 'reason': 'user_close',
        \ })
  call assert_equal('shutdown_client', l:request.type)
  call assert_equal('nb-' . bufnr('%'), l:request.payload.notebook_id)
  call assert_equal('sess-1', l:request.payload.session_id)
  call assert_equal(l:cell.id, l:request.payload.cell_id)
  call assert_equal('client-1', l:request.payload.client_id)
  call assert_equal('user_close', l:request.payload.reason)
endfunction

function! Test_adapter_builds_inspect_client_request_envelope() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let b:jusi_nb.session.id = 'sess-1'
  let l:request = jusi#adapter#build_request('inspect_client', bufnr('%'), {
        \ 'client_id': 'client-1',
        \ })
  call assert_equal('inspect_client', l:request.type)
  call assert_equal('nb-' . bufnr('%'), l:request.payload.notebook_id)
  call assert_equal('sess-1', l:request.payload.session_id)
  call assert_equal('client-1', l:request.payload.client_id)
endfunction

function! Test_adapter_request_handler_receives_protocol_envelope() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'request': function('s:test_request_adapter')}
    let s:last_request_envelope = {}
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('python3')
    call assert_equal('start_session', get(s:last_request_envelope, 'type', ''))
    call assert_equal('request', get(s:last_request_envelope, 'kind', ''))
    call assert_equal('nb-' . bufnr('%'), get(get(s:last_request_envelope, 'payload', {}), 'notebook_id', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_transport_handler_receives_protocol_envelope() abort
  let l:save_handler = get(g:, 'jusi_transport_handler', 0)
  try
    let g:jusi_transport_handler = 'TestTransportHandler'
    let s:last_request_envelope = {}
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('python3')
    call assert_equal('start_session', get(s:last_request_envelope, 'type', ''))
    call assert_equal('request', get(s:last_request_envelope, 'kind', ''))
    call assert_equal('nb-' . bufnr('%'), get(get(s:last_request_envelope, 'payload', {}), 'notebook_id', ''))
  finally
    let g:jusi_transport_handler = l:save_handler
  endtry
endfunction

function! Test_start_kernel_uses_adapter_and_records_connected_session() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'start': function('s:test_session_adapter_start')}
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('python3')
    let l:session = jusi#session#state()
    call assert_equal('connected', l:session.state)
    call assert_equal('sess-start-1', l:session.id)
    call assert_equal('mock', l:session.backend)
    call assert_equal('python3', l:session.kernel_name)
    call assert_equal('mock://kernel/python3', l:session.connection)
    call assert_equal('start', l:session.target.source)
    call assert_equal('python3', l:session.target.alias)
    call assert_equal('kernel', l:session.target.kind)
    call assert_equal('', l:session.target.value)
    call assert_equal('start', l:session.last_action)
    call assert_equal('', l:session.last_error)
    call assert_equal('client-1', l:session.prepared.id)
    call assert_equal('binding', l:session.prepared.state)
    call assert_equal(-1, l:session.prepared.bufnr)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_start_kernel_request_includes_resolved_target() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:save_targets = get(g:, 'jusi_kernel_targets', {})
  try
    let g:jusi_session_adapter = {'request': function('s:test_request_adapter')}
    let g:jusi_kernel_targets = {
          \ 'py': {
          \   'kind': 'venv',
          \   'connection': 'venv://myenv1',
          \   'label': 'local venv',
          \   },
          \ }
    let s:last_request_envelope = {}
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('py')
    call assert_equal('start_session', get(s:last_request_envelope, 'type', ''))
    call assert_equal('py', get(get(get(s:last_request_envelope, 'payload', {}), 'target', {}), 'alias', ''))
    call assert_equal('venv', get(get(get(s:last_request_envelope, 'payload', {}), 'target', {}), 'kind', ''))
    call assert_equal('venv://myenv1', get(get(get(s:last_request_envelope, 'payload', {}), 'target', {}), 'value', ''))
    call assert_equal('local venv', get(get(get(get(s:last_request_envelope, 'payload', {}), 'target', {}), 'config', {}), 'label', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_kernel_targets = l:save_targets
  endtry
endfunction

function! Test_start_kernel_alias_resolves_explicit_target_state() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:save_targets = get(g:, 'jusi_kernel_targets', {})
  try
    let g:jusi_session_adapter = {'start': function('s:test_session_adapter_start')}
    let g:jusi_kernel_targets = {'py': 'venv://myenv1'}
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('py')
    let l:target = jusi#session#target()
    call assert_equal('start', l:target.source)
    call assert_equal('py', l:target.alias)
    call assert_equal('venv', l:target.kind)
    call assert_equal('venv://myenv1', l:target.value)
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_kernel_targets = l:save_targets
  endtry
endfunction

function! Test_start_kernel_alias_preserves_dict_target_config() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:save_targets = get(g:, 'jusi_kernel_targets', {})
  try
    let g:jusi_session_adapter = {'start': function('s:test_session_adapter_start')}
    let g:jusi_kernel_targets = {
          \ 'py': {
          \   'kind': 'docker+ssh',
          \   'connection': 'docker+ssh://user@host2/container3',
          \   'label': 'remote container',
          \   },
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('py')
    let l:target = jusi#session#target()
    call assert_equal('docker+ssh', l:target.kind)
    call assert_equal('docker+ssh://user@host2/container3', l:target.value)
    call assert_equal('remote container', get(l:target.config, 'label', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_kernel_targets = l:save_targets
  endtry
endfunction

function! Test_start_kernel_persists_attach_registry_entry_for_durable_session() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:save_registry = get(g:, 'jusi_attach_registry_file', '')
  try
    let g:jusi_session_adapter = {'start': function('s:test_session_adapter_start')}
    let g:jusi_attach_registry_file = tempname()
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    file project-start.vipynb
    call jusi#session#start('python3')
    let l:registry = jusi#session#attach_registry()
    call assert_true(has_key(l:registry, 'project-start-kernel-start-1'))
    call assert_equal('sess-start-1', get(l:registry['project-start-kernel-start-1'], 'session_id', ''))
    call assert_equal('kernel', get(get(l:registry['project-start-kernel-start-1'], 'target', {}), 'kind', ''))
    call assert_equal('project-start-kernel-start-1', get(jusi#session#state(), 'attach_name', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_attach_registry_file = l:save_registry
  endtry
endfunction

function! Test_attach_records_explicit_target_state() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'attach': function('s:test_session_adapter_attach')}
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#attach('ssh://user@host1')
    let l:session = jusi#session#state()
    call assert_equal('connected', l:session.state)
    call assert_equal('attach', l:session.target.source)
    call assert_equal('ssh', l:session.target.kind)
    call assert_equal('ssh://user@host1', l:session.target.value)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_attach_connection_file_uses_explicit_target_kind() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:save_registry = get(g:, 'jusi_attach_registry_file', '')
  try
    let g:jusi_session_adapter = {'request': function('s:test_request_adapter')}
    let g:jusi_attach_registry_file = tempname()
    let s:last_request_envelope = {}
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#attach('/tmp/kernel-123.json')
    call assert_equal('attach_session', get(s:last_request_envelope, 'type', ''))
    call assert_equal('attach', get(get(get(s:last_request_envelope, 'payload', {}), 'target', {}), 'source', ''))
    call assert_equal('connection_file', get(get(get(s:last_request_envelope, 'payload', {}), 'target', {}), 'kind', ''))
    call assert_equal('/tmp/kernel-123.json', get(get(get(s:last_request_envelope, 'payload', {}), 'target', {}), 'value', ''))
    call assert_equal('connection_file', get(get(b:jusi_nb.session, 'target', {}), 'kind', ''))
    call assert_equal('/tmp/kernel-123.json', get(get(b:jusi_nb.session, 'target', {}), 'value', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_attach_registry_file = l:save_registry
  endtry
endfunction

function! Test_attach_connection_file_persists_generated_registry_alias() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:save_registry = get(g:, 'jusi_attach_registry_file', '')
  try
    let g:jusi_session_adapter = {'attach': function('s:test_session_adapter_attach')}
    let g:jusi_attach_registry_file = tempname()
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    file project-a.vipynb
    call jusi#session#attach('/tmp/kernel-abc.json')
    let l:target = jusi#session#target()
    let l:registry = jusi#session#attach_registry()
    call assert_true(has_key(l:registry, 'project-a-kernel-attach-1'))
    call assert_equal('sess-attach-1', get(l:registry['project-a-kernel-attach-1'], 'session_id', ''))
    call assert_equal('kernel-attach-1', get(l:registry['project-a-kernel-attach-1'], 'kernel_id', ''))
    call assert_equal('/tmp/kernel-abc.json', get(get(l:registry['project-a-kernel-attach-1'], 'target', {}), 'value', ''))
    call assert_equal('connection_file', get(get(l:registry['project-a-kernel-attach-1'], 'target', {}), 'kind', ''))
    call assert_equal('attach', l:target.source)
    call assert_equal('project-a-kernel-attach-1', get(jusi#session#state(), 'attach_name', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_attach_registry_file = l:save_registry
  endtry
endfunction

function! Test_attach_connection_file_does_not_persist_registry_alias_without_session_id() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:save_registry = get(g:, 'jusi_attach_registry_file', '')
  try
    let g:jusi_session_adapter = {'attach': function('s:test_session_adapter_attach_without_ids')}
    let g:jusi_attach_registry_file = tempname()
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    file project-b.vipynb
    call jusi#session#attach('/tmp/kernel-noid.json')
    let l:registry = jusi#session#attach_registry()
    call assert_equal({}, l:registry)
    call assert_equal('', get(jusi#session#state(), 'attach_name', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_attach_registry_file = l:save_registry
  endtry
endfunction

function! Test_attach_connection_file_does_not_persist_registry_alias_before_backend_success() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:save_registry = get(g:, 'jusi_attach_registry_file', '')
  try
    let g:jusi_session_adapter = {'attach': function('s:test_session_adapter_reconnect_error')}
    let g:jusi_attach_registry_file = tempname()
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#attach('/tmp/kernel-persist.json')
    let l:registry = jusi#session#attach_registry()
    call assert_equal({}, l:registry)
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_attach_registry_file = l:save_registry
  endtry
endfunction

function! Test_attach_registry_alias_resolves_to_connection_file_target() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:save_registry = get(g:, 'jusi_attach_registry_file', '')
  try
    let g:jusi_session_adapter = {'request': function('s:test_request_adapter')}
    let g:jusi_attach_registry_file = tempname()
    call writefile(['{"py-remote":{"session_id":"sess-1","kernel_id":"kernel-1","target":{"source":"attach","kind":"connection_file","value":"/tmp/kernel-remote.json","alias":"external-kernel"}}}'], g:jusi_attach_registry_file)
    let s:last_request_envelope = {}
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#attach('py-remote')
    call assert_equal('reconnect_session', get(s:last_request_envelope, 'type', ''))
    call assert_equal('sess-1', get(get(s:last_request_envelope, 'payload', {}), 'session_id', ''))
    call assert_equal('py-remote', get(jusi#session#state(), 'attach_name', ''))
    call assert_equal('connection_file', get(jusi#session#target(), 'kind', ''))
    call assert_equal('/tmp/kernel-remote.json', get(jusi#session#target(), 'value', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_attach_registry_file = l:save_registry
  endtry
endfunction

function! Test_reconnect_terminal_failure_removes_attach_registry_entry() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:save_registry = get(g:, 'jusi_attach_registry_file', '')
  try
    let g:jusi_session_adapter = {
          \ 'reconnect': function('s:test_session_adapter_reconnect_error'),
          \ }
    let g:jusi_attach_registry_file = tempname()
    call writefile(['{"py-remote":{"session_id":"sess-1","kernel_id":"kernel-1","target":{"kind":"connection_file","value":"/tmp/kernel-remote.json","alias":"py-remote"}}}'], g:jusi_attach_registry_file)
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.target = {'source': 'attach', 'alias': 'py-remote', 'kind': 'connection_file', 'value': '/tmp/kernel-remote.json', 'config': {}}
    call jusi#session#set_disconnected()
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.target = {'source': 'attach', 'alias': 'py-remote', 'kind': 'connection_file', 'value': '/tmp/kernel-remote.json', 'config': {}}
    call jusi#session#reconnect()
    call assert_equal({}, jusi#session#attach_registry())
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_attach_registry_file = l:save_registry
  endtry
endfunction

function! Test_session_callback_updates_expires_at() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call jusi#session#callback_session({'state': 'disconnected', 'expires_at': '2030-01-01T00:00:00Z'})
  call assert_equal('disconnected', b:jusi_nb.session.state)
  call assert_equal('2030-01-01T00:00:00Z', b:jusi_nb.session.expires_at)
endfunction

function! Test_execute_requires_connected_session() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call jusi#session#execute_current()
  call assert_equal('failed', b:jusi_nb.session.state)
  call assert_match('Cannot execute cell without a connected session', b:jusi_nb.session.last_error)
  call assert_equal('initial', b:jusi_nb.cells[0].status)
endfunction

function! Test_execute_requires_prepared_client_buffer() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'start': function('s:test_session_adapter_start')}
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('python3')
    let b:jusi_nb.session.prepared = {'state': 'missing', 'bufnr': -1}
    call jusi#session#execute_current()
    call assert_equal('failed', b:jusi_nb.session.state)
    call assert_match('Cannot execute cell without a prepared client buffer', b:jusi_nb.session.last_error)
    call assert_equal('initial', b:jusi_nb.cells[0].status)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_prepared_binding_event_creates_local_buffer_and_sends_bind_ack() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'bind_prepared_client': function('s:test_session_adapter_bind_prepared'),
          \ }
    let s:last_bound_prepared = {}
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('python3')
    call jusi#session#callback_prepared({'id': 'client-1', 'state': 'binding', 'bufnr': -1})
    call assert_equal('binding', b:jusi_nb.session.prepared.state)
    call assert_match('^client-1$', get(s:last_bound_prepared, 'client_id', ''))
    call assert_true(get(s:last_bound_prepared, 'client_bufnr', -1) > 0)
    call assert_equal(s:last_bound_prepared.client_bufnr, b:jusi_nb.session.prepared.bufnr)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_prepared_replacement_allocates_new_local_buffer_and_keeps_client_identity() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'bind_prepared_client': function('s:test_session_adapter_bind_prepared'),
          \ }
    let s:last_bound_prepared = {}
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('python3')
    let l:prepared = jusi#client#create_prepared_buffer(bufnr('%'), 'client-1')
    call jusi#session#apply_prepared({'id': 'client-1', 'state': 'ready', 'client_state': 'active', 'bufnr': l:prepared})
    call jusi#session#callback_prepared({'id': 'client-2', 'state': 'binding', 'bufnr': -1})
    call assert_equal('client-2', b:jusi_nb.session.prepared.id)
    call assert_equal('binding', b:jusi_nb.session.prepared.state)
    call assert_true(b:jusi_nb.session.prepared.bufnr > 0)
    call assert_notequal(l:prepared, b:jusi_nb.session.prepared.bufnr)
    call assert_false(bufexists(l:prepared))
    call assert_equal(b:jusi_nb.session.prepared.bufnr, get(s:last_bound_prepared, 'client_bufnr', -1))
    call assert_equal('client-2', get(s:last_bound_prepared, 'client_id', ''))
    call assert_equal('client-2', getbufvar(b:jusi_nb.session.prepared.bufnr, 'jusi_client_id', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_execute_consumes_ready_prepared_buffer_and_starts_replacement_binding() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'bind_prepared_client': function('s:test_session_adapter_bind_prepared'),
          \ 'execute': function('s:test_session_adapter_execute'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('python3')
    let l:prepared = jusi#client#create_prepared_buffer(bufnr('%'), 'client-1')
    call jusi#session#apply_prepared({'id': 'client-1', 'state': 'ready', 'client_state': 'active', 'bufnr': l:prepared})
    call jusi#session#execute_current()
    call assert_equal('connected', b:jusi_nb.session.state)
    call assert_equal('client-2', b:jusi_nb.session.prepared.id)
    call assert_equal('binding', b:jusi_nb.session.prepared.state)
    call assert_equal(-1, b:jusi_nb.session.prepared.bufnr)
    call assert_equal('busy', b:jusi_nb.cells[0].status)
    call assert_true(bufexists(l:prepared))
    call assert_equal(l:prepared, b:jusi_nb.cells[0].client_bufnr)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_transport_execute_consumes_prepared_buffer_locally_before_async_updates() abort
  let l:save_handler = get(g:, 'jusi_transport_handler', 0)
  try
    let g:jusi_transport_handler = 'TestTransportHandler'
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    let l:prepared = jusi#client#create_prepared_buffer(bufnr('%'), 'client-1')
    call jusi#session#apply({'id': 'sess-1', 'state': 'connected'})
    call jusi#session#apply_prepared({'id': 'client-1', 'state': 'ready', 'client_state': 'active', 'bufnr': l:prepared})
    let s:last_request_envelope = {}
    call jusi#session#execute_current()
    call assert_equal('execute_cell', get(s:last_request_envelope, 'type', ''))
    call assert_equal('busy', b:jusi_nb.cells[0].status)
    call assert_equal('client-1', b:jusi_nb.cells[0].client_id)
    call assert_equal('active', b:jusi_nb.cells[0].client_state)
    call assert_true(bufexists(l:prepared))
    call assert_equal(l:prepared, b:jusi_nb.cells[0].client_bufnr)
    call assert_equal('missing', b:jusi_nb.session.prepared.state)
    call assert_equal(-1, b:jusi_nb.session.prepared.bufnr)
  finally
    call jusi#transport#stop(bufnr('%'))
    let g:jusi_transport_handler = l:save_handler
  endtry
endfunction

function! Test_execute_failure_preserves_prepared_and_cell_runtime_state() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'execute': function('s:test_session_adapter_execute_failure'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('python3')
    let l:prepared = jusi#client#create_prepared_buffer(bufnr('%'), 'client-1')
    call jusi#session#apply_prepared({'id': 'client-1', 'state': 'ready', 'client_state': 'active', 'bufnr': l:prepared})
    call jusi#session#execute_current()
    call assert_equal('failed', b:jusi_nb.session.state)
    call assert_match('mock execute failure', b:jusi_nb.session.last_error)
    call assert_equal('client-1', b:jusi_nb.session.prepared.id)
    call assert_equal('ready', b:jusi_nb.session.prepared.state)
    call assert_equal(l:prepared, b:jusi_nb.session.prepared.bufnr)
    call assert_equal('initial', b:jusi_nb.cells[0].status)
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_interrupt_allows_followup_cells() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'interrupt': function('s:test_session_adapter_interrupt'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ '%%sql main',
          \ 'select 1',
          \ ])
    call jusi#session#start('python3')
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_bufnr = 91
    call jusi#session#interrupt_current()
    call assert_equal('connected', b:jusi_nb.session.state)
    call assert_equal('interrupt', b:jusi_nb.session.last_action)
    call assert_equal('interrupted', b:jusi_nb.cells[0].status)
    call assert_equal('handler', get(get(b:jusi_nb.cells[0], 'owner', {}), 'kind', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_close_client_resets_terminal_cell_state_and_destroys_buffer() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'shutdown_client': function('s:test_session_adapter_shutdown_client'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('python3')
    let l:client = jusi#client#create_prepared_buffer(bufnr('%'), 'client-done')
    let b:jusi_nb.cells[0].status = 'done'
    let b:jusi_nb.cells[0].client_id = 'client-done'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    let b:jusi_nb.cells[0].owner = {'kind': 'kernel'}
    call jusi#session#close_current_client()
    call assert_false(bufexists(l:client))
    call assert_equal('done', b:jusi_nb.cells[0].status)
    call assert_equal('client-done', b:jusi_nb.cells[0].client_id)
    call assert_equal('shutdown', b:jusi_nb.cells[0].client_state)
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
    call assert_equal('kernel', get(get(b:jusi_nb.cells[0], 'owner', {}), 'kind', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_close_client_uses_shutdown_client_for_followup_cells() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'shutdown_client': function('s:test_session_adapter_shutdown_client'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ '%%sql main',
          \ 'select 1',
          \ ])
    call jusi#session#start('python3')
    let l:client = jusi#client#create_prepared_buffer(bufnr('%'), 'client-1')
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    call jusi#session#close_current_client()
    call assert_false(bufexists(l:client))
    call assert_equal('follow-up', b:jusi_nb.cells[0].status)
    call assert_equal('client-1', b:jusi_nb.cells[0].client_id)
    call assert_equal('shutdown', b:jusi_nb.cells[0].client_state)
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
    call assert_equal('handler', get(get(b:jusi_nb.cells[0], 'owner', {}), 'kind', ''))
    call assert_equal(0, get(b:jusi_nb.cells[0], 'close_requested', 0))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_close_client_transport_response_closes_local_followup_buffer() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'request': function('s:test_transport_like_request_adapter')}
    let s:last_request_envelope = {}
    let s:request_envelopes = []
    call Test_open_scratch([
          \ '##',
          \ '%%vd pods',
          \ ])
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'
    let l:client = jusi#client#create_prepared_buffer(bufnr('%'), 'client-1')
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    call jusi#client#mark_attached_buffer(bufnr('%'), b:jusi_nb.cells[0].id, 'client-1', l:client)

    call jusi#session#close_current_client()

    call assert_true(bufexists(l:client))
    call assert_equal('detached', getbufvar(l:client, 'jusi_client_role', ''))
    call assert_equal(0, getbufvar(l:client, 'jusi_client_cell_id', -1))
    call assert_equal('follow-up', b:jusi_nb.cells[0].status)
    call assert_equal('client-1', b:jusi_nb.cells[0].client_id)
    call assert_equal('shutdown', b:jusi_nb.cells[0].client_state)
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
    call assert_equal(0, get(b:jusi_nb.cells[0], 'close_requested', 0))
    call assert_equal('shutdown_client', get(s:last_request_envelope, 'type', ''))
    call assert_equal('user_close', get(s:last_request_envelope, 'payload', {}).reason)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_close_client_transport_response_closes_visible_native_terminal_buffer() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'request': function('s:test_transport_like_request_adapter')}
    let s:last_request_envelope = {}
    let s:request_envelopes = []
    call Test_open_scratch([
          \ '##',
          \ '%%vd pods',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'
    let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
    call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)
    call setbufvar(l:client, 'jusi_client_transport_kind', 'native_terminal')
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    call jusi#focus#place_client_buffer(l:client, 'bsplit', 1)

    call jusi#session#close_current_client()

    call assert_true(bufexists(l:client))
    call assert_equal('detached', getbufvar(l:client, 'jusi_client_role', ''))
    call assert_equal(0, getbufvar(l:client, 'jusi_client_cell_id', -1))
    call assert_equal(-1, bufwinid(l:client))
    call assert_equal('shutdown', b:jusi_nb.cells[0].client_state)
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
    call assert_equal(0, get(b:jusi_nb.cells[0], 'close_requested', 0))
    call assert_equal('shutdown_client', get(s:last_request_envelope, 'type', ''))
    call assert_equal('user_close', get(s:last_request_envelope, 'payload', {}).reason)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_toggle_park_marks_terminal_client_and_restores_status() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let l:client = jusi#client#create_prepared_buffer(bufnr('%'), 'client-done')
  let b:jusi_nb.cells[0].status = 'done'
  let b:jusi_nb.cells[0].client_id = 'client-done'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  call jusi#session#toggle_park_current_client()
  call assert_equal('parked', b:jusi_nb.cells[0].status)
  call assert_equal('done', get(b:jusi_nb.cells[0], 'parked_status', ''))
  call assert_equal(l:client, b:jusi_nb.cells[0].client_bufnr)
  call jusi#session#toggle_park_current_client()
  call assert_equal('done', b:jusi_nb.cells[0].status)
  call assert_equal('', get(b:jusi_nb.cells[0], 'parked_status', ''))
  call assert_equal(l:client, b:jusi_nb.cells[0].client_bufnr)
endfunction

function! Test_toggle_park_rejects_followup_clients() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ ])
  let l:client = jusi#client#create_prepared_buffer(bufnr('%'), 'client-1')
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  call jusi#session#toggle_park_current_client()
  call assert_equal('failed', b:jusi_nb.session.state)
  call assert_match('Cannot park a busy or follow-up client', b:jusi_nb.session.last_error)
  call assert_equal('follow-up', b:jusi_nb.cells[0].status)
  call assert_equal(l:client, b:jusi_nb.cells[0].client_bufnr)
endfunction

function! Test_toggle_focus_opens_current_cell_client_buffer() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let l:cell_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_prepared_buffer(bufnr('%'), 'client-1')
  let b:jusi_nb.cells[0].status = 'done'
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  call jusi#client#mark_attached_buffer(bufnr('%'), l:cell_id, 'client-1', l:client)
  call cursor(2, 1)
  call jusi#focus#toggle()
  call assert_equal(l:client, bufnr('%'))
  call assert_equal(2, winnr('$'))
endfunction

function! Test_toggle_focus_returns_from_client_to_notebook_cell() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("one")',
        \ '##',
        \ 'print("two")',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[1].id
  let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-2')
  let b:jusi_nb.cells[1].status = 'done'
  let b:jusi_nb.cells[1].client_id = 'client-2'
  let b:jusi_nb.cells[1].client_state = 'active'
  let b:jusi_nb.cells[1].client_bufnr = l:client
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-2', l:client)
  call cursor(4, 1)
  call jusi#focus#toggle()
  call assert_equal(l:client, bufnr('%'))
  call jusi#focus#toggle()
  call assert_equal(l:notebook, bufnr('%'))
  call assert_equal(l:cell_id, b:jusi_nb.cells[1].id)
  call assert_equal(4, line('.'))
endfunction

function! Test_toggle_focus_recovers_stale_cell_client_bufnr_from_managed_client_metadata() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd pods',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  let l:client = bufadd('!jusi-native-terminal-recovered')
  call bufload(l:client)
  call setbufvar(l:client, '&buftype', 'terminal')
  call setbufvar(l:client, '&bufhidden', 'hide')
  call setbufvar(l:client, '&swapfile', 0)
  call setbufline(l:client, 1, ['terminal attached'])
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)
  call setbufvar(l:client, 'jusi_client_transport_kind', 'native_terminal')
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = 99999

  call cursor(2, 1)
  call jusi#focus#toggle()

  call assert_equal(l:client, bufnr('%'))
  call assert_equal(l:client, b:jusi_nb.cells[0].client_bufnr)
endfunction

function! Test_cell_callback_recovers_stale_attached_client_bufnr_from_managed_client_metadata() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd pods',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  let l:client = bufadd('!jusi-native-terminal-recovered-callback')
  call bufload(l:client)
  call setbufvar(l:client, '&buftype', 'terminal')
  call setbufvar(l:client, '&bufhidden', 'hide')
  call setbufvar(l:client, '&swapfile', 0)
  call setbufline(l:client, 1, ['terminal attached'])
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)
  call setbufvar(l:client, 'jusi_client_transport_kind', 'native_terminal')
  call jusi#session#apply({'state': 'connected', 'id': 'sess-1'})
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = 99999

  call jusi#session#callback_cell(l:cell_id, {})

  call assert_equal(l:client, b:jusi_nb.cells[0].client_bufnr)
  call assert_equal('active', b:jusi_nb.cells[0].client_state)
  call assert_equal('', get(b:jusi_nb.session, 'last_error', ''))
endfunction

function! Test_cell_callback_places_attached_client_in_default_split_and_returns_focus() abort
  let l:save_layout = get(g:, 'jusi_client_layout', 'bsplit')
  try
    let g:jusi_client_layout = 'bsplit'
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let l:notebook_win = win_getid()
    let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
    call jusi#session#callback_cell(l:cell_id, {
          \ 'status': 'done',
          \ 'client_id': 'client-1',
          \ 'client_state': 'active',
          \ 'client_bufnr': l:client,
          \ })
    call assert_equal(l:notebook, bufnr('%'))
    call assert_equal(l:notebook_win, win_getid())
    call assert_equal(2, winnr('$'))
    call assert_equal(l:client, winbufnr(2))
  finally
    let g:jusi_client_layout = l:save_layout
  endtry
endfunction

function! Test_cell_callback_places_attached_client_in_tab_layout() abort
  let l:save_layout = get(g:, 'jusi_client_layout', 'bsplit')
  try
    let g:jusi_client_layout = 'tab'
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let l:notebook_tab = tabpagenr()
    let l:notebook_win = win_getid()
    let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
    call jusi#session#callback_cell(l:cell_id, {
          \ 'status': 'done',
          \ 'client_id': 'client-1',
          \ 'client_state': 'active',
          \ 'client_bufnr': l:client,
          \ })
    call assert_equal(l:notebook, bufnr('%'))
    call assert_equal(l:notebook_win, win_getid())
    call assert_equal(l:notebook_tab, tabpagenr())
    call assert_equal(2, tabpagenr('$'))
  finally
    let g:jusi_client_layout = l:save_layout
  endtry
endfunction

function! Test_client_refresh_attached_view_renders_inspect_snapshot() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'inspect_client': function('s:test_session_adapter_inspect_client')}
    let s:inspect_client_calls = 0
    let s:inspect_client_response = {
          \ 'revision': 1,
          \ 'title': 'cell 1: done',
          \ 'lines': ['hello from backend', 'second line'],
          \ 'execution_status': 'done',
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'
    let b:jusi_nb.cells[0].status = 'done'
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)

    call jusi#client#refresh_attached_view(l:notebook, l:cell_id, 'client-1', l:client)
    call assert_equal(['hello from backend', 'second line'], getbufline(l:client, 1, '$'))
    call assert_equal(1, getbufvar(l:client, 'jusi_client_revision', -1))
    call assert_equal('done', getbufvar(l:client, 'jusi_client_execution_status', ''))

    let s:inspect_client_response = {
          \ 'revision': 1,
          \ 'title': 'cell 1: changed',
          \ 'lines': ['should not replace'],
          \ 'execution_status': 'done',
          \ }
    call jusi#client#refresh_attached_view(l:notebook, l:cell_id, 'client-1', l:client)
    call assert_equal(['hello from backend', 'second line'], getbufline(l:client, 1, '$'))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_client_refresh_attached_view_rebinds_native_terminal_transport() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:save_launcher = get(g:, 'jusi_native_terminal_launcher', 0)
  try
    let g:jusi_session_adapter = {
          \ 'inspect_client': function('s:test_session_adapter_inspect_client'),
          \ 'request': function('s:test_request_adapter'),
          \ }
    let g:jusi_native_terminal_launcher = function('s:test_native_terminal_launcher')
    let s:inspect_client_calls = 0
    let s:native_terminal_launches = []
    let s:request_envelopes = []
    let s:inspect_client_response = {
          \ 'revision': 1,
          \ 'title': 'vd',
          \ 'lines': [],
          \ 'execution_status': 'follow-up',
          \ 'transport': {
          \   'kind': 'native_terminal',
          \   'attach_cmd': ['python', '-m', 'jusi', 'client-process', 'terminal-attach'],
          \   'attach_env': {
          \     'JUSI_SESSION_ID': 'sess-1',
          \     'JUSI_CLIENT_ID': 'client-1',
          \     'JUSI_HANDLER_ID': 'vd',
          \     },
          \   'session_id': 'sess-1',
          \   'client_id': 'client-1',
          \   'handler_id': 'vd',
          \   },
          \ }
    call Test_open_scratch([
          \ '##',
          \ '%%vd pods',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    let b:jusi_nb.cells[0].handler = {'id': 'vd', 'last_message_type': 'handler_snapshot', 'payload': {}, 'snapshot': {'transport': 'native_terminal'}}
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)

    call jusi#client#refresh_attached_view(l:notebook, l:cell_id, 'client-1', l:client)

    call assert_equal(1, len(s:native_terminal_launches))
    let l:new_client = get(b:jusi_nb.cells[0], 'client_bufnr', -1)
    call assert_notequal(l:client, l:new_client)
    call assert_equal('native_terminal', getbufvar(l:new_client, 'jusi_client_transport_kind', ''))
    call assert_equal('client-1', getbufvar(l:new_client, 'jusi_client_id', ''))
    call assert_equal('sess-1', get(getbufvar(l:new_client, 'jusi_client_transport', {}), 'session_id', ''))
    call assert_equal([], s:request_envelopes)
    call assert_false(bufexists(l:client))
  finally
    let g:jusi_session_adapter = l:save_adapter
    if type(l:save_launcher) == type(function('tr'))
      let g:jusi_native_terminal_launcher = l:save_launcher
    else
      unlet! g:jusi_native_terminal_launcher
    endif
  endtry
endfunction

function! Test_client_updated_event_schedules_inspect_refresh_for_matching_attached_client() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'inspect_client': function('s:test_session_adapter_inspect_client')}
    let s:inspect_client_calls = 0
    let s:inspect_client_response = {
          \ 'revision': 2,
          \ 'title': 'cell 1: done',
          \ 'lines': ['push invalidation refresh'],
          \ 'execution_status': 'done',
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'
    let b:jusi_nb.cells[0].status = 'done'
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)
    call setbufvar(l:client, 'jusi_client_revision', 1)

    call jusi#transport#receive(l:notebook, {
          \ 'kind': 'event',
          \ 'type': 'client_updated',
          \ 'version': 1,
          \ 'payload': {
          \   'notebook_id': 'nb-' . l:notebook,
          \   'session_id': 'sess-1',
          \   'client_id': 'client-1',
          \   'revision': 2,
          \   },
          \ })

    call Test_wait_until({-> getbufline(l:client, 1, '$') == ['push invalidation refresh']}, 500)
    call assert_equal(['push invalidation refresh'], getbufline(l:client, 1, '$'))
    call assert_true(s:inspect_client_calls >= 1)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_client_updated_event_ignores_mismatched_or_already_current_revision() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'inspect_client': function('s:test_session_adapter_inspect_client')}
    let s:inspect_client_calls = 0
    let s:inspect_client_response = {
          \ 'revision': 2,
          \ 'title': 'cell 1: done',
          \ 'lines': ['should not be used'],
          \ 'execution_status': 'done',
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'
    let b:jusi_nb.cells[0].status = 'done'
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)
    call setbufline(l:client, 1, ['existing content'])
    call setbufvar(l:client, 'jusi_client_revision', 2)

    call jusi#transport#receive(l:notebook, {
          \ 'kind': 'event',
          \ 'type': 'client_updated',
          \ 'version': 1,
          \ 'payload': {
          \   'notebook_id': 'nb-' . l:notebook,
          \   'session_id': 'sess-2',
          \   'client_id': 'client-1',
          \   'revision': 3,
          \   },
          \ })
    sleep 30m
    call assert_equal(0, s:inspect_client_calls)
    call assert_equal(['existing content'], getbufline(l:client, 1, '$'))

    call jusi#transport#receive(l:notebook, {
          \ 'kind': 'event',
          \ 'type': 'client_updated',
          \ 'version': 1,
          \ 'payload': {
          \   'notebook_id': 'nb-' . l:notebook,
          \   'session_id': 'sess-1',
          \   'client_id': 'client-1',
          \   'revision': 2,
          \   },
          \ })
    sleep 30m
    call assert_equal(0, s:inspect_client_calls)
    call assert_equal(['existing content'], getbufline(l:client, 1, '$'))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_client_updated_event_skips_inspect_pull_for_handler_client() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'inspect_client': function('s:test_session_adapter_inspect_client')}
    let s:inspect_client_calls = 0
    call Test_open_scratch([
          \ '##',
          \ '%%vd pods',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    let b:jusi_nb.cells[0].handler = {'id': 'vd', 'last_message_type': 'handler_snapshot', 'payload': {}, 'snapshot': {'transport': 'native_terminal'}}
    call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)

    call jusi#transport#receive(l:notebook, {
          \ 'kind': 'event',
          \ 'type': 'client_updated',
          \ 'version': 1,
          \ 'payload': {
          \   'notebook_id': 'nb-' . l:notebook,
          \   'session_id': 'sess-1',
          \   'client_id': 'client-1',
          \   'revision': 2,
          \   },
          \ })
    sleep 30m
    call assert_equal(0, s:inspect_client_calls)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_handler_cell_update_skips_scheduled_refresh_for_handler_client() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'inspect_client': function('s:test_session_adapter_inspect_client')}
    let s:inspect_client_calls = 0
    call Test_open_scratch([
          \ '##',
          \ '%%vd pods',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    let b:jusi_nb.cells[0].handler = {'id': 'vd', 'last_message_type': 'handler_snapshot', 'payload': {}, 'snapshot': {'transport': 'native_terminal'}}
    call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)

    call jusi#session#callback_cell(l:cell_id, {'status': 'follow-up'})
    sleep 30m
    call assert_equal(0, s:inspect_client_calls)
    call assert_equal(-1, getbufvar(l:client, 'jusi_client_refresh_timer', -1))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_handler_snapshot_updates_state_and_stops_existing_refresh_timer() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd pods',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
  let b:jusi_nb.session.id = 'sess-1'
  let b:jusi_nb.session.state = 'connected'
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  let b:jusi_nb.cells[0].handler = {'id': 'vd', 'last_message_type': 'handler_snapshot', 'payload': {}, 'snapshot': {'transport': 'inspect'}}
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)
  call setbufvar(l:client, 'jusi_client_refresh_timer', 17)

  call jusi#transport#receive(l:notebook, {
        \ 'kind': 'event',
        \ 'type': 'handler_message',
        \ 'version': 1,
        \ 'payload': {
        \   'notebook_id': 'nb-' . l:notebook,
        \   'session_id': 'sess-1',
        \   'client_id': 'client-1',
        \   'handler_id': 'vd',
        \   'message_type': 'handler_snapshot',
        \   'payload': {'transport': 'native_terminal', 'mode': 'ready'},
        \   },
        \ })

  call assert_equal(-1, getbufvar(l:client, 'jusi_client_refresh_timer', -1))
  call assert_equal('native_terminal', get(get(get(b:jusi_nb.cells[0], 'handler', {}), 'snapshot', {}), 'transport', ''))
endfunction

function! Test_handler_message_event_updates_attached_cell_and_client_buffer_state() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd pods',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
  let b:jusi_nb.session.id = 'sess-1'
  let b:jusi_nb.session.state = 'connected'
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)

  call jusi#transport#receive(l:notebook, {
        \ 'kind': 'event',
        \ 'type': 'handler_message',
        \ 'version': 1,
        \ 'payload': {
        \   'notebook_id': 'nb-' . l:notebook,
        \   'session_id': 'sess-1',
        \   'client_id': 'client-1',
        \   'handler_id': 'vd',
        \   'message_type': 'handler_snapshot',
        \   'payload': {
        \     'handler_id': 'vd',
        \     'mode': 'browse',
        \     'entry': '%%vd pods',
        \     },
        \   },
        \ })

  call assert_equal('vd', get(get(b:jusi_nb.cells[0], 'handler', {}), 'id', ''))
  call assert_equal('handler_snapshot', get(get(b:jusi_nb.cells[0], 'handler', {}), 'last_message_type', ''))
  call assert_equal('browse', get(get(get(b:jusi_nb.cells[0], 'handler', {}), 'payload', {}), 'mode', ''))
  call assert_equal('browse', get(get(get(b:jusi_nb.cells[0], 'handler', {}), 'snapshot', {}), 'mode', ''))
  call assert_equal('vd', getbufvar(l:client, 'jusi_handler_id', ''))
  call assert_equal('handler_snapshot', getbufvar(l:client, 'jusi_handler_last_message_type', ''))
  call assert_equal('%%vd pods', get(getbufvar(l:client, 'jusi_handler_last_payload', {}), 'entry', ''))
endfunction

function! Test_handler_message_event_ignores_mismatched_session() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd pods',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
  let b:jusi_nb.session.id = 'sess-1'
  let b:jusi_nb.session.state = 'connected'
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)

  call jusi#transport#receive(l:notebook, {
        \ 'kind': 'event',
        \ 'type': 'handler_message',
        \ 'version': 1,
        \ 'payload': {
        \   'notebook_id': 'nb-' . l:notebook,
        \   'session_id': 'sess-2',
        \   'client_id': 'client-1',
        \   'handler_id': 'vd',
        \   'message_type': 'handler_snapshot',
        \   'payload': {'mode': 'browse'},
        \   },
        \ })

  call assert_equal('', get(get(b:jusi_nb.cells[0], 'handler', {}), 'id', ''))
  call assert_equal('', getbufvar(l:client, 'jusi_handler_id', ''))
endfunction

function! Test_send_handler_message_builds_protocol_request() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'request': function('s:test_request_adapter'),
          \ }
    let s:last_request_envelope = {}
    call Test_open_scratch([
          \ '##',
          \ '%%vd pods',
          \ ])
    call jusi#session#apply({
          \ 'state': 'connected',
          \ 'id': 'sess-1',
          \ })
    call jusi#session#send_handler_message('client-1', 'vd', 'terminal_resize', {'rows': 12, 'cols': 40})
    call assert_equal('handler_message', get(s:last_request_envelope, 'type', ''))
    call assert_equal('sess-1', get(get(s:last_request_envelope, 'payload', {}), 'session_id', ''))
    call assert_equal('client-1', get(get(s:last_request_envelope, 'payload', {}), 'client_id', ''))
    call assert_equal('vd', get(get(s:last_request_envelope, 'payload', {}), 'handler_id', ''))
    call assert_equal('terminal_resize', get(get(s:last_request_envelope, 'payload', {}), 'message_type', ''))
    call assert_equal(12, get(get(get(s:last_request_envelope, 'payload', {}), 'payload', {}), 'rows', 0))
    call assert_equal(40, get(get(get(s:last_request_envelope, 'payload', {}), 'payload', {}), 'cols', 0))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_client_window_disables_line_numbers_on_placement() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("x")',
        \ ])
  let l:notebook = bufnr('%')
  setlocal number relativenumber
  let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
  call setbufvar(l:client, 'jusi_client_managed', 1)
  call jusi#focus#place_client_buffer(l:client, 'bsplit', 0)

  call assert_equal(l:client, bufnr('%'))
  call assert_equal(0, &l:number)
  call assert_equal(0, &l:relativenumber)
endfunction

function! Test_send_handler_input_current_builds_send_input_message() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'request': function('s:test_request_adapter'),
          \ }
    let s:last_request_envelope = {}
    call Test_open_scratch([
          \ '##',
          \ '%%vd pods',
          \ ])
    let l:client = jusi#client#create_prepared_buffer(bufnr('%'), 'client-1')
    call jusi#session#apply({'state': 'connected', 'id': 'sess-1'})
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    let b:jusi_nb.cells[0].handler = {'id': 'vd', 'last_message_type': 'handler_snapshot', 'payload': {'mode': 'ready'}}
    call cursor(2, 1)

    call jusi#session#send_handler_input_current('j')
    call assert_equal('handler_message', get(s:last_request_envelope, 'type', ''))
    call assert_equal('send_input', get(get(s:last_request_envelope, 'payload', {}), 'message_type', ''))
    call assert_equal('j', get(get(get(s:last_request_envelope, 'payload', {}), 'payload', {}), 'text', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_cell_callback_schedules_client_view_refresh() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'inspect_client': function('s:test_session_adapter_inspect_client')}
    let s:inspect_client_calls = 0
    let s:inspect_client_response = {
          \ 'revision': 3,
          \ 'title': 'cell 1: done',
          \ 'lines': ['scheduled refresh output'],
          \ 'execution_status': 'done',
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'

    call jusi#session#callback_cell(l:cell_id, {
          \ 'status': 'done',
          \ 'client_id': 'client-1',
          \ 'client_state': 'active',
          \ 'client_bufnr': l:client,
          \ })

    call Test_wait_until({-> getbufline(l:client, 1, '$') == ['scheduled refresh output']}, 500)
    call assert_equal(['scheduled refresh output'], getbufline(l:client, 1, '$'))
    call assert_true(s:inspect_client_calls >= 1)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_busy_client_polling_advances_output_before_terminal_update() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:save_poll_ms = get(g:, 'jusi_client_poll_ms', 150)
  try
    let g:jusi_session_adapter = {'inspect_client': function('s:test_session_adapter_inspect_client')}
    let g:jusi_client_poll_ms = 20
    let s:inspect_client_calls = 0
    let s:inspect_client_sequence = [
          \ {
          \   'revision': 1,
          \   'title': 'cell 1: busy',
          \   'lines': ['started cell 1 [code:python]'],
          \   'execution_status': 'busy',
          \ },
          \ {
          \   'revision': 2,
          \   'title': 'cell 1: busy',
          \   'lines': ['started cell 1 [code:python]', 'stdout> 1'],
          \   'execution_status': 'busy',
          \ },
          \ {
          \   'revision': 3,
          \   'title': 'cell 1: busy',
          \   'lines': ['started cell 1 [code:python]', 'stdout> 1', 'stdout> 2'],
          \   'execution_status': 'busy',
          \ },
          \ ]
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'

    call jusi#session#callback_cell(l:cell_id, {
          \ 'status': 'busy',
          \ 'client_id': 'client-1',
          \ 'client_state': 'active',
          \ 'client_bufnr': l:client,
          \ })

    call Test_wait_until({-> getbufline(l:client, 1, '$') == ['started cell 1 [code:python]', 'stdout> 1', 'stdout> 2']}, 500)
    call assert_equal(['started cell 1 [code:python]', 'stdout> 1', 'stdout> 2'], getbufline(l:client, 1, '$'))
    call assert_true(s:inspect_client_calls >= 3)

    let l:calls_before_done = s:inspect_client_calls
    let s:inspect_client_response = {
          \ 'revision': 4,
          \ 'title': 'cell 1: done',
          \ 'lines': ['started cell 1 [code:python]', 'stdout> 1', 'stdout> 2', 'finished: done'],
          \ 'execution_status': 'done',
          \ }
    call jusi#session#callback_cell(l:cell_id, {'status': 'done'})
    call Test_wait_until({-> getbufline(l:client, 1, '$') == ['started cell 1 [code:python]', 'stdout> 1', 'stdout> 2', 'finished: done']}, 500)
    call assert_equal(['started cell 1 [code:python]', 'stdout> 1', 'stdout> 2', 'finished: done'], getbufline(l:client, 1, '$'))

    sleep 80m
    call assert_true(s:inspect_client_calls <= l:calls_before_done + 1)
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_client_poll_ms = l:save_poll_ms
    let s:inspect_client_sequence = []
  endtry
endfunction

function! Test_client_refresh_tracks_pending_input_from_inspect_snapshot() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'inspect_client': function('s:test_session_adapter_inspect_client')}
    let s:inspect_client_response = {
          \ 'revision': 1,
          \ 'title': 'cell 1: busy',
          \ 'lines': ['started cell 1 [code:python]', 'input> value: '],
          \ 'execution_status': 'busy',
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'
    let b:jusi_nb.cells[0].status = 'busy'
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)

    call jusi#client#refresh_attached_view(l:notebook, l:cell_id, 'client-1', l:client)
    call assert_equal({'prompt': 'value: ', 'password': 0}, get(b:jusi_nb.cells[0], 'pending_input', {}))
    call assert_equal({'prompt': 'value: ', 'password': 0}, getbufvar(l:client, 'jusi_client_pending_input', {}))

    let s:inspect_client_response = {
          \ 'revision': 2,
          \ 'title': 'cell 1: done',
          \ 'lines': ['started cell 1 [code:python]', 'input> value: ', "execute[7]> input('value: ')", 'stdout> typed: answer', 'finished: done'],
          \ 'execution_status': 'done',
          \ }
    call jusi#client#refresh_attached_view(l:notebook, l:cell_id, 'client-1', l:client)
    call assert_equal({}, get(b:jusi_nb.cells[0], 'pending_input', {}))
    call assert_equal({}, getbufvar(l:client, 'jusi_client_pending_input', {}))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_reply_input_current_sends_input_reply_request_and_clears_pending_input() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'input_reply': function('s:test_session_adapter_input_reply')}
    let s:last_input_reply_payload = {}
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    let l:client = jusi#client#create_prepared_buffer(bufnr('%'), 'client-1')
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'
    let b:jusi_nb.cells[0].status = 'busy'
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    let b:jusi_nb.cells[0].pending_input = {'prompt': 'value: ', 'password': 0}

    call jusi#session#reply_input_current('answer')

    call assert_equal(b:jusi_nb.cells[0].id, get(get(s:last_input_reply_payload, 'cell', {}), 'id', 0))
    call assert_equal('client-1', get(s:last_input_reply_payload, 'client_id', ''))
    call assert_equal('answer', get(s:last_input_reply_payload, 'value', ''))
    call assert_equal('input_reply', b:jusi_nb.session.last_action)
    call assert_equal({'cell_id': b:jusi_nb.cells[0].id}, b:jusi_nb.session.request)
    call assert_equal({}, get(b:jusi_nb.cells[0], 'pending_input', {}))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_close_client_requires_attached_buffer() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call jusi#session#close_current_client()
  call assert_equal('failed', b:jusi_nb.session.state)
  call assert_match('Cannot close client without an attached client buffer', b:jusi_nb.session.last_error)
endfunction

function! Test_stop_kernel_moves_local_session_to_stopped() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'stop': function('s:test_session_adapter_stop'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('python3')
    call jusi#session#stop()
    call assert_equal('stopped', b:jusi_nb.session.state)
    call assert_equal('', b:jusi_nb.session.last_error)
    call assert_equal('missing', b:jusi_nb.session.prepared.state)
    call assert_equal(-1, b:jusi_nb.session.prepared.bufnr)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_disconnect_uses_disconnected_state_for_recoverable_link_loss() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call jusi#session#set_disconnected()
  call assert_equal('disconnected', b:jusi_nb.session.state)
  call assert_equal('missing', b:jusi_nb.session.prepared.state)
endfunction

function! Test_notebook_quit_guard_allows_exit_without_active_sessions() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call assert_equal(1, jusi#notebook#guard_quit(0))
endfunction

function! Test_notebook_quit_guard_blocks_normal_exit_with_active_session() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call jusi#session#set_connected()
  try
    call jusi#notebook#guard_quit(0)
    call assert_false(1)
  catch /^jusi-quit-blocked$/
  endtry
endfunction

function! Test_notebook_quit_guard_marks_skip_cleanup_for_forced_exit() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call jusi#session#set_connected()
  call assert_equal(1, jusi#notebook#guard_quit(1))
  call assert_equal(1, getbufvar(bufnr('%'), 'jusi_skip_cleanup_once', 0))
endfunction

function! Test_notebook_wipeout_guard_blocks_normal_wipe_with_active_session() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call jusi#session#set_connected()
  try
    call jusi#notebook#guard_wipeout(bufnr('%'), 0)
    call assert_false(1)
  catch /^jusi-wipeout-blocked$/
  endtry
endfunction

function! Test_notebook_wipeout_guard_marks_skip_cleanup_for_forced_wipe() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call jusi#session#set_connected()
  call assert_equal(1, jusi#notebook#guard_wipeout(bufnr('%'), 1))
  call assert_equal(1, getbufvar(bufnr('%'), 'jusi_skip_cleanup_once', 0))
endfunction

function! Test_cleanup_skips_transport_and_client_shutdown_when_marked_for_abandon() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:save_handler = get(g:, 'jusi_transport_handler', 0)
  try
    let s:shutdown_requests = []
    let g:jusi_session_adapter = {
          \ 'shutdown_client': function('s:test_session_adapter_shutdown_client_record'),
          \ }
    let g:jusi_transport_handler = 'TestTransportHandler'
    let s:last_request_envelope = {}
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#set_connected()
    let b:jusi_nb.session.id = 'sess-1'
    let l:client = jusi#client#create_prepared_buffer(bufnr('%'), 'client-1')
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    call jusi#client#mark_attached_buffer(bufnr('%'), b:jusi_nb.cells[0].id, 'client-1', l:client)
    call setbufvar(bufnr('%'), 'jusi_skip_cleanup_once', 1)
    call jusi#notebook#cleanup(bufnr('%'))
    call assert_equal([], s:shutdown_requests)
    call assert_true(bufexists(l:client))
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_transport_handler = l:save_handler
  endtry
endfunction

function! Test_disconnect_requires_connected_session() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call jusi#session#disconnect()
  call assert_equal('failed', b:jusi_nb.session.state)
  call assert_match('Cannot disconnect unless the session is connected', b:jusi_nb.session.last_error)
endfunction

function! Test_disconnect_connected_session_uses_adapter_and_clears_prepared() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'disconnect': function('s:test_session_adapter_disconnect'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('python3')
    call jusi#session#apply_prepared({'id': 'client-1', 'state': 'ready', 'bufnr': 91})
    call jusi#session#disconnect()
    call assert_equal('disconnected', b:jusi_nb.session.state)
    call assert_equal('disconnect', b:jusi_nb.session.last_action)
    call assert_equal('2030-01-01T00:00:00Z', b:jusi_nb.session.expires_at)
    call assert_equal('missing', b:jusi_nb.session.prepared.state)
    call assert_equal(-1, b:jusi_nb.session.prepared.bufnr)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_reconnect_requires_disconnected_session() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call jusi#session#set_connected()
  call jusi#session#reconnect()
  call assert_equal('failed', b:jusi_nb.session.state)
  call assert_match('Can only reconnect a disconnected session', b:jusi_nb.session.last_error)
endfunction

function! Test_reconnect_disconnected_session_restores_binding_state() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'reconnect': function('s:test_session_adapter_reconnect'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#set_disconnected()
    let b:jusi_nb.session.id = 'sess-1'
    call jusi#session#reconnect()
    call assert_equal('connected', b:jusi_nb.session.state)
    call assert_equal('reconnect', b:jusi_nb.session.last_action)
    call assert_equal('client-2', b:jusi_nb.session.prepared.id)
    call assert_equal('binding', b:jusi_nb.session.prepared.state)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_stop_kernel_moves_disconnected_capable_session_to_stopped() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'stop': function('s:test_session_adapter_stop'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('python3')
    call jusi#session#stop()
    call assert_equal('stopped', b:jusi_nb.session.state)
    call assert_equal('missing', b:jusi_nb.session.prepared.state)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_reconnect_failure_preserves_backend_error_code() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'reconnect': function('s:test_session_adapter_reconnect_error'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#set_disconnected()
    let b:jusi_nb.session.id = 'sess-1'
    call jusi#session#reconnect()
    call assert_equal('failed', b:jusi_nb.session.state)
    call assert_equal('session_expired', b:jusi_nb.session.last_error_code)
    call assert_equal('Session expired', b:jusi_nb.session.last_error)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_restart_after_reconnect_failure_rebinds_prepared_and_executes_cleanly() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'disconnect': function('s:test_session_adapter_disconnect'),
          \ 'reconnect': function('s:test_session_adapter_reconnect_error'),
          \ 'execute': function('s:test_session_adapter_execute'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])

    call jusi#session#start('python3')
    call jusi#session#callback_prepared({'id': 'client-1', 'state': 'binding', 'bufnr': -1})
    let l:first_prepared = b:jusi_nb.session.prepared.bufnr
    call jusi#session#callback_prepared({'id': 'client-1', 'state': 'ready', 'client_state': 'active', 'bufnr': l:first_prepared})
    call jusi#session#execute_current()
    call jusi#session#callback_prepared({'id': 'client-2', 'state': 'binding', 'bufnr': -1})
    let l:next_prepared = b:jusi_nb.session.prepared.bufnr
    call jusi#session#callback_prepared({'id': 'client-2', 'state': 'ready', 'client_state': 'active', 'bufnr': l:next_prepared})
    call assert_true(bufexists(l:next_prepared))

    call jusi#session#disconnect()
    call assert_false(bufexists(l:next_prepared))

    let b:jusi_nb.session.id = 'sess-1'
    call jusi#session#reconnect()
    call assert_equal('failed', b:jusi_nb.session.state)
    call assert_equal('session_expired', b:jusi_nb.session.last_error_code)
    call assert_equal('client-1', get(b:jusi_nb.cells[0], 'client_id', ''))
    call assert_true(get(b:jusi_nb.cells[0], 'client_bufnr', -1) > 0)

    call jusi#session#start('python3')
    call assert_equal('', get(b:jusi_nb.cells[0], 'client_id', ''))
    call assert_equal(-1, get(b:jusi_nb.cells[0], 'client_bufnr', -1))
    call jusi#session#callback_prepared({'id': 'client-1', 'state': 'binding', 'bufnr': -1})
    let l:restarted_prepared = b:jusi_nb.session.prepared.bufnr
    call jusi#session#callback_prepared({'id': 'client-1', 'state': 'ready', 'client_state': 'active', 'bufnr': l:restarted_prepared})
    call jusi#session#execute_current()

    call assert_equal('connected', b:jusi_nb.session.state)
    call assert_equal('execute', b:jusi_nb.session.last_action)
    call assert_equal('busy', b:jusi_nb.cells[0].status)
    call assert_equal('client-1', b:jusi_nb.cells[0].client_id)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_disconnect_transport_response_updates_state_without_separate_event() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'request': function('s:test_transport_like_request_adapter'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('python3')
    call jusi#session#apply_prepared({'id': 'client-1', 'state': 'ready', 'bufnr': 91})
    call jusi#session#disconnect()
    call assert_equal('disconnected', b:jusi_nb.session.state)
    call assert_equal('2030-01-01T00:00:00Z', b:jusi_nb.session.expires_at)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_reconnect_transport_response_updates_state_without_separate_event() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'request': function('s:test_transport_like_request_adapter'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('python3')
    call jusi#session#disconnect()
    call jusi#session#reconnect()
    call assert_equal('connected', b:jusi_nb.session.state)
    call assert_equal('reconnect', b:jusi_nb.session.last_action)
    call assert_equal('client-2', b:jusi_nb.session.prepared.id)
    call assert_equal('binding', b:jusi_nb.session.prepared.state)
    call assert_equal('sess-1', get(get(s:last_request_envelope, 'payload', {}), 'session_id', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_transport_healthcheck_event_sends_reply_for_connected_session() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'request': function('s:test_request_adapter'),
          \ }
    let s:last_request_envelope = {}
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#apply({
          \ 'state': 'connected',
          \ 'id': 'sess-1',
          \ })
    call jusi#transport#receive(bufnr('%'), {
          \ 'kind': 'event',
          \ 'type': 'healthcheck',
          \ 'version': 1,
          \ 'payload': {
          \   'notebook_id': 'nb-' . bufnr('%'),
          \   'session_id': 'sess-1',
          \   'healthcheck_id': 'hc-1',
          \   },
          \ })
    call assert_equal('healthcheck_reply', get(s:last_request_envelope, 'type', ''))
    call assert_equal('sess-1', get(get(s:last_request_envelope, 'payload', {}), 'session_id', ''))
    call assert_equal('hc-1', get(get(s:last_request_envelope, 'payload', {}), 'healthcheck_id', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_transport_healthcheck_event_ignores_unknown_or_inactive_session() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'request': function('s:test_request_adapter'),
          \ }
    let s:last_request_envelope = {}
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#apply({
          \ 'state': 'disconnected',
          \ 'id': 'sess-1',
          \ })
    call jusi#transport#receive(bufnr('%'), {
          \ 'kind': 'event',
          \ 'type': 'healthcheck',
          \ 'version': 1,
          \ 'payload': {
          \   'notebook_id': 'nb-' . bufnr('%'),
          \   'session_id': 'sess-1',
          \   'healthcheck_id': 'hc-1',
          \   },
          \ })
    call assert_equal({}, s:last_request_envelope)

    call jusi#session#apply({
          \ 'state': 'connected',
          \ 'id': 'sess-1',
          \ })
    call jusi#transport#receive(bufnr('%'), {
          \ 'kind': 'event',
          \ 'type': 'healthcheck',
          \ 'version': 1,
          \ 'payload': {
          \   'notebook_id': 'nb-' . bufnr('%'),
          \   'session_id': 'sess-2',
          \   'healthcheck_id': 'hc-2',
          \   },
          \ })
    call assert_equal({}, s:last_request_envelope)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction


function! Test_session_callback_updates_prepared_state() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call jusi#session#callback_prepared({'id': 'client-77', 'state': 'ready', 'client_state': 'active', 'bufnr': 77})
  call assert_equal('client-77', b:jusi_nb.session.prepared.id)
  call assert_equal('ready', b:jusi_nb.session.prepared.state)
  call assert_equal('active', b:jusi_nb.session.prepared.client_state)
  call assert_equal(77, b:jusi_nb.session.prepared.bufnr)
endfunction

function! Test_session_callback_updates_cell_state() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let l:cell_id = b:jusi_nb.cells[0].id
  call jusi#session#callback_cell(l:cell_id, {
        \ 'status': 'follow-up',
        \ 'client_id': 'client-88',
        \ 'client_state': 'active',
        \ 'client_bufnr': 88,
        \ 'owner': {'kind': 'handler'},
        \ })
  call assert_equal('follow-up', b:jusi_nb.cells[0].status)
  call assert_equal('client-88', b:jusi_nb.cells[0].client_id)
  call assert_equal('active', b:jusi_nb.cells[0].client_state)
  call assert_equal(88, b:jusi_nb.cells[0].client_bufnr)
  call assert_equal('handler', get(get(b:jusi_nb.cells[0], 'owner', {}), 'kind', ''))
endfunction

function! Test_execute_releases_disposable_client_buffers_before_starting_next_run() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let s:shutdown_requests = []
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'execute': function('s:test_session_adapter_execute'),
          \ 'shutdown_client': function('s:test_session_adapter_shutdown_client_record'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("one")',
          \ '##',
          \ 'print("two")',
          \ ])
    call jusi#session#start('python3')
    let b:jusi_nb.session.id = 'sess-1'
    let l:old_client = jusi#client#create_prepared_buffer(bufnr('%'), 'client-old')
    let l:prepared = jusi#client#create_prepared_buffer(bufnr('%'), 'client-1')
    let b:jusi_nb.cells[0].status = 'done'
    let b:jusi_nb.cells[0].client_id = 'client-old'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:old_client
    let b:jusi_nb.cells[0].owner = {'kind': 'kernel'}
    call jusi#client#mark_attached_buffer(bufnr('%'), b:jusi_nb.cells[0].id, 'client-old', l:old_client)
    let s:shutdown_requests = []
    call cursor(4, 1)
    call jusi#session#apply_prepared({'id': 'client-1', 'state': 'ready', 'client_state': 'active', 'bufnr': l:prepared})
    call jusi#session#execute_current()
    call assert_false(bufexists(l:old_client))
    call assert_equal('client-old', b:jusi_nb.cells[0].client_id)
    call assert_equal('shutdown', b:jusi_nb.cells[0].client_state)
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
    call assert_equal('kernel', get(get(b:jusi_nb.cells[0], 'owner', {}), 'kind', ''))
    call assert_equal('healthcheck', get(s:shutdown_requests[0], 'reason', ''))
    call assert_equal('client-old', get(s:shutdown_requests[0], 'client_id', ''))
    call assert_equal('busy', b:jusi_nb.cells[1].status)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_execute_keeps_retained_client_buffers_before_starting_next_run() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let s:shutdown_requests = []
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'execute': function('s:test_session_adapter_execute'),
          \ 'shutdown_client': function('s:test_session_adapter_shutdown_client_record'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ '%%sql main',
          \ 'select 1',
          \ '##',
          \ 'print("two")',
          \ ])
    call jusi#session#start('python3')
    let b:jusi_nb.session.id = 'sess-1'
    let l:old_client = jusi#client#create_prepared_buffer(bufnr('%'), 'client-old')
    let l:prepared = jusi#client#create_prepared_buffer(bufnr('%'), 'client-1')
    let b:jusi_nb.cells[0].status = 'parked'
    let b:jusi_nb.cells[0].client_id = 'client-old'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:old_client
    call jusi#client#mark_attached_buffer(bufnr('%'), b:jusi_nb.cells[0].id, 'client-old', l:old_client)
    let s:shutdown_requests = []
    call cursor(5, 1)
    call jusi#session#apply_prepared({'id': 'client-1', 'state': 'ready', 'client_state': 'active', 'bufnr': l:prepared})
    call jusi#session#execute_current()
    call assert_true(bufexists(l:old_client))
    call assert_equal([], s:shutdown_requests)
    call assert_equal('parked', b:jusi_nb.cells[0].status)
    call assert_equal('active', b:jusi_nb.cells[0].client_state)
    call assert_equal(l:old_client, b:jusi_nb.cells[0].client_bufnr)
    call assert_equal('busy', b:jusi_nb.cells[1].status)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_execute_new_duplicate_magic_cell_keeps_existing_followup_client_intact() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let s:shutdown_requests = []
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'execute': function('s:test_session_adapter_execute'),
          \ 'shutdown_client': function('s:test_session_adapter_shutdown_client_record'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("one")',
          \ '##',
          \ 'print("two")',
          \ '##',
          \ '%%vd pods',
          \ ])
    call jusi#session#start('python3')
    let l:notebook = bufnr('%')
    let l:live_client = jusi#client#create_prepared_buffer(l:notebook, 'client-old')
    let l:prepared = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
    let b:jusi_nb.cells[2].status = 'follow-up'
    let b:jusi_nb.cells[2].owner = {'kind': 'handler'}
    let b:jusi_nb.cells[2].client_id = 'client-old'
    let b:jusi_nb.cells[2].client_state = 'active'
    let b:jusi_nb.cells[2].client_bufnr = l:live_client
    let b:jusi_nb.cells[2].handler = {'id': 'vd', 'last_message_type': '', 'payload': {}, 'snapshot': {'transport': 'native_terminal'}}
    call jusi#client#mark_attached_buffer(l:notebook, b:jusi_nb.cells[2].id, 'client-old', l:live_client)

    call cursor(4, 1)
    call jusi#notebook#insert_below()
    call assert_equal(6, line('.'))
    call assert_equal(5, b:jusi_nb.cells[2].start)
    call assert_equal('initial', b:jusi_nb.cells[2].status)
    call assert_equal(7, b:jusi_nb.cells[3].start)
    call assert_equal('follow-up', b:jusi_nb.cells[3].status)
    call setline(line('.'), '%%vd pods')
    call jusi#notebook#handle_insert_exit()
    call assert_equal(6, line('.'))
    call assert_equal(5, b:jusi_nb.cells[2].start)
    call assert_equal(7, b:jusi_nb.cells[3].start)
    stopinsert

    let s:shutdown_requests = []
    call jusi#session#apply_prepared({'id': 'client-1', 'state': 'ready', 'client_state': 'active', 'bufnr': l:prepared})
    call assert_equal('follow-up', b:jusi_nb.cells[3].status)
    call assert_equal('client-old', b:jusi_nb.cells[3].client_id)
    call assert_equal(l:live_client, b:jusi_nb.cells[3].client_bufnr)
    call assert_equal({'ok': 1}, jusi#client#validate_attached_binding(l:notebook, b:jusi_nb.cells[3].id, 'client-old', l:live_client))
    call jusi#session#execute_current()

    call assert_equal(4, len(b:jusi_nb.cells))
    call assert_equal('busy', b:jusi_nb.cells[2].status)
    call assert_equal(l:prepared, b:jusi_nb.cells[2].client_bufnr)
    call assert_equal('follow-up', b:jusi_nb.cells[3].status)
    call assert_equal('client-old', b:jusi_nb.cells[3].client_id)
    call assert_equal(l:live_client, b:jusi_nb.cells[3].client_bufnr)
    call assert_true(bufexists(l:live_client))
    call assert_equal([], s:shutdown_requests)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_execute_releases_current_parked_client_before_rerun() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let s:shutdown_requests = []
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'execute': function('s:test_session_adapter_execute'),
          \ 'shutdown_client': function('s:test_session_adapter_shutdown_client_record'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("one")',
          \ ])
    call jusi#session#start('python3')
    let b:jusi_nb.session.id = 'sess-1'
    let l:old_client = jusi#client#create_prepared_buffer(bufnr('%'), 'client-old')
    let l:prepared = jusi#client#create_prepared_buffer(bufnr('%'), 'client-1')
    let b:jusi_nb.cells[0].status = 'parked'
    let b:jusi_nb.cells[0].parked_status = 'done'
    let b:jusi_nb.cells[0].client_id = 'client-old'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:old_client
    call jusi#client#mark_attached_buffer(bufnr('%'), b:jusi_nb.cells[0].id, 'client-old', l:old_client)
    let s:shutdown_requests = []
    call jusi#session#apply_prepared({'id': 'client-1', 'state': 'ready', 'client_state': 'active', 'bufnr': l:prepared})
    call jusi#session#execute_current()
    call assert_false(bufexists(l:old_client))
    call assert_equal('busy', b:jusi_nb.cells[0].status)
    call assert_equal('', get(b:jusi_nb.cells[0], 'parked_status', ''))
    call assert_equal(l:prepared, b:jusi_nb.cells[0].client_bufnr)
    call assert_equal('healthcheck', get(s:shutdown_requests[0], 'reason', ''))
    call assert_equal('client-old', get(s:shutdown_requests[0], 'client_id', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_execute_releases_interrupted_client_buffers_before_starting_next_run() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let s:shutdown_requests = []
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'execute': function('s:test_session_adapter_execute'),
          \ 'shutdown_client': function('s:test_session_adapter_shutdown_client_record'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("one")',
          \ '##',
          \ 'print("two")',
          \ ])
    call jusi#session#start('python3')
    let b:jusi_nb.session.id = 'sess-1'
    let l:old_client = jusi#client#create_prepared_buffer(bufnr('%'), 'client-old')
    let l:prepared = jusi#client#create_prepared_buffer(bufnr('%'), 'client-1')
    let b:jusi_nb.cells[0].status = 'interrupted'
    let b:jusi_nb.cells[0].client_id = 'client-old'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:old_client
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    call jusi#client#mark_attached_buffer(bufnr('%'), b:jusi_nb.cells[0].id, 'client-old', l:old_client)
    let s:shutdown_requests = []
    call cursor(4, 1)
    call jusi#session#apply_prepared({'id': 'client-1', 'state': 'ready', 'client_state': 'active', 'bufnr': l:prepared})
    call jusi#session#execute_current()
    call assert_false(bufexists(l:old_client))
    call assert_equal('interrupted', b:jusi_nb.cells[0].status)
    call assert_equal('shutdown', b:jusi_nb.cells[0].client_state)
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
    call assert_equal('handler', get(get(b:jusi_nb.cells[0], 'owner', {}), 'kind', ''))
    call assert_equal('healthcheck', get(s:shutdown_requests[0], 'reason', ''))
    call assert_equal('client-old', get(s:shutdown_requests[0], 'client_id', ''))
    call assert_equal('busy', b:jusi_nb.cells[1].status)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_execute_releases_error_client_buffers_before_starting_next_run() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let s:shutdown_requests = []
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'execute': function('s:test_session_adapter_execute'),
          \ 'shutdown_client': function('s:test_session_adapter_shutdown_client_record'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("one")',
          \ '##',
          \ 'print("two")',
          \ ])
    call jusi#session#start('python3')
    let b:jusi_nb.session.id = 'sess-1'
    let l:old_client = jusi#client#create_prepared_buffer(bufnr('%'), 'client-old')
    let l:prepared = jusi#client#create_prepared_buffer(bufnr('%'), 'client-1')
    let b:jusi_nb.cells[0].status = 'error'
    let b:jusi_nb.cells[0].client_id = 'client-old'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:old_client
    let b:jusi_nb.cells[0].owner = {'kind': 'kernel'}
    call jusi#client#mark_attached_buffer(bufnr('%'), b:jusi_nb.cells[0].id, 'client-old', l:old_client)
    let s:shutdown_requests = []
    call cursor(4, 1)
    call jusi#session#apply_prepared({'id': 'client-1', 'state': 'ready', 'client_state': 'active', 'bufnr': l:prepared})
    call jusi#session#execute_current()
    call assert_false(bufexists(l:old_client))
    call assert_equal('error', b:jusi_nb.cells[0].status)
    call assert_equal('shutdown', b:jusi_nb.cells[0].client_state)
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
    call assert_equal('kernel', get(get(b:jusi_nb.cells[0], 'owner', {}), 'kind', ''))
    call assert_equal('healthcheck', get(s:shutdown_requests[0], 'reason', ''))
    call assert_equal('client-old', get(s:shutdown_requests[0], 'client_id', ''))
    call assert_equal('busy', b:jusi_nb.cells[1].status)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_notebook_cleanup_destroys_managed_client_buffers() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let l:prepared = jusi#client#create_prepared_buffer(bufnr('%'), 'client-prepared')
  let l:attached = jusi#client#create_prepared_buffer(bufnr('%'), 'client-attached')
  call jusi#session#apply_prepared({'id': 'client-prepared', 'state': 'ready', 'bufnr': l:prepared})
  let b:jusi_nb.cells[0].client_id = 'client-attached'
  let b:jusi_nb.cells[0].client_bufnr = l:attached
  call jusi#notebook#cleanup(bufnr('%'))
  call assert_false(bufexists(l:prepared))
  call assert_false(bufexists(l:attached))
endfunction

function! Test_rebuild_shutdowns_lost_cell_clients_on_structural_delete() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'shutdown_client': function('s:test_session_adapter_shutdown_client_record'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("one")',
          \ '##',
          \ 'print("two")',
          \ ])
    let s:shutdown_requests = []
    call jusi#session#start('python3')
    let l:client = jusi#client#create_prepared_buffer(bufnr('%'), 'client-old')
    let b:jusi_nb.cells[0].status = 'done'
    let b:jusi_nb.cells[0].client_id = 'client-old'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    call cursor(2, 1)
    call jusi#notebook#delete_current()
    call assert_false(bufexists(l:client))
    call assert_equal(1, len(s:shutdown_requests))
    call assert_equal('client-old', get(s:shutdown_requests[0], 'client_id', ''))
    call assert_equal('cell_deleted', get(s:shutdown_requests[0], 'reason', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_stop_shutdowns_attached_and_prepared_clients_before_stop() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'stop': function('s:test_session_adapter_stop'),
          \ 'shutdown_client': function('s:test_session_adapter_shutdown_client_record'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    let s:shutdown_requests = []
    call jusi#session#start('python3')
    let l:attached = jusi#client#create_prepared_buffer(bufnr('%'), 'client-attached')
    call jusi#session#apply_prepared({'id': 'client-prepared', 'state': 'ready', 'client_state': 'active', 'bufnr': 91})
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].client_id = 'client-attached'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:attached
    call jusi#session#stop()
    let l:session_stop_ids = []
    for l:request in s:shutdown_requests
      if get(l:request, 'reason', '') ==# 'session_stop'
        call add(l:session_stop_ids, get(l:request, 'client_id', ''))
      endif
    endfor
    call assert_true(index(l:session_stop_ids, 'client-attached') >= 0)
    call assert_true(index(l:session_stop_ids, 'client-prepared') >= 0)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_cleanup_shutdowns_clients_with_frontend_unload_reason() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'shutdown_client': function('s:test_session_adapter_shutdown_client_record'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    let s:shutdown_requests = []
    call jusi#session#start('python3')
    let l:attached = jusi#client#create_prepared_buffer(bufnr('%'), 'client-attached')
    call jusi#session#apply_prepared({'id': 'client-prepared', 'state': 'ready', 'client_state': 'active', 'bufnr': 92})
    let b:jusi_nb.cells[0].client_id = 'client-attached'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:attached
    call jusi#notebook#cleanup(bufnr('%'))
    let l:frontend_unload_ids = []
    for l:request in s:shutdown_requests
      if get(l:request, 'reason', '') ==# 'frontend_unload'
        call add(l:frontend_unload_ids, get(l:request, 'client_id', ''))
      endif
    endfor
    call assert_true(index(l:frontend_unload_ids, 'client-attached') >= 0)
    call assert_true(index(l:frontend_unload_ids, 'client-prepared') >= 0)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_cell_shutdown_event_keeps_status_and_clears_binding() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ ])
  let l:client = jusi#client#create_prepared_buffer(bufnr('%'), 'client-1')
  let l:cell_id = b:jusi_nb.cells[0].id
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  call jusi#client#mark_attached_buffer(bufnr('%'), l:cell_id, 'client-1', l:client)
  call jusi#session#callback_cell(l:cell_id, {'client_state': 'shutdown', 'client_bufnr': -1})
  call assert_false(bufexists(l:client))
  call assert_equal('follow-up', b:jusi_nb.cells[0].status)
  call assert_equal('shutdown', b:jusi_nb.cells[0].client_state)
  call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
endfunction

function! Test_execute_healthcheck_shutdowns_stale_attached_client() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let s:shutdown_requests = []
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'execute': function('s:test_session_adapter_execute'),
          \ 'shutdown_client': function('s:test_session_adapter_shutdown_client_record'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("one")',
          \ '##',
          \ 'print("two")',
          \ ])
    call jusi#session#start('python3')
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].client_id = 'client-stale'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = 9999
    call cursor(4, 1)
    let l:prepared = jusi#client#create_prepared_buffer(bufnr('%'), 'client-1')
    call jusi#session#apply_prepared({'id': 'client-1', 'state': 'ready', 'client_state': 'active', 'bufnr': l:prepared})
    let s:shutdown_requests = []
    call jusi#session#execute_current()
    call assert_equal('follow-up', b:jusi_nb.cells[0].status)
    call assert_equal('shutdown', b:jusi_nb.cells[0].client_state)
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
    call assert_equal('healthcheck', get(s:shutdown_requests[0], 'reason', ''))
    call assert_equal('client-stale', get(s:shutdown_requests[0], 'client_id', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_execute_healthcheck_shutdowns_inconsistent_attached_client_binding() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let s:shutdown_requests = []
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'execute': function('s:test_session_adapter_execute'),
          \ 'shutdown_client': function('s:test_session_adapter_shutdown_client_record'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("one")',
          \ '##',
          \ 'print("two")',
          \ ])
    call jusi#session#start('python3')
    let b:jusi_nb.session.id = 'sess-1'
    let l:client = jusi#client#create_prepared_buffer(bufnr('%'), 'client-stale')
    call setbufvar(l:client, 'jusi_client_role', 'prepared')
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].client_id = 'client-stale'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    call jusi#session#apply_prepared({'id': 'client-next', 'state': 'ready', 'client_state': 'active', 'bufnr': jusi#client#create_prepared_buffer(bufnr('%'), 'client-next')})
    let s:shutdown_requests = []
    call cursor(4, 1)
    call jusi#session#execute_current()
    call assert_true(bufexists(l:client))
    call assert_equal('follow-up', b:jusi_nb.cells[0].status)
    call assert_equal('shutdown', b:jusi_nb.cells[0].client_state)
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
    call assert_equal('healthcheck', get(s:shutdown_requests[0], 'reason', ''))
    call assert_equal('client-stale', get(s:shutdown_requests[0], 'client_id', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_execute_clears_inconsistent_attached_client_without_trusted_identity() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let s:shutdown_requests = []
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'execute': function('s:test_session_adapter_execute'),
          \ 'shutdown_client': function('s:test_session_adapter_shutdown_client_record'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("one")',
          \ '##',
          \ 'print("two")',
          \ ])
    call jusi#session#start('python3')
    let l:client = jusi#client#create_prepared_buffer(bufnr('%'), 'client-stale')
    call jusi#client#mark_attached_buffer(bufnr('%'), b:jusi_nb.cells[0].id, 'client-stale', l:client)
    call setbufvar(l:client, 'jusi_client_cell_id', 999)
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].client_id = ''
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    call jusi#session#apply_prepared({'id': 'client-next', 'state': 'ready', 'client_state': 'active', 'bufnr': jusi#client#create_prepared_buffer(bufnr('%'), 'client-next')})
    let s:shutdown_requests = []
    call cursor(4, 1)
    call jusi#session#execute_current()
    call assert_true(bufexists(l:client))
    call assert_equal([], s:shutdown_requests)
    call assert_equal('shutdown', b:jusi_nb.cells[0].client_state)
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_execute_healthcheck_shutdowns_stale_prepared_client() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let s:shutdown_requests = []
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'shutdown_client': function('s:test_session_adapter_shutdown_client_record'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    let s:shutdown_requests = []
    call jusi#session#start('python3')
    let b:jusi_nb.session.id = 'sess-1'
    call jusi#session#apply_prepared({'id': 'client-prepared-stale', 'state': 'ready', 'client_state': 'active', 'bufnr': 9999})
    let s:shutdown_requests = []
    call jusi#session#callback_prepared({'id': 'client-next', 'state': 'binding', 'bufnr': -1})
    call assert_equal('client-next', b:jusi_nb.session.prepared.id)
    call assert_equal('binding', b:jusi_nb.session.prepared.state)
    call assert_equal('healthcheck', get(s:shutdown_requests[0], 'reason', ''))
    call assert_equal('client-prepared-stale', get(s:shutdown_requests[0], 'client_id', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_callback_prepared_healthcheck_shutdowns_inconsistent_binding() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let s:shutdown_requests = []
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'shutdown_client': function('s:test_session_adapter_shutdown_client_record'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('python3')
    let b:jusi_nb.session.id = 'sess-1'
    let l:prepared = jusi#client#create_prepared_buffer(bufnr('%'), 'client-prepared-stale')
    call setbufvar(l:prepared, 'jusi_client_notebook_bufnr', bufnr('%') + 100)
    call jusi#session#apply_prepared({'id': 'client-prepared-stale', 'state': 'ready', 'client_state': 'active', 'bufnr': l:prepared})
    let s:shutdown_requests = []
    call jusi#session#callback_prepared({'id': 'client-next', 'state': 'binding', 'bufnr': -1})
    call assert_true(bufexists(l:prepared))
    call assert_equal('client-next', b:jusi_nb.session.prepared.id)
    call assert_equal('binding', b:jusi_nb.session.prepared.state)
    call assert_equal('healthcheck', get(s:shutdown_requests[0], 'reason', ''))
    call assert_equal('client-prepared-stale', get(s:shutdown_requests[0], 'client_id', ''))
    call assert_match('belongs to another notebook', b:jusi_nb.session.last_error)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_session_callback_response_can_update_multiple_areas() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let l:cell_id = b:jusi_nb.cells[0].id
  call jusi#session#callback_response({
        \ 'session': {'state': 'connected', 'backend': 'mock'},
        \ 'prepared': {'id': 'client-66', 'state': 'ready', 'bufnr': 66},
        \ 'cell': {'id': l:cell_id, 'status': 'done', 'client_bufnr': 55},
        \ })
  call assert_equal('connected', b:jusi_nb.session.state)
  call assert_equal('mock', b:jusi_nb.session.backend)
  call assert_equal('client-66', b:jusi_nb.session.prepared.id)
  call assert_equal('ready', b:jusi_nb.session.prepared.state)
  call assert_equal(66, b:jusi_nb.session.prepared.bufnr)
  call assert_equal('done', b:jusi_nb.cells[0].status)
  call assert_equal(55, b:jusi_nb.cells[0].client_bufnr)
endfunction

function! Test_transport_receive_routes_backend_events_to_callbacks() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let l:cell_id = b:jusi_nb.cells[0].id
  call jusi#transport#receive(bufnr('%'), {
        \ 'kind': 'event',
        \ 'type': 'session_updated',
        \ 'payload': {'session': {'id': 'sess-1', 'state': 'connected', 'backend': 'mock'}},
        \ })
  call jusi#transport#receive(bufnr('%'), {
        \ 'kind': 'event',
        \ 'type': 'prepared_updated',
        \ 'payload': {'prepared': {'id': 'client-9', 'state': 'ready', 'bufnr': 99}},
        \ })
  call jusi#transport#receive(bufnr('%'), {
        \ 'kind': 'event',
        \ 'type': 'cell_updated',
        \ 'payload': {'cell': {'id': l:cell_id, 'status': 'busy', 'client_id': 'client-9', 'client_bufnr': 99, 'owner': {'kind': 'kernel'}}},
        \ })
  call assert_equal('sess-1', b:jusi_nb.session.id)
  call assert_equal('connected', b:jusi_nb.session.state)
  call assert_equal('client-9', b:jusi_nb.session.prepared.id)
  call assert_equal('ready', b:jusi_nb.session.prepared.state)
  call assert_equal(99, b:jusi_nb.session.prepared.bufnr)
  call assert_equal('busy', b:jusi_nb.cells[0].status)
  call assert_equal('client-9', b:jusi_nb.cells[0].client_id)
  call assert_equal(99, b:jusi_nb.cells[0].client_bufnr)
  call assert_equal('kernel', get(get(b:jusi_nb.cells[0], 'owner', {}), 'kind', ''))
endfunction

function! Test_transport_request_parses_real_job_response() abort
  let l:save_backend_cmd = get(g:, 'jusi_backend_cmd', [])
  try
    let g:jusi_backend_cmd = ['sh', '-lc', "IFS= read -r line; printf '%s\\n' '{\"version\":1,\"kind\":\"response\",\"type\":\"start_session\",\"request_id\":\"req-test\",\"ok\":true,\"payload\":{}}'"]
    call Test_open_scratch([
          \ '##',
          \ 'print(\"hello\")',
          \ ])
    let l:response = jusi#transport#request(bufnr('%'), {
          \ 'version': 1,
          \ 'kind': 'request',
          \ 'type': 'start_session',
          \ 'request_id': 'req-test',
          \ 'payload': {'notebook_id': 'nb-1', 'kernel_name': 'python3'},
          \ })
    call assert_equal(1, get(l:response, 'ok', 0))
    call assert_equal('', get(l:response, 'error', ''))
  finally
    call jusi#transport#stop(bufnr('%'))
    let g:jusi_backend_cmd = l:save_backend_cmd
  endtry
endfunction

function! Test_magic_header_has_dedicated_syntax_group() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ ])
  call assert_equal('jusiMagicHeader', Test_syn_name(4, 1))
endfunction

function! Test_syntax_updates_after_cell_type_change() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call assert_notequal('jusiMagicHeader', Test_syn_name(2, 1))
  call setline(2, '%%sql main')
  call append(2, 'select 1')
  call jusi#notebook#rebuild()
  call assert_equal('jusiMagicHeader', Test_syn_name(2, 1))
  call assert_equal('sql', b:jusi_nb.cells[0].syntax)
endfunction

function! Test_visible_cell_body_gets_rich_syntax() abort
  call Test_open_scratch([
        \ '##',
        \ 'return 1',
        \ ])
  call cursor(1, 1)
  call jusi#syntax#schedule(bufnr('%'))
  call assert_notequal('', Test_syn_name(2, 1))
endfunction

function! Test_rich_syntax_covers_all_visible_cells() abort
  call Test_open_scratch([
        \ '##',
        \ 'return 1',
        \ '##',
        \ 'return 2',
        \ ])
  call cursor(1, 1)
  call jusi#syntax#schedule(bufnr('%'))
  call assert_notequal('', Test_syn_name(2, 1))
  call assert_notequal('', Test_syn_name(4, 1))
endfunction

function! Test_rich_syntax_covers_partially_visible_cell() abort
  let l:save_lines = &lines
  try
    let &lines = 8
    call Test_open_scratch([
          \ '##',
          \ '%%sql main',
          \ 'select 1',
          \ 'select 2',
          \ 'select 3',
          \ 'select 4',
          \ 'select 5',
          \ '##',
          \ 'print("tail")',
          \ ])
    call cursor(5, 1)
    normal! zt
    call jusi#syntax#schedule(bufnr('%'))
    call assert_notequal('', Test_syn_name(5, 1))
  finally
    let &lines = l:save_lines
  endtry
endfunction

function! Test_rich_syntax_survives_jump_into_long_cell() abort
  let l:lines = ['##', '%%sql main']
  for l:num in range(1, 1400)
    call add(l:lines, 'select ' . l:num . ',')
  endfor
  call add(l:lines, 'from table_name;')
  call add(l:lines, '##')
  call add(l:lines, 'print("tail")')

  call Test_open_scratch(l:lines)
  call cursor(1400, 1)
  call jusi#syntax#schedule(bufnr('%'))
  call assert_notequal('', Test_syn_name(1400, 1))

  call cursor(line('$'), 1)
  call jusi#syntax#schedule(bufnr('%'))
  call cursor(1200, 1)
  call jusi#syntax#schedule(bufnr('%'))
  call assert_notequal('', Test_syn_name(1200, 1))
endfunction

function! Test_default_cell_uses_python_indent() abort
  call Test_open_scratch([
        \ '##',
        \ 'if True:',
        \ '    pass',
        \ ])
  call cursor(2, 1)
  call jusi#indent#refresh(bufnr('%'))
  call assert_match('python', &l:indentexpr)
  call assert_equal('python', get(b:, 'jusi_indent_dialect', ''))
endfunction

function! Test_magic_cell_updates_indent_dialect() abort
  call Test_open_scratch([
        \ '##',
        \ 'if True:',
        \ '    pass',
        \ '##',
        \ '%%sh',
        \ 'if true; then',
        \ 'echo ok',
        \ 'fi',
        \ ])
  call cursor(2, 1)
  call jusi#indent#refresh(bufnr('%'))
  call assert_match('python', &l:indentexpr)

  call cursor(6, 1)
  call jusi#indent#refresh(bufnr('%'))
  call assert_match('GetShIndent', &l:indentexpr)
  call assert_equal('sh', get(b:, 'jusi_indent_dialect', ''))
endfunction

function! Test_magic_indent_map_overrides_builtin_lookup() abort
  let l:save_map = copy(get(g:, 'jusi_indent_map', {}))
  try
    let g:jusi_indent_map = {'shell': 'indent/sh.vim'}
    call Test_open_scratch([
          \ '##',
          \ '%%shell',
          \ 'if true; then',
          \ 'echo ok',
          \ 'fi',
          \ ])
    call cursor(3, 1)
    call jusi#indent#refresh(bufnr('%'))
    call assert_match('GetShIndent', &l:indentexpr)
    call assert_equal('shell', get(b:, 'jusi_indent_dialect', ''))
  finally
    let g:jusi_indent_map = l:save_map
  endtry
endfunction

function! Test_default_buffer_mappings_exist() abort
  call Test_open_scratch([
        \ '##',
        \ 'one',
        \ ])
  call assert_equal(':JusiRebuild<CR>', maparg('<leader>r', 'n', 0, 1).rhs)
  call assert_equal(':JusiCellNewAbove<CR>', maparg('<leader>a', 'n', 0, 1).rhs)
  call assert_equal(':JusiCellNewBelow<CR>', maparg('<leader>b', 'n', 0, 1).rhs)
  call assert_equal(':JusiCellDelete<CR>', maparg('<leader>x', 'n', 0, 1).rhs)
  call assert_equal(':JusiCellEdit<CR>', maparg('<leader>c', 'n', 0, 1).rhs)
  call assert_equal(':JusiCellCopy<CR>', maparg('<leader>y', 'n', 0, 1).rhs)
  call assert_equal(':JusiCellPasteBelow<CR>', maparg('<leader>p', 'n', 0, 1).rhs)
  call assert_equal(':JusiTogglePark<CR>', maparg('<leader>s', 'n', 0, 1).rhs)
  call assert_equal('', maparg('<leader><Space>', 'n'))
  call assert_equal(':JusiToggleFocus<CR>', maparg("\<C-\\>\<C-\\>", 'n', 0, 1).rhs)
  call assert_equal('', maparg(']]', 'n'))
  call assert_equal('', maparg('[[', 'n'))
  call assert_equal(':JusiCellModeToggle<CR>', maparg('<Space>', 'n', 0, 1).rhs)
  call assert_equal('', maparg('o', 'n'))
  call assert_equal('', maparg('d', 'n'))
  call assert_equal('', maparg('p', 'x'))
  call assert_equal('<C-R>=jusi#focus#toggle()<CR>', maparg("\<C-\\>\<C-\\>", 'i', 0, 1).rhs)
  call assert_equal('<C-\><C-n>:call jusi#notebook#handle_insert_exit()<Bar>call jusi#cellmode#update_indicator()<CR>', maparg('<C-C>', 'i', 0, 1).rhs)
endfunction

function! Test_cell_mode_toggle_maps_navigation_keys() abort
  call Test_open_scratch([
        \ '##',
        \ 'one',
        \ '##',
        \ 'two',
        \ ])
  call assert_equal('', maparg('j', 'n'))
  call jusi#cellmode#enable()
  call assert_equal(1, get(b:, 'jusi_cell_mode', 0))
  call assert_equal(':<C-U>execute "JusiCellNext"<CR>', maparg('j', 'n', 0, 1).rhs)
  call assert_equal(':<C-U>execute "JusiCellPrev"<CR>', maparg('k', 'n', 0, 1).rhs)
  call assert_equal(':JusiExecute<CR>', maparg('<CR>', 'n', 0, 1).rhs)
  call assert_equal('', maparg('J', 'n'))
  call assert_equal('', maparg('<leader><Space>', 'n'))
  call assert_equal(':JusiCellNewBelow<CR>', maparg('B', 'n', 0, 1).rhs)
  call assert_equal(':JusiCellNewAbove<CR>', maparg('A', 'n', 0, 1).rhs)
  call assert_equal(':JusiCellDelete<CR>', maparg('X', 'n', 0, 1).rhs)
  call assert_equal(':JusiCellEdit<CR>', maparg('C', 'n', 0, 1).rhs)
  call assert_equal(':JusiCellCopy<CR>', maparg('Y', 'n', 0, 1).rhs)
  call assert_equal(':JusiCellPasteBelow<CR>', maparg('P', 'n', 0, 1).rhs)
  call assert_equal(':JusiTogglePark<CR>', maparg('S', 'n', 0, 1).rhs)
  call assert_equal(':JusiCloseClient<CR>', maparg('Q', 'n', 0, 1).rhs)
  call assert_equal(':JusiRebuild<CR>', maparg('R', 'n', 0, 1).rhs)
  call jusi#cellmode#disable()
  call assert_equal(0, get(b:, 'jusi_cell_mode', 1))
  call assert_equal('', maparg('j', 'n'))
  call assert_equal('', maparg('<CR>', 'n'))
endfunction

function! Test_client_buffer_gets_toggle_focus_mappings() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd pods',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_prepared_buffer(l:notebook, 'client-1')
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)

  call jusi#focus#place_client_buffer(l:client, 'bsplit', 0)
  call assert_equal(':JusiToggleFocus<CR>', maparg("\<C-\\>\<C-\\>", 'n', 0, 1).rhs)
  call assert_equal('<C-R>=jusi#focus#toggle()<CR>', maparg("\<C-\\>\<C-\\>", 'i', 0, 1).rhs)
  call win_gotoid(bufwinid(l:notebook))
endfunction

function! Test_cell_mode_switches_sign_highlights() abort
  call Test_open_scratch([
        \ '##',
        \ 'one',
        \ ])
  call jusi#cellmode#disable()
  call assert_match('ctermfg=', execute('highlight JusiSignDone'))
  call assert_notmatch('ctermbg=', execute('highlight JusiSignDone'))
  call jusi#cellmode#enable()
  call assert_match('ctermbg=', execute('highlight JusiSignDone'))
  call assert_match('guibg=', execute('highlight JusiSignDone'))
endfunction

function! Test_blank_body_cell_sign_uses_first_body_line() abort
  call Test_open_scratch([
        \ '##',
        \ '',
        \ ])
  let l:signs = Test_sign_lines(bufnr('%'))
  call assert_equal(1, len(l:signs))
  call assert_equal(2, l:signs[0][1])
endfunction

function! Test_empty_vipynb_buffer_gets_initial_delimiter() abort
  call Test_open_scratch([])
  call assert_equal(['##'], getline(1, '$'))
  let l:cells = jusi#notebook#cells()
  call assert_equal(1, len(l:cells))
  call assert_equal(1, l:cells[0].start)
  call assert_equal(1, l:cells[0].end)
endfunction

function! Test_cell_mode_indicator_state_transitions() abort
  call Test_open_scratch([
        \ '##',
        \ 'one',
        \ ])
  let g:jusi_cellmode_indicator = 0
  call jusi#cellmode#disable()
  call assert_equal(0, jusi#cellmode#should_show_indicator())
  call assert_equal(0, g:jusi_cellmode_indicator)
  call jusi#cellmode#enable()
  call assert_equal(&filetype ==# 'jusinb' && mode() =~# '^[nc]', jusi#cellmode#should_show_indicator())
  call jusi#cellmode#update_indicator(v:true)
  call assert_equal(0, g:jusi_cellmode_indicator)
endfunction

function! Test_insert_invalidation_defers_rebuild_until_exit() abort
  call Test_open_scratch([
        \ '##',
        \ 'one',
        \ ])
  let l:tick_before = b:jusi_nb.changedtick
  call setline(2, 'ONE')
  call jusi#notebook#invalidate()
  call assert_equal(l:tick_before, b:jusi_nb.changedtick)
  call assert_equal(1, b:jusi_nb.dirty_insert)
  call jusi#notebook#handle_insert_exit()
  call assert_equal(0, b:jusi_nb.dirty_insert)
  call assert_notequal(l:tick_before, b:jusi_nb.changedtick)
endfunction

function! Test_insert_mode_line_insert_updates_ranges_incrementally() abort
  call Test_open_scratch([
        \ '##',
        \ 'one',
        \ '##',
        \ 'two',
        \ ])
  call append(2, 'one more')
  call jusi#notebook#handle_text_changed_insert()
  call assert_equal(3, b:jusi_nb.cells[0].end)
  call assert_equal(4, b:jusi_nb.cells[1].start)
  call assert_equal(0, b:jusi_nb.dirty_insert)
endfunction

function! Test_insert_mode_o_from_single_delimiter_cell_does_not_crash() abort
  call Test_open_scratch([])
  call append(1, '')
  call jusi#notebook#handle_text_changed_insert()
  call assert_equal(['##', ''], getline(1, '$'))
  call assert_equal(1, len(b:jusi_nb.cells))
  call assert_equal(1, b:jusi_nb.cells[0].start)
  call jusi#notebook#handle_insert_exit()
  call assert_equal(2, b:jusi_nb.cells[0].end)
  call assert_equal(0, b:jusi_nb.dirty_insert)
endfunction

function! Test_normal_mode_same_line_edit_uses_fast_path() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("one")',
        \ '##',
        \ 'print("two")',
        \ ])
  let l:ids_before = map(copy(b:jusi_nb.cells), 'v:val.id')
  call setline(2, 'print("ONE")')
  call jusi#notebook#handle_text_changed()
  call assert_equal(l:ids_before, map(copy(b:jusi_nb.cells), 'v:val.id'))
  call assert_equal('print("ONE")', getline(2))
  call assert_equal(2, len(b:jusi_nb.cells))
endfunction

function! Test_normal_mode_line_insert_inside_cell_updates_ranges_without_full_rebuild() abort
  call Test_open_scratch([
        \ '##',
        \ 'one',
        \ '##',
        \ 'two',
        \ ])
  let l:ids_before = map(copy(b:jusi_nb.cells), 'v:val.id')
  call append(2, 'one more')
  call jusi#notebook#handle_text_changed()
  call assert_equal(l:ids_before, map(copy(b:jusi_nb.cells), 'v:val.id'))
  call assert_equal(3, b:jusi_nb.cells[0].end)
  call assert_equal(4, b:jusi_nb.cells[1].start)
  call assert_equal(5, line('$'))
endfunction

function! Test_delimiter_insert_falls_back_to_full_rebuild() abort
  call Test_open_scratch([
        \ '##',
        \ 'one',
        \ ])
  call append(2, '##')
  call jusi#notebook#handle_text_changed()
  call assert_equal(2, len(b:jusi_nb.cells))
  call assert_equal(1, b:jusi_nb.cells[0].start)
  call assert_equal(2, b:jusi_nb.cells[0].end)
  call assert_equal(3, b:jusi_nb.cells[1].start)
endfunction

function! Test_resize_fast_path_flush_keeps_model_consistent() abort
  call Test_open_scratch([
        \ '##',
        \ 'one',
        \ '##',
        \ 'two',
        \ ])
  call append(2, 'one more')
  call jusi#notebook#handle_text_changed()
  call assert_equal(3, b:jusi_nb.cells[0].end)
  call assert_equal(4, b:jusi_nb.cells[1].start)
  call jusi#notebook#flush_deferred()
  call assert_equal(0, b:jusi_nb.syntax_dirty)
endfunction

function! Test_resize_fast_path_keeps_navigation_on_cell_entry_lines() abort
  call Test_open_scratch([
        \ '##',
        \ 'top',
        \ '##',
        \ 'middle',
        \ '##',
        \ 'bottom',
        \ ])
  call cursor(4, 1)
  call append(4, 'middle more')
  call jusi#notebook#handle_text_changed()

  call cursor(2, 1)
  call jusi#notebook#goto_next()
  call assert_equal(3, b:jusi_nb.cells[1].start)
  call assert_equal(4, line('.'))
  call jusi#notebook#goto_next()
  call assert_equal(6, b:jusi_nb.cells[2].start)
  call assert_equal(7, line('.'))
endfunction

function! Test_resize_fast_path_shifts_body_ranges_for_following_cells() abort
  call Test_open_scratch([
        \ '##',
        \ 'one',
        \ '##',
        \ 'two',
        \ '##',
        \ 'three',
        \ ])
  call append(4, 'two more')
  call jusi#notebook#handle_text_changed()

  call assert_equal(5, b:jusi_nb.cells[1].end)
  call assert_equal(5, b:jusi_nb.cells[1].body_end)
  call assert_equal(6, b:jusi_nb.cells[2].start)
  call assert_equal(7, b:jusi_nb.cells[2].end)
  call assert_equal(7, b:jusi_nb.cells[2].body_end)
endfunction

function! Test_resize_fast_path_keeps_navigation_after_deleting_first_body_line() abort
  call Test_open_scratch([
        \ '##',
        \ 'top',
        \ '##',
        \ 'middle one',
        \ 'middle two',
        \ '##',
        \ 'bottom',
        \ ])
  call deletebufline(bufnr('%'), 4)
  call jusi#notebook#handle_text_changed()

  call assert_equal(3, b:jusi_nb.cells[1].start)
  call assert_equal(4, b:jusi_nb.cells[1].end)
  call assert_equal(5, b:jusi_nb.cells[2].start)

  call cursor(2, 1)
  call jusi#notebook#goto_next()
  call assert_equal(4, line('.'))
  call jusi#notebook#goto_next()
  call assert_equal(6, line('.'))
endfunction

function! Test_linewise_put_into_new_cell_then_delete_keeps_navigation_and_ranges() abort
  call Test_open_scratch([
        \ '##',
        \ 'top',
        \ '##',
        \ 'bottom',
        \ ])
  call cursor(2, 1)
  call jusi#notebook#insert_below()
  stopinsert

  call setreg('"', ['one', 'two', 'three', 'four', 'five', 'six'], 'l')
  call cursor(4, 1)
  normal! p
  call jusi#notebook#handle_text_changed()

  call cursor(2, 1)
  call jusi#notebook#goto_next()
  call jusi#notebook#goto_prev()
  call jusi#notebook#goto_next()
  call assert_equal(4, line('.'))

  call cursor(5, 1)
  normal! dd
  call jusi#notebook#handle_text_changed()

  call assert_equal(3, b:jusi_nb.cells[1].start)
  call assert_equal(9, b:jusi_nb.cells[1].end)
  call assert_equal(10, b:jusi_nb.cells[2].start)

  call cursor(2, 1)
  call jusi#notebook#goto_next()
  call assert_equal(4, line('.'))
  call jusi#notebook#goto_next()
  call assert_equal(11, line('.'))
endfunction

function! Test_autocmd_resize_sequence_after_linewise_put_keeps_ranges_and_syntax() abort
  call Test_open_scratch([
        \ '##',
        \ 'top',
        \ '##',
        \ 'bottom one',
        \ 'bottom two',
        \ ])
  call cursor(2, 1)
  call jusi#notebook#insert_below()
  stopinsert

  call setreg('"', ['one', 'two', 'three', 'four', 'five', 'six'], 'l')
  call cursor(4, 1)
  normal! p

  call cursor(2, 1)
  call jusi#notebook#goto_next()
  call jusi#notebook#goto_prev()
  call jusi#notebook#goto_next()
  call cursor(5, 1)
  normal! dd

  call jusi#notebook#refresh_if_changed()

  call assert_equal(3, b:jusi_nb.cells[1].start)
  call assert_equal(9, b:jusi_nb.cells[1].end)
  call assert_equal(10, b:jusi_nb.cells[2].start)
  call assert_equal(12, b:jusi_nb.cells[2].end)

  call cursor(2, 1)
  call jusi#notebook#goto_next()
  call assert_equal(4, line('.'))
  call jusi#notebook#goto_next()
  call assert_equal(11, line('.'))
endfunction

function! Test_refresh_if_changed_repairs_missed_normal_mode_resize_update() abort
  call Test_open_scratch([
        \ '##',
        \ 'top',
        \ '##',
        \ 'bottom one',
        \ 'bottom two',
        \ ])
  call cursor(2, 1)
  call jusi#notebook#insert_below()
  stopinsert

  call setreg('"', ['one', 'two', 'three', 'four', 'five', 'six'], 'l')
  call cursor(4, 1)
  call feedkeys("p", 'xt')
  call cursor(5, 1)
  call feedkeys("dd", 'xt')

  call assert_notequal(b:jusi_nb.changedtick, getbufvar(bufnr('%'), 'changedtick'))
  call jusi#notebook#refresh_if_changed()

  call assert_equal(b:jusi_nb.changedtick, getbufvar(bufnr('%'), 'changedtick'))
  call assert_equal(3, b:jusi_nb.cells[1].start)
  call assert_equal(9, b:jusi_nb.cells[1].end)
  call assert_equal(10, b:jusi_nb.cells[2].start)
  call assert_equal(12, b:jusi_nb.cells[2].end)
endfunction

function! Test_cursor_move_refresh_repairs_missed_normal_mode_resize_update() abort
  call Test_open_scratch([
        \ '##',
        \ 'top',
        \ '##',
        \ 'bottom one',
        \ 'bottom two',
        \ ])
  call cursor(2, 1)
  call jusi#notebook#insert_below()
  stopinsert

  call setreg('"', ['one', 'two', 'three', 'four', 'five', 'six'], 'l')
  call cursor(4, 1)
  call feedkeys("p", 'xt')
  call cursor(5, 1)
  call feedkeys("dd", 'xt')

  call assert_notequal(b:jusi_nb.changedtick, getbufvar(bufnr('%'), 'changedtick'))
  call cursor(6, 1)
  doautocmd <nomodeline> CursorMoved

  call assert_equal(b:jusi_nb.changedtick, getbufvar(bufnr('%'), 'changedtick'))
  call assert_equal(3, b:jusi_nb.cells[1].start)
  call assert_equal(9, b:jusi_nb.cells[1].end)
  call assert_equal(10, b:jusi_nb.cells[2].start)
  call assert_equal(12, b:jusi_nb.cells[2].end)
endfunction

function! Test_refresh_if_changed_rebuilds_inconsistent_state_even_when_changedtick_matches() abort
  call Test_open_scratch([
        \ '##',
        \ 'top',
        \ '##',
        \ 'middle',
        \ '##',
        \ 'bottom',
        \ ])
  let b:jusi_nb.cells[1].end = 99
  let b:jusi_nb.cells[1].body_end = 99
  let b:jusi_nb.changedtick = getbufvar(bufnr('%'), 'changedtick')
  let b:jusi_nb.consistency_check_pending = 1

  call jusi#notebook#refresh_if_changed()

  call assert_equal(4, b:jusi_nb.cells[1].end)
  call assert_equal(4, b:jusi_nb.cells[1].body_end)
  call assert_equal(5, b:jusi_nb.cells[2].start)
  call assert_equal(6, b:jusi_nb.cells[2].end)
endfunction
