if !has('vim9script')
  finish
endif
vim9script

# Name:        StylePicker
# Author:      Lifepillar <lifepillar@lifepillar.me>
# Maintainer:  Lifepillar <lifepillar@lifepillar.me>
# License:     Vim license (see `:help license`)

if !(has('popupwin') && has('textprop'))
  finish
endif

import '../autoload/stylepicker.vim' as sp
command! -nargs=? -bar -complete=highlight StylePicker sp.Open(<q-args>)
