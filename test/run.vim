set nocompatible
set runtimepath^=.
set viminfofile=NONE
syntax on

runtime plugin/jusi.vim

source test/notebook.vim

call Test_parser_detects_cells_and_magic()
call Test_rebuild_places_signs_on_cell_starts()
call Test_insert_below_creates_new_cell()
call Test_insert_above_creates_new_cell()
call Test_navigation_moves_to_cell_boundaries()
call Test_existing_cell_ids_are_preserved_across_rebuilds()
call Test_cell_lookup_works_inside_long_cell_without_line_map()
call Test_existing_syntax_override_survives_rebuild()
call Test_magic_header_has_dedicated_syntax_group()
call Test_syntax_updates_after_cell_type_change()
call Test_long_sql_cell_multiline_comment_sync()
call Test_default_buffer_mappings_exist()
call Test_cell_mode_toggle_maps_navigation_keys()
call Test_cell_mode_switches_sign_highlights()
call Test_blank_body_cell_sign_uses_first_body_line()
call Test_empty_vipynb_buffer_gets_initial_delimiter()
call Test_cell_mode_indicator_state_transitions()

if empty(v:errors)
  cquit 0
endif

for error in v:errors
  echom error
endfor

cquit 1
