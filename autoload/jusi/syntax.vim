function! s:normalize_bufnr(bufnr) abort
  if a:bufnr is# 0 || a:bufnr is# ''
    return bufnr('%')
  endif
  return str2nr(a:bufnr)
endfunction

function! s:clear_dynamic_groups() abort
  let l:groups = get(b:, 'jusi_dynamic_syntax_groups', [])
  for l:group in l:groups
    execute 'syntax clear ' . l:group
  endfor
  let b:jusi_dynamic_syntax_groups = []
endfunction

function! s:register_group(name) abort
  if !exists('b:jusi_dynamic_syntax_groups')
    let b:jusi_dynamic_syntax_groups = []
  endif
  call add(b:jusi_dynamic_syntax_groups, a:name)
endfunction

function! s:clear_sync_groups() abort
  syntax sync clear
  let b:jusi_dynamic_sync_groups = []
endfunction

function! s:register_sync_group(name) abort
  if !exists('b:jusi_dynamic_sync_groups')
    let b:jusi_dynamic_sync_groups = []
  endif
  call add(b:jusi_dynamic_sync_groups, a:name)
endfunction

function! s:include_cluster(filetype) abort
  let l:loaded = get(b:, 'jusi_syntax_includes', {})
  if has_key(l:loaded, a:filetype)
    return 1
  endif

  let l:path = globpath(&runtimepath, 'syntax/' . a:filetype . '.vim', 0, 1)
  if empty(l:path)
    return 0
  endif

  let l:current = exists('b:current_syntax') ? b:current_syntax : ''
  if exists('b:current_syntax')
    unlet b:current_syntax
  endif
  execute 'syntax include @jusiSyntax_' . a:filetype . ' syntax/' . a:filetype . '.vim'
  let b:current_syntax = l:current

  let l:loaded[a:filetype] = 1
  let b:jusi_syntax_includes = l:loaded
  return 1
endfunction

function! jusi#syntax#define_base() abort
  syntax match jusiDelimiter '^##\s*$'
  syntax match jusiMagicHeader '^%%\k\+.*$'
  highlight default link jusiDelimiter Comment
  highlight default link jusiMagicHeader PreProc
endfunction

function! s:body_start(cell) abort
  if a:cell.kind ==# 'magic'
    return a:cell.start + 2
  endif
  return a:cell.start + 1
endfunction

function! s:body_filetype(cell) abort
  return get(a:cell, 'syntax', '')
endfunction

function! s:apply_sync(cells) abort
  let l:max_span = 1

  call s:clear_sync_groups()
  for l:cell in a:cells
    let l:start = s:body_start(l:cell)
    if l:start <= l:cell.end
      let l:group = 'jusiCellSync_' . l:cell.id
      call s:register_sync_group(l:group)
      execute 'syntax sync match ' . l:group
            \ . ' grouphere NONE /\%' . l:start . 'l^/'
      let l:max_span = max([l:max_span, l:cell.end - l:start + 1])
    endif
  endfor

  execute 'syntax sync minlines=' . l:max_span . ' maxlines=' . l:max_span
endfunction

function! s:define_body_region(cell) abort
  let l:start = s:body_start(a:cell)
  let l:end = a:cell.end
  if l:start > l:end
    return
  endif

  let l:filetype = s:body_filetype(a:cell)
  if empty(l:filetype) || !s:include_cluster(l:filetype)
    return
  endif

  let l:group = 'jusiCellBody_' . a:cell.id
  call s:register_group(l:group)
  execute 'syntax region ' . l:group
        \ . ' start=/\%' . l:start . 'l^/'
        \ . ' end=/\%' . l:end . 'l$/'
        \ . ' keepend contains=@jusiSyntax_' . l:filetype
endfunction

function! jusi#syntax#sync(bufnr, cells) abort
  let l:bufnr = s:normalize_bufnr(a:bufnr)
  if l:bufnr != bufnr('%')
    return
  endif

  call jusi#syntax#define_base()
  call s:clear_dynamic_groups()
  call s:apply_sync(a:cells)

  for l:cell in a:cells
    call s:define_body_region(l:cell)
  endfor
endfunction
