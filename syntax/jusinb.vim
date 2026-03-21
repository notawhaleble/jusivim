if exists('b:current_syntax')
  finish
endif

call jusi#syntax#define_base()

let b:current_syntax = 'jusinb'
