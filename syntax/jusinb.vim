if exists('b:current_syntax')
  finish
endif

syntax match jusiDelimiter '^##\s*$'
highlight default link jusiDelimiter Comment

let b:current_syntax = 'jusinb'
