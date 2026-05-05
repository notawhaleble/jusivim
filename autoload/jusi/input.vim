function! jusi#input#pending_input_from_view(view) abort
  if get(a:view, 'execution_status', '') !=# 'busy'
    return {}
  endif
  let l:lines = get(a:view, 'lines', [])
  let l:idx = len(l:lines) - 1
  while l:idx >= 0
    let l:line = l:lines[l:idx]
    if empty(l:line)
      let l:idx -= 1
      continue
    endif
    if l:line =~# '^input>\s*'
      return {
            \ 'prompt': matchstr(l:line, '^input>\s*\zs.*$'),
            \ 'password': 0,
            \ }
    endif
    if l:line =~# '^password>\s*'
      return {
            \ 'prompt': matchstr(l:line, '^password>\s*\zs.*$'),
            \ 'password': 1,
            \ }
    endif
    return {}
  endwhile
  return {}
endfunction
