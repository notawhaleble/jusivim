function! jusi#window#client_layout_command(layout) abort
  let l:layout = empty(a:layout) ? get(g:, 'jusi_client_layout', 'bsplit') : a:layout
  let l:map = {
        \ 'asplit': 'aboveleft split',
        \ 'Asplit': 'topleft split',
        \ 'bsplit': 'belowright split',
        \ 'Bsplit': 'botright split',
        \ 'rsplit': 'vertical belowright split',
        \ 'lsplit': 'vertical topleft split',
        \ 'tab': 'tab split',
        \ }
  return get(l:map, l:layout, l:map['bsplit'])
endfunction
