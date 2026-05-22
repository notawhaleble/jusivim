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
  call assert_equal('python', l:parsed.cells[1].syntax)
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
  let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
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
  call jusi#session#apply({'plugin_specs': {'sql': {'syntax': 'sql'}}})
  call cursor(3, 1)
  call jusi#notebook#edit_current()
  call assert_equal(['##', '%%sql main', '', '##<<', '###', 'select 0', '##>>'], getline(1, '$'))
  call assert_equal(['%%sql main', ''], jusi#notebook#cell_main_lines())
  call assert_equal(['##<<', '###', 'select 0', '##>>'], jusi#notebook#cell_history_lines())
  call assert_equal(3, line('.'))
endfunction

function! Test_append_history_entry_creates_magic_history_region() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ ])
  call jusi#session#apply({'plugin_specs': {'sql': {'syntax': 'sql'}}})
  call cursor(3, 1)
  call jusi#notebook#append_history_entry()

  call assert_equal([
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ '##<<',
        \ '###',
        \ 'select 1',
        \ '##>>',
        \ ], getline(1, '$'))
  call assert_equal(3, b:jusi_nb.cells[0].body_end)
  call assert_equal(4, b:jusi_nb.cells[0].history_start)
  call assert_equal(7, b:jusi_nb.cells[0].history_end)
endfunction

function! Test_append_history_entry_prepends_to_existing_magic_history_region() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ '##<<',
        \ '###',
        \ 'select 0',
        \ '##>>',
        \ ])
  call jusi#session#apply({'plugin_specs': {'sql': {'syntax': 'sql'}}})
  call cursor(3, 1)
  call jusi#notebook#append_history_entry()

  call assert_equal([
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ '##<<',
        \ '###',
        \ 'select 1',
        \ '###',
        \ 'select 0',
        \ '##>>',
        \ ], getline(1, '$'))
  call assert_equal(3, b:jusi_nb.cells[0].body_end)
  call assert_equal(4, b:jusi_nb.cells[0].history_start)
  call assert_equal(9, b:jusi_nb.cells[0].history_end)
endfunction

function! Test_append_history_entry_moves_duplicate_to_top() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ '##<<',
        \ '###',
        \ 'select 0',
        \ '###',
        \ 'select 1',
        \ '##>>',
        \ ])
  call jusi#session#apply({'plugin_specs': {'sql': {'syntax': 'sql'}}})
  call cursor(3, 1)
  call jusi#notebook#append_history_entry()

  call assert_equal([
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ '##<<',
        \ '###',
        \ 'select 1',
        \ '###',
        \ 'select 0',
        \ '##>>',
        \ ], getline(1, '$'))
  call assert_equal(9, b:jusi_nb.cells[0].history_end)
endfunction

function! Test_append_history_entry_dedupes_inside_closed_history_fold() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ '##<<',
        \ '###',
        \ 'select 1',
        \ '###',
        \ 'select 0',
        \ '##>>',
        \ '##',
        \ 'tail',
        \ ])
  call jusi#session#apply({'plugin_specs': {'sql': {'syntax': 'sql'}}})
  call cursor(3, 1)
  call jusi#notebook#fold_all_history(bufnr('%'))
  call assert_equal(4, foldclosed(4))

  call jusi#notebook#append_history_entry()

  call assert_equal([
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ '##<<',
        \ '###',
        \ 'select 1',
        \ '###',
        \ 'select 0',
        \ '##>>',
        \ '##',
        \ 'tail',
        \ ], getline(1, '$'))
  call assert_equal(9, b:jusi_nb.cells[0].history_end)
  call assert_equal(10, b:jusi_nb.cells[1].start)
endfunction

function! Test_paste_below_refolds_history_regions() abort
  let g:jusi_cell_clipboard = [
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ '##<<',
        \ '###',
        \ 'select 0',
        \ '##>>',
        \ ]
  call Test_open_scratch([
        \ '##',
        \ 'print("host")',
        \ ])
  call jusi#session#apply({'plugin_specs': {'sql': {'syntax': 'sql'}}})
  call cursor(2, 1)

  call jusi#notebook#paste_below()

  call assert_equal(2, len(b:jusi_nb.cells))
  call assert_equal(6, foldclosed(6))
endfunction

function! Test_capture_history_and_fold_all_preserves_cursor() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ '##<<',
        \ '###',
        \ 'select 1',
        \ '###',
        \ 'select 0',
        \ '##>>',
        \ '##',
        \ 'tail',
        \ ])
  call jusi#session#apply({'plugin_specs': {'sql': {'syntax': 'sql'}}})
  call cursor(3, 4)
  call jusi#notebook#fold_all_history(bufnr('%'))

  call jusi#notebook#capture_history_and_fold_all(b:jusi_nb.cells[0], bufnr('%'))

  call assert_equal([3, 4], [line('.'), col('.')])
  call assert_equal(4, foldclosed(4))
  call assert_equal([
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ '##<<',
        \ '###',
        \ 'select 1',
        \ '###',
        \ 'select 0',
        \ '##>>',
        \ '##',
        \ 'tail',
        \ ], getline(1, '$'))
endfunction

function! Test_append_history_entry_ignores_regular_code_cells() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call cursor(2, 1)
  call jusi#notebook#append_history_entry()

  call assert_equal(['##', 'print("hello")'], getline(1, '$'))
  call assert_equal([], jusi#notebook#cell_history_lines())
endfunction

function! Test_append_history_entry_ignores_non_plugin_magics() abort
  call Test_open_scratch([
        \ '##',
        \ '%%time',
        \ 'print("hello")',
        \ ])
  call cursor(3, 1)
  call jusi#notebook#append_history_entry()

  call assert_equal(['##', '%%time', 'print("hello")'], getline(1, '$'))
  call assert_equal([], jusi#notebook#cell_history_lines())
endfunction

function! Test_history_toggle_folds_and_unfolds_current_cell_history() abort
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

  call jusi#notebook#toggle_history_fold_current()
  call assert_equal(4, foldclosed(4))

  call jusi#notebook#toggle_history_fold_current()
  call assert_equal(-1, foldclosed(4))
endfunction

function! Test_history_fold_all_is_idempotent_and_uses_minimal_foldtext() abort
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

  call jusi#notebook#fold_all_history(bufnr('%'))
  call jusi#notebook#fold_all_history(bufnr('%'))
  call assert_equal(4, foldclosed(4))
  call assert_equal('jusi#notebook#fold_text()', &l:foldtext)
  call assert_equal('history: 4 lines', foldtextresult(4))

  call jusi#notebook#toggle_history_fold_current()
  call assert_equal(-1, foldclosed(4))
endfunction

function! Test_apply_history_at_cursor_replaces_magic_body_without_executing() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql main',
        \ 'select current',
        \ '##<<',
        \ '###',
        \ 'select old',
        \ 'where x = 1',
        \ '##>>',
        \ ])
  call cursor(6, 1)
  call jusi#notebook#apply_history_at_cursor()

  call assert_equal([
        \ '##',
        \ '%%sql main',
        \ 'select old',
        \ 'where x = 1',
        \ '##<<',
        \ '###',
        \ 'select old',
        \ 'where x = 1',
        \ '##>>',
        \ ], getline(1, '$'))
  call assert_equal(3, line('.'))
  call assert_equal(4, b:jusi_nb.cells[0].body_end)
  call assert_equal(5, foldclosed(5))
  call assert_equal('initial', b:jusi_nb.cells[0].status)
endfunction

function! Test_apply_history_relative_traverses_newest_to_oldest() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql main',
        \ 'select current',
        \ '##<<',
        \ '###',
        \ 'select newest',
        \ '###',
        \ 'select older',
        \ '##>>',
        \ ])
  call cursor(3, 1)

  call jusi#notebook#apply_history_relative(-1)
  call assert_equal('select newest', getline(3))
  call assert_equal(4, foldclosed(4))
  call jusi#notebook#apply_history_relative(-1)
  call assert_equal('select older', getline(3))
  call assert_equal(4, foldclosed(4))
  call jusi#notebook#apply_history_relative(1)
  call assert_equal('select newest', getline(3))
  call assert_equal(4, foldclosed(4))
endfunction

function! Test_cellmode_history_navigation_walks_open_history_before_next_cell() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql main',
        \ 'select current',
        \ '##<<',
        \ '###',
        \ 'select newest',
        \ '###',
        \ 'select older',
        \ '##>>',
        \ '##',
        \ 'print("tail")',
        \ ])
  call cursor(3, 1)

  call jusi#notebook#goto_next_cellmode_target()
  call assert_equal(6, line('.'))
  call jusi#notebook#goto_next_cellmode_target()
  call assert_equal(8, line('.'))
  call jusi#notebook#goto_next_cellmode_target()
  call assert_equal(11, line('.'))

  call cursor(8, 1)
  call jusi#notebook#goto_prev_cellmode_target()
  call assert_equal(6, line('.'))
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
        \ }
endfunction

function! s:test_session_adapter_attach_transport_unreachable(bufnr, payload) abort
  return {'ok': 0, 'error': 'Timed out waiting for backend response', 'error_code': 'transport_timeout'}
endfunction

let s:last_bound_prepared = {}
let s:shutdown_requests = []
let s:inspect_client_response = {}
let s:inspect_client_calls = 0
let s:inspect_client_sequence = []
let s:native_terminal_launches = []
let s:reentrant_native_terminal_refresh = {}

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
  call setbufvar(l:bufnr, '&buftype', 'nofile')
  call setbufvar(l:bufnr, '&bufhidden', 'hide')
  call setbufvar(l:bufnr, '&swapfile', 0)
  call setbufline(l:bufnr, 1, ['terminal attached'])
  call setbufvar(l:bufnr, 'jusi_client_transport_kind', 'native_terminal')
  call setbufvar(l:bufnr, 'jusi_client_transport', copy(a:transport))
  call add(s:native_terminal_launches, {
        \ 'notebook_bufnr': a:notebook_bufnr,
        \ 'cell_id': a:cell_id,
        \ 'client_id': a:client_id,
        \ 'transport': copy(a:transport),
        \ 'bufnr': l:bufnr,
        \ })
  return l:bufnr
endfunction

function! s:test_native_terminal_reentrant_launcher(notebook_bufnr, cell_id, client_id, transport) abort
  let l:bufnr = s:test_native_terminal_launcher(a:notebook_bufnr, a:cell_id, a:client_id, a:transport)
  if !get(s:reentrant_native_terminal_refresh, 'done', 0)
    let s:reentrant_native_terminal_refresh.done = 1
    call jusi#client#refresh_attached_view(
          \ a:notebook_bufnr,
          \ a:cell_id,
          \ a:client_id,
          \ get(s:reentrant_native_terminal_refresh, 'old_client_bufnr', 0))
  endif
  return l:bufnr
endfunction

function! TestNativeTerminalLauncher(notebook_bufnr, cell_id, client_id, transport) abort
  return s:test_native_terminal_launcher(a:notebook_bufnr, a:cell_id, a:client_id, a:transport)
endfunction

function! TestNativeTerminalReentrantLauncher(notebook_bufnr, cell_id, client_id, transport) abort
  return s:test_native_terminal_reentrant_launcher(a:notebook_bufnr, a:cell_id, a:client_id, a:transport)
endfunction

let s:last_request_envelope = {}
let s:request_envelopes = []
let s:test_request_response = {}

function! s:test_request_adapter(bufnr, envelope) abort
  let s:last_request_envelope = copy(a:envelope)
  call add(s:request_envelopes, copy(a:envelope))
  if type(s:test_request_response) == type({}) && !empty(s:test_request_response)
    return copy(s:test_request_response)
  endif
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
        \ 'cell': {
        \   'id': get(get(a:payload, 'cell', {}), 'id', 0),
        \   'status': 'busy',
        \   'client_id': 'client-2',
        \   'client_state': 'active',
        \   'client_bufnr': -1,
        \   'owner': {'kind': 'kernel'},
        \   },
        \ }
endfunction

function! s:test_session_adapter_execute_failure(bufnr, payload) abort
  return {'ok': 0, 'error': 'mock execute failure'}
endfunction

function! s:test_session_adapter_execute_transport_unreachable(bufnr, payload) abort
  return {'ok': 0, 'error': 'Transport is not configured', 'error_code': 'transport_unreachable'}
endfunction

function! s:test_session_adapter_interrupt_transport_unreachable(bufnr, payload) abort
  return {'ok': 0, 'error': 'Timed out waiting for backend response', 'error_code': 'transport_timeout'}
endfunction

function! s:test_session_adapter_input_reply_transport_unreachable(bufnr, payload) abort
  return {'ok': 0, 'error': 'Transport is not configured', 'error_code': 'transport_unreachable'}
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

function! s:test_session_adapter_shutdown_client_transport_unreachable(bufnr, payload) abort
  return {'ok': 0, 'error': 'Timed out waiting for backend response', 'error_code': 'transport_timeout'}
endfunction

function! s:test_session_adapter_stop(bufnr, payload) abort
  return {
        \ 'ok': 1,
        \ 'session': {
        \   'request': {},
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
        \ }
endfunction

function! s:test_session_adapter_reconnect_error(bufnr, payload) abort
  return {'ok': 0, 'error': 'Session expired', 'error_code': 'session_expired'}
endfunction

function! s:test_session_adapter_reconnect_transport_unreachable(bufnr, payload) abort
  return {'ok': 0, 'error': 'Timed out waiting for backend response', 'error_code': 'transport_timeout'}
endfunction

function! s:test_session_adapter_reconnect_not_found(bufnr, payload) abort
  return {'ok': 0, 'error': 'Session not found', 'error_code': 'session_not_found'}
endfunction

function! s:test_session_adapter_restart_start(bufnr, payload) abort
  let s:restart_calls = get(s:, 'restart_calls', [])
  call add(s:restart_calls, {'op': 'start', 'payload': copy(a:payload)})
  return {
        \ 'ok': 1,
        \ 'session': {
        \   'id': 'sess-restart-1',
        \   'kernel_id': 'kernel-restart-1',
        \   'state': 'connected',
        \   'kernel_name': get(a:payload, 'kernel_name', ''),
        \   'connection': 'mock://kernel/' . get(a:payload, 'kernel_name', ''),
        \   'target': copy(get(a:payload, 'target', {})),
        \   },
        \ }
endfunction

function! s:test_session_adapter_restart_stop(bufnr, payload) abort
  let s:restart_calls = get(s:, 'restart_calls', [])
  call add(s:restart_calls, {'op': 'stop', 'payload': copy(a:payload)})
  return {
        \ 'ok': 1,
        \ 'session': {
        \   'request': {},
        \   },
        \ }
endfunction

function! s:test_session_adapter_restart_stop_transport(bufnr, payload) abort
  let s:restart_calls = get(s:, 'restart_calls', [])
  call add(s:restart_calls, {'op': 'stop', 'payload': copy(a:payload)})
  return {'ok': 1, '_transport': 1}
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
  call assert_equal({}, get(l:session, 'palette', {}))
  call assert_equal({}, get(l:session, 'plugin_specs', {}))
  call assert_false(has_key(l:session, 'prepared'))
endfunction

function! Test_config_ensure_file_creates_default_jusi_toml() abort
  let l:save_config = get(g:, 'jusi_config_file', '')
  try
    let g:jusi_config_file = tempname() . '/jusi.toml'
    let l:path = jusi#config#ensure_file()
    call assert_equal(fnamemodify(g:jusi_config_file, ':p'), l:path)
    call assert_true(filereadable(l:path))
    let l:lines = readfile(l:path)
    call assert_true(index(l:lines, '[plugins]') >= 0)
  finally
    let g:jusi_config_file = l:save_config
  endtry
endfunction

function! Test_config_load_visidatarc_reads_raw_content() abort
  let l:path = tempname() . '.visidatarc'
  let l:save_visidatarc = get(g:, 'jusi_visidatarc_file', '')
  try
    let g:jusi_visidatarc_file = l:path
    call writefile([
          \ 'from visidata import vd',
          \ 'vd.options.set(''disp_menu'', False)',
          \ ], l:path)
    let l:result = jusi#config#load_visidatarc()
    call assert_equal(1, l:result.ok)
    call assert_equal("from visidata import vd\nvd.options.set('disp_menu', False)\n", l:result.content)
  finally
    let g:jusi_visidatarc_file = l:save_visidatarc
    call delete(l:path)
  endtry
endfunction

function! Test_config_load_parses_nested_plugin_sections() abort
  let l:save_config = get(g:, 'jusi_config_file', '')
  try
    let g:jusi_config_file = tempname()
    call writefile([
          \ '[plugins.sqlite]',
          \ 'database = "/tmp/app.db"',
          \ 'readonly = true',
          \ 'limit = 10',
          \ 'columns = ["id", "name"]',
          \ ], g:jusi_config_file)
    let l:result = jusi#config#load()
    call assert_equal(1, l:result.ok)
    call assert_equal('/tmp/app.db', get(get(get(l:result.config, 'plugins', {}), 'sqlite', {}), 'database', ''))
    call assert_equal(v:true, get(get(get(l:result.config, 'plugins', {}), 'sqlite', {}), 'readonly', v:false))
    call assert_equal(10, get(get(get(l:result.config, 'plugins', {}), 'sqlite', {}), 'limit', 0))
    call assert_equal(['id', 'name'], get(get(get(l:result.config, 'plugins', {}), 'sqlite', {}), 'columns', []))
  finally
    let g:jusi_config_file = l:save_config
  endtry
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
        \ 'visidatarc': "vd.options.set('disp_menu', False)\n",
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
  call assert_equal("vd.options.set('disp_menu', False)\n", l:request.payload.visidatarc)
endfunction

function! Test_adapter_builds_attach_session_request_with_visidatarc() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let l:request = jusi#adapter#build_request('attach', bufnr('%'), {
        \ 'target': {'kind': 'connection_file', 'value': '/tmp/kernel.json'},
        \ 'visidatarc': "set-option foo\n",
        \ })
  call assert_equal('attach_session', l:request.type)
  call assert_equal('/tmp/kernel.json', l:request.payload.target.value)
  call assert_equal("set-option foo\n", l:request.payload.visidatarc)
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
    call assert_equal({}, get(l:session, 'prepared', {}))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_start_kernel_request_includes_resolved_target() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:save_targets = get(g:, 'jusi_kernel_targets', {})
  let l:save_config = get(g:, 'jusi_config_file', '')
  try
    let g:jusi_session_adapter = {'request': function('s:test_request_adapter')}
    let g:jusi_kernel_targets = {
          \ 'py': {
          \   'kind': 'venv',
          \   'connection': 'venv://myenv1',
          \   'label': 'local venv',
          \   },
          \ }
    let g:jusi_config_file = tempname()
    call writefile([
          \ '[plugins.sqlite]',
          \ 'database = "/tmp/start.db"',
          \ ], g:jusi_config_file)
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
    call assert_equal('/tmp/start.db', get(get(get(get(get(get(s:last_request_envelope, 'payload', {}), 'target', {}), 'config', {}), 'plugins', {}), 'sqlite', {}), 'database', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_kernel_targets = l:save_targets
    let g:jusi_config_file = l:save_config
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

function! Test_start_kernel_request_preserves_nested_target_config_without_structural_nesting() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:save_targets = get(g:, 'jusi_kernel_targets', {})
  try
    let g:jusi_session_adapter = {'request': function('s:test_request_adapter')}
    let g:jusi_kernel_targets = {
          \ 'dockerjusi': {
          \   'kind': 'docker',
          \   'value': 'docker://jolly_blackwell',
          \   'config': {'kernel_name': 'python3'},
          \   },
          \ }
    let s:last_request_envelope = {}
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('dockerjusi')
    call assert_equal('start_session', get(s:last_request_envelope, 'type', ''))
    call assert_equal('docker', get(get(get(s:last_request_envelope, 'payload', {}), 'target', {}), 'kind', ''))
    call assert_equal('docker://jolly_blackwell', get(get(get(s:last_request_envelope, 'payload', {}), 'target', {}), 'value', ''))
    call assert_equal('python3', get(get(get(get(s:last_request_envelope, 'payload', {}), 'target', {}), 'config', {}), 'kernel_name', ''))
    call assert_false(has_key(get(get(get(get(s:last_request_envelope, 'payload', {}), 'target', {}), 'config', {}), 'config', {}), 'kernel_name'))
    call assert_false(has_key(get(get(get(s:last_request_envelope, 'payload', {}), 'target', {}), 'config', {}), 'kind'))
    call assert_false(has_key(get(get(get(s:last_request_envelope, 'payload', {}), 'target', {}), 'config', {}), 'value'))
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_kernel_targets = l:save_targets
  endtry
endfunction

function! Test_transport_backend_cmd_for_venv_target_uses_venv_python() abort
  let l:venv = '/tmp/jusi-test-venv'
  let l:cmd = jusi#transport#backend_cmd_for_target({
        \ 'kind': 'venv',
        \ 'value': 'venv://' . l:venv,
        \ })
  call assert_equal([fnamemodify(l:venv . '/bin/python', ':p'), '-m', 'jusi'], l:cmd)
endfunction

function! Test_transport_backend_cmd_for_local_target_uses_default_backend() abort
  let l:cmd = jusi#transport#backend_cmd_for_target({
        \ 'kind': 'local',
        \ 'value': 'local://',
        \ })
  call assert_equal(jusi#transport#default_backend_cmd(), l:cmd)
endfunction

function! Test_transport_backend_cmd_for_ssh_target_supports_auth_options() abort
  let l:cmd = jusi#transport#backend_cmd_for_target({
        \ 'kind': 'ssh',
        \ 'value': 'ssh://niku@example.com',
        \ 'config': {
        \   'key_path': '/tmp/test-key',
        \   'port': 2222,
        \   },
        \ })
  call assert_equal(['ssh', '-i', '/tmp/test-key', '-p', '2222', 'niku@example.com', 'python3', '-m', 'jusi'], l:cmd)

  let l:password_cmd = jusi#transport#backend_cmd_for_target({
        \ 'kind': 'ssh',
        \ 'value': 'ssh://example.com',
        \ 'config': {
        \   'user': 'root',
        \   'password': 'secret',
        \   },
        \ })
  call assert_equal(['sshpass', '-p', 'secret', 'ssh', 'root@example.com', 'python3', '-m', 'jusi'], l:password_cmd)
endfunction

function! Test_transport_backend_cmd_for_docker_target_uses_container_name() abort
  let l:cmd = jusi#transport#backend_cmd_for_target({
        \ 'kind': 'docker',
        \ 'value': 'docker://jusi-backend',
        \ })
  call assert_equal(['docker', 'exec', '-i', 'jusi-backend', 'python3', '-m', 'jusi'], l:cmd)
endfunction

function! Test_transport_backend_cmd_for_docker_ssh_target_combines_remote_and_container() abort
  let l:cmd = jusi#transport#backend_cmd_for_target({
        \ 'kind': 'docker+ssh',
        \ 'value': 'docker+ssh://niku@example.com/jusi-backend',
        \ 'config': {
        \   'key_path': '/tmp/test-key',
        \   },
        \ })
  call assert_equal(['ssh', '-i', '/tmp/test-key', 'niku@example.com', 'docker', 'exec', '-i', 'jusi-backend', 'python3', '-m', 'jusi'], l:cmd)
endfunction

function! Test_transport_terminal_attach_spec_for_venv_target_rewrites_python_and_keeps_env() abort
  let l:venv = '/tmp/jusi-test-venv'
  let l:spec = jusi#transport#terminal_attach_spec_for_target({
        \ 'kind': 'venv',
        \ 'value': 'venv://' . l:venv,
        \ }, ['python3', '-m', 'jusi', 'client-process', 'terminal-attach'], {'A': '1'})
  call assert_equal([fnamemodify(l:venv . '/bin/python', ':p'), '-m', 'jusi', 'client-process', 'terminal-attach'], get(l:spec, 'cmd', []))
  call assert_equal({'A': '1'}, get(l:spec, 'env', {}))
endfunction

function! Test_transport_rewrites_native_terminal_exec_attach_env_for_venv_target() abort
  let l:save_path = $PATH
  let l:save_home = $HOME
  let l:save_term = $TERM
  try
    let $PATH = '/usr/bin:/bin'
    let $HOME = '/Users/niku'
    let $TERM = 'xterm-256color'
    let l:venv = '/tmp/jusi-test-venv'
    let l:env = jusi#transport#rewrite_native_terminal_attach_env_for_target({
          \ 'kind': 'venv',
          \ 'value': 'venv://' . l:venv,
          \ }, {
          \ 'JUSI_TERMINAL_CMD_JSON': json_encode(['/usr/local/bin/python3', '-m', 'jusi', 'plugin-runtime']),
          \ 'JUSI_TERMINAL_ENV_JSON': json_encode({
          \   'PATH': '/usr/local/bin:/usr/bin',
          \   'HOME': '/root',
          \   'HOSTNAME': 'old-container',
          \   'TERM': 'xterm-256color',
          \   'JUSI_PLUGIN_RUNTIME_CALLABLE': 'jusi_vd.runner:run_vd_runner',
          \   }),
          \ })
    call assert_equal(
          \ [fnamemodify(l:venv . '/bin/python', ':p'), '-m', 'jusi', 'plugin-runtime'],
          \ json_decode(get(l:env, 'JUSI_TERMINAL_CMD_JSON', '[]')))
    let l:child_env = json_decode(get(l:env, 'JUSI_TERMINAL_ENV_JSON', '{}'))
    call assert_equal('jusi_vd.runner:run_vd_runner', get(l:child_env, 'JUSI_PLUGIN_RUNTIME_CALLABLE', ''))
    call assert_equal('/Users/niku', get(l:child_env, 'HOME', ''))
    call assert_equal('xterm-256color', get(l:child_env, 'TERM', ''))
    call assert_equal('/tmp/jusi-test-venv', get(l:child_env, 'VIRTUAL_ENV', ''))
    call assert_equal(fnamemodify(l:venv . '/bin', ':p') . ':' . $PATH, get(l:child_env, 'PATH', ''))
    call assert_false(has_key(l:child_env, 'HOSTNAME'))
  finally
    let $PATH = l:save_path
    let $HOME = l:save_home
    let $TERM = l:save_term
  endtry
endfunction


function! Test_transport_terminal_attach_spec_for_docker_target_wraps_command_and_env() abort
  let l:save_term = $TERM
  let l:save_colorterm = $COLORTERM
  try
    let $TERM = 'xterm-256color'
    let $COLORTERM = 'truecolor'
    let l:spec = jusi#transport#terminal_attach_spec_for_target({
          \ 'kind': 'docker',
          \ 'value': 'docker://jusi-backend',
          \ }, ['python3', '-m', 'jusi', 'client-process', 'terminal-attach'], {'B': '2', 'A': '1'})
    call assert_equal(['docker', 'exec', '-it', '-e', 'A=1', '-e', 'B=2', '-e', 'COLORTERM=truecolor', '-e', 'TERM=xterm-256color', 'jusi-backend', 'python3', '-m', 'jusi', 'client-process', 'terminal-attach'], get(l:spec, 'cmd', []))
    call assert_equal({}, get(l:spec, 'env', {}))
  finally
    let $TERM = l:save_term
    let $COLORTERM = l:save_colorterm
  endtry
endfunction

function! Test_transport_terminal_attach_spec_for_ssh_target_wraps_command_and_env() abort
  let l:spec = jusi#transport#terminal_attach_spec_for_target({
        \ 'kind': 'ssh',
        \ 'value': 'ssh://niku@example.com',
        \ 'config': {'key_path': '/tmp/test-key'},
        \ }, ['python3', '-m', 'jusi', 'client-process', 'terminal-attach'], {'A': '1'})
  call assert_equal(['ssh', '-tt', '-i', '/tmp/test-key', 'niku@example.com', 'env', 'A=1', 'python3', '-m', 'jusi', 'client-process', 'terminal-attach'], get(l:spec, 'cmd', []))
  call assert_equal({}, get(l:spec, 'env', {}))
endfunction

function! Test_transport_terminal_attach_spec_for_docker_ssh_target_wraps_command_env_and_tty() abort
  let l:save_term = $TERM
  try
    let $TERM = 'xterm-256color'
    let l:spec = jusi#transport#terminal_attach_spec_for_target({
          \ 'kind': 'docker+ssh',
          \ 'value': 'docker+ssh://niku@example.com/jusi-backend',
          \ 'config': {'key_path': '/tmp/test-key'},
          \ }, ['python3', '-m', 'jusi', 'client-process', 'terminal-attach'], {'A': '1'})
    call assert_equal(['ssh', '-tt', '-i', '/tmp/test-key', 'niku@example.com', 'docker', 'exec', '-it', '-e', 'A=1', '-e', 'TERM=xterm-256color', 'jusi-backend', 'python3', '-m', 'jusi', 'client-process', 'terminal-attach'], get(l:spec, 'cmd', []))
    call assert_equal({}, get(l:spec, 'env', {}))
  finally
    let $TERM = l:save_term
  endtry
endfunction

function! Test_cell_callback_ignores_stale_client_update_after_rebind() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd pods',
        \ ])
  let l:cell_id = b:jusi_nb.cells[0].id
  let b:jusi_nb.session.id = 'sess-1'
  let b:jusi_nb.session.state = 'connected'
  let b:jusi_nb.cells[0].status = 'busy'
  let b:jusi_nb.cells[0].client_id = 'client-new'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = 91

  call jusi#session#callback_cell(l:cell_id, {
        \ 'client_id': 'client-old',
        \ 'client_state': 'shutdown',
        \ 'client_bufnr': -1,
        \ 'status': 'done',
        \ })

  call assert_equal('client-new', b:jusi_nb.cells[0].client_id)
  call assert_equal('active', b:jusi_nb.cells[0].client_state)
  call assert_equal(91, b:jusi_nb.cells[0].client_bufnr)
  call assert_equal('busy', b:jusi_nb.cells[0].status)
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
  let l:save_config = get(g:, 'jusi_config_file', '')
  try
    let g:jusi_session_adapter = {'request': function('s:test_request_adapter')}
    let g:jusi_attach_registry_file = tempname()
    let g:jusi_config_file = tempname()
    call writefile([
          \ '[plugins.sqlite]',
          \ 'database = "/tmp/attach.db"',
          \ ], g:jusi_config_file)
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
    call assert_equal('/tmp/attach.db', get(get(get(get(get(get(s:last_request_envelope, 'payload', {}), 'target', {}), 'config', {}), 'plugins', {}), 'sqlite', {}), 'database', ''))
    call assert_equal('connection_file', get(get(b:jusi_nb.session, 'target', {}), 'kind', ''))
    call assert_equal('/tmp/kernel-123.json', get(get(b:jusi_nb.session, 'target', {}), 'value', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_attach_registry_file = l:save_registry
    let g:jusi_config_file = l:save_config
  endtry
endfunction

function! Test_start_rejects_invalid_local_jusi_config() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:save_config = get(g:, 'jusi_config_file', '')
  try
    let g:jusi_session_adapter = {'request': function('s:test_request_adapter')}
    let g:jusi_config_file = tempname()
    call writefile(['[plugins.sqlite]', 'database = {'], g:jusi_config_file)
    let s:last_request_envelope = {}
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('python3')
    call assert_equal('idle', b:jusi_nb.session.state)
    call assert_match('Invalid Jusi config', b:jusi_nb.session.last_error)
    call assert_equal({}, s:last_request_envelope)
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_config_file = l:save_config
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

function! Test_attach_unknown_alias_preserves_existing_registry_entry() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:save_registry = get(g:, 'jusi_attach_registry_file', '')
  try
    let g:jusi_session_adapter = {'request': function('s:test_request_adapter')}
    let g:jusi_attach_registry_file = tempname()
    call writefile([
          \ json_encode({
          \   'ololo-jusi': {
          \     'session_id': 'sess-attach-1',
          \     'kernel_id': 'kernel-attach-1',
          \     'target': {'kind': 'connection_file', 'value': '/tmp/kernel-abc.json'},
          \   },
          \ }),
          \ ], g:jusi_attach_registry_file)
    let s:last_request_envelope = {}
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    let b:jusi_nb.session.state = 'disconnected'
    let b:jusi_nb.session.id = 'sess-attach-1'
    let b:jusi_nb.session.attach_name = 'ololo-jusi'
    let b:jusi_nb.session.target = {'source': 'attach', 'alias': 'ololo-jusi', 'kind': 'connection_file', 'value': '/tmp/kernel-abc.json', 'config': {}}
    call jusi#session#attach('ololo-jusi-typo')
    call assert_equal('disconnected', b:jusi_nb.session.state)
    call assert_equal('sess-attach-1', b:jusi_nb.session.id)
    call assert_equal('ololo-jusi', b:jusi_nb.session.attach_name)
    call assert_match('Unknown attach target alias: ololo-jusi-typo', b:jusi_nb.session.last_error)
    call assert_equal({}, s:last_request_envelope)
    let l:registry = jusi#session#attach_registry()
    call assert_true(has_key(l:registry, 'ololo-jusi'))
    call assert_false(has_key(l:registry, 'ololo-jusi-typo'))
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_attach_registry_file = l:save_registry
  endtry
endfunction

function! Test_attach_registry_alias_timeout_preserves_registry_entry() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:save_registry = get(g:, 'jusi_attach_registry_file', '')
  try
    let g:jusi_session_adapter = {'reconnect': function('s:test_session_adapter_reconnect_transport_unreachable')}
    let g:jusi_attach_registry_file = tempname()
    call writefile([
          \ json_encode({
          \   'ololo-jusi': {
          \     'session_id': 'sess-attach-1',
          \     'kernel_id': 'kernel-attach-1',
          \     'target': {'kind': 'connection_file', 'value': '/tmp/kernel-abc.json'},
          \   },
          \ }),
          \ ], g:jusi_attach_registry_file)
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#attach('ololo-jusi')
    call assert_equal('disconnected', b:jusi_nb.session.state)
    call assert_equal('transport_timeout', b:jusi_nb.session.last_error_code)
    call assert_match('Backend is unreachable', b:jusi_nb.session.last_error)
    let l:registry = jusi#session#attach_registry()
    call assert_true(has_key(l:registry, 'ololo-jusi'))
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_attach_registry_file = l:save_registry
  endtry
endfunction

function! Test_attach_registry_alias_timeout_preserves_existing_cell_runtime() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:save_registry = get(g:, 'jusi_attach_registry_file', '')
  try
    let g:jusi_session_adapter = {'reconnect': function('s:test_session_adapter_reconnect_transport_unreachable')}
    let g:jusi_attach_registry_file = tempname()
    call writefile([
          \ json_encode({
          \   'ololo-jusi': {
          \     'session_id': 'sess-attach-1',
          \     'kernel_id': 'kernel-attach-1',
          \     'target': {'kind': 'connection_file', 'value': '/tmp/kernel-abc.json'},
          \   },
          \ }),
          \ ], g:jusi_attach_registry_file)
    call Test_open_scratch([
          \ '##',
          \ '%%vd data',
          \ ])
    let l:client = jusi#client#create_managed_buffer(bufnr('%'), 'client-old')
    call jusi#client#mark_attached_buffer(bufnr('%'), b:jusi_nb.cells[0].id, 'client-old', l:client)
    let b:jusi_nb.session.state = 'disconnected'
    let b:jusi_nb.session.id = 'sess-attach-1'
    let b:jusi_nb.session.attach_name = 'ololo-jusi'
    let b:jusi_nb.session.target = {'source': 'attach', 'alias': 'ololo-jusi', 'kind': 'connection_file', 'value': '/tmp/kernel-abc.json', 'config': {}}
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].client_id = 'client-old'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client

    call jusi#session#attach('ololo-jusi')

    call assert_equal('disconnected', b:jusi_nb.session.state)
    call assert_equal('client-old', b:jusi_nb.cells[0].client_id)
    call assert_equal('active', b:jusi_nb.cells[0].client_state)
    call assert_equal(l:client, b:jusi_nb.cells[0].client_bufnr)
    call assert_true(bufexists(l:client))
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_attach_registry_file = l:save_registry
  endtry
endfunction

function! Test_attach_registry_alias_authoritative_reconnect_error_removes_registry_entry() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:save_registry = get(g:, 'jusi_attach_registry_file', '')
  try
    let g:jusi_session_adapter = {'reconnect': function('s:test_session_adapter_reconnect_not_found')}
    let g:jusi_attach_registry_file = tempname()
    call writefile([
          \ json_encode({
          \   'ololo-jusi': {
          \     'session_id': 'sess-attach-1',
          \     'kernel_id': 'kernel-attach-1',
          \     'target': {'kind': 'connection_file', 'value': '/tmp/kernel-abc.json'},
          \   },
          \ }),
          \ ], g:jusi_attach_registry_file)
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#attach('ololo-jusi')
    call assert_equal('failed', b:jusi_nb.session.state)
    call assert_equal('session_not_found', b:jusi_nb.session.last_error_code)
    let l:registry = jusi#session#attach_registry()
    call assert_false(has_key(l:registry, 'ololo-jusi'))
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_attach_registry_file = l:save_registry
  endtry
endfunction

function! Test_attach_direct_transport_failure_keeps_previous_session_state() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'attach': function('s:test_session_adapter_attach_transport_unreachable')}
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#attach('ssh://user@host1')
    call assert_equal('idle', b:jusi_nb.session.state)
    call assert_equal('transport_timeout', b:jusi_nb.session.last_error_code)
    call assert_match('Backend is unreachable', b:jusi_nb.session.last_error)
    call assert_equal('', get(b:jusi_nb.session, 'id', ''))
    call assert_equal('', get(get(b:jusi_nb.session, 'target', {}), 'kind', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
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

function! Test_execute_magic_cell_appends_history_after_accepted_request() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'execute': function('s:test_session_adapter_execute'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ '%%sql main',
          \ 'select 1',
          \ ])
    call jusi#session#apply({'id': 'sess-1', 'state': 'connected', 'plugin_specs': {'sql': {'syntax': 'sql'}}})
    call cursor(3, 1)

    call jusi#session#execute_current()

    call assert_equal([
          \ '##',
          \ '%%sql main',
          \ 'select 1',
          \ '##<<',
          \ '###',
          \ 'select 1',
          \ '##>>',
          \ ], getline(1, '$'))
    call assert_equal('busy', b:jusi_nb.cells[0].status)
    call assert_equal(['%%sql main', 'select 1'], jusi#notebook#cell_main_lines(b:jusi_nb.cells[0]))
    call assert_equal([3, 1], [line('.'), col('.')])
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_execute_and_edit_current_clears_body_after_accepted_magic_execute() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'execute': function('s:test_session_adapter_execute'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ '%%sql main',
          \ 'select 1',
          \ ])
    call jusi#session#apply({'id': 'sess-1', 'state': 'connected', 'plugin_specs': {'sql': {'syntax': 'sql'}}})
    call cursor(3, 1)

    call jusi#notebook#execute_and_edit_current()

    call assert_equal([
          \ '##',
          \ '%%sql main',
          \ '',
          \ '##<<',
          \ '###',
          \ 'select 1',
          \ '##>>',
          \ ], getline(1, '$'))
    call assert_equal(['%%sql main', ''], jusi#notebook#cell_main_lines(b:jusi_nb.cells[0]))
    call assert_equal(['##<<', '###', 'select 1', '##>>'], jusi#notebook#cell_history_lines(b:jusi_nb.cells[0]))
    call assert_equal(3, line('.'))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_execute_code_cell_does_not_append_history() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'execute': function('s:test_session_adapter_execute'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#apply({'id': 'sess-1', 'state': 'connected'})
    call cursor(2, 1)

    call jusi#session#execute_current()

    call assert_equal(['##', 'print("hello")'], getline(1, '$'))
    call assert_equal([], jusi#notebook#cell_history_lines(b:jusi_nb.cells[0]))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_execute_rejected_magic_cell_does_not_append_history() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'execute': function('s:test_session_adapter_execute_failure'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ '%%sql main',
          \ 'select 1',
          \ ])
    call jusi#session#apply({'id': 'sess-1', 'state': 'connected', 'plugin_specs': {'sql': {'syntax': 'sql'}}})
    call cursor(3, 1)

    call jusi#session#execute_current()

    call assert_equal(['##', '%%sql main', 'select 1'], getline(1, '$'))
    call assert_equal([], jusi#notebook#cell_history_lines(b:jusi_nb.cells[0]))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_interrupt_rejects_non_busy_cells() abort
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
    call assert_match('Cannot interrupt the current cell unless it is busy', b:jusi_nb.session.last_error)
    call assert_equal('follow-up', b:jusi_nb.cells[0].status)
    call assert_equal('handler', get(get(b:jusi_nb.cells[0], 'owner', {}), 'kind', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_execute_transport_failure_keeps_connected_session_state() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'execute': function('s:test_session_adapter_execute_transport_unreachable'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('python3')
    call jusi#session#execute_current()
    call assert_equal('connected', b:jusi_nb.session.state)
    call assert_equal('transport_unreachable', b:jusi_nb.session.last_error_code)
    call assert_match('Backend is unreachable', b:jusi_nb.session.last_error)
    call assert_equal('initial', b:jusi_nb.cells[0].status)
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_interrupt_transport_failure_keeps_connected_session_state() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'interrupt': function('s:test_session_adapter_interrupt_transport_unreachable'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ '%%sql main',
          \ 'select 1',
          \ ])
    call jusi#session#start('python3')
    let b:jusi_nb.cells[0].status = 'busy'
    let b:jusi_nb.cells[0].owner = {'kind': 'kernel'}
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = 91
    call jusi#session#interrupt_current()
    call assert_equal('connected', b:jusi_nb.session.state)
    call assert_equal('transport_timeout', b:jusi_nb.session.last_error_code)
    call assert_match('Backend is unreachable', b:jusi_nb.session.last_error)
    call assert_equal('busy', b:jusi_nb.cells[0].status)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_reply_input_transport_failure_keeps_connected_session_state() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'input_reply': function('s:test_session_adapter_input_reply_transport_unreachable'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#start('python3')
    let b:jusi_nb.cells[0].status = 'busy'
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].pending_input = {'prompt': 'value', 'password': 0}
    call jusi#session#reply_input_current('hello')
    call assert_equal('connected', b:jusi_nb.session.state)
    call assert_equal('transport_unreachable', b:jusi_nb.session.last_error_code)
    call assert_match('Backend is unreachable', b:jusi_nb.session.last_error)
    call assert_equal({'prompt': 'value', 'password': 0}, b:jusi_nb.cells[0].pending_input)
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
    let l:client = jusi#client#create_managed_buffer(bufnr('%'), 'client-done')
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
    let l:client = jusi#client#create_managed_buffer(bufnr('%'), 'client-1')
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    call jusi#session#close_current_client()
    call assert_false(bufexists(l:client))
    call assert_equal('initial', b:jusi_nb.cells[0].status)
    call assert_equal('', b:jusi_nb.cells[0].client_id)
    call assert_equal('shutdown', b:jusi_nb.cells[0].client_state)
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
    call assert_equal('', get(get(b:jusi_nb.cells[0], 'owner', {}), 'kind', ''))
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
    let l:client = jusi#client#create_managed_buffer(bufnr('%'), 'client-1')
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
    call assert_equal('initial', b:jusi_nb.cells[0].status)
    call assert_equal('', b:jusi_nb.cells[0].client_id)
    call assert_equal('shutdown', b:jusi_nb.cells[0].client_state)
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
    call assert_equal('', get(get(b:jusi_nb.cells[0], 'owner', {}), 'kind', ''))
    call assert_equal(0, get(b:jusi_nb.cells[0], 'close_requested', 0))
    call assert_equal('shutdown_client', get(s:last_request_envelope, 'type', ''))
    call assert_equal('user_close', get(s:last_request_envelope, 'payload', {}).reason)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_close_client_transport_failure_keeps_connected_session_state() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_start'),
          \ 'shutdown_client': function('s:test_session_adapter_shutdown_client_transport_unreachable'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ '%%sql main',
          \ 'select 1',
          \ ])
    call jusi#session#start('python3')
    let l:client = jusi#client#create_managed_buffer(bufnr('%'), 'client-1')
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    call jusi#client#mark_attached_buffer(bufnr('%'), b:jusi_nb.cells[0].id, 'client-1', l:client)

    call jusi#session#close_current_client()

    call assert_equal('connected', b:jusi_nb.session.state)
    call assert_equal('transport_timeout', b:jusi_nb.session.last_error_code)
    call assert_match('Backend is unreachable', b:jusi_nb.session.last_error)
    call assert_equal('follow-up', b:jusi_nb.cells[0].status)
    call assert_equal('active', b:jusi_nb.cells[0].client_state)
    call assert_equal(l:client, b:jusi_nb.cells[0].client_bufnr)
    call assert_equal(0, get(b:jusi_nb.cells[0], 'close_requested', 0))
    call assert_true(bufexists(l:client))
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
    let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
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

function! Test_close_client_after_transport_close_requires_attached_buffer() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'request': function('s:test_transport_like_request_adapter')}
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'
    let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
    call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)
    let b:jusi_nb.cells[0].status = 'done'
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    let b:jusi_nb.cells[0].owner = {'kind': 'kernel'}

    call jusi#session#close_current_client()
    call assert_equal('detached', getbufvar(l:client, 'jusi_client_role', ''))
    call assert_equal('client-1', b:jusi_nb.cells[0].client_id)
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)

    call jusi#session#close_current_client()
    call assert_match('Cannot close client without an attached client buffer', b:jusi_nb.session.last_error)
    call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
    call assert_equal('detached', getbufvar(l:client, 'jusi_client_role', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_toggle_park_marks_terminal_client_and_restores_status() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let l:client = jusi#client#create_managed_buffer(bufnr('%'), 'client-done')
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
  let l:client = jusi#client#create_managed_buffer(bufnr('%'), 'client-1')
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  call jusi#session#toggle_park_current_client()
  call assert_equal('idle', b:jusi_nb.session.state)
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
  let l:client = jusi#client#create_managed_buffer(bufnr('%'), 'client-1')
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
  let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-2')
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
  let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
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
  call assert_equal(l:client, getbufvar(l:notebook, 'jusi_nb').cells[0].client_bufnr)
endfunction

function! Test_toggle_focus_recovers_from_mismatched_existing_client_bufnr() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd pods',
        \ '##',
        \ 'print("other")',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[1].id
  let l:wrong = jusi#client#create_managed_buffer(l:notebook, 'client-wrong')
  let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-2')
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-2', l:client)
  let b:jusi_nb.cells[1].status = 'follow-up'
  let b:jusi_nb.cells[1].owner = {'kind': 'handler'}
  let b:jusi_nb.cells[1].client_id = 'client-2'
  let b:jusi_nb.cells[1].client_state = 'active'
  let b:jusi_nb.cells[1].client_bufnr = l:wrong

  call cursor(4, 1)
  call jusi#focus#toggle()

  call assert_equal(l:client, bufnr('%'))
  call assert_equal(l:client, getbufvar(l:notebook, 'jusi_nb').cells[1].client_bufnr)
endfunction

function! Test_cell_callback_recovers_stale_attached_client_bufnr_from_managed_client_metadata() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd pods',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  call jusi#session#apply({'state': 'connected', 'id': 'sess-1'})
  let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)
  call setbufvar(l:client, 'jusi_client_transport_kind', 'native_terminal')
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

function! Test_cell_callback_reuses_existing_attached_buffer_for_same_client() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd',
        \ 'a',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  call jusi#session#apply({'state': 'connected', 'id': 'sess-1'})
  let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = -1

  call jusi#session#callback_cell(l:cell_id, {
        \ 'status': 'done',
        \ 'client_id': 'client-1',
        \ 'client_state': 'active',
        \ 'client_bufnr': -1,
        \ 'owner': {'kind': 'handler'},
        \ })

  let l:matches = []
  for l:bufnr in range(1, bufnr('$'))
    if getbufvar(l:bufnr, 'jusi_client_id', '') ==# 'client-1'
          \ && getbufvar(l:bufnr, 'jusi_client_notebook_bufnr', -1) ==# l:notebook
      call add(l:matches, l:bufnr)
    endif
  endfor
  call assert_equal(l:client, b:jusi_nb.cells[0].client_bufnr)
  call assert_equal([l:client], l:matches)
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
    let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
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
    let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
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
    let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
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
  let l:save_launcher_ref = get(g:, 'JusiNativeTerminalLauncher', 0)
  try
    let g:jusi_session_adapter = {
          \ 'inspect_client': function('s:test_session_adapter_inspect_client'),
          \ 'request': function('s:test_request_adapter'),
          \ }
    let g:JusiNativeTerminalLauncher = function('TestNativeTerminalLauncher')
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
    let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
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

    call jusi#session#callback_cell(l:cell_id, {
          \ 'status': 'done',
          \ 'owner': {'kind': 'kernel'},
          \ 'transport': copy(get(s:inspect_client_response, 'transport', {})),
          \ 'client_state': 'active',
          \ 'runtime_mode': 'transcript',
          \ 'client_id': 'client-1',
          \ }, l:notebook)
    call assert_equal(l:new_client, get(b:jusi_nb.cells[0], 'client_bufnr', -1))
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_native_terminal_launcher = l:save_launcher
    if type(l:save_launcher_ref) == type(function('tr'))
      let g:JusiNativeTerminalLauncher = l:save_launcher_ref
    else
      unlet! g:JusiNativeTerminalLauncher
    endif
  endtry
endfunction

function! Test_client_refresh_attached_view_can_keep_transcript_for_remote_kernel_cells() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:save_launcher = get(g:, 'jusi_native_terminal_launcher', 0)
  let l:save_launcher_ref = get(g:, 'JusiNativeTerminalLauncher', 0)
  let l:save_fallback = get(g:, 'jusi_remote_plain_cell_transcript_fallback', 0)
  try
    let g:jusi_session_adapter = {
          \ 'inspect_client': function('s:test_session_adapter_inspect_client'),
          \ 'request': function('s:test_request_adapter'),
          \ }
    let g:JusiNativeTerminalLauncher = function('TestNativeTerminalLauncher')
    let g:jusi_remote_plain_cell_transcript_fallback = 1
    let s:inspect_client_calls = 0
    let s:native_terminal_launches = []
    let s:request_envelopes = []
    let s:inspect_client_response = {
          \ 'revision': 8,
          \ 'title': 'cell 1: done',
          \ 'lines': [
          \   'meta> client=client-1 session=sess-1 bufnr=unbound',
          \   'started cell 1 [code:python]',
          \   'execute[1]> print(''lalala'')',
          \   'stdout> lalala',
          \   'finished: done',
          \   ],
          \ 'execution_status': 'done',
          \ 'transport': {
          \   'kind': 'native_terminal',
          \   'attach_cmd': ['python3', '-m', 'jusi', 'client-process', 'terminal-attach'],
          \   'attach_env': {'JUSI_SESSION_ID': 'sess-1', 'JUSI_CLIENT_ID': 'client-1'},
          \   'session_id': 'sess-1',
          \   'client_id': 'client-1',
          \   },
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'
    let b:jusi_nb.session.target = {'kind': 'docker', 'value': 'docker://jusi-backend', 'config': {}}
    let b:jusi_nb.cells[0].status = 'done'
    let b:jusi_nb.cells[0].owner = {'kind': 'kernel'}
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)

    call jusi#client#refresh_attached_view(l:notebook, l:cell_id, 'client-1', l:client)

    call assert_equal(0, len(s:native_terminal_launches))
    call assert_equal(l:client, get(b:jusi_nb.cells[0], 'client_bufnr', -1))
    call assert_equal('', getbufvar(l:client, 'jusi_client_transport_kind', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_native_terminal_launcher = l:save_launcher
    let g:jusi_remote_plain_cell_transcript_fallback = l:save_fallback
    if type(l:save_launcher_ref) == type(function('tr'))
      let g:JusiNativeTerminalLauncher = l:save_launcher_ref
    else
      unlet! g:JusiNativeTerminalLauncher
    endif
  endtry
endfunction

function! Test_client_refresh_attached_view_does_not_double_launch_native_terminal_transport() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:save_launcher = get(g:, 'jusi_native_terminal_launcher', 0)
  let l:save_launcher_ref = get(g:, 'JusiNativeTerminalLauncher', 0)
  try
    let g:jusi_session_adapter = {
          \ 'inspect_client': function('s:test_session_adapter_inspect_client'),
          \ 'request': function('s:test_request_adapter'),
          \ }
    let g:JusiNativeTerminalLauncher = function('TestNativeTerminalReentrantLauncher')
    let s:inspect_client_calls = 0
    let s:native_terminal_launches = []
    let s:request_envelopes = []
    let s:reentrant_native_terminal_refresh = {'done': 0}
    let s:inspect_client_response = {
          \ 'revision': 1,
          \ 'title': 'sql',
          \ 'lines': [],
          \ 'execution_status': 'follow-up',
          \ 'transport': {
          \   'kind': 'native_terminal',
          \   'attach_cmd': ['python', '-m', 'jusi', 'client-process', 'terminal-attach'],
          \   'attach_env': {
          \     'JUSI_SESSION_ID': 'sess-1',
          \     'JUSI_CLIENT_ID': 'client-1',
          \     'JUSI_HANDLER_ID': 'sqlite',
          \     },
          \   'session_id': 'sess-1',
          \   'client_id': 'client-1',
          \   'handler_id': 'sqlite',
          \   },
          \ }
    call Test_open_scratch([
          \ '##',
          \ '%%sql',
          \ 'select 1',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
    let s:reentrant_native_terminal_refresh.old_client_bufnr = l:client
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    let b:jusi_nb.cells[0].handler = {'id': 'sqlite', 'last_message_type': 'handler_snapshot', 'payload': {}, 'snapshot': {'transport': 'native_terminal'}}
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)

    call jusi#client#refresh_attached_view(l:notebook, l:cell_id, 'client-1', l:client)

    call assert_equal(1, len(s:native_terminal_launches))
    let l:new_client = get(b:jusi_nb.cells[0], 'client_bufnr', -1)
    call assert_notequal(l:client, l:new_client)
    call assert_true(bufexists(l:new_client))
    call assert_false(bufexists(l:client))
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_native_terminal_launcher = l:save_launcher
    if type(l:save_launcher_ref) == type(function('tr'))
      let g:JusiNativeTerminalLauncher = l:save_launcher_ref
    else
      unlet! g:JusiNativeTerminalLauncher
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
    let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
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
    let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
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
    let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
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
    let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
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
  let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
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
  let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
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

function! Test_handler_complete_result_event_normalizes_and_stores_completion_items() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql main',
        \ 'select na',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
  let b:jusi_nb.session.id = 'sess-1'
  let b:jusi_nb.session.state = 'connected'
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  let b:jusi_nb.cells[0].handler = {'id': 'sqlite', 'last_message_type': 'handler_snapshot', 'payload': {}}
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)

  call jusi#transport#receive(l:notebook, {
        \ 'kind': 'event',
        \ 'type': 'handler_message',
        \ 'version': 1,
        \ 'payload': {
        \   'notebook_id': 'nb-' . l:notebook,
        \   'session_id': 'sess-1',
        \   'client_id': 'client-1',
        \   'handler_id': 'sqlite',
        \   'message_type': 'complete_result',
        \   'payload': {
        \     'items': [
        \       {'value': 'name', 'label': 'name', 'kind': 'column', 'detail': 'users.name', 'documentation': 'column users.name'},
        \       {'value': 'namespace', 'label': 'namespace', 'kind': 'keyword'},
        \     ],
        \   },
        \   },
        \ })

  let l:result = getbufvar(l:notebook, 'jusi_handler_completion_result', {})
  call assert_equal(l:cell_id, get(l:result, 'cell_id', 0))
  call assert_equal('client-1', get(l:result, 'client_id', ''))
  call assert_equal('sqlite', get(l:result, 'handler_id', ''))
  call assert_equal([
        \ {'word': 'name', 'abbr': 'name', 'menu': 'users.name', 'info': 'column users.name', 'kind': 'column'},
        \ {'word': 'namespace', 'abbr': 'namespace', 'menu': '', 'info': '', 'kind': 'keyword'},
        \ ], get(l:result, 'items', []))
  call assert_equal('complete_result', get(get(b:jusi_nb.cells[0], 'handler', {}), 'last_message_type', ''))
endfunction

function! Test_completion_result_in_normal_mode_schedules_pending_popup() abort
  call Test_open_scratch([
        \ '##',
        \ 'pr',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  call setbufvar(l:notebook, 'jusi_handler_completion_request', {
        \ 'cell_id': l:cell_id,
        \ 'client_id': '',
        \ 'handler_id': '',
        \ 'startcol': 1,
        \ 'line_nr': 2,
        \ 'line_text': 'pr',
        \ })

  call jusi#session#apply_completion_result(l:notebook, l:cell_id, '', '', {
        \ 'items': [
        \   {'value': 'print', 'label': 'print', 'start_col': 0, 'end_col': 2},
        \   ],
        \ })

  let l:pending = getbufvar(l:notebook, 'jusi_pending_completion_popup', {})
  call assert_equal(1, get(l:pending, 'startcol', 0))
  call assert_equal('print', get(get(l:pending, 'items', [{}])[0], 'word', ''))
endfunction

function! Test_handler_action_request_open_path_opens_file_at_requested_position() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql main',
        \ 'select * from users',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
  let l:path = tempname() . '-open-path.txt'
  call writefile([
        \ 'first line',
        \ 'second line',
        \ 'third line',
        \ ], l:path)
  let b:jusi_nb.session.id = 'sess-1'
  let b:jusi_nb.session.state = 'connected'
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  let b:jusi_nb.cells[0].handler = {'id': 'sqlite', 'last_message_type': 'handler_snapshot', 'payload': {}}
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)

  try
    call jusi#transport#receive(l:notebook, {
          \ 'kind': 'event',
          \ 'type': 'handler_message',
          \ 'version': 1,
          \ 'payload': {
          \   'notebook_id': 'nb-' . l:notebook,
          \   'session_id': 'sess-1',
          \   'client_id': 'client-1',
          \   'handler_id': 'sqlite',
          \   'message_type': 'action_request',
          \   'payload': {
          \     'action_type': 'open_path',
          \     'payload': {
          \       'path': l:path,
          \       'line': 2,
          \       'column': 4,
          \     },
          \   },
          \ },
          \ })

    call assert_equal(fnamemodify(l:path, ':p'), expand('%:p'))
    call assert_equal(2, line('.'))
    call assert_equal(4, col('.'))
    let l:cells = get(getbufvar(l:notebook, 'jusi_nb', {}), 'cells', [])
    call assert_equal('action_request', get(get(get(l:cells, 0, {}), 'handler', {}), 'last_message_type', ''))
    call assert_equal('open_path', get(get(get(get(l:cells, 0, {}), 'handler', {}), 'payload', {}), 'action_type', ''))
  finally
    silent! only
    call delete(l:path)
  endtry
endfunction

function! Test_handler_action_request_open_path_rejects_non_local_session_target() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql main',
        \ 'select * from users',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
  let l:path = tempname() . '-open-path.txt'
  call writefile(['first line'], l:path)
  let b:jusi_nb.session.id = 'sess-1'
  let b:jusi_nb.session.state = 'connected'
  let b:jusi_nb.session.target = {'kind': 'ssh', 'alias': 'remote'}
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  let b:jusi_nb.cells[0].handler = {'id': 'sqlite', 'last_message_type': 'handler_snapshot', 'payload': {}}
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)

  try
    call jusi#transport#receive(l:notebook, {
          \ 'kind': 'event',
          \ 'type': 'handler_message',
          \ 'version': 1,
          \ 'payload': {
          \   'notebook_id': 'nb-' . l:notebook,
          \   'session_id': 'sess-1',
          \   'client_id': 'client-1',
          \   'handler_id': 'sqlite',
          \   'message_type': 'action_request',
          \   'payload': {
          \     'action_type': 'open_path',
          \     'payload': {
          \       'path': l:path,
          \       'line': 1,
          \     },
          \   },
          \ },
          \ })

    call assert_equal(l:notebook, bufnr('%'))
    call assert_match('local-only action "open_path"', get(b:jusi_nb.session, 'last_error', ''))
    call assert_match('kind "ssh"', get(b:jusi_nb.session, 'last_error', ''))
  finally
    call delete(l:path)
  endtry
endfunction

function! Test_handler_action_request_diff_show_opens_readonly_diff_artifacts() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd main',
        \ 'data',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
  let l:before_path = tempname() . '-before.py'
  let l:after_path = tempname() . '-after.py'
  call writefile(['print("old")'], l:before_path)
  call writefile(['print("new")'], l:after_path)
  let b:jusi_nb.session.id = 'sess-1'
  let b:jusi_nb.session.state = 'connected'
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  let b:jusi_nb.cells[0].handler = {'id': 'vd', 'last_message_type': 'handler_snapshot', 'payload': {}}
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)

  try
    belowright split
    execute 'buffer ' . l:client
    let l:client_winid = win_getid()
    call jusi#transport#receive(l:notebook, {
          \ 'kind': 'event',
          \ 'type': 'handler_message',
          \ 'version': 1,
          \ 'payload': {
          \   'notebook_id': 'nb-' . l:notebook,
          \   'session_id': 'sess-1',
          \   'client_id': 'client-1',
          \   'handler_id': 'vd',
          \   'message_type': 'action_request',
          \   'payload': {
          \     'action_type': 'diff_show',
          \     'payload': {
          \       'path': 'relative/project/file.py',
          \       'before_path': l:before_path,
          \       'after_path': l:after_path,
          \       'before_exists': v:true,
          \       'after_exists': v:true,
          \       'open_in': 'split',
          \       'layout': 'below',
          \     },
          \   },
          \ },
          \ })

    let l:after_bufnr = bufnr('%')
    let l:before_bufnr = getbufvar(l:after_bufnr, 'jusi_diff_peer_bufnr', -1)
    call assert_true(l:before_bufnr > 0)
    call assert_equal(fnamemodify(l:after_path, ':p'), expand('#' . l:after_bufnr . ':p'))
    call assert_equal(fnamemodify(l:before_path, ':p'), expand('#' . l:before_bufnr . ':p'))
    call assert_equal(1, getbufvar(l:after_bufnr, '&readonly'))
    call assert_equal(0, getbufvar(l:after_bufnr, '&modifiable'))
    call assert_equal(1, getbufvar(l:before_bufnr, '&readonly'))
    call assert_equal(0, getbufvar(l:before_bufnr, '&modifiable'))
    call assert_equal({'path': 'relative/project/file.py', 'label': 'after'}, getbufvar(l:after_bufnr, 'jusi_diff_show', {}))
    call assert_equal({'path': 'relative/project/file.py', 'label': 'before'}, getbufvar(l:before_bufnr, 'jusi_diff_show', {}))
    call assert_true(getwinvar(bufwinnr(l:after_bufnr), '&diff'))
    call assert_true(getwinvar(bufwinnr(l:before_bufnr), '&diff'))
    call assert_true(win_id2win(l:client_winid) > 0)
  finally
    silent! diffoff!
    silent! only
    call delete(l:before_path)
    call delete(l:after_path)
  endtry
endfunction

function! Test_handler_action_request_diff_show_rejects_non_local_session_target() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd main',
        \ 'data',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
  let l:before_path = tempname() . '-before.py'
  let l:after_path = tempname() . '-after.py'
  call writefile([''], l:before_path)
  call writefile(['print("new")'], l:after_path)
  let b:jusi_nb.session.id = 'sess-1'
  let b:jusi_nb.session.state = 'connected'
  let b:jusi_nb.session.target = {'kind': 'ssh', 'alias': 'remote'}
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  let b:jusi_nb.cells[0].handler = {'id': 'vd', 'last_message_type': 'handler_snapshot', 'payload': {}}
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)

  try
    call jusi#transport#receive(l:notebook, {
          \ 'kind': 'event',
          \ 'type': 'handler_message',
          \ 'version': 1,
          \ 'payload': {
          \   'notebook_id': 'nb-' . l:notebook,
          \   'session_id': 'sess-1',
          \   'client_id': 'client-1',
          \   'handler_id': 'vd',
          \   'message_type': 'action_request',
          \   'payload': {
          \     'action_type': 'diff_show',
          \     'payload': {
          \       'path': 'relative/project/file.py',
          \       'before_path': l:before_path,
          \       'after_path': l:after_path,
          \       'open_in': 'split',
          \       'layout': 'below',
          \     },
          \   },
          \ },
          \ })

    call assert_equal(l:notebook, bufnr('%'))
    call assert_match('local-only action "diff_show"', get(b:jusi_nb.session, 'last_error', ''))
    call assert_match('kind "ssh"', get(b:jusi_nb.session, 'last_error', ''))
  finally
    call delete(l:before_path)
    call delete(l:after_path)
  endtry
endfunction

function! Test_handler_action_request_edit_path_sends_action_result_on_saved_close() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:path = tempname() . '-edit-path.txt'
  try
    let g:jusi_session_adapter = {'request': function('s:test_request_adapter')}
    let s:last_request_envelope = {}
    let s:request_envelopes = []
    call writefile(['first line', 'second line'], l:path)
    call Test_open_scratch([
          \ '##',
          \ '%%vd main',
          \ 'data',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    let b:jusi_nb.cells[0].handler = {'id': 'vd', 'last_message_type': 'handler_snapshot', 'payload': {}}
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
          \   'message_type': 'action_request',
          \   'payload': {
          \     'action_type': 'edit_path',
          \     'payload': {
          \       'request_id': 'edit-1',
          \       'path': l:path,
          \       'line': 2,
          \     },
          \   },
          \ },
          \ })

    call setline(2, 'second line updated')
    silent write
    let l:edit_bufnr = bufnr('%')
    execute 'bwipeout ' . l:edit_bufnr

    call assert_equal('handler_message', get(s:last_request_envelope, 'type', ''))
    call assert_equal('action_result', get(get(s:last_request_envelope, 'payload', {}), 'message_type', ''))
    call assert_equal('edit-1', get(get(get(s:last_request_envelope, 'payload', {}), 'payload', {}), 'request_id', ''))
    call assert_equal(v:true, get(get(get(s:last_request_envelope, 'payload', {}), 'payload', {}), 'ok', v:false))
    call assert_equal(1, len(filter(copy(s:request_envelopes), "get(v:val, 'type', '') ==# 'handler_message' && get(get(v:val, 'payload', {}), 'message_type', '') ==# 'action_result'")))
  finally
    let g:jusi_session_adapter = l:save_adapter
    call delete(l:path)
  endtry
endfunction

function! Test_handler_action_request_edit_path_rejects_non_local_target_and_sends_cancel() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:path = tempname() . '-edit-path.txt'
  try
    let g:jusi_session_adapter = {'request': function('s:test_request_adapter')}
    let s:last_request_envelope = {}
    let s:request_envelopes = []
    call writefile(['first line'], l:path)
    call Test_open_scratch([
          \ '##',
          \ '%%vd main',
          \ 'data',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'
    let b:jusi_nb.session.target = {'kind': 'docker', 'alias': 'ctr'}
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    let b:jusi_nb.cells[0].handler = {'id': 'vd', 'last_message_type': 'handler_snapshot', 'payload': {}}
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
          \   'message_type': 'action_request',
          \   'payload': {
          \     'action_type': 'edit_path',
          \     'payload': {
          \       'request_id': 'edit-remote',
          \       'path': l:path,
          \     },
          \   },
          \ },
          \ })

    call assert_equal(l:notebook, bufnr('%'))
    call assert_match('local-only action "edit_path"', get(b:jusi_nb.session, 'last_error', ''))
    call assert_match('kind "docker"', get(b:jusi_nb.session, 'last_error', ''))
    call assert_equal('handler_message', get(s:last_request_envelope, 'type', ''))
    call assert_equal('action_result', get(get(s:last_request_envelope, 'payload', {}), 'message_type', ''))
    call assert_equal('edit-remote', get(get(get(s:last_request_envelope, 'payload', {}), 'payload', {}), 'request_id', ''))
    call assert_equal(v:false, get(get(get(s:last_request_envelope, 'payload', {}), 'payload', {}), 'ok', v:true))
  finally
    let g:jusi_session_adapter = l:save_adapter
    call delete(l:path)
  endtry
endfunction

function! Test_handler_action_request_edit_path_sends_cancel_on_forced_close_without_save() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:path = tempname() . '-edit-path.txt'
  try
    let g:jusi_session_adapter = {'request': function('s:test_request_adapter')}
    let s:last_request_envelope = {}
    let s:request_envelopes = []
    call writefile(['first line', 'second line'], l:path)
    call Test_open_scratch([
          \ '##',
          \ '%%vd main',
          \ 'data',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    let b:jusi_nb.cells[0].handler = {'id': 'vd', 'last_message_type': 'handler_snapshot', 'payload': {}}
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
          \   'message_type': 'action_request',
          \   'payload': {
          \     'action_type': 'edit_path',
          \     'payload': {
          \       'request_id': 'edit-2',
          \       'path': l:path,
          \     },
          \   },
          \ },
          \ })

    call setline(1, 'first line updated')
    let l:edit_bufnr = bufnr('%')
    execute 'bwipeout! ' . l:edit_bufnr

    call assert_equal('handler_message', get(s:last_request_envelope, 'type', ''))
    call assert_equal('action_result', get(get(s:last_request_envelope, 'payload', {}), 'message_type', ''))
    call assert_equal('edit-2', get(get(get(s:last_request_envelope, 'payload', {}), 'payload', {}), 'request_id', ''))
    call assert_equal(v:false, get(get(get(s:last_request_envelope, 'payload', {}), 'payload', {}), 'ok', v:true))
    call assert_equal(1, len(filter(copy(s:request_envelopes), "get(v:val, 'type', '') ==# 'handler_message' && get(get(v:val, 'payload', {}), 'message_type', '') ==# 'action_result'")))
  finally
    let g:jusi_session_adapter = l:save_adapter
    call delete(l:path)
  endtry
endfunction

function! Test_handler_action_request_yank_text_updates_main_registers() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql main',
        \ 'select * from users',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
  let l:save_unnamed = getreg('"')
  let l:save_zero = getreg('0')
  let l:save_unnamed_type = getregtype('"')
  let l:save_zero_type = getregtype('0')
  let b:jusi_nb.session.id = 'sess-1'
  let b:jusi_nb.session.state = 'connected'
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  let b:jusi_nb.cells[0].handler = {'id': 'sqlite', 'last_message_type': 'handler_snapshot', 'payload': {}}
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)

  try
    call setreg('"', '', 'v')
    call setreg('0', '', 'v')
    call jusi#transport#receive(l:notebook, {
          \ 'kind': 'event',
          \ 'type': 'handler_message',
          \ 'version': 1,
          \ 'payload': {
          \   'notebook_id': 'nb-' . l:notebook,
          \   'session_id': 'sess-1',
          \   'client_id': 'client-1',
          \   'handler_id': 'sqlite',
          \   'message_type': 'action_request',
          \   'payload': {
          \     'action_type': 'yank_text',
          \     'payload': {
          \       'text': 'copied from plugin',
          \     },
          \   },
          \ },
          \ })

    call assert_equal('copied from plugin', getreg('"'))
    call assert_equal('copied from plugin', getreg('0'))
    call assert_equal('action_request', get(get(b:jusi_nb.cells[0], 'handler', {}), 'last_message_type', ''))
    call assert_equal('yank_text', get(get(get(b:jusi_nb.cells[0], 'handler', {}), 'payload', {}), 'action_type', ''))
  finally
    call setreg('"', l:save_unnamed, l:save_unnamed_type)
    call setreg('0', l:save_zero, l:save_zero_type)
  endtry
endfunction

function! Test_handler_message_event_ignores_mismatched_session() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd pods',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
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
  let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
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
    let l:client = jusi#client#create_managed_buffer(bufnr('%'), 'client-1')
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

function! Test_send_handler_followup_current_builds_generic_followup_message() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'request': function('s:test_request_adapter'),
          \ }
    let s:last_request_envelope = {}
    call Test_open_scratch([
          \ '##',
          \ '%%sql main',
          \ 'select 1',
          \ ])
    let l:client = jusi#client#create_managed_buffer(bufnr('%'), 'client-1')
    call jusi#session#apply({'state': 'connected', 'id': 'sess-1', 'plugin_specs': {'sql': {'syntax': 'sql'}}})
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    let b:jusi_nb.cells[0].handler = {'id': 'sqlite', 'last_message_type': 'handler_snapshot', 'payload': {}}
    call cursor(3, 4)

    call jusi#session#send_handler_followup_current()
    call assert_equal('handler_message', get(s:last_request_envelope, 'type', ''))
    call assert_equal('followup', get(get(s:last_request_envelope, 'payload', {}), 'message_type', ''))
    call assert_equal("%%sql main\nselect 1", get(get(get(s:last_request_envelope, 'payload', {}), 'payload', {}), 'cell_text', ''))
    call assert_equal(2, get(get(get(s:last_request_envelope, 'payload', {}), 'payload', {}), 'cursor_row', -1))
    call assert_equal(4, get(get(get(s:last_request_envelope, 'payload', {}), 'payload', {}), 'cursor_col', -1))
    call assert_equal('select 1', get(get(get(s:last_request_envelope, 'payload', {}), 'payload', {}), 'line_text', ''))
    call assert_equal('sel', get(get(get(s:last_request_envelope, 'payload', {}), 'payload', {}), 'current_word', ''))
    call assert_equal([
          \ '##',
          \ '%%sql main',
          \ 'select 1',
          \ '##<<',
          \ '###',
          \ 'select 1',
          \ '##>>',
          \ ], getline(1, '$'))
    call assert_equal([3, 4], [line('.'), col('.')])
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_handler_completion_does_not_append_history() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'request': function('s:test_request_adapter'),
          \ }
    let s:last_request_envelope = {}
    let s:test_request_response = {}
    call Test_open_scratch([
          \ '##',
          \ '%%sql main',
          \ 'select 1',
          \ ])
    let l:client = jusi#client#create_managed_buffer(bufnr('%'), 'client-1')
    call jusi#session#apply({'state': 'connected', 'id': 'sess-1'})
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    let b:jusi_nb.cells[0].handler = {'id': 'sqlite', 'last_message_type': 'handler_snapshot', 'payload': {}}
    call cursor(3, 4)

    call jusi#session#request_completion_current()

    call assert_equal('handler_message', get(s:last_request_envelope, 'type', ''))
    call assert_equal('complete', get(get(s:last_request_envelope, 'payload', {}), 'message_type', ''))
    call assert_equal(['##', '%%sql main', 'select 1'], getline(1, '$'))
  finally
    let s:test_request_response = {}
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_request_completion_current_reuses_active_handler_context() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'request': function('s:test_request_adapter'),
          \ }
    let s:last_request_envelope = {}
    let s:test_request_response = {}
    call Test_open_scratch([
          \ '##',
          \ '%%sql main',
          \ 'select value from items',
          \ ])
    let l:client = jusi#client#create_managed_buffer(bufnr('%'), 'client-1')
    call jusi#session#apply({'state': 'connected', 'id': 'sess-1'})
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    let b:jusi_nb.cells[0].handler = {'id': 'sqlite', 'last_message_type': 'handler_snapshot', 'payload': {}}
    call cursor(3, 13)

    call jusi#session#request_completion_current()
    call assert_equal('handler_message', get(s:last_request_envelope, 'type', ''))
    call assert_equal('complete', get(get(s:last_request_envelope, 'payload', {}), 'message_type', ''))
    call assert_equal("%%sql main\nselect value from items", get(get(get(s:last_request_envelope, 'payload', {}), 'payload', {}), 'cell_text', ''))
    call assert_equal(2, get(get(get(s:last_request_envelope, 'payload', {}), 'payload', {}), 'cursor_row', -1))
    call assert_equal(13, get(get(get(s:last_request_envelope, 'payload', {}), 'payload', {}), 'cursor_col', -1))
    call assert_equal('select value from items', get(get(get(s:last_request_envelope, 'payload', {}), 'payload', {}), 'line_text', ''))
    call assert_equal('value', get(get(get(s:last_request_envelope, 'payload', {}), 'payload', {}), 'current_word', ''))
  finally
    let s:test_request_response = {}
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_request_completion_current_uses_complete_cell_for_plain_code_cells() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'request': function('s:test_request_adapter'),
          \ }
    let s:last_request_envelope = {}
    let s:test_request_response = {
          \ 'ok': 1,
          \ 'completion': {
          \   'items': [
          \     {'value': 'print', 'label': 'print', 'start_col': 0, 'end_col': 2},
          \   ],
          \   },
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'pr ',
          \ ])
    call jusi#session#apply({'state': 'connected', 'id': 'sess-1'})
    call cursor(2, 3)

    call jusi#session#request_completion_current()

    call assert_equal('complete_cell', get(s:last_request_envelope, 'type', ''))
    call assert_equal(1, get(get(get(s:last_request_envelope, 'payload', {}), 'cell', {}), 'id', 0))
    call assert_equal('code', get(get(get(s:last_request_envelope, 'payload', {}), 'cell', {}), 'kind', ''))
    call assert_equal(['pr '], get(get(get(s:last_request_envelope, 'payload', {}), 'cell', {}), 'main_lines', []))
    call assert_equal(1, get(get(s:last_request_envelope, 'payload', {}), 'cursor_row', -1))
    call assert_equal(3, get(get(s:last_request_envelope, 'payload', {}), 'cursor_col', -1))
    call assert_equal('pr ', get(get(s:last_request_envelope, 'payload', {}), 'line_text', ''))
    call assert_equal('pr', get(get(s:last_request_envelope, 'payload', {}), 'current_word', ''))
    call assert_equal('print', get(get(getbufvar(bufnr('%'), 'jusi_handler_completion_result', {}), 'items', [{}])[0], 'word', ''))
  finally
    let s:test_request_response = {}
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_request_completion_current_rejects_unbootstrapped_magic_cells() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'request': function('s:test_request_adapter'),
          \ }
    let s:last_request_envelope = {}
    let s:test_request_response = {}
    call Test_open_scratch([
          \ '##',
          \ '%%shell',
          \ 'ls',
          \ ])
    call jusi#session#apply({'state': 'connected', 'id': 'sess-1'})
    call cursor(3, 3)

    call jusi#session#request_completion_current()

    call assert_equal({}, s:last_request_envelope)
    call assert_equal('Cannot complete a plugin cell before it has an active client', get(b:jusi_nb.session, 'last_error', ''))
    call assert_equal('complete_cell', get(b:jusi_nb.session, 'last_action', ''))
    call assert_equal('', get(b:jusi_nb.cells[0], 'client_id', ''))
    call assert_equal('', get(get(b:jusi_nb.cells[0], 'owner', {}), 'kind', ''))
    call assert_equal('initial', get(b:jusi_nb.cells[0], 'status', ''))
    call assert_equal(['##', '%%shell', 'ls'], getline(1, '$'))
  finally
    let s:test_request_response = {}
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_execute_current_uses_handler_followup_for_handler_owned_followup_cells() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'request': function('s:test_request_adapter'),
          \ }
    let s:last_request_envelope = {}
    call Test_open_scratch([
          \ '##',
          \ '%%sql main',
          \ 'select 1',
          \ ])
    let l:client = jusi#client#create_managed_buffer(bufnr('%'), 'client-1')
    call jusi#session#apply({'state': 'connected', 'id': 'sess-1'})
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    let b:jusi_nb.cells[0].handler = {'id': 'sqlite', 'last_message_type': 'handler_snapshot', 'payload': {}}
    call cursor(3, 1)

    call jusi#session#execute_current()
    call assert_equal('handler_message', get(s:last_request_envelope, 'type', ''))
    call assert_equal('followup', get(get(s:last_request_envelope, 'payload', {}), 'message_type', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_execute_followup_context_error_does_not_fail_session() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ ])
  call jusi#session#apply({'state': 'connected', 'id': 'sess-1'})
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'shutdown'
  let b:jusi_nb.cells[0].client_bufnr = -1
  let b:jusi_nb.cells[0].handler = {'id': '', 'last_message_type': '', 'payload': {}, 'snapshot': {}}
  call cursor(3, 1)

  call jusi#session#execute_current()

  call assert_equal('connected', b:jusi_nb.session.state)
  call assert_equal('handler_message', get(b:jusi_nb.session, 'last_action', ''))
  call assert_match('Current cell has no tracked handler id', get(b:jusi_nb.session, 'last_error', ''))
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
    let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
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
    let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'

    call jusi#session#callback_cell(l:cell_id, {
          \ 'status': 'busy',
          \ 'client_id': 'client-1',
          \ 'client_state': 'active',
          \ 'client_bufnr': l:client,
          \ })

    call Test_wait_until({-> getbufline(l:client, 1, '$') == ['1', '2']}, 500)
    call assert_equal(['1', '2'], getbufline(l:client, 1, '$'))
    call assert_true(s:inspect_client_calls >= 3)

    let l:calls_before_done = s:inspect_client_calls
    let s:inspect_client_response = {
          \ 'revision': 4,
          \ 'title': 'cell 1: done',
          \ 'lines': ['started cell 1 [code:python]', 'stdout> 1', 'stdout> 2', 'finished: done'],
          \ 'execution_status': 'done',
          \ }
    call jusi#session#callback_cell(l:cell_id, {'status': 'done'})
    call Test_wait_until({-> getbufline(l:client, 1, '$') == ['1', '2']}, 500)
    call assert_equal(['1', '2'], getbufline(l:client, 1, '$'))

    sleep 80m
    call assert_true(s:inspect_client_calls <= l:calls_before_done + 1)
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_client_poll_ms = l:save_poll_ms
    let s:inspect_client_sequence = []
  endtry
endfunction

function! Test_client_refresh_hides_transcript_noise_in_display_buffer() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'inspect_client': function('s:test_session_adapter_inspect_client')}
    let s:inspect_client_response = {
          \ 'revision': 1,
          \ 'title': 'cell 1: done',
          \ 'lines': [
          \   'meta> client=client-6 session=sess-1 bufnr=10',
          \   'status> busy',
          \   'handler.meta {"kind":"native_terminal"}',
          \   'handler.handoff {"transport":"native_terminal"}',
          \   'started cell 1 [code:python]',
          \   "execute[3]> print('lalala')",
          \   'stdout> lalala',
          \   'finished: done',
          \ ],
          \ 'execution_status': 'done',
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'
    let b:jusi_nb.cells[0].status = 'done'
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)

    call jusi#client#refresh_attached_view(l:notebook, l:cell_id, 'client-1', l:client)

    call assert_equal(['lalala'], getbufline(l:client, 1, '$'))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_client_refresh_formats_structured_error_events_in_display_buffer() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'inspect_client': function('s:test_session_adapter_inspect_client')}
    let s:inspect_client_response = {
          \ 'revision': 1,
          \ 'title': 'cell 1: error',
          \ 'lines': [
          \   {'type': 'error', 'message': 'sqlite database is locked'},
          \ ],
          \ 'execution_status': 'done',
          \ }
    call Test_open_scratch([
          \ '##',
          \ '%%sql main',
          \ 'select 1',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'
    let b:jusi_nb.cells[0].status = 'error'
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)

    call jusi#client#refresh_attached_view(l:notebook, l:cell_id, 'client-1', l:client)

    call assert_equal(['error: sqlite database is locked'], getbufline(l:client, 1, '$'))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_client_refresh_strips_ansi_from_traceback_lines() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'inspect_client': function('s:test_session_adapter_inspect_client')}
    let s:inspect_client_response = {
          \ 'revision': 1,
          \ 'title': 'cell 1: error',
          \ 'lines': [
          \   'error: ZeroDivisionError: division by zero',
          \   "trace> \u001b[0;31m---------------------------------------------------------------------------\u001b[0m",
          \   "trace> \u001b[0;31mZeroDivisionError\u001b[0m                         Traceback (most recent call last)",
          \   'trace> Cell [0;32mIn[1], line 1[0m',
          \   "[0;32m----> 1[0m [38;5;28mprint[39m([38;5;241;43m1[39;49m[38;5;241;43m/[39;49m[38;5;241;43m0[39;49m)",
          \   "trace> \u001b[0;31mZeroDivisionError\u001b[0m: division by zero",
          \ ],
          \ 'execution_status': 'error',
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    let l:notebook = bufnr('%')
    let l:cell_id = b:jusi_nb.cells[0].id
    let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
    let b:jusi_nb.session.id = 'sess-1'
    let b:jusi_nb.session.state = 'connected'
    let b:jusi_nb.cells[0].status = 'error'
    let b:jusi_nb.cells[0].client_id = 'client-1'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
    call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)

    call jusi#client#refresh_attached_view(l:notebook, l:cell_id, 'client-1', l:client)

    call assert_equal([
          \ 'ZeroDivisionError: division by zero',
          \ '---------------------------------------------------------------------------',
          \ 'ZeroDivisionError                         Traceback (most recent call last)',
          \ 'Cell In[1], line 1',
          \ '----> 1 print(1/0)',
          \ 'ZeroDivisionError: division by zero',
          \ ], getbufline(l:client, 1, '$'))
  finally
    let g:jusi_session_adapter = l:save_adapter
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
    let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
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
          \ 'title': 'cell 1: busy',
          \ 'lines': ['started cell 1 [code:python]', 'input> value: ', ''],
          \ 'execution_status': 'busy',
          \ }
    call jusi#client#refresh_attached_view(l:notebook, l:cell_id, 'client-1', l:client)
    call assert_equal({'prompt': 'value: ', 'password': 0}, get(b:jusi_nb.cells[0], 'pending_input', {}))
    call assert_equal({'prompt': 'value: ', 'password': 0}, getbufvar(l:client, 'jusi_client_pending_input', {}))

    let s:inspect_client_response = {
          \ 'revision': 3,
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
    let l:client = jusi#client#create_managed_buffer(bufnr('%'), 'client-1')
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
  call assert_equal('idle', b:jusi_nb.session.state)
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
    call assert_false(has_key(b:jusi_nb.session, 'prepared'))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_restart_kernel_restarts_connected_start_managed_session() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let s:restart_calls = []
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_restart_start'),
          \ 'stop': function('s:test_session_adapter_restart_stop'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#apply({
          \ 'id': 'sess-old',
          \ 'state': 'connected',
          \ 'kernel_name': 'python3',
          \ 'target': {'source': 'start', 'alias': 'py', 'kind': 'venv', 'value': 'venv://py', 'config': {'plugins': {'sql': {'main': {'provider': 'sqlite'}}}}},
          \ })
    call jusi#session#restart()
    call assert_equal(['stop', 'start'], map(copy(s:restart_calls), 'v:val.op'))
    call assert_equal('python3', get(get(s:restart_calls[1], 'payload', {}), 'kernel_name', ''))
    call assert_equal('venv', get(get(get(s:restart_calls[1], 'payload', {}), 'target', {}), 'kind', ''))
    call assert_equal('venv://py', get(get(get(s:restart_calls[1], 'payload', {}), 'target', {}), 'value', ''))
    call assert_equal('connected', b:jusi_nb.session.state)
    call assert_equal('restart', b:jusi_nb.session.last_action)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_restart_kernel_refreshes_local_jusi_config() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  let l:save_config = get(g:, 'jusi_config_file', '')
  try
    let s:restart_calls = []
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_restart_start'),
          \ 'stop': function('s:test_session_adapter_restart_stop'),
          \ }
    let g:jusi_config_file = tempname()
    call writefile([
          \ '[plugins.sqlite]',
          \ 'database = "/tmp/restart.db"',
          \ ], g:jusi_config_file)
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#apply({
          \ 'id': 'sess-old',
          \ 'state': 'connected',
          \ 'kernel_name': 'python3',
          \ 'target': {'source': 'start', 'alias': 'py', 'kind': 'venv', 'value': 'venv://py', 'config': {'label': 'existing target', 'plugins': {'sql': {'main': {'provider': 'old'}}}}},
          \ })
    call jusi#session#restart()
    let l:target_config = get(get(get(s:restart_calls[1], 'payload', {}), 'target', {}), 'config', {})
    call assert_equal('existing target', get(l:target_config, 'label', ''))
    call assert_equal('/tmp/restart.db', get(get(get(l:target_config, 'plugins', {}), 'sqlite', {}), 'database', ''))
    call assert_false(has_key(get(l:target_config, 'plugins', {}), 'sql'))
  finally
    let g:jusi_session_adapter = l:save_adapter
    let g:jusi_config_file = l:save_config
  endtry
endfunction

function! Test_restart_kernel_restarts_stopped_start_managed_session_without_stop_call() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let s:restart_calls = []
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_restart_start'),
          \ 'stop': function('s:test_session_adapter_restart_stop'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#apply({
          \ 'state': 'stopped',
          \ 'kernel_name': 'python3',
          \ 'target': {'source': 'start', 'alias': 'python3', 'kind': 'kernel', 'value': '', 'config': {}},
          \ })
    call jusi#session#restart()
    call assert_equal(['start'], map(copy(s:restart_calls), 'v:val.op'))
    call assert_equal('connected', b:jusi_nb.session.state)
    call assert_equal('restart', b:jusi_nb.session.last_action)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_restart_kernel_continues_after_transport_backed_stop_callback() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let s:restart_calls = []
    let g:jusi_session_adapter = {
          \ 'start': function('s:test_session_adapter_restart_start'),
          \ 'stop': function('s:test_session_adapter_restart_stop_transport'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#apply({
          \ 'id': 'sess-old',
          \ 'state': 'connected',
          \ 'kernel_name': 'python3',
          \ 'target': {'source': 'start', 'alias': 'py', 'kind': 'venv', 'value': 'venv://py', 'config': {}},
          \ })
    call jusi#session#restart()
    call assert_equal(['stop'], map(copy(s:restart_calls), 'v:val.op'))
    call assert_equal('stopping', b:jusi_nb.session.state)
    call jusi#session#callback_session({'state': 'stopped', 'request': {}})
    call assert_equal(['stop', 'start'], map(copy(s:restart_calls), 'v:val.op'))
    call assert_equal('connected', b:jusi_nb.session.state)
    call assert_equal('restart', b:jusi_nb.session.last_action)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_restart_kernel_rejects_disconnected_session() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call jusi#session#apply({
        \ 'state': 'disconnected',
        \ 'kernel_name': 'python3',
        \ 'target': {'source': 'start', 'alias': 'python3', 'kind': 'kernel', 'value': '', 'config': {}},
        \ })
  call jusi#session#restart()
  call assert_equal('failed', b:jusi_nb.session.state)
  call assert_match('Cannot restart while the session is disconnected', b:jusi_nb.session.last_error)
endfunction

function! Test_restart_kernel_rejects_attach_managed_session() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call jusi#session#apply({
        \ 'state': 'connected',
        \ 'kernel_name': 'python3',
        \ 'target': {'source': 'attach', 'alias': 'external', 'kind': 'connection_file', 'value': '/tmp/kernel.json', 'config': {}},
        \ })
  call jusi#session#restart()
  call assert_equal('failed', b:jusi_nb.session.state)
  call assert_match('Can only restart sessions started by JusiStartKernel', b:jusi_nb.session.last_error)
endfunction

function! Test_disconnect_uses_disconnected_state_for_recoverable_link_loss() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call jusi#session#set_disconnected()
  call assert_equal('disconnected', b:jusi_nb.session.state)
  call assert_false(has_key(b:jusi_nb.session, 'prepared'))
endfunction

function! Test_execute_while_disconnected_keeps_disconnected_state() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call jusi#session#set_disconnected()
  call jusi#session#execute_current()
  call assert_equal('disconnected', b:jusi_nb.session.state)
  call assert_match('Cannot execute while the session is disconnected', b:jusi_nb.session.last_error)
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
    let l:client = jusi#client#create_managed_buffer(bufnr('%'), 'client-1')
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

function! Test_disconnect_connected_session_uses_adapter_and_preserves_direct_session_shape() abort
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
    call jusi#session#disconnect()
    call assert_equal('disconnected', b:jusi_nb.session.state)
    call assert_equal('disconnect', b:jusi_nb.session.last_action)
    call assert_equal('2030-01-01T00:00:00Z', b:jusi_nb.session.expires_at)
    call assert_false(has_key(b:jusi_nb.session, 'prepared'))
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

function! Test_reconnect_disconnected_session_restores_connected_state() abort
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
    call assert_false(has_key(b:jusi_nb.session, 'prepared'))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_reconnect_transport_failure_preserves_disconnected_state() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {
          \ 'reconnect': function('s:test_session_adapter_reconnect_transport_unreachable'),
          \ }
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    call jusi#session#set_disconnected()
    let b:jusi_nb.session.id = 'sess-1'
    call jusi#session#reconnect()
    call assert_equal('disconnected', b:jusi_nb.session.state)
    call assert_equal('transport_timeout', b:jusi_nb.session.last_error_code)
    call assert_match('Backend is unreachable', b:jusi_nb.session.last_error)
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
    call assert_false(has_key(b:jusi_nb.session, 'prepared'))
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

function! Test_recover_attached_buffer_requires_exact_client_identity_when_known() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  let b:jusi_nb.session.id = 'sess-current'
  let l:stale = jusi#client#create_managed_buffer(l:notebook, 'client-old', 'cell', l:cell_id)

  call assert_equal(l:stale, jusi#client#recover_attached_buffer(l:notebook, l:cell_id, ''))
  call assert_equal(0, jusi#client#recover_attached_buffer(l:notebook, l:cell_id, 'client-new'))
  call assert_equal(l:stale, jusi#client#recover_attached_buffer(l:notebook, l:cell_id, 'client-old'))
endfunction

function! Test_recover_attached_buffer_ignores_detached_client_buffers() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  let b:jusi_nb.session.id = 'sess-current'
  let l:detached = jusi#client#create_managed_buffer(l:notebook, 'client-old', 'detached')
  call setbufvar(l:detached, 'jusi_client_cell_id', 0)

  call assert_equal(0, jusi#client#recover_attached_buffer(l:notebook, l:cell_id, ''))
  call assert_equal(0, jusi#client#recover_attached_buffer(l:notebook, l:cell_id, 'client-old'))
endfunction

function! Test_recover_attached_buffer_ignores_other_session_buffers() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  let b:jusi_nb.session.id = 'sess-old'
  let l:old = jusi#client#create_managed_buffer(l:notebook, 'client-1', 'cell', l:cell_id)
  let b:jusi_nb.session.id = 'sess-new'
  call assert_equal(0, jusi#client#recover_attached_buffer(l:notebook, l:cell_id, 'client-1'))
  call assert_equal('sess-old', getbufvar(l:old, 'jusi_client_session_id', ''))
endfunction

function! Test_session_start_purges_local_client_buffers_from_previous_session() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'start': function('s:test_session_adapter_start')}
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    let b:jusi_nb.session.id = 'sess-old'
    let l:old = jusi#client#create_managed_buffer(bufnr('%'), 'client-old', 'cell', b:jusi_nb.cells[0].id)
    call assert_true(bufexists(l:old))
    call jusi#session#start('python3')
    call assert_false(bufexists(l:old))
    call assert_equal('sess-start-1', get(get(b:, 'jusi_nb', {}), 'session', {}).id)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_destroying_replaced_attached_buffer_does_not_reset_new_binding() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  let l:old = jusi#client#create_attached_buffer(l:notebook, l:cell_id, 'client-1')
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:old
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:old)
  call jusi#client#allow_editor_close(l:old)

  let l:new = jusi#client#create_managed_buffer(l:notebook, 'client-1', 'cell', l:cell_id)
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:new)
  call jusi#session#repair_local_client_binding(l:cell_id, 'client-1', l:new, l:notebook)
  call jusi#client#destroy_buffer(l:old)

  call assert_false(bufexists(l:old))
  call assert_equal(l:new, get(b:jusi_nb.cells[0], 'client_bufnr', -1))
  call assert_equal('active', get(b:jusi_nb.cells[0], 'client_state', ''))
  call assert_equal('client-1', get(b:jusi_nb.cells[0], 'client_id', ''))
endfunction

function! Test_start_clears_stale_transport_runtime_from_previous_session() abort
  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'start': function('s:test_session_adapter_start')}
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])
    let b:jusi_nb.cells[0].status = 'done'
    let b:jusi_nb.cells[0].client_id = 'client-old'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = 77
    let b:jusi_nb.cells[0].runtime_mode = 'handler'
    let b:jusi_nb.cells[0].transport = {
          \ 'kind': 'native_terminal',
          \ 'client_id': 'client-old',
          \ 'session_id': 'sess-old',
          \ }
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    let b:jusi_nb.cells[0].presentation = {'syntax': 'sql'}

    call jusi#session#start('python3')

    call assert_equal('', get(b:jusi_nb.cells[0], 'client_id', ''))
    call assert_equal(-1, get(b:jusi_nb.cells[0], 'client_bufnr', -1))
    call assert_equal('shutdown', get(b:jusi_nb.cells[0], 'client_state', ''))
    call assert_equal('', get(b:jusi_nb.cells[0], 'runtime_mode', ''))
    call assert_equal({}, get(b:jusi_nb.cells[0], 'transport', {}))
    call assert_equal({'kind': ''}, get(b:jusi_nb.cells[0], 'owner', {}))
    call assert_equal({}, get(b:jusi_nb.cells[0], 'presentation', {}))
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
    call assert_false(has_key(b:jusi_nb.session, 'prepared'))
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
    let l:old_client = jusi#client#create_managed_buffer(bufnr('%'), 'client-old')
    let b:jusi_nb.cells[0].status = 'done'
    let b:jusi_nb.cells[0].client_id = 'client-old'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:old_client
    let b:jusi_nb.cells[0].owner = {'kind': 'kernel'}
    call jusi#client#mark_attached_buffer(bufnr('%'), b:jusi_nb.cells[0].id, 'client-old', l:old_client)
    let s:shutdown_requests = []
    call cursor(4, 1)
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
    let l:old_client = jusi#client#create_managed_buffer(bufnr('%'), 'client-old')
    let b:jusi_nb.cells[0].status = 'parked'
    let b:jusi_nb.cells[0].client_id = 'client-old'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:old_client
    call jusi#client#mark_attached_buffer(bufnr('%'), b:jusi_nb.cells[0].id, 'client-old', l:old_client)
    let s:shutdown_requests = []
    call cursor(5, 1)
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
    let l:live_client = jusi#client#create_managed_buffer(l:notebook, 'client-old')
    let l:prepared = jusi#client#create_managed_buffer(l:notebook, 'client-1')
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
    call assert_equal('follow-up', b:jusi_nb.cells[3].status)
    call assert_equal('client-old', b:jusi_nb.cells[3].client_id)
    call assert_equal(l:live_client, b:jusi_nb.cells[3].client_bufnr)
    call assert_equal({'ok': 1}, jusi#client#validate_attached_binding(l:notebook, b:jusi_nb.cells[3].id, 'client-old', l:live_client))
    call jusi#session#execute_current()

    call assert_equal(4, len(b:jusi_nb.cells))
    call assert_equal('busy', b:jusi_nb.cells[2].status)
    call assert_equal('client-2', b:jusi_nb.cells[2].client_id)
    call assert_true(b:jusi_nb.cells[2].client_bufnr > 0)
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
    let l:old_client = jusi#client#create_managed_buffer(bufnr('%'), 'client-old')
    let b:jusi_nb.cells[0].status = 'parked'
    let b:jusi_nb.cells[0].parked_status = 'done'
    let b:jusi_nb.cells[0].client_id = 'client-old'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:old_client
    call jusi#client#mark_attached_buffer(bufnr('%'), b:jusi_nb.cells[0].id, 'client-old', l:old_client)
    let s:shutdown_requests = []
    call jusi#session#execute_current()
    call assert_false(bufexists(l:old_client))
    call assert_equal('busy', b:jusi_nb.cells[0].status)
    call assert_equal('', get(b:jusi_nb.cells[0], 'parked_status', ''))
    call assert_equal('client-2', b:jusi_nb.cells[0].client_id)
    call assert_true(b:jusi_nb.cells[0].client_bufnr > 0)
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
    let l:old_client = jusi#client#create_managed_buffer(bufnr('%'), 'client-old')
    let b:jusi_nb.cells[0].status = 'interrupted'
    let b:jusi_nb.cells[0].client_id = 'client-old'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:old_client
    let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
    call jusi#client#mark_attached_buffer(bufnr('%'), b:jusi_nb.cells[0].id, 'client-old', l:old_client)
    let s:shutdown_requests = []
    call cursor(4, 1)
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
    let l:old_client = jusi#client#create_managed_buffer(bufnr('%'), 'client-old')
    let b:jusi_nb.cells[0].status = 'error'
    let b:jusi_nb.cells[0].client_id = 'client-old'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:old_client
    let b:jusi_nb.cells[0].owner = {'kind': 'kernel'}
    call jusi#client#mark_attached_buffer(bufnr('%'), b:jusi_nb.cells[0].id, 'client-old', l:old_client)
    let s:shutdown_requests = []
    call cursor(4, 1)
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
  let l:prepared = jusi#client#create_managed_buffer(bufnr('%'), 'client-prepared')
  let l:attached = jusi#client#create_managed_buffer(bufnr('%'), 'client-attached')
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
    let l:client = jusi#client#create_managed_buffer(bufnr('%'), 'client-old')
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
    let l:attached = jusi#client#create_managed_buffer(bufnr('%'), 'client-attached')
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
    let l:attached = jusi#client#create_managed_buffer(bufnr('%'), 'client-attached')
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
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_handler_cell_shutdown_event_resets_followup_identity_and_clears_binding() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ ])
  let l:client = jusi#client#create_managed_buffer(bufnr('%'), 'client-1')
  let l:cell_id = b:jusi_nb.cells[0].id
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_state = 'active'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  let b:jusi_nb.cells[0].owner = {'kind': 'handler'}
  call jusi#client#mark_attached_buffer(bufnr('%'), l:cell_id, 'client-1', l:client)
  call jusi#session#callback_cell(l:cell_id, {'client_state': 'shutdown', 'client_bufnr': -1})
  call assert_false(bufexists(l:client))
  call assert_equal('initial', b:jusi_nb.cells[0].status)
  call assert_equal('', b:jusi_nb.cells[0].client_id)
  call assert_equal('shutdown', b:jusi_nb.cells[0].client_state)
  call assert_equal(-1, b:jusi_nb.cells[0].client_bufnr)
  call assert_equal('', get(get(b:jusi_nb.cells[0], 'owner', {}), 'kind', ''))
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
    let l:client = jusi#client#create_managed_buffer(bufnr('%'), 'client-stale')
    call setbufvar(l:client, 'jusi_client_role', 'prepared')
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].client_id = 'client-stale'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
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

function! Test_execute_healthcheck_recovers_exact_client_binding_before_shutdown() abort
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
    let l:stale = jusi#client#create_managed_buffer(bufnr('%'), 'client-stale')
    let l:live = jusi#client#create_managed_buffer(bufnr('%'), 'client-stale', 'cell', b:jusi_nb.cells[0].id)
    call setbufvar(l:stale, 'jusi_client_role', 'prepared')
    call jusi#client#mark_attached_buffer(bufnr('%'), b:jusi_nb.cells[0].id, 'client-stale', l:live)
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].client_id = 'client-stale'
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:stale
    let s:shutdown_requests = []
    call cursor(4, 1)
    call jusi#session#execute_current()
    call assert_equal('follow-up', b:jusi_nb.cells[0].status)
    call assert_equal('active', b:jusi_nb.cells[0].client_state)
    call assert_equal(l:live, b:jusi_nb.cells[0].client_bufnr)
    call assert_equal([], s:shutdown_requests)
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
    let l:client = jusi#client#create_managed_buffer(bufnr('%'), 'client-stale')
    call jusi#client#mark_attached_buffer(bufnr('%'), b:jusi_nb.cells[0].id, 'client-stale', l:client)
    call setbufvar(l:client, 'jusi_client_cell_id', 999)
    let b:jusi_nb.cells[0].status = 'follow-up'
    let b:jusi_nb.cells[0].client_id = ''
    let b:jusi_nb.cells[0].client_state = 'active'
    let b:jusi_nb.cells[0].client_bufnr = l:client
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
    let l:prepared = jusi#client#create_managed_buffer(bufnr('%'), 'client-prepared-stale')
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
        \ 'cell': {'id': l:cell_id, 'status': 'done', 'client_bufnr': 55},
        \ })
  call assert_equal('connected', b:jusi_nb.session.state)
  call assert_equal('mock', b:jusi_nb.session.backend)
  call assert_false(has_key(b:jusi_nb.session, 'prepared'))
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
        \ 'type': 'cell_updated',
        \ 'payload': {'cell': {'id': l:cell_id, 'status': 'busy', 'client_id': 'client-9', 'client_bufnr': 99, 'owner': {'kind': 'kernel'}}},
        \ })
  call assert_equal('sess-1', b:jusi_nb.session.id)
  call assert_equal('connected', b:jusi_nb.session.state)
  call assert_false(has_key(b:jusi_nb.session, 'prepared'))
  call assert_equal('busy', b:jusi_nb.cells[0].status)
  call assert_equal('client-9', b:jusi_nb.cells[0].client_id)
  call assert_equal(99, b:jusi_nb.cells[0].client_bufnr)
  call assert_equal('kernel', get(get(b:jusi_nb.cells[0], 'owner', {}), 'kind', ''))
endfunction

function! Test_cell_callback_ignores_transport_update_from_other_session() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let l:cell_id = b:jusi_nb.cells[0].id
  call jusi#session#apply({'state': 'connected', 'id': 'sess-new'})
  call jusi#session#callback_cell(l:cell_id, {
        \ 'id': l:cell_id,
        \ 'status': 'busy',
        \ 'client_id': 'client-old',
        \ 'client_state': 'active',
        \ 'transport': {
        \   'kind': 'native_terminal',
        \   'session_id': 'sess-old',
        \   'client_id': 'client-old',
        \   },
        \ })
  call assert_equal('initial', b:jusi_nb.cells[0].status)
  call assert_equal('', b:jusi_nb.cells[0].client_id)
  call assert_equal('shutdown', b:jusi_nb.cells[0].client_state)
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

function! Test_transport_request_can_start_backend_from_venv_target() abort
  let l:save_backend_cmd = get(g:, 'jusi_backend_cmd', [])
  let l:root = tempname()
  let l:venv = l:root . '/test-venv'
  let l:bin = l:venv . '/bin'
  let l:python = l:bin . '/python'
  try
    call mkdir(l:bin, 'p')
    call writefile([
          \ '#!/bin/sh',
          \ "IFS= read -r line",
          \ "printf '%s\\n' '{\"version\":1,\"kind\":\"response\",\"type\":\"start_session\",\"request_id\":\"req-test\",\"ok\":true,\"payload\":{}}'",
          \ ], l:python)
    call setfperm(l:python, 'rwxr-xr-x')
    let g:jusi_backend_cmd = []
    call Test_open_scratch([
          \ '##',
          \ 'print(\"hello\")',
          \ ])
    let l:response = jusi#transport#request(bufnr('%'), {
          \ 'version': 1,
          \ 'kind': 'request',
          \ 'type': 'start_session',
          \ 'request_id': 'req-test',
          \ 'payload': {
          \   'notebook_id': 'nb-1',
          \   'kernel_name': 'py',
          \   'target': {
          \     'kind': 'venv',
          \     'value': 'venv://' . l:venv,
          \     },
          \   },
          \ })
    call assert_equal(1, get(l:response, 'ok', 0))
    call assert_equal('', get(l:response, 'error', ''))
  finally
    call jusi#transport#stop(bufnr('%'))
    let g:jusi_backend_cmd = l:save_backend_cmd
  endtry
endfunction

function! Test_transport_request_can_start_backend_from_docker_target() abort
  let l:save_backend_cmd = get(g:, 'jusi_backend_cmd', [])
  let l:save_path = $PATH
  let l:root = tempname()
  let l:bin = l:root . '/bin'
  let l:docker = l:bin . '/docker'
  try
    call mkdir(l:bin, 'p')
    call writefile([
          \ '#!/bin/sh',
          \ 'IFS= read -r line',
          \ "printf '%s\\n' '{\"version\":1,\"kind\":\"response\",\"type\":\"start_session\",\"request_id\":\"req-test\",\"ok\":true,\"payload\":{}}'",
          \ ], l:docker)
    call setfperm(l:docker, 'rwxr-xr-x')
    let $PATH = l:bin . ':' . l:save_path
    let g:jusi_backend_cmd = []
    call Test_open_scratch([
          \ '##',
          \ 'print(\"hello\")',
          \ ])
    let l:response = jusi#transport#request(bufnr('%'), {
          \ 'version': 1,
          \ 'kind': 'request',
          \ 'type': 'start_session',
          \ 'request_id': 'req-test',
          \ 'payload': {
          \   'notebook_id': 'nb-1',
          \   'kernel_name': 'py',
          \   'target': {
          \     'kind': 'docker',
          \     'value': 'docker://jusi-backend',
          \     },
          \   },
          \ })
    call assert_equal(1, get(l:response, 'ok', 0))
    call assert_equal('', get(l:response, 'error', ''))
  finally
    call jusi#transport#stop(bufnr('%'))
    let g:jusi_backend_cmd = l:save_backend_cmd
    let $PATH = l:save_path
  endtry
endfunction

function! s:write_transport_switch_backend(path, label, marker) abort
  call writefile([
        \ '#!/bin/sh',
        \ 'marker=' . shellescape(a:marker),
        \ 'label=' . shellescape(a:label),
        \ 'while IFS= read -r line; do',
        \ '  printf ''%s\n'' "$label" >> "$marker"',
        \ '  printf ''%s\n'' ''{"version":1,"kind":"response","type":"start_session","request_id":"req-switch-1","ok":true,"payload":{}}''',
        \ '  printf ''%s\n'' ''{"version":1,"kind":"response","type":"start_session","request_id":"req-switch-2","ok":true,"payload":{}}''',
        \ 'done',
        \ ], a:path)
  call setfperm(a:path, 'rwxr-xr-x')
endfunction

function! Test_transport_restarts_backend_when_start_target_command_changes() abort
  let l:save_backend_cmd = get(g:, 'jusi_backend_cmd', [])
  let l:save_path = $PATH
  let l:root = tempname()
  let l:bin = l:root . '/bin'
  let l:venv = l:root . '/venv'
  let l:marker = l:root . '/marker'
  try
    call mkdir(l:bin, 'p')
    call mkdir(l:venv . '/bin', 'p')
    call s:write_transport_switch_backend(l:bin . '/docker', 'docker', l:marker)
    call s:write_transport_switch_backend(l:venv . '/bin/python', 'venv', l:marker)
    let $PATH = l:bin . ':' . l:save_path
    let g:jusi_backend_cmd = []
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])

    let l:first = jusi#transport#request(bufnr('%'), {
          \ 'version': 1,
          \ 'kind': 'request',
          \ 'type': 'start_session',
          \ 'request_id': 'req-switch-1',
          \ 'payload': {
          \   'notebook_id': 'nb-1',
          \   'kernel_name': 'dockerjusi',
          \   'target': {
          \     'kind': 'docker',
          \     'value': 'docker://jusi-backend',
          \     },
          \   },
          \ })
    call assert_equal(1, get(l:first, 'ok', 0))

    let l:second = jusi#transport#request(bufnr('%'), {
          \ 'version': 1,
          \ 'kind': 'request',
          \ 'type': 'start_session',
          \ 'request_id': 'req-switch-2',
          \ 'payload': {
          \   'notebook_id': 'nb-1',
          \   'kernel_name': 'jusi',
          \   'target': {
          \     'kind': 'venv',
          \     'value': 'venv://' . l:venv,
          \     },
          \   },
          \ })
    call assert_equal(1, get(l:second, 'ok', 0))
    call assert_equal(['docker', 'venv'], readfile(l:marker))
  finally
    call jusi#transport#stop(bufnr('%'))
    let g:jusi_backend_cmd = l:save_backend_cmd
    let $PATH = l:save_path
    call delete(l:root, 'rf')
  endtry
endfunction

function! Test_transport_keeps_start_target_backend_for_execute_request() abort
  let l:save_backend_cmd = get(g:, 'jusi_backend_cmd', [])
  let l:save_path = $PATH
  let l:root = tempname()
  let l:bin = l:root . '/bin'
  let l:marker = l:root . '/marker'
  try
    call mkdir(l:bin, 'p')
    call s:write_transport_switch_backend(l:bin . '/docker', 'docker', l:marker)
    call s:write_transport_switch_backend(l:bin . '/fallback', 'fallback', l:marker)
    let $PATH = l:bin . ':' . l:save_path
    let g:jusi_backend_cmd = [l:bin . '/fallback']
    call Test_open_scratch([
          \ '##',
          \ 'print("hello")',
          \ ])

    let l:first = jusi#transport#request(bufnr('%'), {
          \ 'version': 1,
          \ 'kind': 'request',
          \ 'type': 'start_session',
          \ 'request_id': 'req-switch-1',
          \ 'payload': {
          \   'notebook_id': 'nb-1',
          \   'kernel_name': 'dockerjusi',
          \   'target': {
          \     'kind': 'docker',
          \     'value': 'docker://jusi-backend',
          \     },
          \   },
          \ })
    call assert_equal(1, get(l:first, 'ok', 0))

    let l:second = jusi#transport#request(bufnr('%'), {
          \ 'version': 1,
          \ 'kind': 'request',
          \ 'type': 'execute_cell',
          \ 'request_id': 'req-switch-2',
          \ 'payload': {
          \   'notebook_id': 'nb-1',
          \   'session_id': 'sess-1',
          \   'cell': {
          \     'id': 1,
          \     'kind': 'code',
          \     'syntax': 'python',
          \     'main_lines': ['print("hello")'],
          \     },
          \   },
          \ })
    call assert_equal(1, get(l:second, 'ok', 0))
    call assert_equal(['docker', 'docker'], readfile(l:marker))
  finally
    call jusi#transport#stop(bufnr('%'))
    let g:jusi_backend_cmd = l:save_backend_cmd
    let $PATH = l:save_path
    call delete(l:root, 'rf')
  endtry
endfunction

function! Test_transport_request_can_start_backend_from_docker_ssh_target() abort
  let l:save_backend_cmd = get(g:, 'jusi_backend_cmd', [])
  let l:save_path = $PATH
  let l:root = tempname()
  let l:bin = l:root . '/bin'
  let l:ssh = l:bin . '/ssh'
  try
    call mkdir(l:bin, 'p')
    call writefile([
          \ '#!/bin/sh',
          \ 'IFS= read -r line',
          \ "printf '%s\\n' '{\"version\":1,\"kind\":\"response\",\"type\":\"start_session\",\"request_id\":\"req-test\",\"ok\":true,\"payload\":{}}'",
          \ ], l:ssh)
    call setfperm(l:ssh, 'rwxr-xr-x')
    let $PATH = l:bin . ':' . l:save_path
    let g:jusi_backend_cmd = []
    call Test_open_scratch([
          \ '##',
          \ 'print(\"hello\")',
          \ ])
    let l:response = jusi#transport#request(bufnr('%'), {
          \ 'version': 1,
          \ 'kind': 'request',
          \ 'type': 'start_session',
          \ 'request_id': 'req-test',
          \ 'payload': {
          \   'notebook_id': 'nb-1',
          \   'kernel_name': 'py',
          \   'target': {
          \     'kind': 'docker+ssh',
          \     'value': 'docker+ssh://niku@example.com/jusi-backend',
          \     'config': {
          \       'key_path': '/tmp/test-key',
          \     },
          \     },
          \   },
          \ })
    call assert_equal(1, get(l:response, 'ok', 0))
    call assert_equal('', get(l:response, 'error', ''))
  finally
    call jusi#transport#stop(bufnr('%'))
    let g:jusi_backend_cmd = l:save_backend_cmd
    let $PATH = l:save_path
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
  call assert_equal('python', b:jusi_nb.cells[0].syntax)
endfunction

function! Test_builtin_plugin_metadata_maps_vd_to_python_dialect() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd',
        \ '[1, 2, 3]',
        \ ])
  call assert_equal('magic', b:jusi_nb.cells[0].kind)
  call assert_equal('vd', b:jusi_nb.cells[0].magic)
  call assert_equal('python', b:jusi_nb.cells[0].syntax)

  call cursor(3, 1)
  call jusi#indent#refresh(bufnr('%'))
  call assert_equal('jusi#indent#expr(v:lnum)', &l:indentexpr)
  call assert_match('python#GetIndent', get(b:, 'jusi_indent_delegate_expr', ''))
  call assert_equal('python', get(b:, 'jusi_indent_dialect', ''))
  call assert_equal(1, &l:expandtab)
  call assert_equal(4, &l:tabstop)
  call assert_equal(4, &l:softtabstop)
  call assert_equal(4, shiftwidth())
endfunction

function! Test_plugin_specs_declare_magic_syntax_and_indent_without_ftplugin() abort
  call Test_open_scratch([
        \ '##',
        \ '%%acme',
        \ 'if true; then',
        \ 'echo ok',
        \ 'fi',
        \ ])
  call jusi#session#apply({'plugin_specs': {
        \ 'acme': {'syntax': 'sh', 'indent': 'sh'},
        \ }})
  call assert_equal('magic', b:jusi_nb.cells[0].kind)
  call assert_equal('acme', b:jusi_nb.cells[0].magic)
  call assert_equal('sh', b:jusi_nb.cells[0].syntax)

  call cursor(3, 1)
  call jusi#indent#refresh(bufnr('%'))
  call assert_equal('jusi#indent#expr(v:lnum)', &l:indentexpr)
  call assert_match('GetShIndent', get(b:, 'jusi_indent_delegate_expr', ''))
  call assert_equal('sh', get(b:, 'jusi_indent_dialect', ''))
endfunction

function! Test_session_plugin_specs_callback_refreshes_existing_magic_cells() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql',
        \ 'select 1',
        \ ])
  let b:jusi_nb.session.id = 'sess-1'
  let b:jusi_nb.session.state = 'connected'
  call assert_equal('python', b:jusi_nb.cells[0].syntax)

  call jusi#session#callback_session({
        \ 'state': 'connected',
        \ 'id': 'sess-1',
        \ 'plugin_specs': {'sql': {'syntax': 'sql', 'indent': 'sql'}},
        \ })

  call assert_equal('sql', b:jusi_nb.cells[0].syntax)
  call assert_equal('sql', get(get(b:jusi_nb.session.plugin_specs, 'sql', {}), 'syntax', ''))
endfunction

function! Test_cell_presentation_overrides_session_plugin_specs() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql',
        \ 'select 1',
        \ ])
  call jusi#session#apply({'state': 'connected', 'id': 'sess-1'})
  call jusi#session#apply({'plugin_specs': {'sql': {'syntax': 'sql', 'indent': 'sql'}}})
  let l:cell_id = b:jusi_nb.cells[0].id
  call assert_equal('sql', b:jusi_nb.cells[0].syntax)

  call jusi#session#callback_cell(l:cell_id, {
        \ 'id': l:cell_id,
        \ 'status': 'follow-up',
        \ 'presentation': {'syntax': 'sh', 'indent': 'sh'},
        \ })

  call assert_equal('sh', b:jusi_nb.cells[0].syntax)
  call assert_equal({'syntax': 'sh', 'indent': 'sh'}, get(b:jusi_nb.cells[0], 'presentation', {}))
  call cursor(3, 1)
  call jusi#indent#refresh(bufnr('%'))
  call assert_equal('jusi#indent#expr(v:lnum)', &l:indentexpr)
  call assert_match('GetShIndent', get(b:, 'jusi_indent_delegate_expr', ''))
  call assert_equal('sh', get(b:, 'jusi_indent_dialect', ''))
endfunction

function! Test_unavailable_cell_presentation_syntax_is_ignored_and_existing_syntax_survives() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql',
        \ 'select 1',
        \ ])
  call jusi#session#apply({'state': 'connected', 'id': 'sess-1'})
  call jusi#session#apply({'plugin_specs': {'sql': {'syntax': 'sql', 'indent': 'sql'}}})
  let l:cell_id = b:jusi_nb.cells[0].id
  call assert_equal('sql', b:jusi_nb.cells[0].syntax)

  call jusi#session#callback_cell(l:cell_id, {
        \ 'id': l:cell_id,
        \ 'status': 'follow-up',
        \ 'presentation': {'syntax': 'sqlite', 'indent': 'sqlite'},
        \ })

  call assert_equal('sql', b:jusi_nb.cells[0].syntax)
  call assert_equal({}, get(b:jusi_nb.cells[0], 'presentation', {}))
  call cursor(3, 1)
  call jusi#indent#refresh(bufnr('%'))
  call assert_equal('jusi#indent#expr(v:lnum)', &l:indentexpr)
  call assert_notequal('', Test_syn_name(3, 1))
  call assert_true(has_key(get(b:jusi_nb, 'plugin_warnings', {}), 'syntax:sqlite'))
  call assert_true(has_key(get(b:jusi_nb, 'plugin_warnings', {}), 'indent:sqlite'))
endfunction

function! Test_unknown_magic_defaults_to_python_syntax_and_indent() abort
  call Test_open_scratch([
        \ '##',
        \ '%%unknown_magic',
        \ 'some plugin text',
        \ ])
  call assert_equal('magic', b:jusi_nb.cells[0].kind)
  call assert_equal('unknown_magic', b:jusi_nb.cells[0].magic)
  call assert_equal('python', b:jusi_nb.cells[0].syntax)

  call cursor(3, 1)
  call jusi#indent#refresh(bufnr('%'))
  call assert_equal('jusi#indent#expr(v:lnum)', &l:indentexpr)
  call assert_match('python#GetIndent', get(b:, 'jusi_indent_delegate_expr', ''))
  call assert_equal('python', get(b:, 'jusi_indent_dialect', ''))
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
    call jusi#session#apply({'plugin_specs': {'sql': {'syntax': 'sql'}}})
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
  call jusi#session#apply({'plugin_specs': {'sql': {'syntax': 'sql'}}})
  call cursor(1400, 1)
  call jusi#syntax#schedule(bufnr('%'))
  call assert_notequal('', Test_syn_name(1400, 1))

  call cursor(line('$'), 1)
  call jusi#syntax#schedule(bufnr('%'))
  call cursor(1200, 1)
  call jusi#syntax#schedule(bufnr('%'))
  call assert_notequal('', Test_syn_name(1200, 1))
endfunction

function! Test_syntax_refresh_timer_stays_bound_to_origin_buffer() abort
  if !exists('*timer_start')
    return
  endif

  call Test_open_scratch([
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ ])
  call jusi#session#apply({'plugin_specs': {'sql': {'syntax': 'sql'}}})
  let l:notebook = bufnr('%')
  let l:before_timer = getbufvar(l:notebook, 'jusi_syntax_refresh_timer', -1)
  call setbufvar(l:notebook, 'jusi_syntax_visible_key', 'stale')

  belowright new
  let l:other = bufnr('%')
  setlocal buftype=
  setlocal filetype=text

  execute 'buffer ' . l:notebook
  call jusi#syntax#request_refresh(l:notebook)
  let l:scheduled = getbufvar(l:notebook, 'jusi_syntax_refresh_timer', -1)
  call assert_true(l:scheduled > 0)

  execute 'buffer ' . l:other
  sleep 30m

  call assert_equal(0, getbufvar(l:other, 'jusi_syntax_refresh_bufnr', 0))
  call assert_equal(l:before_timer, getbufvar(l:other, 'jusi_syntax_refresh_timer', l:before_timer))
  call assert_equal(0, getbufvar(l:notebook, 'jusi_syntax_refresh_bufnr', 0))
  call assert_equal(-1, getbufvar(l:notebook, 'jusi_syntax_refresh_timer', -1))
  call assert_notequal('stale', getbufvar(l:notebook, 'jusi_syntax_visible_key', ''))
endfunction

function! Test_default_cell_uses_python_indent() abort
  call Test_open_scratch([
        \ '##',
        \ 'if True:',
        \ '    pass',
        \ ])
  call cursor(2, 1)
  call jusi#indent#refresh(bufnr('%'))
  call assert_equal('jusi#indent#expr(v:lnum)', &l:indentexpr)
  call assert_match('python#GetIndent', get(b:, 'jusi_indent_delegate_expr', ''))
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
  call jusi#session#apply({'plugin_specs': {'sh': {'syntax': 'sh', 'indent': 'sh'}}})
  call cursor(2, 1)
  call jusi#indent#refresh(bufnr('%'))
  call assert_equal('jusi#indent#expr(v:lnum)', &l:indentexpr)
  call assert_match('python#GetIndent', get(b:, 'jusi_indent_delegate_expr', ''))

  call cursor(6, 1)
  call jusi#indent#refresh(bufnr('%'))
  call assert_equal('jusi#indent#expr(v:lnum)', &l:indentexpr)
  call assert_match('GetShIndent', get(b:, 'jusi_indent_delegate_expr', ''))
  call assert_equal('sh', get(b:, 'jusi_indent_dialect', ''))
endfunction

function! Test_sql_indent_does_not_keep_python_indentexpr() abort
  call Test_open_scratch([
        \ '##',
        \ 'if True:',
        \ '    pass',
        \ '##',
        \ '%%sql',
        \ 'select * from (',
        \ ])
  call jusi#session#apply({'plugin_specs': {'sql': {'syntax': 'sql', 'indent': 'sql'}}})
  call cursor(2, 1)
  call jusi#indent#refresh(bufnr('%'))
  call assert_equal('jusi#indent#expr(v:lnum)', &l:indentexpr)
  call assert_match('python#GetIndent', get(b:, 'jusi_indent_delegate_expr', ''))

  call cursor(6, 1)
  call jusi#indent#refresh(bufnr('%'))
  call assert_equal('sql', get(b:, 'jusi_indent_dialect', ''))
  call assert_equal('jusi#indent#expr(v:lnum)', &l:indentexpr)
  call assert_notequal('python#GetIndent(v:lnum)', get(b:, 'jusi_indent_delegate_expr', ''))
endfunction

function! Test_python_indent_returns_after_sql_cell() abort
  call Test_open_scratch([
        \ '##',
        \ 'if True:',
        \ '    pass',
        \ '##',
        \ '%%sql',
        \ 'select * from (',
        \ ])
  call jusi#session#apply({'plugin_specs': {'sql': {'syntax': 'sql', 'indent': 'sql'}}})
  call cursor(6, 1)
  call jusi#indent#refresh(bufnr('%'))
  call assert_equal('sql', get(b:, 'jusi_indent_dialect', ''))
  call assert_notequal('python#GetIndent(v:lnum)', get(b:, 'jusi_indent_delegate_expr', ''))

  call cursor(2, 1)
  call jusi#indent#refresh(bufnr('%'))
  call assert_equal('python', get(b:, 'jusi_indent_dialect', ''))
  call assert_equal('python', get(b:, 'jusi_indent_loaded_dialect', ''))
  call assert_equal('jusi#indent#expr(v:lnum)', &l:indentexpr)
  call assert_match('python#GetIndent', get(b:, 'jusi_indent_delegate_expr', ''))
endfunction

function! Test_notebook_indent_does_not_cross_cell_boundaries() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql',
        \ 'select * from (',
        \ '##',
        \ '',
        \ 'if True:',
        \ '',
        \ ])
  call jusi#session#apply({'plugin_specs': {'sql': {'syntax': 'sql', 'indent': 'sql'}}})

  call cursor(5, 1)
  call jusi#indent#refresh(bufnr('%'))
  call assert_equal('python', get(b:, 'jusi_indent_dialect', ''))
  call assert_equal('jusi#indent#expr(v:lnum)', &l:indentexpr)
  call assert_match('python#GetIndent', get(b:, 'jusi_indent_delegate_expr', ''))
  call assert_equal(4, shiftwidth())
endfunction

function! Test_indent_refresh_does_not_reload_when_cell_end_changes() abort
  call Test_open_scratch([
        \ '##',
        \ 'if True:',
        \ ])
  call cursor(2, 1)
  call jusi#indent#refresh(bufnr('%'))
  let l:key = get(b:, 'jusi_indent_cell_key', '')
  let l:did_indent = get(b:, 'did_indent', 0)

  call append(2, '    pass')
  call jusi#notebook#rebuild(bufnr('%'))
  call cursor(3, 1)
  call jusi#indent#refresh(bufnr('%'))

  call assert_equal(l:key, get(b:, 'jusi_indent_cell_key', ''))
  call assert_equal(l:did_indent, get(b:, 'did_indent', 0))
  call assert_equal('jusi#indent#expr(v:lnum)', &l:indentexpr)
  call assert_match('python#GetIndent', get(b:, 'jusi_indent_delegate_expr', ''))
endfunction

function! Test_insert_enter_uses_active_python_indent() abort
  call Test_open_scratch([
        \ '##',
        \ '',
        \ ])
  call cursor(2, 1)
  call jusi#indent#refresh(bufnr('%'))

  call feedkeys('iif True:' . "\<CR>" . 'pass' . "\<Esc>", 'tx')

  call assert_equal(['##', 'if True:', '    pass'], getline(1, '$'))
  call assert_equal(4, indent(3))
  call assert_equal('jusi#indent#expr(v:lnum)', &l:indentexpr)
  call assert_match('python#GetIndent', get(b:, 'jusi_indent_delegate_expr', ''))
endfunction

function! Test_python_indent_after_sql_cell_ignores_sql_brackets() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql',
        \ 'select * from (',
        \ '##',
        \ '',
        \ ])
  call jusi#session#apply({'plugin_specs': {'sql': {'syntax': 'sql', 'indent': 'sql'}}})

  call cursor(3, 1)
  call jusi#indent#refresh(bufnr('%'))
  call assert_equal('sql', get(b:, 'jusi_indent_dialect', ''))

  call cursor(5, 1)
  call jusi#indent#refresh(bufnr('%'))
  call feedkeys('iif True:' . "\<CR>" . 'pass' . "\<Esc>", 'tx')

  call assert_equal(['##', '%%sql', 'select * from (', '##', 'if True:', '    pass'], getline(1, '$'))
  call assert_equal(4, indent(6))
  call assert_equal('python', get(b:, 'jusi_indent_dialect', ''))
  call assert_equal('jusi#indent#expr(v:lnum)', &l:indentexpr)
  call assert_match('python#GetIndent', get(b:, 'jusi_indent_delegate_expr', ''))
endfunction

function! s:test_open_named_notebook(path, lines, palette) abort
  enew!
  setlocal buftype=
  setlocal bufhidden=hide
  setlocal swapfile&
  execute 'file ' . a:path
  setlocal filetype=jusinb
  setlocal syntax=jusinb
  runtime! ftplugin/jusinb.vim
  runtime! syntax/jusinb.vim
  call setline(1, a:lines)
  call jusi#notebook#rebuild()
  call jusi#session#apply({
        \ 'state': 'connected',
        \ 'palette': copy(a:palette),
        \ })
  return bufnr('%')
endfunction

function! s:test_cleanup_palette_buffers() abort
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
endfunction

function! s:test_open_plain_buffer(name, lines) abort
  enew!
  setlocal buftype=
  setlocal bufhidden=hide
  setlocal swapfile&
  execute 'file ' . a:name
  call setline(1, a:lines)
  return bufnr('%')
endfunction

function! Test_palette_completion_lists_current_notebook_first() abort
  call s:test_cleanup_palette_buffers()
  let l:first = s:test_open_named_notebook('alpha.vipynb', ['##', '%%sql db'], {
        \ 'sql': {'entries': ['db1', 'db2']},
        \ 'shell': {'entries': []},
        \ })
  let l:second = s:test_open_named_notebook('beta.vipynb', ['##', '%%mail main'], {
        \ 'mail': {'entries': ['main']},
        \ })

  call assert_equal(l:second, bufnr('%'))
  call assert_equal(['beta', 'alpha'], jusi#palette#complete('', 'J ', 3))
  call assert_equal(['mail'], jusi#palette#complete('', 'J beta ', 8))
  call assert_equal(['main'], jusi#palette#complete('', 'J beta mail ', 13))

  execute 'buffer ' . l:first
  call assert_equal(['alpha', 'beta'], jusi#palette#complete('', 'J ', 3))
  call assert_equal(['shell', 'sql'], jusi#palette#complete('', 'J alpha ', 9))
  call assert_equal([], jusi#palette#complete('', 'J alpha shell ', 15))
endfunction

function! Test_palette_command_creates_new_magic_cell() abort
  call s:test_cleanup_palette_buffers()
  call s:test_open_named_notebook('alpha.vipynb', ['##', 'print("hello")'], {
        \ 'sql': {'entries': ['db1']},
        \ })

  call jusi#palette#command(0, 0, 0, 'alpha sql db1')
  silent! stopinsert

  call assert_equal('alpha.vipynb', bufname('%'))
  call assert_equal([
        \ '##',
        \ 'print("hello")',
        \ '##',
        \ '%%sql db1',
        \ '',
        \ ], getline(1, '$'))
  call assert_equal('%%sql db1', getline(4))
  call assert_equal(5, line('.'))
endfunction

function! Test_palette_command_notebook_only_creates_plain_code_cell() abort
  call s:test_cleanup_palette_buffers()
  call s:test_open_named_notebook('alpha.vipynb', ['##', 'print("hello")'], {
        \ 'sql': {'entries': ['db1']},
        \ })

  call jusi#palette#command(0, 0, 0, 'alpha')
  silent! stopinsert

  call assert_equal([
        \ '##',
        \ 'print("hello")',
        \ '##',
        \ '',
        \ ], getline(1, '$'))
  call assert_equal(4, line('.'))
endfunction

function! Test_palette_command_accepts_bare_magic_section_without_entry() abort
  call s:test_cleanup_palette_buffers()
  call s:test_open_named_notebook('alpha.vipynb', ['##', 'print("hello")'], {
        \ 'shell': {'entries': []},
        \ })

  call jusi#palette#command(0, 0, 0, 'alpha shell')
  silent! stopinsert

  call assert_equal([
        \ '##',
        \ 'print("hello")',
        \ '##',
        \ '%%shell',
        \ '',
        \ ], getline(1, '$'))
  call assert_equal(5, line('.'))
endfunction

function! Test_palette_command_reuses_existing_magic_cell_with_extra_args() abort
  call s:test_cleanup_palette_buffers()
  call s:test_open_named_notebook('alpha.vipynb', [
        \ '##',
        \ '%%mail mymail -f outbox',
        \ 'old body',
        \ ], {
        \ 'mail': {'entries': ['mymail']},
        \ })

  call jusi#palette#command(0, 0, 0, 'alpha mail mymail -f outbox')
  silent! stopinsert

  call assert_equal(1, len(filter(copy(jusi#notebook#cells()), 'get(v:val, "kind", "") ==# "magic"')))
  call assert_equal('%%mail mymail -f outbox', getline(2))
  call assert_equal('old body', getline(3))
  call assert_equal(2, line('.'))
endfunction

function! Test_palette_command_reuses_exact_entry_prefix_not_longer_entry() abort
  call s:test_cleanup_palette_buffers()
  call s:test_open_named_notebook('alpha.vipynb', [
        \ '##',
        \ '%%codex jusivim',
        \ 'vim body',
        \ '##',
        \ '%%codex jusi',
        \ 'jusi body',
        \ ], {
        \ 'codex': {'entries': ['jusi', 'jusivim']},
        \ })

  call jusi#palette#command(0, 0, 0, 'alpha codex jusi')
  silent! stopinsert

  call assert_equal('%%codex jusivim', getline(2))
  call assert_equal('vim body', getline(3))
  call assert_equal('%%codex jusi', getline(5))
  call assert_equal('jusi body', getline(6))
  call assert_equal(5, line('.'))
endfunction

function! Test_palette_command_creates_short_entry_instead_of_reusing_longer_entry() abort
  call s:test_cleanup_palette_buffers()
  call s:test_open_named_notebook('alpha.vipynb', [
        \ '##',
        \ '%%codex jusivim',
        \ 'vim body',
        \ ], {
        \ 'codex': {'entries': ['jusi', 'jusivim']},
        \ })

  call jusi#palette#command(0, 0, 0, 'alpha codex jusi')
  silent! stopinsert

  call assert_equal([
        \ '##',
        \ '%%codex jusivim',
        \ 'vim body',
        \ '##',
        \ '%%codex jusi',
        \ '',
        \ ], getline(1, '$'))
  call assert_equal(6, line('.'))
endfunction

function! Test_palette_command_bang_opens_target_notebook_split() abort
  call s:test_cleanup_palette_buffers()
  let l:target = s:test_open_named_notebook('alpha.vipynb', ['##', '%%sql db1', 'select 1'], {
        \ 'sql': {'entries': ['db1']},
        \ })
  call s:test_open_plain_buffer(tempname() . '.txt', ['outside'])

  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'execute': function('s:test_session_adapter_execute')}
    call jusi#palette#command(1, 0, 0, 'alpha sql db1')
    call assert_equal('alpha.vipynb', bufname('%'))
    call assert_true(len(getwininfo()) > 1)
    call assert_equal('busy', get(jusi#notebook#cell_at_line(), 'status', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_palette_command_bang_splits_when_target_visible_only_in_other_tab() abort
  call s:test_cleanup_palette_buffers()
  let l:target = s:test_open_named_notebook('alpha.vipynb', ['##', '%%sql db1', 'select 1'], {
        \ 'sql': {'entries': ['db1']},
        \ })
  tabnew
  call s:test_open_plain_buffer(tempname() . '.txt', ['outside'])
  let l:outside_tab = tabpagenr()

  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'execute': function('s:test_session_adapter_execute')}
    call jusi#palette#command(1, 0, 0, 'alpha sql db1')
    call assert_equal(l:outside_tab, tabpagenr())
    call assert_equal('alpha.vipynb', bufname('%'))
    call assert_true(len(filter(getwininfo(), 'v:val.tabnr == tabpagenr()')) > 1)
    call assert_equal('busy', get(jusi#notebook#cell_at_line(), 'status', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_palette_command_range_replaces_target_cell_body() abort
  call s:test_cleanup_palette_buffers()
  call s:test_open_plain_buffer(tempname() . '.txt', ['one line', 'two line'])
  let l:source = bufnr('%')
  call setpos("'<", [bufnr('%'), 1, 1, 0])
  call setpos("'>", [bufnr('%'), 2, 8, 0])
  call s:test_open_named_notebook('alpha.vipynb', ['##', '%%shell main', 'old'], {
        \ 'shell': {'entries': ['main']},
        \ })
  execute 'buffer ' . l:source

  call jusi#palette#command(0, 1, 2, 'alpha shell main')
  silent! stopinsert

  execute 'buffer alpha.vipynb'
  call assert_equal([
        \ '##',
        \ '%%shell main',
        \ 'one line',
        \ 'two line',
        \ ], getline(1, '$'))
endfunction

function! Test_palette_command_bang_range_notebook_only_creates_plain_code_cell_and_executes() abort
  call s:test_cleanup_palette_buffers()
  call s:test_open_plain_buffer(tempname() . '.txt', ['one line', 'two line'])
  call setpos("'<", [bufnr('%'), 1, 1, 0])
  call setpos("'>", [bufnr('%'), 2, 8, 0])
  call s:test_open_named_notebook('alpha.vipynb', ['##', 'print("hello")'], {
        \ 'sql': {'entries': ['db1']},
        \ })
  buffer #

  let l:save_adapter = get(g:, 'jusi_session_adapter', {})
  try
    let g:jusi_session_adapter = {'execute': function('s:test_session_adapter_execute')}
    call jusi#palette#command(1, 1, 2, 'alpha')
    call assert_equal('alpha.vipynb', bufname('%'))
    call assert_equal([
          \ '##',
          \ 'print("hello")',
          \ '##',
          \ 'one line',
          \ 'two line',
          \ ], getline(1, '$'))
    call assert_equal('busy', get(jusi#notebook#cell_at_line(), 'status', ''))
  finally
    let g:jusi_session_adapter = l:save_adapter
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
  call assert_equal(':<C-U>call jusi#notebook#toggle_history_fold_current()<CR>', maparg('<leader>h', 'n', 0, 1).rhs)
  call assert_equal(':<C-U>call jusi#notebook#execute_or_apply_history()<CR>', maparg('<leader>j', 'n', 0, 1).rhs)
  call assert_equal(':JusiTogglePark<CR>', maparg('<leader>s', 'n', 0, 1).rhs)
  call assert_equal(':JusiRestartKernel<CR>', maparg('<leader>00', 'n', 0, 1).rhs)
  call assert_equal(':JusiInterruptKernel<CR>', maparg('<leader>ii', 'n', 0, 1).rhs)
  call assert_equal(':<C-U>call jusi#cellmode#close_client(v:count)<CR>', maparg('<leader>q', 'n', 0, 1).rhs)
  call assert_equal(':<C-U>call jusi#cellmode#goto_client(v:count)<CR>', maparg('<leader>g', 'n', 0, 1).rhs)
  call assert_equal('', maparg('<leader><Space>', 'n'))
  call assert_equal(':JusiToggleFocus<CR>', maparg("\<C-\\>\<C-\\>", 'n', 0, 1).rhs)
  call assert_equal('', maparg(']]', 'n'))
  call assert_equal('', maparg('[[', 'n'))
  call assert_equal(':JusiCellModeToggle<CR>', maparg('<Space>', 'n', 0, 1).rhs)
  call assert_equal('', maparg('o', 'n'))
  call assert_equal('', maparg('d', 'n'))
  call assert_equal('', maparg('p', 'x'))
  call assert_equal('<C-R>=jusi#focus#toggle()<CR>', maparg("\<C-\\>\<C-\\>", 'i', 0, 1).rhs)
  call assert_equal('<C-\><C-o>:JusiComplete<CR>', maparg('<Tab>', 'i', 0, 1).rhs)
  call assert_equal('', maparg('<CR>', 'i'))
  call assert_equal('<C-\><C-o>:call jusi#notebook#execute_and_edit_current()<CR>', maparg('<C-Y>', 'i', 0, 1).rhs)
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
  call assert_equal(':<C-U>call jusi#notebook#goto_next_cellmode_target()<CR>', maparg('j', 'n', 0, 1).rhs)
  call assert_equal(':<C-U>call jusi#notebook#goto_next_cellmode_target()<CR>', maparg('n', 'n', 0, 1).rhs)
  call assert_equal(':<C-U>call jusi#notebook#goto_prev_cellmode_target()<CR>', maparg('k', 'n', 0, 1).rhs)
  call assert_equal(':<C-U>call jusi#notebook#execute_or_apply_history()<CR>', maparg('<CR>', 'n', 0, 1).rhs)
  call assert_equal(':<C-U>call jusi#notebook#apply_history_relative(-1)<CR>', maparg('<C-P>', 'n', 0, 1).rhs)
  call assert_equal(':<C-U>call jusi#notebook#apply_history_relative(1)<CR>', maparg('<C-N>', 'n', 0, 1).rhs)
  call assert_equal(':<C-U>call jusi#notebook#toggle_history_fold_current()<CR>', maparg('H', 'n', 0, 1).rhs)
  call assert_equal('', maparg('J', 'n'))
  call assert_equal('', maparg('<leader><Space>', 'n'))
  call assert_equal('', maparg('B', 'n'))
  call assert_equal('', maparg('A', 'n'))
  call assert_equal(':JusiCellDelete<CR>', maparg('X', 'n', 0, 1).rhs)
  call assert_equal(':JusiCellEdit<CR>', maparg('C', 'n', 0, 1).rhs)
  call assert_equal(':JusiCellCopy<CR>', maparg('Y', 'n', 0, 1).rhs)
  call assert_equal(':JusiCellPasteBelow<CR>', maparg('P', 'n', 0, 1).rhs)
  call assert_equal(':JusiTogglePark<CR>', maparg('S', 'n', 0, 1).rhs)
  call assert_equal(':<C-U>call jusi#cellmode#close_client(v:count)<CR>', maparg('Q', 'n', 0, 1).rhs)
  call assert_equal(':<C-U>call jusi#cellmode#goto_client(v:count)<CR>', maparg('G', 'n', 0, 1).rhs)
  call assert_equal(':JusiRebuild<CR>', maparg('R', 'n', 0, 1).rhs)
  call jusi#cellmode#disable()
  call assert_equal(0, get(b:, 'jusi_cell_mode', 1))
  call assert_equal('', maparg('j', 'n'))
  call assert_equal('', maparg('n', 'n'))
  call assert_equal('', maparg('<CR>', 'n'))
endfunction

function! Test_client_buffer_gets_toggle_focus_mappings() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd pods',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)

  call jusi#focus#place_client_buffer(l:client, 'bsplit', 0)
  call assert_equal(':JusiToggleFocus<CR>', maparg("\<C-\\>\<C-\\>", 'n', 0, 1).rhs)
  call assert_equal('<C-R>=jusi#focus#toggle()<CR>', maparg("\<C-\\>\<C-\\>", 'i', 0, 1).rhs)
  call assert_equal('<C-\><C-n>:call jusi#focus#toggle_from_terminal()<CR>', maparg("\<C-\\>\<C-\\>", 't', 0, 1).rhs)
  call assert_match('^%!jusi#statusline#render_client()', &l:statusline)
  call win_gotoid(bufwinid(l:notebook))
endfunction

function! Test_client_buffer_bufenter_hook_applies_statusline() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
  let b:jusi_nb.cells[0].status = 'done'
  let b:jusi_nb.cells[0].client_id = 'client-1'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)

  execute 'sbuffer ' . l:client

  call assert_match('^%!jusi#statusline#render_client()', &l:statusline)
  call assert_match('Jusi client-1', jusi#statusline#render_client())
  call win_gotoid(bufwinid(l:notebook))
endfunction

function! Test_nvim_native_terminal_bufenter_follows_output_tail() abort
  if !has('nvim')
    return
  endif
  call Test_open_scratch([
        \ '##',
        \ '%%vd pods',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
  call setbufvar(l:client, 'jusi_client_transport_kind', 'native_terminal')
  call setbufline(l:client, 1, ['one', 'two', 'three', 'four', 'five', 'six'])
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)

  call jusi#focus#place_client_buffer(l:client, 'bsplit', 0)
  normal! gg
  call jusi#focus#refresh_client_window(l:client)

  call assert_equal(line('$'), line('.'))
  call win_gotoid(bufwinid(l:notebook))
endfunction

function! Test_nvim_native_terminal_prime_visible_window_follows_output_tail() abort
  if !has('nvim')
    return
  endif
  call Test_open_scratch([
        \ '##',
        \ '%%shell',
        \ 'echo hi',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-1')
  call setbufvar(l:client, 'jusi_client_transport_kind', 'native_terminal')
  call setbufline(l:client, 1, ['one', 'two', 'three', 'four', 'five', 'six'])
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-1', l:client)

  call jusi#focus#place_client_buffer(l:client, 'bsplit', 1)
  let l:client_winid = bufwinid(l:client)
  call win_execute(l:client_winid, 'normal! gg')

  call jusi#focus#prime_client_windows_for_buffer(l:client)

  call assert_equal(trim(win_execute(l:client_winid, 'echo line("$")')), trim(win_execute(l:client_winid, 'echo line(".")')))
endfunction

function! Test_notebook_statusline_shows_session_and_current_cell() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ ])
  call jusi#session#apply({'state': 'connected', 'target': {'alias': 'ololo', 'kind': 'venv'}})
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].client_id = 'client-11'
  call cursor(3, 1)

  call assert_match('Jusi test\.vipynb', jusi#statusline#render_notebook())
  call assert_match('connected', jusi#statusline#render_notebook())
  call assert_match('target:ololo', jusi#statusline#render_notebook())
  call assert_notmatch('mode:cell', jusi#statusline#render_notebook())
  call jusi#cellmode#enable()
  call assert_match('target:ololo mode:cell', jusi#statusline#render_notebook())
  call assert_match('%#JusiStatusNotebookMode# mode:cell%#StatusLine#', jusi#statusline#render_notebook())
  call assert_notmatch('cell:', jusi#statusline#render_notebook())
  call assert_match('^%!jusi#statusline#render_notebook()', &l:statusline)
endfunction

function! Test_client_statusline_shows_client_identity() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd pods',
        \ ])
  let l:notebook = bufnr('%')
  let l:cell_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-11')
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].client_id = 'client-11'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-11', l:client)

  call jusi#focus#place_client_buffer(l:client, 'bsplit', 0)
  call assert_match('Jusi client-11', jusi#statusline#render_client())
  call assert_match('nb:test', jusi#statusline#render_client())
  call assert_notmatch('cell:', jusi#statusline#render_client())
  call assert_notmatch('status:', jusi#statusline#render_client())
  call win_gotoid(bufwinid(l:notebook))
endfunction

function! Test_statusline_render_uses_target_window_context() abort
  call Test_open_scratch([
        \ '##',
        \ '%%vd pods',
        \ ])
  let l:notebook = bufnr('%')
  call jusi#session#apply({'state': 'connected', 'target': {'alias': 'ololo', 'kind': 'venv'}})
  let l:cell_id = b:jusi_nb.cells[0].id
  let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-11')
  let b:jusi_nb.cells[0].status = 'follow-up'
  let b:jusi_nb.cells[0].client_id = 'client-11'
  let b:jusi_nb.cells[0].client_bufnr = l:client
  call jusi#client#mark_attached_buffer(l:notebook, l:cell_id, 'client-11', l:client)

  call jusi#focus#place_client_buffer(l:client, 'bsplit', 0)
  let l:notebook_winid = bufwinid(l:notebook)
  let l:client_winid = bufwinid(l:client)
  call win_gotoid(l:client_winid)
  let g:statusline_winid = l:notebook_winid
  call assert_match('Jusi test\.vipynb', jusi#statusline#render_notebook())
  call assert_match('connected', jusi#statusline#render_notebook())
  let g:statusline_winid = l:client_winid
  call assert_match('Jusi client-11', jusi#statusline#render_client())
  call assert_match('nb:test', jusi#statusline#render_client())
  unlet g:statusline_winid
  call win_gotoid(l:notebook_winid)
endfunction

function! Test_cellmode_goto_client_uses_numeric_client_suffix() abort
  call Test_open_scratch([
        \ '##',
        \ 'one',
        \ '##',
        \ 'two',
        \ ])
  let b:jusi_nb.cells[1].client_id = 'client-11'
  call jusi#cellmode#enable()

  call jusi#cellmode#goto_client(11)
  call assert_equal(4, line('.'))
endfunction

function! Test_cellmode_goto_client_without_count_behaves_like_normal_G() abort
  call Test_open_scratch([
        \ '##',
        \ 'one',
        \ '##',
        \ 'two',
        \ '##',
        \ 'three',
        \ ])
  call cursor(2, 1)
  call jusi#cellmode#enable()

  call jusi#cellmode#goto_client(0)
  call assert_equal(line('$'), line('.'))
endfunction

function! Test_cellmode_close_client_with_count_targets_matching_cell() abort
  call Test_open_scratch([
        \ '##',
        \ 'one',
        \ '##',
        \ 'two',
        \ ])
  let l:notebook = bufnr('%')
  let l:client = jusi#client#create_managed_buffer(l:notebook, 'client-11')
  let b:jusi_nb.cells[1].client_id = 'client-11'
  let b:jusi_nb.cells[1].client_bufnr = l:client
  let b:jusi_nb.cells[1].status = 'done'
  call jusi#client#mark_attached_buffer(l:notebook, b:jusi_nb.cells[1].id, 'client-11', l:client)
  call cursor(2, 1)
  call jusi#cellmode#enable()

  call jusi#cellmode#close_client(11)
  call assert_equal('', get(b:jusi_nb.cells[1], 'client_id', ''))
  call assert_equal(-1, get(b:jusi_nb.cells[1], 'client_bufnr', -1))
endfunction

function! Test_start_kernel_completion_uses_kernel_target_aliases() abort
  let l:save_targets = get(g:, 'jusi_kernel_targets', {})
  try
    let g:jusi_kernel_targets = {
          \ 'py': 'venv://venv1',
          \ 'remote': 'ssh://user@host',
          \ }
    call assert_equal(['py', 'remote'], jusi#session#complete_start('', 'JusiStartKernel ', 17))
    call assert_equal(['remote'], jusi#session#complete_start('re', 'JusiStartKernel re', 19))
  finally
    let g:jusi_kernel_targets = l:save_targets
  endtry
endfunction

function! Test_attach_completion_uses_attach_registry_aliases() abort
  let l:save_registry = get(g:, 'jusi_attach_registry_file', '')
  try
    let g:jusi_attach_registry_file = tempname()
    call writefile(['{"py-remote":{"session_id":"sess-1"},"sql-prod":{"session_id":"sess-2"}}'], g:jusi_attach_registry_file)
    call assert_equal(['py-remote', 'sql-prod'], jusi#session#complete_attach('', 'JusiAttach ', 12))
    call assert_equal(['sql-prod'], jusi#session#complete_attach('sq', 'JusiAttach sq', 14))
  finally
    let g:jusi_attach_registry_file = l:save_registry
  endtry
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
  call jusi#cellmode#disable()
  call assert_equal(0, jusi#cellmode#should_show_indicator())
  call assert_equal('', jusi#cellmode#indicator_text())
  call assert_notmatch('mode:cell', jusi#statusline#render_notebook())
  call jusi#cellmode#enable()
  call assert_equal(&filetype ==# 'jusinb' && mode() =~# '^[nc]', jusi#cellmode#should_show_indicator())
  call assert_equal('cell', jusi#cellmode#indicator_text())
  call assert_match('mode:cell', jusi#statusline#render_notebook())
  call assert_match('%#JusiStatusNotebookMode# mode:cell%#StatusLine#', jusi#statusline#render_notebook())
  call jusi#cellmode#update_indicator(v:true)
  call assert_match('mode:cell', jusi#statusline#render_notebook())
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

function! Test_insert_mode_text_changed_only_invalidates_until_exit() abort
  call Test_open_scratch([
        \ '##',
        \ 'one',
        \ '##',
        \ 'two',
        \ ])
  call append(2, 'one more')
  call jusi#notebook#handle_text_changed_insert()
  call assert_equal(2, b:jusi_nb.cells[0].end)
  call assert_equal(3, b:jusi_nb.cells[1].start)
  call assert_equal(1, b:jusi_nb.dirty_insert)
  call jusi#notebook#handle_insert_exit()
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
  call assert_equal(1, b:jusi_nb.dirty_insert)
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

function! Test_normal_mode_same_line_edit_preserves_magic_history_region() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ '##<<',
        \ '###',
        \ 'select 0',
        \ '##>>',
        \ ])
  let l:id_before = b:jusi_nb.cells[0].id

  call setline(3, 'select 2')
  call jusi#notebook#handle_text_changed()

  call assert_equal(l:id_before, b:jusi_nb.cells[0].id)
  call assert_equal(3, b:jusi_nb.cells[0].body_end)
  call assert_equal(4, b:jusi_nb.cells[0].history_start)
  call assert_equal(7, b:jusi_nb.cells[0].history_end)
  call assert_equal(['%%sql main', 'select 2'], jusi#notebook#cell_main_lines(b:jusi_nb.cells[0]))
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

function! Test_normal_mode_line_insert_preserves_magic_history_region() abort
  call Test_open_scratch([
        \ '##',
        \ '%%sql main',
        \ 'select 1',
        \ '##<<',
        \ '###',
        \ 'select 0',
        \ '##>>',
        \ '##',
        \ 'print("next")',
        \ ])
  let l:ids_before = map(copy(b:jusi_nb.cells), 'v:val.id')

  call append(3, 'limit 1')
  call jusi#notebook#handle_text_changed()

  call assert_equal(l:ids_before, map(copy(b:jusi_nb.cells), 'v:val.id'))
  call assert_equal(4, b:jusi_nb.cells[0].body_end)
  call assert_equal(5, b:jusi_nb.cells[0].history_start)
  call assert_equal(8, b:jusi_nb.cells[0].history_end)
  call assert_equal(9, b:jusi_nb.cells[1].start)
  call assert_equal(['%%sql main', 'select 1', 'limit 1'], jusi#notebook#cell_main_lines(b:jusi_nb.cells[0]))
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
