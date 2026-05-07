function! jusi#buffer#is_valid_bufnr(bufnr) abort
  return type(a:bufnr) == type(0) && a:bufnr > 0 && bufexists(a:bufnr)
endfunction
