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
  call assert_equal(1, l:signs[0][1])
  call assert_equal(3, l:signs[1][1])
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
endfunction

function! Test_long_sql_cell_multiline_comment_sync() abort
  let l:lines = ['##', '%%sql main', '/*']
  for l:num in range(1, 1200)
    call add(l:lines, 'comment line ' . l:num)
  endfor
  call add(l:lines, '*/')
  call add(l:lines, 'select 1;')

  call Test_open_scratch(l:lines)

  let l:comment_line = len(l:lines) - 1
  let l:select_line = len(l:lines)
  call cursor(l:select_line, 1)

  call assert_equal('sqlComment', Test_syn_name(l:comment_line, 1))
  call assert_equal('sqlStatement', Test_syn_name(l:select_line, 1))
endfunction
