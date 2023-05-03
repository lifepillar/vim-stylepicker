vim9script

var stylePickerId = - 1 # Style picker's window ID

const SAMPLE_TEXT = get(g:, 'stylepicker_quotes', [
       "Absentem edit cum ebrio qui litigat.",
       "Accipere quam facere praestat iniuriam",
       "Amicum cum vides obliviscere miserias.",
       "Diligite iustitiam qui iudicatis terram.",
       "Etiam capillus unus habet umbram suam.",
       "Impunitas semper ad deteriora invitat.",
       "Mala tempora currunt sed peiora parantur",
       "Nec quod fuimusve sumusve, cras erimus",
       "Nec sine te, nec tecum vivere possum",
       "Quis custodiet ipsos custodes?",
       "Quod non vetat lex, hoc vetat fieri pudor.",
       "Vim vi repellere licet",
       "Vana gloria spica ingens est sine grano.",
      ])

def SampleText()
  return SAMPLE_TEXT[rand() % len(SAMPLE_TEXT)]
enddef

def Closed(id: number, result: any)
  echo 'Stylepicker closed'
  stylePickerId = -1
enddef

def Filter(winId: number, key: string): number
  return 0
enddef

class StylePicker
  this.hiGroup: string = null_string
  this.x               = 0
  this.y               = 0
  this.mode        = (has('gui_running') || (has('termguicolors') && &termguicolors) ? 'gui' : 'cterm')
  this.attrMode    = (has('gui_running') ? 'gui' : (exists('&t_Co') && str2nr(&t_Co) > 2 ? 'cterm' : 'term'))
  this.markSym     = get(g:, 'stylepicker_marker', '❯❯ ')
  this.starSym     = get(g:, 'stylepicker_star', '*')
  this.winId: number
  this.width: number
  this.gutterWidth: number

  def new(this.hiGroup = v:none, this.x = v:none, this.y = v:none)
    this.width = max([39 + strdisplaywidth(this.markSym), 42])
    this.gutterWidth = strdisplaywidth(this.markSym, 0)
    this.winId = popup_create('', {
          \ border:      [1, 1, 1, 1],
          \ borderchars: get(g:, 'stylepicker_borderchars', ['─', '│', '─', '│', '╭', '╮', '╯', '╰']),
          \ callback:    'Closed',
          \ close:       'button',
          \ cursorline:  0,
          \ drag:        1,
          \ filter:      'Filter',
          \ filtermode:  'n',
          \ highlight:   get(g:, 'stylepicker_bg', 'Normal'),
          \ mapping:     get(g:, 'stylepicker_mapping', true),
          \ maxwidth:    this.width,
          \ minwidth:    this.width,
          \ padding:     [0, 1, 0, 1],
          \ pos:         'topleft',
          \ line:        this.y,
          \ col:         this.x,
          \ resize:      0,
          \ scrollbar:   0,
          \ tabpage:     0,
          \ title:       '',
          \ wrap:        0,
          \ zindex:      200,
          \ })

    setbufvar(winbufnr(this.winId), '&tabstop', &tabstop)  # Inherit global tabstop value
  enddef

  def Bufnr()
    return winbufnr(this.winId)
  enddef
endclass


export def Open(hiGroup: string = null_string)
  if stylePickerId < 0
    const stylePicker = StylePicker.new(hiGroup)
    stylePickerId = stylePicker.winId
  else
    popup_show(stylePickerId)
  endif
enddef
