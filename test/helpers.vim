function! Test_open_scratch(lines) abort
  enew!
  setlocal buftype=
  setlocal bufhidden=wipe
  setlocal swapfile&
  file test.vipynb
  setlocal filetype=jusinb
  if empty(a:lines)
    call setline(1, [''])
  else
    call setline(1, a:lines)
  endif
  if line('$') > len(a:lines)
    execute (len(a:lines) + 1) . ',$delete _'
  endif
  call jusi#notebook#rebuild()
endfunction

function! Test_sign_lines(bufnr) abort
  let l:result = []
  for l:item in sign_getplaced(a:bufnr, {'group': jusi#render#sign_group()})[0].signs
    call add(l:result, [l:item.id, l:item.lnum, l:item.name])
  endfor
  return l:result
endfunction
