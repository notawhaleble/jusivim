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
