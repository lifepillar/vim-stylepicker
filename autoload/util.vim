vim9script

const QUOTES = get(g:, 'stylepicker_quotes', [
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

export def Quote(): string
  return QUOTES[rand() % len(QUOTES)]
enddef

export def Msg(text: string, error = false)
  if error
    echohl Error
  else
    echohl WarningMsg
  endif

  echomsg $'[StylePicker] {text}.'
  echohl None
enddef

export def ErrMsg(text: string)
  Msg(text, true)
enddef

export def Center(text: string, width: number): string
  const lPad = repeat(' ', (width + 1 - strwidth(text)) / 2)
  const rPad = repeat(' ', (width - strwidth(text)) / 2)
  return $'{lPad}{text}{rPad}'
enddef

export def In(v: any, items: list<any>): bool
  return index(items, v) != -1
enddef

export def NotIn(v: any, items: list<any>): bool
  return index(items, v) == -1
enddef

export def Int(cond: bool): number
  return cond ? 1 : 0
enddef

