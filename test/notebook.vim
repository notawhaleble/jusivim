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
  call assert_equal([1, 2], map(copy(l:cells), 'v:val.id'))
  call assert_equal(2, line('.'))
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
  call assert_equal(['##', ''], jusi#notebook#cell_main_lines())
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
  call assert_equal(-1, l:parsed.cells[0].client_bufnr)
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

function! s:test_session_adapter_start(bufnr, payload) abort
  return {
        \ 'ok': 1,
        \ 'session': {
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

let s:last_bound_prepared = {}

function! s:test_session_adapter_bind_prepared(bufnr, payload) abort
  let s:last_bound_prepared = copy(a:payload)
  return {'ok': 1}
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

function! Test_default_session_state_is_initialized_for_notebook() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let l:session = jusi#session#state()
  call assert_equal('idle', l:session.state)
  call assert_equal('', l:session.backend)
  call assert_equal('', l:session.last_error)
  call assert_equal('', l:session.prepared.id)
  call assert_equal('missing', l:session.prepared.state)
  call assert_equal(-1, l:session.prepared.bufnr)
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
    call assert_equal('mock', l:session.backend)
    call assert_equal('python3', l:session.kernel_name)
    call assert_equal('mock://kernel/python3', l:session.connection)
    call assert_equal('start', l:session.last_action)
    call assert_equal('', l:session.last_error)
    call assert_equal('client-1', l:session.prepared.id)
    call assert_equal('binding', l:session.prepared.state)
    call assert_equal(-1, l:session.prepared.bufnr)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
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
    call jusi#session#apply_prepared({'id': 'client-1', 'state': 'ready', 'bufnr': 91})
    call jusi#session#execute_current()
    call assert_equal('connected', b:jusi_nb.session.state)
    call assert_equal('client-2', b:jusi_nb.session.prepared.id)
    call assert_equal('binding', b:jusi_nb.session.prepared.state)
    call assert_equal(-1, b:jusi_nb.session.prepared.bufnr)
    call assert_equal('busy', b:jusi_nb.cells[0].status)
    call assert_equal(91, b:jusi_nb.cells[0].client_bufnr)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
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

function! Test_stop_kernel_moves_attachable_session_to_stopped() abort
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
    let b:jusi_nb.session.attachable = 1
    call jusi#session#stop()
    call assert_equal('stopped', b:jusi_nb.session.state)
    call assert_equal('missing', b:jusi_nb.session.prepared.state)
  finally
    let g:jusi_session_adapter = l:save_adapter
  endtry
endfunction

function! Test_session_callback_updates_prepared_state() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  call jusi#session#callback_prepared({'id': 'client-77', 'state': 'ready', 'bufnr': 77})
  call assert_equal('client-77', b:jusi_nb.session.prepared.id)
  call assert_equal('ready', b:jusi_nb.session.prepared.state)
  call assert_equal(77, b:jusi_nb.session.prepared.bufnr)
endfunction

function! Test_session_callback_updates_cell_state() abort
  call Test_open_scratch([
        \ '##',
        \ 'print("hello")',
        \ ])
  let l:cell_id = b:jusi_nb.cells[0].id
  call jusi#session#callback_cell(l:cell_id, {'status': 'follow-up', 'client_bufnr': 88})
  call assert_equal('follow-up', b:jusi_nb.cells[0].status)
  call assert_equal(88, b:jusi_nb.cells[0].client_bufnr)
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
  call assert_equal('', maparg(']]', 'n'))
  call assert_equal('', maparg('[[', 'n'))
  call assert_equal(':JusiCellModeToggle<CR>', maparg('<Space>', 'n', 0, 1).rhs)
  call assert_equal('', maparg('o', 'n'))
  call assert_equal('', maparg('d', 'n'))
  call assert_equal('', maparg('p', 'x'))
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
  call assert_equal(':JusiCellNewBelow<CR>', maparg('B', 'n', 0, 1).rhs)
  call assert_equal(':JusiCellNewAbove<CR>', maparg('A', 'n', 0, 1).rhs)
  call assert_equal(':JusiCellDelete<CR>', maparg('X', 'n', 0, 1).rhs)
  call assert_equal(':JusiCellEdit<CR>', maparg('C', 'n', 0, 1).rhs)
  call assert_equal(':JusiCellCopy<CR>', maparg('Y', 'n', 0, 1).rhs)
  call assert_equal(':JusiCellPasteBelow<CR>', maparg('P', 'n', 0, 1).rhs)
  call assert_equal(':JusiRebuild<CR>', maparg('R', 'n', 0, 1).rhs)
  call jusi#cellmode#disable()
  call assert_equal(0, get(b:, 'jusi_cell_mode', 1))
  call assert_equal('', maparg('j', 'n'))
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
  call assert_equal(&filetype ==# 'jusinb' && mode() =~# '^n', jusi#cellmode#should_show_indicator())
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
