set nocompatible
set runtimepath^=.
set viminfofile=NONE

runtime plugin/jusi.vim

source test/notebook.vim

call Test_parser_detects_cells_and_magic()
call Test_rebuild_places_signs_on_cell_starts()
call Test_insert_below_creates_new_cell()
call Test_insert_above_creates_new_cell()
call Test_navigation_moves_to_cell_boundaries()
call Test_existing_cell_ids_are_preserved_across_rebuilds()

if empty(v:errors)
  cquit 0
endif

for error in v:errors
  echom error
endfor

cquit 1
