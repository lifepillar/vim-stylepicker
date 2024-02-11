vim9script

# TODO:
#
# - Search for FIXME issues
# - Search for TODO issues
# - Other panes (HSV, Gray)
# - Mouse support

if !has('popupwin') || !has('textprop') || v:version < 901
  export def Open(hiGroup: string = null_string)
    echomsg 'Stylepicker requires Vim 9.1 compiled with popupwin and textprop.'
  enddef
  finish
endif

import 'libcolor.vim'        as libcolor
import 'libreactive.vim'     as react
import autoload './util.vim' as util

type Reader = func(): any
type Writer = func(any)

const ColorMode           = util.ColorMode
const StyleMode           = util.StyleMode
const Int                 = util.Int
const Msg                 = util.Msg
const Quote               = util.Quote

const NUM_COLORS_PER_LINE = 10
const RGB_PANE            = 0
const HSB_PANE            = 1
const GRAY_PANE           = 2
const HELP_PANE           = 99

# Internal state
var DEBUG                 = false
var gStylePickerID        = -1 # The style picker's window ID
var gX                    = 0
var gY                    = 0
var gEdited               = {fg: false, bg: false, sp: false} # Has the color been edited?
var gFavoritePath         = ''
var gTimeLastDigitPressed = reltime()
var gRecentCapacity       = get(g:, 'stylepicker_recent', 20)
var gNumRedraws           = 0 # For debugging
var gActionMap: dict<func(): bool>


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
      line:        get(popup_getoptions(winID), 'line', 1),
      col:         get(popup_getoptions(winID), 'col', 1),
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
  const cr = libcolor.ContrastRatio(hexCol1, hexCol2)
  const cd = libcolor.ColorDifference(hexCol1, hexCol2)
  const bd = libcolor.BrightnessDifference(hexCol1, hexCol2)

  return Int(cr >= 3.0) + Int(cr >= 4.5) + Int(cr >= 7.0) + Int(cd >= 500) + Int(bd >= 125)
enddef

def HiGroupUnderCursor(): string
  return synIDattr(synIDtrans(synID(line('.'), col('.'), true)), 'name')
enddef

# When mode is 'gui', return either a hex value or an empty string
# When mode is 'cterm', return either a numeric string or an empty string
def HiGroupColorAttr(hiGroup: string, fgBgS: string, mode: string): string
  var value = synIDattr(synIDtrans(hlID(hiGroup)), $'{fgBgS}#', mode)

  if mode == 'gui'
    if !empty(value) && value[0] != '#' # In terminals, HiGroupColorAttr() may return a GUI color name
      value = libcolor.RgbName2Hex(value, '')
    endif

    return value
  endif

  if value !~ '\m^\d\+'
    const num = libcolor.CtermColorNumber(value, 16)

    if num >= 0
      value = string(num)
    else
      value = ''
    endif
  endif

  return value
enddef

def UltimateFallbackColor(what: string): string
  if what == 'bg'
    return &bg == 'dark' ? '#000000' : '#ffffff'
  else
    return &bg == 'dark' ? '#ffffff' : '#000000'
  endif
enddef

# Try hard to determine a sensible hex value for the requested color attribute
def GetColor(hiGroup: string, what: string): string
  var value = HiGroupColorAttr(hiGroup, what, 'gui')

  if !empty(value) # Fast path
    return value
  endif

  if ColorMode() == 'cterm'
    const ctermValue = HiGroupColorAttr(hiGroup, what == 'sp' ? 'ul' : what, 'cterm')

    if !empty(ctermValue)
      const hex = libcolor.ColorNumber2Hex(str2nr(ctermValue))
      execute 'hi' hiGroup $'gui{what}={hex}'
      return hex
    endif
  endif

  if what == 'sp'
    return GetColor(hiGroup, 'fg')
  elseif hiGroup == 'Normal'
    return UltimateFallbackColor(what)
  endif

  return GetColor('Normal', what)
enddef

# Initialize the highlight groups used by the style picker
def ResetHighlight()
  const mode         = ColorMode()
  const warnColor    = HiGroupColorAttr('WarningMsg', 'fg', mode)
  const labelColor   = HiGroupColorAttr('Label',      'fg', mode)
  const commentColor = HiGroupColorAttr('Comment',    'fg', mode)

  execute $'hi stylePickerOn            {mode}fg={labelColor}   term=bold             {mode}=bold'
  execute $'hi stylePickerOff           {mode}fg={commentColor} term=NONE             {mode}=NONE'
  execute $'hi stylePickerWarning       {mode}fg={warnColor}                          {mode}=bold'
  execute $'hi stylePickerBold          {mode}fg={labelColor}   term=bold             {mode}=bold'
  execute $'hi stylePickerItalic        {mode}fg={labelColor}   term=bold,italic      {mode}=bold,italic'
  execute $'hi stylePickerUnderline     {mode}fg={labelColor}   term=bold,underline   {mode}=bold,underline'
  execute $'hi stylePickerUndercurl     {mode}fg={labelColor}   term=bold,undercurl   {mode}=bold,undercurl'
  execute $'hi stylePickerUnderdouble   {mode}fg={labelColor}   term=bold,underdouble {mode}=bold,underdouble'
  execute $'hi stylePickerUnderdotted   {mode}fg={labelColor}   term=bold,underdotted {mode}=bold,underdotted'
  execute $'hi stylePickerUnderdashed   {mode}fg={labelColor}   term=bold,underdashed {mode}=bold,underdashed'
  execute $'hi stylePickerStandout      {mode}fg={labelColor}   term=bold,standout    {mode}=bold,standout'
  execute $'hi stylePickerInverse       {mode}fg={labelColor}   term=bold,inverse     {mode}=bold,inverse'
  execute $'hi stylePickerStrikethrough {mode}fg={labelColor}   term=bold,inverse     {mode}=bold,inverse'
  hi! stylePickerGray000 guibg=#000000 ctermbg=16
  hi! stylePickerGray025 guibg=#404040 ctermbg=238
  hi! stylePickerGray050 guibg=#7f7f7f ctermbg=244
  hi! stylePickerGray075 guibg=#bfbfbf ctermbg=250
  hi! stylePickerGray100 guibg=#ffffff ctermbg=231
  hi clear stylePickerGuiColor
  hi clear stylePickerTermColor
enddef

def LoadPalette(loadPath: string): list<string>
  if empty(loadPath)
    return []
  endif

  var palette: list<string>

  try
    palette = readfile(loadPath)
  catch /.*/
    Msg($'Could not load favorite colors: {v:exception}', true)
    palette = []
  endtry

  filter(palette, (_, v) => v =~ '\m^#[A-Fa-f0-9]\{6}$')

  return palette
enddef

def SavePalette(palette: list<string>, savePath: string)
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
# }}}

# Text with Properties {{{
class Prop
  static const NORMAL            = '_norm' # Normal text
  static const ON                = '_on__' # Property for 'enabled' stuff
  static const OFF               = '_off_' # Property for 'disabled' stuff
  static const SELECTABLE        = '_sel_' # Mark line as an item that can be selected
  static const LABEL             = '_labe' # Mark line as a label
  static const SLIDER            = '_leve' # Mark line as a level bar (slider)
  static const RECENT            = '_mru_' # Mark line as a 'recent colors' line
  static const FAVORITE          = '_fav_' # Mark line as a 'favorite colors' line
  static const CURRENT_HIGHLIGHT = '_curr' # To highlight text with the currently selected highglight group
  static const WARNING           = '_warn' # Highlight for warning symbols
  static const TITLE             = '_titl' # Highlight for title section
  static const GUI_HIGHLIGHT     = '_gcol' # Highlight for the current GUI color
  static const CTERM_HIGHLIGHT   = '_tcol' # Highlight for the current cterm color
  static const BOLD              = '_bold' # Highlight for bold attribute
  static const ITALIC            = '_ital' # Highlight for italic attribute
  static const UNDERLINE         = '_ulin' # Highlight for underline attribute
  static const UNDERCURL         = '_curl' # Highlight for undercurl attribute
  static const STANDOUT          = '_sout' # Highlight for standout attribute
  static const INVERSE           = '_invr' # Highlight for inverse attribute
  static const STRIKETHROUGH     = '_strk' # Highlight for strikethrough attribute
  static const GRAY              = '_gray' # Grayscale blocks
  static const GRAY000           = '_g000' # Grayscale blocks
  static const GRAY025           = '_g025' # Grayscale blocks
  static const GRAY050           = '_g050' # Grayscale blocks
  static const GRAY075           = '_g075' # Grayscale blocks
  static const GRAY100           = '_g100' # Grayscale blocks
endclass

# IDs for selectable items
class ID
  static const RED_SLIDER      = 128
  static const GREEN_SLIDER    = 129
  static const BLUE_SLIDER     = 130
  static const GRAY_SLIDER     = 132
  static const RECENT_COLORS   = 1024 # Each recent color line gets a +1 id
  static const FAVORITE_COLORS = 8192 # Each favorite color line gets a +1 id
endclass

type TextProperty = dict<any> # See :help text-properties
type RichText     = dict<any> # {text: '...', props: [textProp1, ..., textPropN]}

def PropertyTypes(bufnr: number): dict<dict<any>>
  return {
    [Prop.NORMAL]:            {bufnr: bufnr, highlight: 'Normal'                   },
    [Prop.ON]:                {bufnr: bufnr, highlight: 'stylePickerOn'            },
    [Prop.OFF]:               {bufnr: bufnr, highlight: 'stylePickerOff'           },
    [Prop.SELECTABLE]:        {bufnr: bufnr                                        },
    [Prop.LABEL]:             {bufnr: bufnr, highlight: 'Label'                    },
    [Prop.SLIDER]:            {bufnr: bufnr                                        },
    [Prop.RECENT]:            {bufnr: bufnr                                        },
    [Prop.FAVORITE]:          {bufnr: bufnr                                        },
    [Prop.CURRENT_HIGHLIGHT]: {bufnr: bufnr                                        },
    [Prop.WARNING]:           {bufnr: bufnr, highlight: 'stylePickerWarning'       },
    [Prop.TITLE]:             {bufnr: bufnr, highlight: 'Title'                    },
    [Prop.GUI_HIGHLIGHT]:     {bufnr: bufnr, highlight: 'stylePickerGuiColor'      },
    [Prop.CTERM_HIGHLIGHT]:   {bufnr: bufnr, highlight: 'stylePickerTermColor'     },
    [Prop.BOLD]:              {bufnr: bufnr, highlight: 'stylePickerBold'          },
    [Prop.ITALIC]:            {bufnr: bufnr, highlight: 'stylePickerItalic'        },
    [Prop.UNDERLINE]:         {bufnr: bufnr, highlight: 'stylePickerUnderline'     },
    [Prop.UNDERCURL]:         {bufnr: bufnr, highlight: 'stylePickerUndercurl'     },
    [Prop.STANDOUT]:          {bufnr: bufnr, highlight: 'stylePickerStandout'      },
    [Prop.INVERSE]:           {bufnr: bufnr, highlight: 'stylePickerInverse'       },
    [Prop.STRIKETHROUGH]:     {bufnr: bufnr, highlight: 'stylePickerStrikethrough' },
    [Prop.GRAY]:              {bufnr: bufnr                                        },
    [Prop.GRAY000]:           {bufnr: bufnr, highlight: 'stylePickerGray000'       },
    [Prop.GRAY025]:           {bufnr: bufnr, highlight: 'stylePickerGray025'       },
    [Prop.GRAY050]:           {bufnr: bufnr, highlight: 'stylePickerGray050'       },
    [Prop.GRAY075]:           {bufnr: bufnr, highlight: 'stylePickerGray075'       },
    [Prop.GRAY100]:           {bufnr: bufnr, highlight: 'stylePickerGray100'       },
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

def Blank(width = 0): RichText
  return Text(repeat(' ', width))
enddef

def Styled(
    t: RichText, propType: string, from = 1, length = strchars(t.text), id = 0
    ): RichText
  var newProp = {col: from, length: length, type: propType }

  if id > 0
    newProp.id = id
  endif

  return { text: t.text, props: t.props->add(newProp) }
enddef

def Tag(t: RichText, propName: string, id = 0): RichText
  return Styled(t, propName, 1, 0, id)
enddef

def Title(t: RichText, from = 1, length = strchars(t.text)): RichText
  return Styled(t, Prop.TITLE, from, length)
enddef

def Label(t: RichText, from = 1, length = strchars(t.text)): RichText
  return Styled(t, Prop.LABEL, from, length)
enddef

def OnOff(t: RichText, enabled: bool, from = 1, length = strchars(t.text)): RichText
  return Styled(t, enabled ? Prop.ON : Prop.OFF, from, length)
enddef

def GuiHighlight(t: RichText, from = 1, length = strchars(t.text)): RichText
  return Styled(t, Prop.GUI_HIGHLIGHT, from, length)
enddef

def CtermHighlight(t: RichText, from = 1, length = strchars(t.text)): RichText
  return Styled(t, Prop.CTERM_HIGHLIGHT, from, length)
enddef

def CurrentHighlight(t: RichText, from = 1, length = strchars(t.text)): RichText
  return Styled(t, Prop.CURRENT_HIGHLIGHT, from, length)
enddef

def GetPropertyByType(bufnr: number, propType: string): dict<any>
  return prop_find({bufnr: bufnr, type: proptType, lnum: 1, col: 1, skipstart: false}, 'f')
enddef

def GetLineNumberForID(bufnr: number, propertyID: number): number
  return prop_find({bufnr: bufnr, id: propertyID, lnum: 1, col: 1, skipstart: false}, 'f').lnum
enddef

# Return the list of the names of the text properties for the given line in the given buffer.
def GetProperties(bufnr: number, lnum: number): list<string>
  return map(prop_list(lnum, {bufnr: bufnr}), (i, v) => v.type)
enddef

def FirstSelectable(winID: number): number
  return prop_find({bufnr: winbufnr(winID), type: Prop.SELECTABLE, lnum: 1, col: 1}, 'f').id
enddef

def LastSelectable(winID: number): number
  return prop_find({bufnr: winbufnr(winID), type: Prop.SELECTABLE, lnum: line('$', winID), col: 1}, 'b').id
enddef

def NextSelectable(winID: number, propertyID: number): number
  const bufnr = winbufnr(winID)
  const lnum = GetLineNumberForID(bufnr, propertyID)
  const nextItem = prop_find({bufnr: bufnr, type: Prop.SELECTABLE, lnum: lnum, col: 1, skipstart: true}, 'f')

  if empty(nextItem)
    return FirstSelectable(winID)
  else
    return nextItem.id
  endif
enddef

def PrevSelectable(winID: number, propertyID: number): number
  const bufnr = winbufnr(winID)
  const lnum = GetLineNumberForID(bufnr, propertyID)
  const prevItem = prop_find({bufnr: bufnr, type: Prop.SELECTABLE, lnum: lnum, col: 1, skipstart: true}, 'b')

  if empty(prevItem)
    return LastSelectable(winID)
  else
    return prevItem.id
  endif
enddef

def HasProperty(winID: number, propertyID: number, propName: string): bool
  const bufnr = winbufnr(winID)
  return propName->In(GetProperties(bufnr, GetLineNumberForID(bufnr, propertyID)))
enddef

def IsSlider(winID: number, propertyID: number): bool
  return HasProperty(winID, propertyID, Prop.SLIDER)
enddef

def IsRecentPalette(winID: number, propertyID: number): bool
  return HasProperty(winID, propertyID, Prop.RECENT)
enddef

def RecentRow(bufnr: number, propertyID: number): bool
  const lnum = GetLineNumberForID(bufnr, propertyID)
  return prop_find({bufnr: bufnr, id: propertyID, lnum: 1, col: 1, skipstart: false}, 'f').lnum
enddef


def IsFavoritePalette(winID: number, propertyID: number): bool
  return HasProperty(winID, propertyID, Prop.FAVORITE)
enddef
# }}}

# Reactive properties {{{
const POOL       = 'stylepicker_pool'
var   Pane       = react.Property.new(RGB_PANE,      POOL) # Current pane
var   HiGrp      = react.Property.new('Normal',      POOL) # Current highlight group
var   FgBgS      = react.Property.new('fg',          POOL) # Current attribute ('fg', 'bg', or 'sp')
var   SelectedID = react.Property.new(ID.RED_SLIDER, POOL) # Text property ID of the currently selected line
var   Step       = react.Property.new(1,             POOL) # Current increment/decrement step
var   Recent     = react.Property.new([],            POOL) # List of recent colors
var   Favorite   = react.Property.new([],            POOL) # List of favorite colors

def Edited(): bool
  return gEdited[FgBgS.Get()]
enddef

def SetEdited()
  gEdited = {fg: false, bg: false, sp: false}
  gEdited[FgBgS.Get()] = true
enddef

def SetNotEdited()
  gEdited = {fg: false, bg: false, sp: false}
enddef

def SaveToRecent(color: string)
  var recent: list<string> = Recent.Get()

  if color->NotIn(recent)
    recent->add(color)

    if len(recent) > gRecentCapacity
      remove(recent, 0)
    endif

    Recent.Set(recent)
  endif
enddef

class ColorProperty extends react.Property
  def Get(): string
    this._value = GetColor(HiGrp.Get(), FgBgS.Get())
    return super.Get()
  enddef

  def Set(newValue: string)
    var fgBgS = FgBgS.Get()
    var attrs: dict<any> = {name: HiGrp.Get(), [$'gui{fgBgS}']: newValue}

    if newValue == 'NONE'
      attrs[$'cterm{fgBgS == "sp" ? "ul" : fgBgS}'] = newValue
    else
      attrs[$'cterm{fgBgS == "sp" ? "ul" : fgBgS}'] = string(libcolor.Approximate(newValue).xterm)
    endif

    react.Begin()

    if !Edited()
      SaveToRecent(Color.Get())
      SetEdited()
    endif

    hlset([attrs])
    super.Set(newValue)

    react.Commit()
  enddef
endclass

class StyleProperty extends react.Property
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

  def Get(): dict<bool>
    const hl = hlget(HiGrp.Get(), true)[0]
    var style: dict<bool> = get(hl, 'gui', get(hl, 'cterm', {}))

    this._value = StyleProperty.styles->extendnew(style, 'force')

    if this._value.undercurl || this._value.underdashed || this._value.underdotted || this._value.underdouble
      this._value.underline = true
    endif

    return super.Get()
  enddef

  def Set(newValue: dict<bool>)
    const style = filter(newValue, (_, v) => v)

    hlset([{name: HiGrp.Get(), 'gui': style, 'cterm': style}])
    super.Set(newValue)
  enddef
endclass

var Color = ColorProperty.new(v:none, POOL) # Value of the current color (e.g., '#fdfdfd')
var Style = StyleProperty.new(v:none, POOL) # Dictionary of style attributes (e.g., {bold, true, italic: false, etc...})

def AltColor(): string
  if FgBgS.Get() == 'bg'
    return GetColor(HiGrp.Get(), 'fg')
  else
    return GetColor(HiGrp.Get(), 'bg')
  endif
enddef
# }}}

# Key map {{{
const KEYMAP = extend({
  'add-to-favorite':      "A",
  'bot':                  ">",
  'cancel':               "X",
  'clear-color':          "Z",
  'close':                "x",
  'decrement':            "\<left>",
  'down':                 "\<down>",
  'fg<bg<sp':             "\<s-tab>",
  'fg>bg>sp':             "\<tab>",
  'gray-pane':            "G",
  'help':                 "?",
  'hsb-pane':             "H",
  'increment':            "\<right>",
  'paste':                "P",
  'pick-from-palette':    "\<enter>",
  'remove-from-palette':  "D",
  'rgb-pane':             "R",
  'set-color':            "E",
  'set-higroup':          "N",
  'toggle-bold':          "B",
  'toggle-italic':        "I",
  'toggle-reverse':       "V",
  'toggle-standout':      "S",
  'toggle-strikethrough': "K",
  'toggle-undercurl':     "~",
  'toggle-underdashed':   "-",
  'toggle-underdotted':   ".",
  'toggle-underdouble':   "=",
  'toggle-underline':     "U",
  'top':                  "<",
  'up':                   "\<up>",
  'yank':                 "Y",
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
# Action Helpers {{{
def SaveToFavorite(color: string, savePath: string)
  var favorite: list<string> = Favorite.Get()

  if color->NotIn(favorite)
    favorite->add(color)
    Favorite.Set(favorite)
    SavePalette(favorite, savePath)
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
    Palette:    react.Property,
    rowNum:     number,
    Action:     func(list<string>, number, react.Property)
    ): bool
  var palette: list<string> = Palette.Get()
  var from = rowNum * NUM_COLORS_PER_LINE
  var to = from + NUM_COLORS_PER_LINE - 1

  if to >= len(palette)
    to = len(palette) - 1
  endif

  const n = AskIndex(to - from)

  if n >= 0
    Action(palette, from + n, Palette)
    return true
  endif

  return false
enddef

def GetPaletteInfo(winID: number): dict<any>
  const id = SelectedID.Get()

  if IsRecentPalette(winID, id)
    return {rowNum: id - ID.RECENT_COLORS, palette: Recent}
  endif

  if IsFavoritePalette(winID, id)
    return {rowNum: id - ID.FAVORITE_COLORS, palette: Favorite}
  endif

  return {}
enddef
# }}}

def PickColor(winID: number): func(): bool
  const bufnr = winbufnr(winID)
  const Pick = (colors: list<string>, n: number, palette: react.Property) => {
    Color.Set(colors[n])
  }

  return (): bool => {
    const info = GetPaletteInfo(winID)

    if !empty(info)
      ActOnPalette(winID, info.palette, info.rowNum, Pick)
    endif

    return !empty(info)
  }
enddef

def RemoveColor(winID: number): func(): bool
  const bufnr = winbufnr(winID)
  const Remove = (colors: list<string>, n: number, palette: react.Property) => {
    remove(colors, n)
    palette.Set(colors)
  }

  return (): bool => {
    const info = GetPaletteInfo(winID)
    const palette: react.Property = info.palette

    if !empty(info)
      react.Transaction(() => {

        ActOnPalette(winID, palette, info.rowNum, Remove)

        if empty(palette.Get())
          SelectPrev(winID)()
        endif
      })

      if palette is Favorite
        SavePalette(palette.Get(), gFavoritePath)
      endif
    endif

    return !empty(info)
  }
enddef

def YankColor(winID: number): func(): bool
  const bufnr = winbufnr(winID)
  const Yank = (colors: list<string>, n: number, palette: react.Property) => {
    @" = colors[n] # TODO: allow setting register via user option
  }

  return (): bool => {
    const info = GetPaletteInfo(winID)

    if empty(info)
      @" = Color.Get()
      Notification(winID, 'Color yanked: ' .. @")
    else
      if ActOnPalette(winID, info.palette, info.rowNum, Yank)
        Notification(winID, 'Color yanked: ' .. @")
      endif
    endif

    return true
  }
enddef

def PasteColor(windID: number): func(): bool
  return (): bool => {
    if @" =~ '\m^#\=[A-Fa-f0-9]\{6}$'
      SetNotEdited() # Force saving the current color to recent palette
      Color.Set(@"[0] == '#' ? @" : '#' .. @")
    endif
    return true
  }
enddef

def AddToFavorite(winID: number): func(): bool
  return (): bool => {
    SaveToFavorite(Color.Get(), gFavoritePath)
    return true
  }
enddef

def IncrementValue(value: number, max: number): number
  const newValue = value + Step.Get()

  if newValue > max
    return max
  else
    return newValue
  endif
enddef

def DecrementValue(value: number, min: number): number
  const newValue = value - Step.Get()

  if newValue < min
    return min
  else
    return newValue
  endif
enddef

def Increment(winID: number): func(): bool
  return (): bool => {
    const pane = Pane.Get()
    const selectedID = SelectedID.Get()

    if pane == RGB_PANE
      var [red, green, blue] = libcolor.Hex2Rgb(Color.Get())

      if selectedID == ID.RED_SLIDER
        red = IncrementValue(red, 255)
      elseif selectedID == ID.GREEN_SLIDER
        green = IncrementValue(green, 255)
      elseif selectedID == ID.BLUE_SLIDER
        blue = IncrementValue(blue, 255)
      else
        return false
      endif

      Color.Set(libcolor.Rgb2Hex(red, green, blue))
      return true
    endif

    if pane == GRAY_PANE && selectedID == ID.GRAY_SLIDER
      var gray = libcolor.Hex2Gray(Color.Get())
      gray = IncrementValue(gray, 255)
      Color.Set(libcolor.Gray2Hex(gray))
      return true
    endif

    return false
  }
enddef

def Decrement(winID: number): func(): bool
  return (): bool => {
    const pane = Pane.Get()
    const selectedID = SelectedID.Get()

    if pane == RGB_PANE
      var [red, green, blue] = libcolor.Hex2Rgb(Color.Get())

      if selectedID == ID.RED_SLIDER
        red = DecrementValue(red, 0)
      elseif selectedID == ID.GREEN_SLIDER
        green = DecrementValue(green, 0)
      elseif selectedID == ID.BLUE_SLIDER
        blue = DecrementValue(blue, 0)
      else
        return false
      endif

      Color.Set(libcolor.Rgb2Hex(red, green, blue))
      return true
    endif

    if pane == GRAY_PANE && selectedID == ID.GRAY_SLIDER
      var gray = libcolor.Hex2Gray(Color.Get())
      gray = DecrementValue(gray, 0)
      Color.Set(libcolor.Gray2Hex(gray))
      return true
    endif

    return false
  }
enddef

def FgBgSNext(): func(): bool
  return (): bool => {
    const old = FgBgS.Get()
    const new = (old == 'fg' ? 'bg' : old == 'bg' ? 'sp' : 'fg')
    FgBgS.Set(new)
    return true
  }
enddef

def FgBgSPrev(): func(): bool
  return (): bool => {
    const old = FgBgS.Get()
    const new = (old == 'fg' ? 'sp' : old == 'sp' ? 'bg' : 'fg')
    FgBgS.Set(new)
    return true
  }
enddef

def GoToTop(winID: number): func(): bool
  return (): bool => {
    SelectedID.Set(FirstSelectable(winID))
    return true
  }
enddef

def GoToBottom(winID: number): func(): bool
  return (): bool => {
    SelectedID.Set(LastSelectable(winID))
    return true
  }
enddef

def SelectNext(winID: number): func(): bool
  return (): bool => {
    SelectedID.Set(NextSelectable(winID, SelectedID.Get()))
    return true
  }
enddef

def SelectPrev(winID: number): func(): bool
  return (): bool => {
    SelectedID.Set(PrevSelectable(winID, SelectedID.Get()))
    return true
  }
enddef

def Close(winID: number): func(): bool
  return (): bool => {
    popup_close(winID)
    return true
  }
enddef

def Cancel(winID: number): func(): bool
  return (): bool => {
    popup_close(winID)

    # TODO: revert only the changes of the stylepicker
    if exists('g:colors_name') && !empty('g:colors_name')
      execute 'colorscheme' g:colors_name
    endif
    return true
  }
enddef

def ChooseColor(): func(): bool
  return (): bool => {
    var newCol: string

    if ColorMode() == 'gui'
      newCol = ChooseGuiColor()
    else
      newCol = ChooseTermColor()
    endif

    if !empty(newCol)
      Color.Set(newCol)
    endif

    return true
  }
enddef

def ChooseHiGrp(): func(): bool
  return (): bool => {
    const hiGroup = input('Highlight group: ', '', 'highlight')
    echo "\r"

    if hlexists(hiGroup)
      HiGrp.Set(hiGroup)
    endif

    return true
  }
enddef

def ToggleStyleAttribute(attr: string): func(): bool
  return (): bool => {
    var currentStyle: dict<bool> = Style.Get()

    if attr[0 : 4] == 'under'
      const wasOn = currentStyle[attr]

      currentStyle.underline   = false
      currentStyle.undercurl   = false
      currentStyle.underdashed = false
      currentStyle.underdotted = false
      currentStyle.underdouble = false

      if !wasOn
        currentStyle[attr]     = true
        currentStyle.underline = true
      endif
    else
      currentStyle[attr] = !currentStyle[attr]
    endif

    Style.Set(currentStyle)
    return true
    }
enddef

def ClearColor(winID: number): func(): bool
  return (): bool => {
    Color.Set('NONE')
    Notification(winID, $'[{FgBgS.Get()}] Color cleared')
    return true
  }
enddef

def SwitchPane(winID: number, pane: number): func(): bool
  return () => {
    Pane.Set(pane)

    if pane != HELP_PANE
      SelectedID.Set(FirstSelectable(winID))
    endif

    return true
  }
enddef

def ActionMap(winID: number): dict<func(): bool>
  return {
      [KEYMAP['add-to-favorite'     ]]: AddToFavorite(winID),
      [KEYMAP['bot'                 ]]: GoToBottom(winID),
      [KEYMAP['cancel'              ]]: Cancel(winID),
      [KEYMAP['clear-color'         ]]: ClearColor(winID),
      [KEYMAP['close'               ]]: Close(winID),
      [KEYMAP['decrement'           ]]: Decrement(winID),
      [KEYMAP['down'                ]]: SelectNext(winID),
      [KEYMAP['fg<bg<sp'            ]]: FgBgSPrev(),
      [KEYMAP['fg>bg>sp'            ]]: FgBgSNext(),
      [KEYMAP['gray-pane'           ]]: SwitchPane(winID, GRAY_PANE),
      [KEYMAP['help'                ]]: SwitchPane(winID, HELP_PANE),
      [KEYMAP['hsb-pane'            ]]: SwitchPane(winID, HSB_PANE),
      [KEYMAP['increment'           ]]: Increment(winID),
      [KEYMAP['paste'               ]]: PasteColor(winID),
      [KEYMAP['pick-from-palette'   ]]: PickColor(winID),
      [KEYMAP['remove-from-palette' ]]: RemoveColor(winID),
      [KEYMAP['rgb-pane'            ]]: SwitchPane(winID, RGB_PANE),
      [KEYMAP['set-color'           ]]: ChooseColor(),
      [KEYMAP['set-higroup'         ]]: ChooseHiGrp(),
      [KEYMAP['toggle-bold'         ]]: ToggleStyleAttribute('bold'),
      [KEYMAP['toggle-italic'       ]]: ToggleStyleAttribute('italic'),
      [KEYMAP['toggle-reverse'      ]]: ToggleStyleAttribute('reverse'),
      [KEYMAP['toggle-standout'     ]]: ToggleStyleAttribute('standout'),
      [KEYMAP['toggle-strikethrough']]: ToggleStyleAttribute('strikethrough'),
      [KEYMAP['toggle-undercurl'    ]]: ToggleStyleAttribute('undercurl'),
      [KEYMAP['toggle-underdashed'  ]]: ToggleStyleAttribute('underdashed'),
      [KEYMAP['toggle-underdotted'  ]]: ToggleStyleAttribute('underdotted'),
      [KEYMAP['toggle-underdouble'  ]]: ToggleStyleAttribute('underdouble'),
      [KEYMAP['toggle-underline'    ]]: ToggleStyleAttribute('underline'),
      [KEYMAP['top'                 ]]: GoToTop(winID),
      [KEYMAP['up'                  ]]: SelectPrev(winID),
      [KEYMAP['yank'                ]]: YankColor(winID),
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
    ->Label(len(gutter) + 1, 1)
    ->Tag(Prop.SLIDER)
    ->Tag(Prop.SELECTABLE, id)
enddef
# }}}

# View and VStack {{{
type View = func(): list<RichText>

def VStack(...views: list<View>): View
  var stacked: list<func(): any>

  for V in views
    const VRead = react.CreateMemo(V, POOL)
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
def BlankView(): list<RichText>
  return [Blank()]
enddef
# }}}
# TitleView {{{
def TitleView(): list<RichText>
  const attrs  = 'BIUVSK' # Bold, Italic, Underline, reVerse, Standout, striKethrough
  const width  = PopupWidth()
  const name   = HiGrp.Get()
  const offset = width - len(attrs) + 1
  const spaces = repeat(' ', width - strchars(name) - strchars(FgBgS.Get()) - strchars(attrs) - 3)
  const text   = $"{name} [{FgBgS.Get()}]{spaces}{attrs}"
  const style  = Style.Get()

  return [Text(text)
    ->Title(1, strchars(name) + strchars(FgBgS.Get()) + 3)
    ->OnOff(style.bold,          offset,     1)
    ->OnOff(style.italic,        offset + 1, 1)
    ->OnOff(style.underline,     offset + 2, 1)
    ->OnOff(style.reverse,       offset + 3, 1)
    ->OnOff(style.standout,      offset + 4, 1)
    ->OnOff(style.strikethrough, offset + 5, 1)
  ]
enddef
# }}}
# StepView {{{
def StepView(): list<RichText>
  const text = printf('Step  %02d', Step.Get())
  return [Text(text)->Label(1, 4)]
enddef
# }}}
# ColorInfoView {{{
def ColorInfoView(): list<RichText>
  const curColor    = Color.Get()
  const altColor    = AltColor()
  const approxCol   = libcolor.Approximate(curColor)
  const approxAlt   = libcolor.Approximate(altColor)
  const contrast    = libcolor.ContrastColor(curColor)
  const contrastAlt = libcolor.Approximate(contrast)
  const guiScore    = ComputeScore(curColor, altColor)
  const termScore   = ComputeScore(approxCol.hex, approxAlt.hex)
  const delta       = printf("%.1f", approxCol.delta)[ : 2]
  const guiGuess    = (curColor != HiGroupColorAttr(HiGrp.Get(), FgBgS.Get(), 'gui') ? '!' : ' ')
  const ctermGuess  = (string(approxCol.xterm) != HiGroupColorAttr(HiGrp.Get(), FgBgS.Get(), 'cterm') ? '!' : ' ')

  execute $'hi stylePickerGuiColor guifg={contrast} guibg={curColor} ctermfg={contrastAlt.xterm} ctermbg={approxCol.xterm}'
  execute $'hi stylePickerTermColor guifg={contrast} guibg={approxCol.hex} ctermfg={contrastAlt.xterm} ctermbg={approxCol.xterm}'

  const info = $' {guiGuess}   {ctermGuess}   %s %-5S %3d/%s %-5S Δ{delta}'
  return [
    Text(printf(info,
      curColor[1 : ],
      repeat(Star(), guiScore),
      approxCol.xterm,
      approxCol.hex[1 : ],
      repeat(Star(), termScore)))->GuiHighlight(1, 3)->CtermHighlight(5, 3)
  ]
enddef
# }}}
# QuotationView {{{
def QuotationView(): list<RichText>
  return [Text(Center(Quote(), PopupWidth()))->CurrentHighlight()]
enddef
# }}}
# BuildPaletteView {{{
def SyncPaletteHighlightEffect(bufnr: number, prop: string, Palette: react.Property)
  const prefix = $'stylePicker{prop}'

  react.CreateEffect(() => {
    const palette: list<string> = Palette.Get()
    var i = 0

    while i < len(palette)
      const hiGroup  = $'{prefix}{i}'
      const propName = $'{prop}{i}'
      const hexCol   = palette[i]
      const approx   = libcolor.Approximate(hexCol)

      execute $'hi {hiGroup} guibg={hexCol} ctermbg={approx.xterm}'
      prop_type_delete(propName, {bufnr: bufnr})
      prop_type_add(propName, {bufnr: bufnr, highlight: hiGroup})
      ++i
    endwhile
  })
enddef

def BuildPaletteView(
    bufnr:       number,
    Palette:     react.Property,
    title:       string,
    prop:        string, # Prop.RECENT, Prop.FAVORITE
    baseID:      number, # First text property ID for the view (incremented by one for each additional line)
    alwaysVisible = false
    ): View
  const emptyPaletteText: list<RichText> = alwaysVisible ? [Label(Text(title)), Blank(), Blank()] : []

  SyncPaletteHighlightEffect(bufnr, prop, Palette)

  return (): list<RichText> => {
    const palette: list<string> = Palette.Get()

    if empty(palette)
      return emptyPaletteText
    endif

    var paletteText = [Label(Text(title))]
    var i = 0

    while i < len(palette)
      const lineColors  = palette[(i) : (i + NUM_COLORS_PER_LINE - 1)]
      const indexes     = range(len(lineColors))
      const rowNum      = i / NUM_COLORS_PER_LINE
      const id          = baseID + rowNum
      const selectedID  = SelectedID.Get()
      const gutter      = Gutter(selectedID == id)
      var   colorStrip  = Text(gutter .. repeat(' ', PopupWidth() - strdisplaywidth(gutter)))

      if i == 0
        paletteText->add(
          Label(Text(repeat(' ', strdisplaywidth(gutter) + 1) .. join(indexes, '   ')))
        )
      else
        paletteText->add(Blank())
      endif

      for k in indexes
        const m = i + k
        const propName = $'{prop}{m}'
        colorStrip = colorStrip->Styled(propName, len(gutter) + 4 * k + 1, 3)
      endfor

      colorStrip = colorStrip->Tag(prop, rowNum)->Tag(Prop.SELECTABLE, id)
      paletteText->add(colorStrip)
      i += NUM_COLORS_PER_LINE
    endwhile

    return paletteText
  }
enddef
# }}}

# RGB Pane {{{
def RGBSliderView(): list<RichText>
  const [red, green, blue] = libcolor.Hex2Rgb(Color.Get())
  const selectedID         = SelectedID.Get()

  return [
    Slider(ID.RED_SLIDER,   'R', red,   selectedID == ID.RED_SLIDER),
    Slider(ID.GREEN_SLIDER, 'G', green, selectedID == ID.GREEN_SLIDER),
    Slider(ID.BLUE_SLIDER,  'B', blue,  selectedID == ID.BLUE_SLIDER),
  ]
enddef

def RgbPane(winID: number, RecentView: View, FavoriteView: View)
  const RgbView = VStack(
    TitleView,
    BlankView,
    RGBSliderView,
    StepView,
    BlankView,
    ColorInfoView,
    BlankView,
    QuotationView,
    BlankView,
    RecentView,
    BlankView,
    FavoriteView,
  )

  react.CreateEffect(() => {
    if Pane.Get() != RGB_PANE
      return
    endif

    popup_settext(winID, RgbView())
    ++gNumRedraws

    if DEBUG && gNumRedraws > 1
      Notification(winID, $'Multiple ({gNumRedraws}) redraws!')
    endif
  })
enddef
# }}}
# Grayscale Pane {{{
def GraySliderView(): list<RichText>
  const gray       = libcolor.Hex2Gray(Color.Get())
  const isSelected = SelectedID.Get() == ID.GRAY_SLIDER
  const gutterWidth = strdisplaywidth(Gutter(isSelected), 0)

  return [
    Label(Text('Grayscale')),
    Blank(PopupWidth())
    ->Styled(Prop.GRAY000, gutterWidth + 6, 2)
    ->Styled(Prop.GRAY025, gutterWidth + 14, 2)
    ->Styled(Prop.GRAY050, gutterWidth + 22, 2)
    ->Styled(Prop.GRAY075, gutterWidth + 30, 2)
    ->Styled(Prop.GRAY100, gutterWidth + 38, 2),
    Slider(ID.GRAY_SLIDER, 'G', gray, isSelected),
  ]
enddef

def GrayscalePane(winID: number, RecentView: View, FavoriteView: View)
  const GrayscaleView = VStack(
   TitleView,
    BlankView,
    GraySliderView,
    StepView,
    BlankView,
    ColorInfoView,
    BlankView,
    QuotationView,
    BlankView,
    RecentView,
    BlankView,
    FavoriteView,
  )

  react.CreateEffect(() => {
    if Pane.Get() != GRAY_PANE
      return
    endif

    popup_settext(winID, GrayscaleView())
    ++gNumRedraws

    if DEBUG && gNumRedraws > 1
      Notification(winID, $'Multiple ({gNumRedraws}) redraws!')
    endif
  })
enddef
# }}}

# Help Pane {{{
def HelpPane(winID: number)
  var s = [
    KeySymbol('up'),                   # 00
    KeySymbol('down'),                 # 01
    KeySymbol('top'),                  # 02
    KeySymbol('bot'),                  # 03
    KeySymbol('fg>bg>sp'),             # 04
    KeySymbol('fg<bg<sp'),             # 05
    KeySymbol('rgb-pane'),             # 06
    KeySymbol('hsb-pane'),             # 07
    KeySymbol('gray-pane'),            # 08
    KeySymbol('close'),                # 09
    KeySymbol('cancel'),               # 10
    KeySymbol('help'),                 # 11
    KeySymbol('toggle-bold'),          # 12
    KeySymbol('toggle-italic'),        # 13
    KeySymbol('toggle-reverse'),       # 14
    KeySymbol('toggle-standout'),      # 15
    KeySymbol('toggle-strikethrough'), # 16
    KeySymbol('toggle-underline'),     # 17
    KeySymbol('toggle-undercurl'),     # 18
    KeySymbol('toggle-underdashed'),   # 19
    KeySymbol('toggle-underdotted'),   # 20
    KeySymbol('toggle-underdouble'),   # 21
    KeySymbol('increment'),            # 22
    KeySymbol('decrement'),            # 23
    KeySymbol('yank'),                 # 24
    KeySymbol('paste'),                # 25
    KeySymbol('set-color'),            # 26
    KeySymbol('set-higroup'),          # 27
    KeySymbol('clear-color'),          # 28
    KeySymbol('add-to-favorite'),      # 29
    KeySymbol('yank'),                 # 30
    KeySymbol('remove-from-palette'),  # 31
    KeySymbol('pick-from-palette'),    # 32
  ]
  const maxSymbolWidth = max(mapnew(s, (_, v) => strdisplaywidth(v)))

  # Pad with spaces, so all symbol strings have the same width
  map(s, (_, v) => v .. repeat(' ', maxSymbolWidth - strdisplaywidth(v)))

  react.CreateEffect(() => {
    if Pane.Get() != HELP_PANE
      return
    endif

    popup_settext(winID, [
      Title(Text('Keyboard Controls')),
      Blank(),
      Label(Text('Popup')),
      Text($'{s[00]} Move up           {s[06]} RGB Pane'),
      Text($'{s[01]} Move down         {s[07]} HSB Pane'),
      Text($'{s[02]} Go to top         {s[08]} Grayscale'),
      Text($'{s[03]} Go to bottom      {s[09]} Close'),
      Text($'{s[04]} fg->bg->sp        {s[10]} Close and reset'),
      Text($'{s[05]} sp->bg->fg        {s[11]} Help pane'),
      Blank(),
      Label(Text('Attributes')),
      Text($'{s[12]} Toggle boldface   {s[17]} Toggle underline'),
      Text($'{s[13]} Toggle italics    {s[18]} Toggle undercurl'),
      Text($'{s[14]} Toggle reverse    {s[19]} Toggle underdaashed'),
      Text($'{s[15]} Toggle standout   {s[20]} Toggle underdotted'),
      Text($'{s[16]} Toggle strikethr. {s[21]} Toggle underdouble'),
      Blank(),
      Label(Text('Color')),
      Text($'{s[22]} Increment value   {s[26]} Set value'),
      Text($'{s[23]} Decrement value   {s[27]} Set hi group'),
      Text($'{s[24]} Yank color        {s[28]} Clear color'),
      Text($'{s[25]} Paste color       {s[29]} Add to favorites'),
      Blank(),
      Label(Text('Recent & Favorites')),
      Text($'{s[30]} Yank color        {s[32]} Pick color'),
      Text($'{s[31]} Delete color'),
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

  react.Clear(POOL)

  gX = popup_getoptions(winID).col
  gY = popup_getoptions(winID).line
enddef
# }}}

def SetHiGroupUnderCursor()
  var hiGroup = HiGroupUnderCursor()

  if empty(hiGroup)
    hiGroup = 'Normal'
  endif

  HiGrp.Set(hiGroup)
enddef

def HandleDigit(winID: number, digit: number): bool
  const isSlider = IsSlider(winID, SelectedID.Get())

  if isSlider
    var newStep = digit
    var elapsed = gTimeLastDigitPressed->reltime()

    gTimeLastDigitPressed = reltime()

    if elapsed->reltimefloat() < get(g:, 'stylepicker_step_delay', 1.0)
      newStep = 10 * Step.Get() + newStep

      if newStep > 99
        newStep = digit
      endif
    endif

    if newStep < 1
      newStep = 1
    endif

    Step.Set(newStep)
  endif

  return isSlider
enddef

def ProcessKeyPress(winID: number, key: string): bool
  if get(g:, 'stylepicker_disable_keys', false)
    return false
  endif

  gNumRedraws = 0

  if Pane.Get() == HELP_PANE && key !~ '\m[RGB?xX]'
    return false
  endif

  if key =~ '\m\d'
    return HandleDigit(winID, str2nr(key))
  endif

  if has_key(gActionMap, key)
    return gActionMap[key]()
  endif

  return false
enddef

def StylePicker(hiGroup: string = '', x = gX, y = gY)
  DEBUG = get(g:, 'stylepicker_debug', false)
  react.Reinit() # TODO: REMOVE ME
  react.Clear(POOL) # Clear all effects
  ResetHighlight()
  gEdited = {fg: false, bg: false, sp: false}
  gNumRedraws = 0
  gFavoritePath = get(g:, 'stylepicker_favorite_path', '')

  if !empty(gFavoritePath)
    Favorite.Set(LoadPalette(gFavoritePath))
  endif

  if empty(hiGroup)
    SetHiGroupUnderCursor()

    augroup stylepicker
      autocmd!
      autocmd CursorMoved * SetHiGroupUnderCursor()
    augroup END
  else
    HiGrp.Set(hiGroup)
  endif

  const winID = popup_create('', {
    border:      [1, 1, 1, 1],
    borderchars: get(g:, 'stylepicker_borderchars', ['─', '│', '─', '│', '╭', '╮', '╯', '╰']),
    callback:    ClosedCallback,
    close:       'button',
    col:         x,
    cursorline:  0,
    drag:        1,
    filter:      ProcessKeyPress,
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

  # Shared views
  const RecentView   = BuildPaletteView(bufnr, Recent,   'Recent Colors',   Prop.RECENT,   ID.RECENT_COLORS,   true)
  const FavoriteView = BuildPaletteView(bufnr, Favorite, 'Favorite Colors', Prop.FAVORITE, ID.FAVORITE_COLORS, false)

  Pane.Set(RGB_PANE)
  SelectedID.Set(ID.RED_SLIDER)

  RgbPane(winID, RecentView, FavoriteView)
  GrayscalePane(winID, RecentView, FavoriteView)
  HelpPane(winID)

  react.CreateEffect(() => {
    prop_type_change(Prop.CURRENT_HIGHLIGHT, {bufnr: bufnr, highlight: HiGrp.Get()})
  })

  gActionMap = ActionMap(winID)
  gStylePickerID = winID

  popup_show(winID)
enddef

# Public interface {{{
export def Open(hiGroup: string = '')
  const stylePickerIsOpened = gStylePickerID->In(popup_list())

  if !stylePickerIsOpened
    StylePicker(hiGroup)
    return
  endif

  if empty(hiGroup)
    SetHiGroupUnderCursor()

    augroup stylepicker
      autocmd!
      autocmd CursorMoved * SetHiGroupUnderCursor()
    augroup END
  else
    HiGrp.Set(hiGroup)
  endif

  # Trigger the highlighting effect, because highlight groups are deleted
  # when the style picker is hidden.
  # react.Transaction(() => {
  #   Recent.Set(Recent.Get())
  #   Favorite.Set(Favorite.Get())
  # })
  popup_show(gStylePickerID)
enddef
# }}}
