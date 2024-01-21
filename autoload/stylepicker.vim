vim9script

if !has('popupwin') || !has('textprop')
  export def Open(hiGroup: string = null_string)
    echomsg 'Stylepicker requires Vim compiled with popupwin and textprop'
  enddef
  finish
endif

import 'libcolor.vim'              as libcolor
import '../import/libreactive.vim' as react
import autoload './util.vim'       as util

const ColorMode = util.ColorMode
const StyleMode = util.StyleMode
const Int       = util.Int
const Msg       = util.Msg
const Quote     = util.Quote

type Reader = func(): any
type Writer = func(any)

# Internal state
var gStylePickerID = -1 # The style picker's window ID
var gX = 0
var gY = 0
var gEdited = {fg: false, bg: false, sp: false}
var gRecentColors: list<string> = []
var gFavoriteColors: list<string> = []
var gFavoritePath = get(g:, 'stylepicker_favorite_path', '')
var gActionMap: dict<func()>
var gTimeLastDigitPressed = reltime()

const NUM_COLORS_PER_LINE = 10
const RGB_PANE  = 0
const HSB_PANE  = 1
const GRAY_PANE = 2
const HELP_PANE = 99

# Helper functions {{{
def In(v: any, items: list<any>): bool
  return index(items, v) != -1
enddef

def NotIn(v: any, items: list<any>): bool
  return index(items, v) == -1
enddef

def Borderchars(): list<string>
  return get(
    g:, 'stylepicker_borderchars', ['─', '│', '─', '│', '┌', '┐', '┘', '└']
  )
enddef

def Marker(): string
  return get(g:, 'stylepicker_marker', '❯❯ ')
enddef

def Star(): string
  return get(
    g:, 'stylepicker_star', get(g:, 'stylepicker_ascii', false) ? '*' : '★'
  )
enddef

def Gutter(selected: bool): string
  const marker = Marker()

  if selected
    return marker
  else
    return repeat(' ', strdisplaywidth(marker, 0))
  endif
enddef

def PopupWidth(): number
  return max([39 + strdisplaywidth(Marker()), 42])
enddef

def Center(text: string, width: number = PopupWidth()): string
  const lPad = repeat(' ', (width + 1 - strwidth(text)) / 2)
  const rPad = repeat(' ', (width - strwidth(text)) / 2)
  return $'{lPad}{text}{rPad}'
enddef

def Notification(winID: number, text: string, duration = 2000)
  if get(g:, 'stylepicker_notifications', true)
    const width = PopupWidth()

    popup_notification(Center(text), {
      pos:         'topleft',
      line:        popup_getoptions(winID).line,
      col:         popup_getoptions(winID).col,
      highlight:   'Normal',
      time:        duration,
      moved:       'any',
      mousemoved:  'any',
      minwidth:    width,
      maxwidth:    width,
      borderchars: Borderchars(),
    })
  endif
enddef

# Assign an integer score from zero to five to a pair of colors according to
# how many criteria the pair satifies. Thresholds follow W3C guidelines.
def ComputeScore(hexCol1: string, hexCol2: string): number
  # TODO: convert to rgb first
  const cr = libcolor.ContrastRatio(hexCol1, hexCol2)
  const cd = libcolor.ColorDifference(hexCol1, hexCol2)
  const bd = libcolor.BrightnessDifference(hexCol1, hexCol2)

  return Int(cr >= 3.0) + Int(cr >= 4.5) + Int(cr >= 7.0) + Int(cd >= 500) + Int(bd >= 125)
enddef

def HiGroupUnderCursor(): string
  return synIDattr(synIDtrans(synID(line('.'), col('.'), true)), 'name')
enddef

def HiGroupAttr(hiGroup: string, what: string, mode: string): string
  return synIDattr(synIDtrans(hlID(hiGroup)), $'{what}#', mode)
enddef

def UltimateFallbackColor(what: string): string
  if what == 'bg'
    return &bg == 'dark' ? '#000000' : '#ffffff'
  else
    return &bg == 'dark' ? '#ffffff' : '#000000'
  endif
enddef

# Try hard to determine a sensible hex value for the requested color attribute
def GetColor(hiGroup: string, what: string, mode: string): string
  const fgbgs = (what == 'sp' && mode == 'cterm' ? 'ul' : what)
  const value = HiGroupAttr(hiGroup, fgbgs, mode)

  if !empty(value) # Fast path
    if mode == 'gui'
      return value
    else
      return libcolor.ColorNumber2Hex(str2nr(value))
    endif
  endif

  if what == 'sp'
    return GetColor(hiGroup, 'fg', mode)
  elseif hiGroup == 'Normal'
    return UltimateFallbackColor(what)
  endif

  return GetColor('Normal', what, mode)
enddef

# Initialize the highlight groups used by the style picker
def ResetHighlight()
  const mode         = ColorMode()
  const warnColor    = HiGroupAttr('WarningMsg', 'fg', mode)
  const labelColor   = HiGroupAttr('Label',      'fg', mode)
  const commentColor = HiGroupAttr('Comment',    'fg', mode)

  execute $'hi stylePickerOn            {mode}fg={labelColor}   term=bold             cterm=bold             gui=bold'
  execute $'hi stylePickerOff           {mode}fg={commentColor} term=NONE             cterm=NONE             gui=NONE'
  execute $'hi stylePickerWarning       {mode}fg={warnColor}                          cterm=bold             gui=bold'
  execute $'hi stylePickerBold          {mode}fg={labelColor}   term=bold             cterm=bold             gui=bold'
  execute $'hi stylePickerItalic        {mode}fg={labelColor}   term=bold,italic      cterm=bold,italic      gui=bold,italic'
  execute $'hi stylePickerUnderline     {mode}fg={labelColor}   term=bold,underline   cterm=bold,underline   gui=bold,underline'
  execute $'hi stylePickerUndercurl     {mode}fg={labelColor}   term=bold,undercurl   cterm=bold,undercurl   gui=bold,undercurl'
  execute $'hi stylePickerUnderdouble   {mode}fg={labelColor}   term=bold,underdouble cterm=bold,underdouble gui=bold,underdouble'
  execute $'hi stylePickerUnderdotted   {mode}fg={labelColor}   term=bold,underdotted cterm=bold,underdotted gui=bold,underdotted'
  execute $'hi stylePickerUnderdashed   {mode}fg={labelColor}   term=bold,underdashed cterm=bold,underdashed gui=bold,underdashed'
  execute $'hi stylePickerStandout      {mode}fg={labelColor}   term=bold,standout    cterm=bold,standout    gui=bold,standout'
  execute $'hi stylePickerInverse       {mode}fg={labelColor}   term=bold,inverse     cterm=bold,inverse     gui=bold,inverse'
  execute $'hi stylePickerStrikethrough {mode}fg={labelColor}   term=bold,inverse     cterm=bold,inverse     gui=bold,inverse'
  hi! stylePickerGray000 guibg=#000000 ctermbg=16
  hi! stylePickerGray025 guibg=#404040 ctermbg=238
  hi! stylePickerGray050 guibg=#7f7f7f ctermbg=244
  hi! stylePickerGray075 guibg=#bfbfbf ctermbg=250
  hi! stylePickerGray100 guibg=#ffffff ctermbg=231
  hi clear stylePickerGuiColor
  hi clear stylePickerTermColor
enddef
# }}}

# Text with Properties {{{
# _norm: Normal text
# _on__: Property for 'enabled' stuff
# _off_: Property for 'disabled' stuff
# _sel_: Mark line as an item that can be selected
# _labe: Mark line as a label
# _leve: Mark line as a level bar (slider)
# _mru_: Mark line as a 'recent colors' line
# _fav_: Mark line as a 'favorite colors' line
# _curr: To highlight text with the currently selected highglight group
# _warn: Highlight for warning symbols
# _titl: Highlight for title section
# _gcol: Highlight for the current GUI color
# _tcol: Highlight for the current cterm color
# _bold: Highlight for bold attribute
# _ital: Highlight for italic attribute
# _ulin: Highlight for underline attribute
# _curl: Highlight for undercurl attribute
# _sout: Highlight for standout attribute
# _invr: Highlight for inverse attribute
# _strk: Highlight for strikethrough attribute
# _gray: Grayscale blocks
# _g000: Grayscale blocks
# _g025: Grayscale blocks
# _g050: Grayscale blocks
# _g075: Grayscale blocks
# _g100: Grayscale blocks

# IDs for selectable items
const RGB_RED_SLIDER_ID    = 128
const RGB_GREEN_SLIDER_ID = 129
const RGB_BLUE_SLIDER_ID   = 130
const RECENT_COLORS_ID     = 1024
const FAVORITE_COLORS_ID   = 8192

type TextProperty = dict<any> # See :help text-properties
type RichText     = dict<any> # {text: '...', props: [textProp1, ..., textPropN]}

def PropertyTypes(bufnr: number): dict<dict<any>>
  return {
    '_norm': {bufnr: bufnr, highlight: 'Normal'                   },
    '_on__': {bufnr: bufnr, highlight: 'stylePickerOn'            },
    '_off_': {bufnr: bufnr, highlight: 'stylePickerOff'           },
    '_sel_': {bufnr: bufnr                                        },
    '_labe': {bufnr: bufnr, highlight: 'Label'                    },
    '_leve': {bufnr: bufnr                                        },
    '_mru_': {bufnr: bufnr                                        },
    '_fav_': {bufnr: bufnr                                        },
    '_curr': {bufnr: bufnr                                        },
    '_warn': {bufnr: bufnr, highlight: 'stylePickerWarning'       },
    '_titl': {bufnr: bufnr, highlight: 'Title'                    },
    '_gcol': {bufnr: bufnr, highlight: 'stylePickerGuiColor'      },
    '_tcol': {bufnr: bufnr, highlight: 'stylePickerTermColor'     },
    '_bold': {bufnr: bufnr, highlight: 'stylePickerBold'          },
    '_ital': {bufnr: bufnr, highlight: 'stylePickerItalic'        },
    '_ulin': {bufnr: bufnr, highlight: 'stylePickerUnderline'     },
    '_curl': {bufnr: bufnr, highlight: 'stylePickerUndercurl'     },
    '_sout': {bufnr: bufnr, highlight: 'stylePickerStandout'      },
    '_invr': {bufnr: bufnr, highlight: 'stylePickerInverse'       },
    '_strk': {bufnr: bufnr, highlight: 'stylePickerStrikethrough' },
    '_gray': {bufnr: bufnr                                        },
    '_g000': {bufnr: bufnr, highlight: 'stylePickerGray000'       },
    '_g025': {bufnr: bufnr, highlight: 'stylePickerGray025'       },
    '_g050': {bufnr: bufnr, highlight: 'stylePickerGray050'       },
    '_g075': {bufnr: bufnr, highlight: 'stylePickerGray075'       },
    '_g100': {bufnr: bufnr, highlight: 'stylePickerGray100'       },
  }
enddef

def SetPropertyTypes(bufnr: number)
  const propTypes = PropertyTypes(bufnr)

  for [propType, propValue] in items(propTypes)
    prop_type_add(propType, propValue)
  endfor
enddef

def Text(t: string): RichText
  return {text: t, props: []}
enddef

def Blank(): RichText
  return Text('')
enddef

def Styled(
    t: RichText, propType: string, from = 1, length = strchars(t.text), id = 0
    ): RichText
  var newProp = {col: from, length: length, type: propType }

  if id > 0
    newProp.id = id
  endif

  var styledText = {
    text: t.text,
    props: t.props->add(newProp)
  }

  return styledText
enddef

def Title(t: RichText, from = 1, length = strchars(t.text)): RichText
  return Styled(t, '_titl', from, length)
enddef

def Label(t: RichText, from = 1, length = strchars(t.text)): RichText
  return Styled(t, '_labe', from, length)
enddef

def OnOff(
    t: RichText, enable: bool, from = 1, length = strchars(t.text)
    ): RichText
  return Styled(t, enable ? '_on__' : '_off_', from, length)
enddef

def Selectable(t: RichText, id: number): RichText
  return {
    text: t.text,
    props: t.props->add({col: 1, length: 1, type: '_sel_', id: id})
  }
enddef

# Return the list of the names of the text properties for the given line in
# the given buffer.
def GetProperties(bufnr: number, lnum: number): list<string>
  return map(prop_list(lnum, {bufnr: bufnr}), (i, v) => v.type)
enddef

def GetPropertyID(bufnr: number, lnum: number, propName: string): number
  return get(prop_find({bufnr: bufnr, lnum: lnum, col: 1, type: propName}), 'id', -1)
enddef
# }}}

# Signals {{{
var Pane:        Reader # Current pane
var HiGrp:       Reader # Current highlgiht group
var FgBgS:       Reader # Current attribute ('fg', 'bg', or 'sp')
var Selected:    Reader # Line number of the currently selected line
var Step:        Reader # Current increment/decrement step
var Recent:      Reader # List of recent colors
var Favorite:    Reader # List of favorite colors
var Color:       Reader # Value of the current color (e.g., '#fdfdfd')
var Style:       Reader # Dictionary of style attributes (e.g., {bold, true, italic: false, etc...})
var SetPane:     Writer
var SetHiGrp:    Writer
var SetFgBgS:    Writer
var SetSelected: Writer
var SetStep:     Writer
var SetRecent:   Writer
var SetFavorite: Writer
var SetColor:    Writer
var SetStyle:    Writer

def InitSignals(hiGroup: string)
  [Pane,     SetPane]     = react.Property(-1)
  [HiGrp,    SetHiGrp]    = react.Property(hiGroup)
  [FgBgS,    SetFgBgS]    = react.Property('fg')
  [Selected, SetSelected] = react.Property(1)
  [Step,     SetStep]     = react.Property(1)
  [Recent,   SetRecent]   = react.Property([])
  [Favorite, SetFavorite] = react.Property([])
  [Color,    SetColor]    = ColorSignal.new().GetterSetter()
  [Style,    SetStyle]    = StyleSignal.new().GetterSetter()
enddef

# ID of the selected line
def SelectedID(bufnr: number): number
  return GetPropertyID(bufnr, Selected(), '_sel_')
enddef

const gRecentCapacity = get(g:, 'stylepicker_recent', 20)

def SaveToRecent(color: string)
  var recent: list<string> = Recent()

  if color->NotIn(recent)
    recent->add(color)

    if len(recent) > gRecentCapacity
      remove(recent, 0)
    endif

    SetRecent(recent)
  endif

  gEdited = {fg: false, bg: false, sp: false}
  gEdited[FgBgS()] = true
enddef

def LoadColors(loadPath: string)
  if empty(loadPath)
    return
  endif

  var palette: list<string>

  try
    palette = readfile(loadPath)
  catch /.*/
    Msg($'Could not load favorite colors: {v:exception}', true)
    palette = []
  endtry

  filter(palette, (_, v) => v =~ '\m^#[A-Fa-f0-9]\{6}$')
  SetFavorite(palette)
enddef

def PersistColors(palette: list<string>, savePath: string)
  if empty(savePath)
    return
  endif

  try
    if writefile(palette, savePath, 's') < 0
      Msg($'Failed to write {savePath}', true)
    endif
  catch /.*/
    Msg($'Could not persist favorite colors: {v:exception}')
  endtry
enddef

def SaveToFavorite(color: string, savePath: string)
  var favorite: list<string> = Favorite()

  if color->NotIn(favorite)
    favorite->add(color)
    SetFavorite(favorite)
    PersistColors(favorite, savePath)
  endif
enddef

def AskIndex(max: number): number
  echo $'[StylePicker] Which color (0-{max})? '
  const key = getcharstr()
  echo "\r"

  if key =~ '\m^\d$'
    const n = str2nr(key)

    if n <= max
      return n
    endif
  endif

  return -1
enddef

def ActOnPalette(
    winID:      number,
    Palette:    Reader,
    SetPalette: Writer,
    line:       number,
    Action:     func(list<string>, number, Reader, Writer)
    ): bool
  var palette: list<string> = Palette()
  var from = line * NUM_COLORS_PER_LINE
  var to   = from + NUM_COLORS_PER_LINE - 1

  if to >= len(palette)
    to = len(palette) - 1
  endif

  const n = AskIndex(to - from)

  if n >= 0
    Action(palette, from + n, Palette, SetPalette)
    return true
  endif

  return false
enddef

class ColorSignal extends react.Signal
  def Read(): string
    this._value = GetColor(HiGrp(), FgBgS(), ColorMode())
    return super.Read()
  enddef

  def Write(newValue: string)
    if !gEdited[FgBgS()]
      SaveToRecent(Color())
    endif

    hlset([{name: HiGrp(), [$'gui{FgBgS()}']: newValue}]) # FIXME: doesn't work in terminal
    super.Write(newValue)
  enddef
endclass

class StyleSignal extends react.Signal
  static const styles: dict<bool> = {
    bold:          false,
    italic:        false,
    reverse:       false,
    standout:      false,
    strikethrough: false,
    underline:     false,
    undercurl:     false,
    underdashed:   false,
    underdotted:   false,
    underdouble:   false,
  }

  def Read(): dict<bool>
    const hl = hlget(HiGrp(), true)[0]
    var style: dict<bool> = get(hl, 'gui', get(hl, 'cterm', {}))

    this._value = StyleSignal.styles->extendnew(style, 'force')

    if this._value.undercurl || this._value.underdashed || this._value.underdotted || this._value.underdouble
      this._value.underline = true
    endif

    return super.Read()
  enddef

  def Write(newValue: dict<bool>)
    const style = filter(newValue, (_, v) => v)

    hlset([{name: HiGrp(), 'gui': style, 'cterm': style}])
    super.Write(newValue)
  enddef
endclass

def AltColor(): string
  if FgBgS() == 'bg'
    return HiGroupAttr(HiGrp(), 'fg', 'gui')
  else
    return HiGroupAttr(HiGrp(), 'bg', 'gui')
  endif
enddef
# }}}

# Key map {{{
const KEYMAP = extend({
  'close':            "x",
  'cancel':           "X",
  'yank':             "Y",
  'paste':            "P",
  'down':             "\<down>",
  'up':               "\<up>",
  'top':              "<",
  'bot':              ">",
  'decrement':        "\<left>",
  'increment':        "\<right>",
  'fg>bg>sp':         "\<tab>",
  'fg<bg<sp':         "\<s-tab>",
  'pick-color':       "\<enter>",
  'remove-color':     "D",
  'toggle-bold':      "B",
  'toggle-italic':    "I",
  'toggle-underline': "U",
  'toggle-reverse':   "V",
  'toggle-standout':  "S",
  'toggle-strike':    "K",
  'set-underline':    "_",
  'set-undercurl':    "~",
  'set-underdotted':  ".",
  'set-underdashed':  "-",
  'set-underdouble':  "=",
  'new-color':        "E",
  'new-higroup':      "N",
  'clear':            "Z",
  'add-to-favorite':  "A",
  'rgb-pane':         "R",
  'hsb-pane':         "H",
  'gray-pane':        "G",
  'help':             "?",
}, get(g:, 'stylepicker_keys', {}), 'force')

const PRETTY_KEY = {
  "\<left>":  "←",
  "\<right>": "→",
  "\<up>":    "↑",
  "\<down>":  "↓",
  "\<tab>":   "↳",
  "\<s-tab>": "⇧-↳",
  "\<enter>": "↲",
}

def KeySymbol(action: string): string
  const key = KEYMAP[action]
  return get(PRETTY_KEY, key, key)
enddef
# }}}

# Actions {{{
def GetPaletteInfo(bufnr: number, lnum: number): dict<any>
  const props = GetProperties(bufnr, lnum)

  if '_mru_'->In(props)
    const id = GetPropertyID(bufnr, lnum, '_mru_')
    return {id: id, Getter: Recent, Setter: SetRecent}
  elseif '_fav_'->In(props)
    const id = GetPropertyID(bufnr, lnum, '_fav_')
    return {id: id, Getter: Favorite, Setter: SetFavorite}
  endif

  return {}
enddef

def PickColor(winID: number): func()
  const bufnr = winbufnr(winID)
  const Pick = (palette: list<string>, n: number, R: Reader, W: Writer) => {
    SaveToRecent(Color())
    SetColor(palette[n])
  }

  return () => {
    const info = GetPaletteInfo(bufnr, Selected())

    if !empty(info)
      ActOnPalette(winID, info.Getter, info.Setter, info.id - 1, Pick)
    endif
  }
enddef

def RemoveColor(winID: number): func()
  const bufnr = winbufnr(winID)
  const Remove = (palette: list<string>, n: number, R: Reader, SetPalette: Writer) => {
    remove(palette, n)
    SetPalette(palette)
  }

  return () => {
    const info = GetPaletteInfo(bufnr, Selected())

    if !empty(info)
      ActOnPalette(winID, info.Getter, info.Setter, info.id - 1, Remove)

      if empty(info.Getter())
        SelectPrev(winID)() # TODO: optimize (double redraw: after deleting and after selecting previous)
      endif

      if info.Getter is Favorite
        PersistColors(info.Getter(), gFavoritePath)
      endif
    endif
  }
enddef

def YankColor(winID: number): func()
  const bufnr = winbufnr(winID)
  const Yank = (palette: list<string>, n: number, R: Reader, W: Writer) => {
    @" = palette[n]
  }

  return () => {
    const info = GetPaletteInfo(bufnr, Selected())

    if empty(info)
      @" = Color()
      Notification(winID, 'Color yanked: ' .. @")
    else
      if ActOnPalette(winID, info.Getter, info.Setter, info.id - 1, Yank)
        Notification(winID, 'Color yanked: ' .. @")
      endif
    endif
  }
enddef

def PasteColor(windID: number): func()
  return () => {
    if @" =~ '\m^#\=[A-Fa-f0-9]\{6}$'
      # FIXME: this will redraw twice
      SaveToRecent(Color())
      SetColor(@"[0] == '#' ? @" : '#' .. @")
    endif
  }
enddef

def AddToFavorite(winID: number): func()
  return () => {
    SaveToFavorite(Color(), gFavoritePath)
  }
enddef

def Increment(winID: number): func()
  return () => {
    const selectedID = SelectedID(winbufnr(winID))

    if selectedID == RGB_RED_SLIDER_ID || selectedID == RGB_GREEN_SLIDER_ID || selectedID == RGB_BLUE_SLIDER_ID
      var [red, green, blue] = libcolor.Hex2Rgb(Color())

      if selectedID == RGB_RED_SLIDER_ID
        red += Step()

        if red > 255
          red = 255
        endif
      elseif selectedID == RGB_GREEN_SLIDER_ID
        green += Step()

        if green > 255
          green = 255
        endif
      else
        blue += Step()

        if blue > 255
          blue = 255
        endif
      endif

      SetColor(libcolor.Rgb2Hex(red, green, blue))
    endif
  }
enddef

def Decrement(winID: number): func()
  return () => {
    const selectedID = SelectedID(winbufnr(winID))

    if selectedID == RGB_RED_SLIDER_ID || selectedID == RGB_GREEN_SLIDER_ID || selectedID == RGB_BLUE_SLIDER_ID
      var [red, green, blue] = libcolor.Hex2Rgb(Color())

      if selectedID == RGB_RED_SLIDER_ID
        red -= Step()

        if red < 0
          red = 0
        endif
      elseif selectedID == RGB_GREEN_SLIDER_ID
        green -= Step()

        if green < 0
          green = 0
        endif
      else
        blue -= Step()

        if blue < 0
          blue = 0
        endif
      endif

      SetColor(libcolor.Rgb2Hex(red, green, blue))
    endif
  }
enddef

def FgBgSNext(): func()
  return () => {
    const old = FgBgS()
    const new = (old == 'fg' ? 'bg' : old == 'bg' ? 'sp' : 'fg')
    SetFgBgS(new)
  }
enddef

def FgBgSPrev(): func()
  return () => {
    const old = FgBgS()
    const new = (old == 'fg' ? 'sp' : old == 'sp' ? 'bg' : 'fg')
    SetFgBgS(new)
  }
enddef

def SelectTop_(winID: number)
  const bufnr = winbufnr(winID)
  const lnum = prop_find({bufnr: bufnr, type: '_sel_', lnum: 1, col: 1}, 'f').lnum
  SetSelected(lnum)
enddef

def SelectBot_(winID: number)
  const bufnr = winbufnr(winID)
  const lnum = prop_find({bufnr: bufnr, type: '_sel_', lnum: line('$', winID), col: 1}, 'b').lnum
  SetSelected(lnum)
enddef

def SelectTop(winID: number): func()
  return () => SelectTop_(winID)
enddef

def SelectBot(winID: number): func()
  return () => SelectBot_(winID)
enddef

def SelectNext(winID: number): func()
  const bufnr = winbufnr(winID)

  return () => {
    const nextItem = prop_find({bufnr: bufnr, type: '_sel_', lnum: Selected(), col: 1, skipstart: true}, 'f')

    if empty(nextItem)
      SelectTop_(winID)
    else
      SetSelected(nextItem.lnum)
    endif
  }
enddef

def SelectPrev(winID: number): func()
  const bufnr = winbufnr(winID)

  return () => {
    const prevItem = prop_find({bufnr: bufnr, type: '_sel_', lnum: Selected(), col: 1, skipstart: true}, 'b')

    if empty(prevItem)
      SelectBot_(winID)
    else
      SetSelected(prevItem.lnum)
    endif
  }
enddef

def Close(winID: number): func()
  return () => {
    ClosedCallback(winID)
    popup_hide(winID)
  }
enddef

def Cancel(winID: number): func()
  return () => {
    ClosedCallback(winID)
    popup_hide(winID)

    # FIXME: revert only the changes of the stylepicker
    if exists('g:colors_name') && !empty('g:colors_name')
      execute 'colorscheme' g:colors_name
    endif
    echo "\r"
    echomsg $'[Stylepicker] {gStylePickerID} canceled'
  }
enddef

def ChooseGuiColor(): string
  var newCol = input('New color: #', '')
  echo "\r"

  if newCol =~ '\m^[0-9a-fa-f]\{1,6}$'
    if len(newCol) <= 3
      newCol = repeat(newCol, 6 /  len(newCol))
    endif

    if len(newCol) == 6
      return $'#{newCol}'
    endif
  endif

  return ''
enddef

def ChooseTermColor(): string
  var newCol = input('New terminal color [16-255]: ', '')
  echo "\r"
  const numCol = str2nr(newCol)

  if 16 <= numCol && numCol <= 255
    return libcolor.Xterm2Hex(numCol)
  endif

  return ''
enddef

def ChooseColor(): func()
  return () => {
    var newCol: string

    if ColorMode() == 'gui'
      newCol = ChooseGuiColor()
    else
      newCol = ChooseTermColor()
    endif

    if !empty(newCol)
      SaveToRecent(Color())
      SetColor(newCol)
    endif
  }
enddef

def ChooseHiGrp(): func()
  return () => {
    const name = input('Highlight group: ', '', 'highlight')
    echo "\r"

    if hlexists(name)
      gEdited = {fg: false, bg: false, sp: false}
      SetHiGrp(name)
    endif
  }
enddef

def ToggleStyleAttribute(attr: string): func()
  return () => {
    var currentStyle: dict<bool> = Style()
    currentStyle[attr] = !currentStyle[attr]
    SetStyle(currentStyle)
    }
enddef

def ClearColor(winID: number): func()
  return () => {
    const hiGroup = HiGrp()
    const guiAttr = FgBgS()
    const termAttr = guiAttr == 'sp' ? 'ul' : guiAttr

    # FIXME: double redraw
    SaveToRecent(Color())
    execute $'hi! {hiGroup} gui{guiAttr}=NONE cterm{termAttr}=NONE'
    SetHiGrp(hiGroup) # Force updating the UI
    Notification(winID, 'Color cleared')
  }
enddef

def SwitchPane(pane: number): func()
  return () => {
    SetPane(pane)
  }
enddef

def ActionMap(winID: number): dict<func()>
  return {
      [KEYMAP['close'           ]]: Close(winID),
      [KEYMAP['cancel'          ]]: Cancel(winID),
      [KEYMAP['down'            ]]: SelectNext(winID),
      [KEYMAP['up'              ]]: SelectPrev(winID),
      [KEYMAP['top'             ]]: SelectTop(winID),
      [KEYMAP['bot'             ]]: SelectBot(winID),
      [KEYMAP['decrement'       ]]: Decrement(winID),
      [KEYMAP['increment'       ]]: Increment(winID),
      [KEYMAP['fg>bg>sp'        ]]: FgBgSNext(),
      [KEYMAP['fg<bg<sp'        ]]: FgBgSPrev(),
      [KEYMAP['pick-color'      ]]: PickColor(winID),
      [KEYMAP['remove-color'    ]]: RemoveColor(winID),
      [KEYMAP['yank'            ]]: YankColor(winID),
      [KEYMAP['paste'           ]]: PasteColor(winID),
      [KEYMAP['add-to-favorite' ]]: AddToFavorite(winID),
      [KEYMAP['toggle-bold'     ]]: ToggleStyleAttribute('bold'),
      [KEYMAP['toggle-italic'   ]]: ToggleStyleAttribute('italic'),
      [KEYMAP['toggle-underline']]: ToggleStyleAttribute('underline'),
      [KEYMAP['toggle-reverse'  ]]: ToggleStyleAttribute('reverse'),
      [KEYMAP['toggle-standout' ]]: ToggleStyleAttribute('standout'),
      [KEYMAP['toggle-strike'   ]]: ToggleStyleAttribute('strikethrough'),
      [KEYMAP['set-underline'   ]]: ToggleStyleAttribute('underline'),
      [KEYMAP['set-undercurl'   ]]: ToggleStyleAttribute('undercurl'),
      [KEYMAP['set-underdotted' ]]: ToggleStyleAttribute('underdotted'),
      [KEYMAP['set-underdashed' ]]: ToggleStyleAttribute('underdashed'),
      [KEYMAP['set-underdouble' ]]: ToggleStyleAttribute('underdouble'),
      [KEYMAP['new-color'       ]]: ChooseColor(),
      [KEYMAP['new-higroup'     ]]: ChooseHiGrp(),
      [KEYMAP['clear'           ]]: ClearColor(winID),
      [KEYMAP['rgb-pane'        ]]: SwitchPane(RGB_PANE),
      [KEYMAP['hsb-pane'        ]]: SwitchPane(HSB_PANE),
      [KEYMAP['gray-pane'       ]]: SwitchPane(GRAY_PANE),
      [KEYMAP['help'            ]]: SwitchPane(HELP_PANE),
  }
enddef
# }}}

# Sliders {{{
const DEFAULT_SLIDER_SYMBOLS = get(g:, 'stylepicker_ascii', false)
  ? [" ", ".", ":", "!", "|", "/", "-", "=", "#"]
  : [" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", '█']

# NOTE: for a slider to be rendered correctly, ambiwidth must be set to 'single'.
def Slider(id: number, name: string, value: number, selected: bool, min = 0, max = 255): RichText
  const gutter    = Gutter(selected)
  const width     = PopupWidth() - strchars(gutter) - 6
  const range     = max + 1 - min
  const whole     = value * width / range
  const frac      = value * width / (1.0 * range) - whole
  const bar       = repeat(DEFAULT_SLIDER_SYMBOLS[8], whole)
  const part_char = DEFAULT_SLIDER_SYMBOLS[1 + float2nr(floor(frac * 8))]

  return Text(printf("%s%s %3d %s%s", gutter, name, value, bar, part_char))
    ->Styled('_leve', 1, 0)
    ->Label(len(gutter) + 1, 1)
    ->Selectable(id)
enddef
# }}}

# View and VStack {{{
type View = func(): list<RichText>

def VStack(...views: list<View>): View
  var stacked: list<func(): any>

  for V in views
    const VRead = react.CreateMemo(V)
    stacked->add(VRead)
  endfor

  return (): list<RichText> => {
    var text: list<RichText> = []

    for V in stacked
      text->extend(V())
    endfor

    return text
  }
enddef
# }}}
# BlankView {{{
def BlankView(n = 1): View
  return (): list<RichText> => repeat([Blank()], n)
enddef
# }}}
# TitleView {{{
def TitleView(): View
  return (): list<RichText> => {
      const attrs  = 'BIUVSK' # Bold, Italic, Underline, reVerse, Standout, striKethrough
      const width  = PopupWidth()
      const name   = HiGrp()
      const offset = width - len(attrs) + 1
      const spaces = repeat(' ', width - strchars(name) - strchars(FgBgS()) - strchars(attrs) - 3)
      const text   = $"{name} [{FgBgS()}]{spaces}{attrs}"
      const style  = Style()

      return [Text(text)
      ->Title(1, strchars(name) + strchars(FgBgS()) + 3)
      ->OnOff(style.bold,          offset,     1, )
      ->OnOff(style.italic,        offset + 1, 1, )
      ->OnOff(style.underline,     offset + 2, 1, )
      ->OnOff(style.reverse,       offset + 3, 1, )
      ->OnOff(style.standout,      offset + 4, 1, )
      ->OnOff(style.strikethrough, offset + 5, 1, )]
  }
enddef
# }}}
# StepView {{{
def StepView(): View
  return (): list<RichText> => {
    const text = printf('Step  %02d', Step())
    return [Text(text)->Label(1, 4)]
  }
enddef
# }}}
# ColorInfoView {{{
def ColorInfoView(): View
  return (): list<RichText> => {
    const curColor  = Color()
    const altColor  = AltColor()
    const approxCol = libcolor.Approximate(curColor)
    const approxAlt = libcolor.Approximate(altColor)
    const guiScore  = ComputeScore(curColor, altColor)
    const termScore = ComputeScore(approxCol.hex, approxAlt.hex)
    const deltaFmt  = approxCol.delta >= 10.0 ? '%.f' : '%.1f'
    const info      = $'      %s %-5S %3d/%s %-5S Δ{deltaFmt}'

    try # FIXME
      execute $'hi stylePickerGuiColor guibg={curColor}'
      execute $'hi stylePickerTermColor guibg={approxCol.hex}'
    catch
      echomsg $'ERR: col={curColor} altColor={approxCol.hex}'
    endtry

    return [
      Text(printf(info,
      curColor,
      repeat(Star(), guiScore),
      approxCol.xterm,
      approxCol.hex,
      repeat(Star(), termScore),
      approxCol.delta))->Styled('_gcol', 1, 2)->Styled('_tcol', 4, 2)]
  }
enddef
# }}}
# QuotationView {{{
def QuotationView(): View
  return (): list<RichText> => {
    return [Text(Center(Quote(), PopupWidth()))->Styled('_curr', 1)]
  }
enddef
# }}}
# PaletteView {{{
def PaletteView(
    bufnr:   number,
    name:    string, # 'mru' or 'fav' (must match text properties '_mru_' or '_fav_')
    Palette: func(): any,
    title:   string,
    baseID:  number, # First text property ID for the view (incremented by one for each additional line)
    alwaysVisible = false
    ): View
  const emptyPaletteText: list<RichText> = alwaysVisible ? [Label(Text(title)), Blank(), Blank()] : []

  return (): list<RichText> => {
    const palette: list<string> = Palette()

    if empty(palette)
      return emptyPaletteText
    endif

    var paletteText = [Label(Text(title))]
    var i = 0

    while i < len(palette)
      const lineColors  = palette[(i) : (i + NUM_COLORS_PER_LINE - 1)]
      const indexes     = range(len(lineColors))
      const j: number   = i / NUM_COLORS_PER_LINE
      const id          = baseID + j
      const gutter      = Gutter(SelectedID(bufnr) == id)
      var   colorStrip  = Text(gutter .. repeat(' ', PopupWidth() - strdisplaywidth(gutter)))

      if i == 0
        paletteText->add(
          Label(Text(repeat(' ', strdisplaywidth(gutter) + 1) .. join(indexes, '   ')))
        )
      else
        paletteText->add(Blank())
      endif

      for k in indexes
        const hexCol   = lineColors[k]
        const approx   = libcolor.Approximate(hexCol)
        const m        = i + k
        const hiGroup  = $'stylePicker{toupper(name)}{m}'
        const propName = $'_{name}{m}'

        execute $'hi {hiGroup} guibg={hexCol} ctermbg={approx.xterm}'
        prop_type_delete(propName, {bufnr: bufnr}) # TODO: use prop_type_change() instead?
        prop_type_add(propName, {bufnr: bufnr, highlight: hiGroup})
        colorStrip = colorStrip->Styled(propName, len(gutter) + 4 * k + 1, 3)
      endfor

      colorStrip = colorStrip->Styled($'_{name}_', 1, 0, j + 1)->Selectable(id)
      paletteText->add(colorStrip)
      i += NUM_COLORS_PER_LINE
    endwhile

    return paletteText
  }
enddef
# }}}

# RGB Pane {{{
def SliderView(bufnr: number): View
  return (): list<RichText> => {
    const [red, green, blue] = libcolor.Hex2Rgb(Color())
    const selectedID = SelectedID(bufnr)

    return [
      Slider(RGB_RED_SLIDER_ID,   'R', red, selectedID == RGB_RED_SLIDER_ID),
      Slider(RGB_GREEN_SLIDER_ID, 'G', green, selectedID == RGB_GREEN_SLIDER_ID),
      Slider(RGB_BLUE_SLIDER_ID,  'B', blue, selectedID == RGB_BLUE_SLIDER_ID),
    ]
  }
enddef

def RgbPane(winID: number, RecentView: View, FavoriteView: View)
  const bufnr = winbufnr(winID)

  const RgbView = VStack(
    TitleView(),
    BlankView(),
    SliderView(bufnr),
    StepView(),
    BlankView(),
    ColorInfoView(),
    BlankView(),
    QuotationView(),
    BlankView(),
    RecentView,
    BlankView(),
    FavoriteView,
  )

  react.CreateEffect(() => {
    if Pane() != RGB_PANE
      return
    endif

    popup_settext(winID, RgbView())
  })
enddef
# }}}

# Help Pane {{{
def HelpPane(winID: number)
  var s = [
    KeySymbol("up"),
    KeySymbol("down"),
    KeySymbol("top"),
    KeySymbol("fg>bg>sp"),
    KeySymbol("fg<bg<sp"),
    KeySymbol("help"),
    KeySymbol("rgb-pane"),
    KeySymbol("hsb-pane"),
    KeySymbol("gray-pane"),
    KeySymbol("close"),
    KeySymbol("cancel"),
    KeySymbol("toggle-bold"),
    KeySymbol("toggle-italic"),
    KeySymbol("toggle-underline"),
    KeySymbol("toggle-strike"),
    KeySymbol("toggle-reverse"),
    KeySymbol("toggle-standout"),
    KeySymbol("set-undercurl"),
    KeySymbol("increment"),
    KeySymbol("decrement"),
    KeySymbol("yank"),
    KeySymbol("paste"),
    KeySymbol("new-color"),
    KeySymbol("new-higroup"),
    KeySymbol("clear"),
    KeySymbol("add-to-favorite"),
    KeySymbol("yank"),
    KeySymbol("remove-color"),
    KeySymbol("pick-color"),
  ]
  const maxSymbolWidth = max(mapnew(s, (_, v) => strdisplaywidth(v)))

  # Pad with spaces, so all symbol strings have the same width
  map(s, (_, v) => v .. repeat(' ', maxSymbolWidth - strdisplaywidth(v)))

  react.CreateEffect(() => {
    if Pane() != HELP_PANE
      return
    endif

    popup_settext(winID, [
      Title(Text('Keyboard Controls')),
      Blank(),
      Label(Text('Popup')),
      Text($'{s[00]} Move up           {s[06]} RGB Pane'),
      Text($'{s[01]} Move down         {s[07]} HSB Pane'),
      Text($'{s[02]} Go to top         {s[08]} Grayscale'),
      Text($'{s[03]} fg->bg->sp        {s[09]} Hide'),
      Text($'{s[04]} sp->bg->fg        {s[10]} Hide and reset'),
      Text($'{s[05]} Help pane'),
      Blank(),
      Label(Text('Attributes')),
      Text($'{s[11]} Toggle boldface   {s[15]} Toggle reverse'),
      Text($'{s[12]} Toggle italics    {s[16]} Toggle standout'),
      Text($'{s[13]} Toggle underline  {s[17]} Toggle undercurl'),
      Text($'{s[14]} Toggle strikethrough'),
      Blank(),
      Label(Text('Color')),
      Text($'{s[18]} Increment value   {s[22]} New value'),
      Text($'{s[19]} Decrement value   {s[23]} New hi group'),
      Text($'{s[20]} Yank color        {s[24]} Clear color'),
      Text($'{s[21]} Paste color       {s[25]} Add to favorites'),
      Blank(),
      Label(Text('Recent & Favorites')),
      Text($'{s[20]} Yank color        {s[28]} Pick color'),
      Text($'{s[27]} Delete color'),
    ])
  })
enddef
# }}}

# Callbacks {{{
def ClosedCallback(winID: number, result: any = '')
  if exists('#stylepicker')
    autocmd! stylepicker
    augroup! stylepicker
  endif

  gX = popup_getoptions(winID).col
  gY = popup_getoptions(winID).line

  echomsg $'[Stylepicker] {gStylePickerID} closed'
enddef
# }}}

def SetHiGroupUnderCursor()
  const hiGroup = HiGroupUnderCursor()

  if empty(hiGroup)
    return
  endif

  # FIXME: double draw
  if gEdited[FgBgS()]
    SaveToRecent(Color())
  endif

  SetHiGrp(hiGroup)
enddef

def HandleDigit(digit: number): bool
  const bufnr = winbufnr(gStylePickerID)
  const isSlider = '_leve'->In(GetProperties(bufnr, Selected()))

  if isSlider
    var elapsed = gTimeLastDigitPressed->reltime()

    gTimeLastDigitPressed = reltime()

    if elapsed->reltimefloat() > 1.0 # TODO: user setting
      SetStep(digit)
      return true
    endif

    var newStep = 10 * Step() + digit

    if newStep > 99
      newStep = digit
    endif

    if newStep < 1
      newStep = 1
    endif

    SetStep(newStep)
  endif

  return isSlider
enddef

def ProcessKeyPress(key: string): bool
  if Pane() == HELP_PANE && key !~ '\m[RGB?xX]'
    return false
  endif

  if key =~ '\m\d'
    return HandleDigit(str2nr(key))
  endif

  if has_key(gActionMap, key)
    gActionMap[key]()
    return true
  endif

  return false
enddef

def StylePicker(hiGroup: string = '', x = gX, y = gY)
  var hiGroup_: string

  if empty(hiGroup)
    hiGroup_ = HiGroupUnderCursor()

    augroup stylepicker
      autocmd!
      autocmd CursorMoved * SetHiGroupUnderCursor()
    augroup END
  else
    hiGroup_ = hiGroup
  endif

  ResetHighlight()

  if gStylePickerID > 0 && !empty(popup_getpos(gStylePickerID)) # TODO: better way?
    SetHiGrp(hiGroup_)
    popup_show(gStylePickerID)
    echomsg $'DEBUG: Reopening {gStylePickerID}'
    return
  endif

  InitSignals(hiGroup_)

  const winID = popup_create('', {
    border:      [1, 1, 1, 1],
    borderchars: get(g:, 'stylepicker_borderchars', ['─', '│', '─', '│', '╭', '╮', '╯', '╰']),
    callback:    ClosedCallback,
    close:       'button',
    col:         x,
    cursorline:  0,
    drag:        1,
    filter:      (_, key) => ProcessKeyPress(key),
    filtermode:  'n',
    hidden:      true,
    highlight:   get(g:, 'stylepicker_bg', 'Normal'),
    line:        y,
    mapping:     get(g:, 'stylepicker_mapping', true),
    minwidth:    max([39 + strdisplaywidth(Marker()), 42]),
    padding:     [0, 1, 0, 1],
    pos:         'topleft',
    resize:      0,
    scrollbar:   0,
    tabpage:     0,
    title:       '',
    wrap:        0,
    zindex:      200,
  })

  const bufnr = winbufnr(winID)

  setbufvar(bufnr, '&tabstop', &tabstop)  # Inherit global tabstop value

  SetPropertyTypes(bufnr)

  gActionMap = ActionMap(winID)

  const RecentView   = PaletteView(bufnr, 'mru', Recent, 'Recent Colors', RECENT_COLORS_ID, true)
  const FavoriteView = PaletteView(bufnr, 'fav', Favorite, 'Favorite Colors', FAVORITE_COLORS_ID, false)

  RgbPane(winID, RecentView, FavoriteView)
  HelpPane(winID)

  SetPane(get(g:, 'stylepicker_default_pane', RGB_PANE))

  react.CreateEffect(() => {
    prop_type_change('_curr', {bufnr: bufnr, highlight: HiGrp()})
  })

  gStylePickerID = winID
  echomsg $'DEBUG: {winID}'

  popup_show(winID)
enddef

export def Open(hiGroup: string = '')
  StylePicker(hiGroup)
enddef
