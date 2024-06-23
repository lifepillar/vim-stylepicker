vim9script

# TODO:
#
# - Search for FIXME issues
# - Search for TODO issues
# - Hooks
# - Mouse support

# Requirements Check {{{
if !has('popupwin') || !has('textprop') || v:version < 901
  export def Open(hiGroup: string = null_string)
    echomsg 'Stylepicker requires Vim 9.1 compiled with popupwin and textprop.'
  enddef
  finish
endif
# }}}
# Imports {{{
import 'libcolor.vim'        as libcolor
import 'libreactive.vim'     as react
import autoload './util.vim' as util
# }}}
# Options {{{
var gASCII:           bool         # Whether the style picker's text should be limited to ASCII
var gAllowKeyMapping: bool         # Allow for key mapping in the popup?
var gBackground:      string       # Highlight group for the popup's background color
var gBorder:          list<string> # Popup border
var gFavoritePath:    string       # Path to saved favorite colors
var gMarker:          string       # String for the marker of selected item
var gRecentCapacity:  number       # Maximum number of recent colors
var gStar:            string       # Symbol for stars (must be a single character)

def GetOptions()
  gASCII           = get(g:, 'stylepicker_ascii', false)
  gAllowKeyMapping = get(g:, 'stylepicker_key_mapping', true)
  gBackground      = get(g:, 'stylepicker_background', 'Normal')
  gBorder          = get(g:, 'stylepicker_borderchars', ['─', '│', '─', '│', '┌', '┐', '┘', '└'])
  gFavoritePath    = get(g:, 'stylepicker_favorite_path', '')
  gMarker          = get(g:, 'stylepicker_marker', '❯❯ ')
  gRecentCapacity  = get(g:, 'stylepicker_recent', 20)
  gStar            = get(g:, 'stylepicker_star', gASCII ? '*' : '★')
enddef

def DisabledKeys(): bool
  return get(g:, 'stylepicker_disable_keys', false)
enddef

# Examples:
#
# stylepicker.Opt.marker = '> '
#
class Opt
  public static var border = ['─', '│', '─', '│', '┌', '┐', '┘', '└']
  public static var marker = '❯❯ '
endclass
# }}}
# Constants {{{
const Center              = util.Center
const ErrMsg              = util.ErrMsg
const In                  = util.In
const Int                 = util.Int
const Msg                 = util.Msg
const NotIn               = util.NotIn
const Quote               = util.Quote

const RGB_PANE            = 0
const HSB_PANE            = 1
const GRAY_PANE           = 2
const HELP_PANE           = 99
const NUM_COLORS_PER_LINE = 10
# }}}
# Internal state {{{
type Action = func(): bool

var sActionMap:            dict<Action> # Mapping from keys to actions
var sColorMode:            string       # Prefix for color attributes ('gui' or 'cterm')
var sDefaultSliderSymbols: list<string> # List of 9 default symbols to draw the sliders
var sEdited:               dict<bool>   # Has a color attribute been edited?
var sGutter:               string       # Gutter of unselected items
var sPopupWidth:           number       # Minimum width of the style picker
var sStyleMode:            string       # Key for style attributes ('gui' or 'cterm')
var sTimeLastDigitPressed: list<number> # Time since last digit key was pressed
var sX:                    number = 0   # Horizontal position of the style picker
var sY:                    number = 0   # Vertical position of the style picker
var sWinID:                number = -1  # ID of the currently opened style picker

def InitInternalState()
  sColorMode            = (has('gui_running') || (has('termguicolors') && &termguicolors)) ? 'gui' : 'cterm'
  sEdited               = {fg: false, bg: false, sp: false}
  sGutter               = repeat(' ', strdisplaywidth(gMarker, 0))
  sPopupWidth           = max([39 + strdisplaywidth(gMarker), 42])
  sStyleMode            = has('gui_running') ? 'gui' : 'cterm'
  sTimeLastDigitPressed = reltime()
  sDefaultSliderSymbols = gASCII
    ? [" ", ".", ":", "!", "|", "/", "-", "=", "#"]
    : [" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", '█']
enddef
# }}}
# Helper Functions {{{
def Gutter(selected: bool): string
  return selected ? gMarker : sGutter
enddef

def SpSuffix(attr: string, mode: string): string
  if attr == 'sp' && mode == 'cterm'
    return 'ul'
  endif
  return attr
enddef

def Notification(winID: number, text: string, duration = 2000, width = sPopupWidth, border = gBorder)
  popup_notification(Center(text, width), {
    pos:         'topleft',
    line:        get(popup_getoptions(winID), 'line', 1),
    col:         get(popup_getoptions(winID), 'col', 1),
    highlight:   'Normal',
    time:        duration,
    moved:       'any',
    mousemoved:  'any',
    minwidth:    width,
    maxwidth:    width,
    borderchars: border,
  })
enddef

def Warn(text: string, duration = 2000, border = gBorder, width = sPopupWidth)
  popup_notification(Center(text, width), {
    pos:         'topleft',
    highlight:   'Normal',
    time:        duration,
    moved:       'any',
    mousemoved:  'any',
    borderchars: border,
  })
enddef

# Assign an integer score from zero to five to a pair of colors according to
# how many criteria the pair satifies. Thresholds follow W3C guidelines.
def ComputeScore(hexCol1: string, hexCol2: string): number
  const cr = libcolor.ContrastRatio(hexCol1, hexCol2)
  const cd = libcolor.ColorDifference(hexCol1, hexCol2)
  const bd = libcolor.BrightnessDifference(hexCol1, hexCol2)

  return Int(cr >= 3.0) + Int(cr >= 4.5) + Int(cr >= 7.0) + Int(cd >= 500) + Int(bd >= 125)
enddef

# Return the name of the highlight group under the cursor. Return 'Normal' if
# the highlgiht group cannot be determined.
def HiGroupUnderCursor(): string
  var hiGrp: string = synIDattr(synIDtrans(synID(line('.'), col('.'), true)), 'name')

  if empty(hiGrp)
    return 'Normal'
  endif

  return hiGrp
enddef

# When mode is 'gui', return either a hex value or 'NONE'.
# When mode is 'cterm', return either a numeric string or 'NONE'.
def HiGroupColorAttr(hiGroup: string, fgBgS: string, mode: string): string
  var value = synIDattr(synIDtrans(hlID(hiGroup)), $'{fgBgS}#', mode)

  if empty(value)
    return 'NONE'
  endif

  if mode == 'gui'
    if value[0] != '#' # In terminals, HiGroupColorAttr() may return a GUI color name
      value = libcolor.RgbName2Hex(value, '')
    endif
    return value
  endif

  if value !~ '\m^\d\+'
    const num = libcolor.CtermColorNumber(value, 16)

    if num >= 0
      value = string(num)
    else
      value = 'NONE'
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
def GetColor(hiGroup: string, what: string, colorMode = sColorMode): string
  # Always prefer the GUI definition if it exists
  var value = HiGroupColorAttr(hiGroup, what, 'gui')

  if value != 'NONE' # Fast path
    return value
  endif

  if colorMode == 'cterm'
    const ctermValue = HiGroupColorAttr(hiGroup, SpSuffix(what, 'cterm'), 'cterm')

    if ctermValue != 'NONE'
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

# Return the 'opposite' color of the current color attribute. That is the
# background color if the input color attribute is foreground; otherwise, it
# is the foreground color.
def AltColor(hiGrp: string, fgBgS: string): string
  if fgBgS == 'bg'
    return GetColor(hiGrp, 'fg')
  else
    return GetColor(hiGrp, 'bg')
  endif
enddef

# Initialize the highlight groups used by the style picker
def InitHighlight(mode = sColorMode, style = sStyleMode)
  const warnColor    = HiGroupColorAttr('WarningMsg', 'fg', mode)
  const labelColor   = HiGroupColorAttr('Label',      'fg', mode)
  const commentColor = HiGroupColorAttr('Comment',    'fg', mode)

  execute $'hi stylePickerOn            {mode}fg={labelColor}   {style}=bold              term=bold'
  execute $'hi stylePickerOff           {mode}fg={commentColor} {style}=NONE              term=NONE'
  execute $'hi stylePickerWarning       {mode}fg={warnColor}    {style}=bold              term=bold'
  execute $'hi stylePickerBold          {mode}fg={labelColor}   {style}=bold              term=bold'
  execute $'hi stylePickerItalic        {mode}fg={labelColor}   {style}=bold,italic       term=bold,italic'
  execute $'hi stylePickerUnderline     {mode}fg={labelColor}   {style}=bold,underline    term=bold,underline'
  execute $'hi stylePickerUndercurl     {mode}fg={labelColor}   {style}=bold,undercurl    term=bold,undercurl'
  execute $'hi stylePickerUnderdouble   {mode}fg={labelColor}   {style}=bold,underdouble  term=bold,underdouble'
  execute $'hi stylePickerUnderdotted   {mode}fg={labelColor}   {style}=bold,underdotted  term=bold,underdotted'
  execute $'hi stylePickerUnderdashed   {mode}fg={labelColor}   {style}=bold,underdashed  term=bold,underdashed'
  execute $'hi stylePickerStandout      {mode}fg={labelColor}   {style}=bold,standout     term=bold,standout'
  execute $'hi stylePickerInverse       {mode}fg={labelColor}   {style}=bold,inverse      term=bold,inverse'
  execute $'hi stylePickerStrikethrough {mode}fg={labelColor}   {style}=bold,inverse      term=bold,inverse'

  hi! stylePickerGray000 guibg=#000000 ctermbg=16
  hi! stylePickerGray025 guibg=#404040 ctermbg=238
  hi! stylePickerGray050 guibg=#7f7f7f ctermbg=244
  hi! stylePickerGray075 guibg=#bfbfbf ctermbg=250
  hi! stylePickerGray100 guibg=#ffffff ctermbg=231

  hi clear stylePickerGuiColor
  hi clear stylePickerTermColor
enddef

def LoadPalette(loadPath: string): list<string>
  var palette: list<string>

  try
    palette = readfile(loadPath)
  catch /.*/
    ErrMsg($'Could not load favorite colors: {v:exception}')
    palette = []
  endtry

  filter(palette, (_, v) => v =~ '\m^#[A-Fa-f0-9]\{6}$')  # TODO: improve parsing

  return palette
enddef

def SavePalette(palette: list<string>, savePath: string)
  try
    if writefile(palette, savePath, 's') < 0
      ErrMsg($'Failed to write {savePath}')
    endif
  catch /.*/
    ErrMsg($'Could not persist favorite colors: {v:exception}')
  endtry
enddef

# Prompt the user to enter a hex value for a color.
# Return an empty string if the input is invalid.
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

# Prompt the user to enter a numeric value for a terminal color and return the
# value as a string. Return an empty string if the input is invalid.
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
# Text with Properties (:help text-properties) {{{
type TextPropertyType = dict<any>
type TextProperty     = dict<any>

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

# Define the property types for the style picker buffer
def InitTextPropertyTypes(bufnr: number)
  const propTypes = {
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

  for [propType, propValue] in items(propTypes)
    prop_type_add(propType, propValue)
  endfor
enddef

class TextLine
  var text:     string
  var props:    list<TextProperty> = []

  def Draw(bufnr: number, lnum: number)
    setbufline(bufnr, lnum, this.text)

    for p in this.props
      p.bufnr = bufnr
      prop_add(lnum, p.col, p)
    endfor
  enddef

  def AsDict(): dict<any>
    return {text: this.text, props: this.props}
  enddef
endclass

def Text(s: string): TextLine
  return TextLine.new(s)
enddef

def Blank(width = 0): TextLine
  return TextLine.new(repeat(' ', width))
enddef

# Add a style picker property to a text line.
#
# t:        the input text line. This is modified in-place.
# propType: the name of a property type.
# from:     the start position of the property, in bytes (:help prop_add()).
# length:   the extension of the property, in bytes (can be zero).
# id:       the property ID (must be non-negative).
#
# Returns the modified text line.
def WithStyle(
    t: TextLine, propType: string, from = 1, length = strchars(t.text), id = 0
    ): TextLine
  t.props->add({col: from, length: length, type: propType, id: id})
  return t
enddef

def WithTag(t: TextLine, propType: string, id = 0): TextLine
  return WithStyle(t, propType, 1, 0, id)
enddef

def WithTitle(t: TextLine, from = 1, length = strchars(t.text)): TextLine
  return WithStyle(t, Prop.TITLE, from, length)
enddef

def WithLabel(t: TextLine, from = 1, length = strchars(t.text)): TextLine
  return WithStyle(t, Prop.LABEL, from, length)
enddef

def WithState(t: TextLine, enabled: bool, from = 1, length = strchars(t.text)): TextLine
  return WithStyle(t, enabled ? Prop.ON : Prop.OFF, from, length)
enddef

def WithGuiHighlight(t: TextLine, from = 1, length = strchars(t.text)): TextLine
  return WithStyle(t, Prop.GUI_HIGHLIGHT, from, length)
enddef

def WithCtermHighlight(t: TextLine, from = 1, length = strchars(t.text)): TextLine
  return WithStyle(t, Prop.CTERM_HIGHLIGHT, from, length)
enddef

def WithCurrentHighlight(t: TextLine, from = 1, length = strchars(t.text)): TextLine
  return WithStyle(t, Prop.CURRENT_HIGHLIGHT, from, length)
enddef

# IDs for selectable items
class ID
  static const RED_SLIDER        = 128
  static const GREEN_SLIDER      = 129
  static const BLUE_SLIDER       = 130
  static const HUE_SLIDER        = 132
  static const SATURATION_SLIDER = 133
  static const BRIGHTNESS_SLIDER = 134
  static const GRAYSCALE_SLIDER  = 256
  static const RECENT_COLORS     = 1024 # Each recent color line gets a +1 id
  static const FAVORITE_COLORS   = 8192 # Each favorite color line gets a +1 id
endclass

# Return the list of the names of the text properties for the given line in the given buffer.
def GetProperties(bufnr: number, lnum: number): list<string>
  return map(prop_list(lnum, {bufnr: bufnr}), (i, v) => v.type)
enddef

def GetLineNumberForID(bufnr: number, propertyID: number): number
  return prop_find({bufnr: bufnr, id: propertyID, lnum: 1, col: 1, skipstart: false}, 'f').lnum
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
# Sliders {{{
# NOTE: for a slider to be rendered correctly, ambiwidth must be set to 'single'.
def Slider(
    id:         number,
    name:       string,
    value:      number,
    selected:   bool,
    max:        number       = 255,
    min:        number       = 0,
    popupWidth: number       = sPopupWidth,
    symbols:    list<string> = sDefaultSliderSymbols
    ): TextLine
  const gutter    = Gutter(selected)
  const width     = popupWidth - strchars(gutter) - 6
  const range     = max + 1 - min
  const whole     = value * width / range
  const frac      = value * width / (1.0 * range) - whole
  const bar       = repeat(symbols[-1], whole)
  const part_char = symbols[1 + float2nr(floor(frac * 8))]

  return Text(printf("%s%s %3d %s%s", gutter, name, value, bar, part_char))
    ->WithLabel(len(gutter) + 1, 1)
    ->WithTag(Prop.SLIDER)
    ->WithTag(Prop.SELECTABLE, id)
enddef
# }}}
# Reactive properties {{{
const POOL = 'stylepicker_pool'

react.Clear(POOL, true) # Hard-reset when sourcing the script

var pWinID      = react.Property.new(-1,                     POOL) # StylePicker window ID
var pPane       = react.Property.new(-1,                     POOL) # ID of the current pane
var pHiGrp      = react.Property.new('',                     POOL) # Current highlight group
var pHSBColor   = react.Property.new((): list<number> => [], POOL) # HSB values for the current color
var pFgBgS      = react.Property.new('fg',                   POOL) # Current color attribute ('fg', 'bg', or 'sp')
var pSelectedID = react.Property.new(0,                      POOL) # Text property ID of the currently selected line
var pStep       = react.Property.new(1,                      POOL) # Current increment/decrement step
var pRecent     = react.Property.new([],                     POOL) # List of recent colors
var pFavorite   = react.Property.new([],                     POOL) # List of favorite colors

var red        = react.Property.new(0, POOL)
var green      = react.Property.new(0, POOL)
var blue       = react.Property.new(0, POOL)
var gray       = react.Property.new(0, POOL)
var hue        = react.Property.new(0, POOL)
var saturation = react.Property.new(0, POOL)
var brightness = react.Property.new(0, POOL)

def PopupExists(): bool
  return pWinID.Get()->In(popup_list())
enddef

def Edited(fgBgS: string): bool
  return sEdited[fgBgS]
enddef

def SetEdited(fgBgS: string)
  sEdited = {fg: false, bg: false, sp: false}
  sEdited[fgBgS] = true
enddef

def SetUnedited()
  sEdited = {fg: false, bg: false, sp: false}
enddef

def SaveToRecent(color: string)
  var recent: list<string> = pRecent.Get()

  if color->NotIn(recent)
    recent->add(color)

    if len(recent) > gRecentCapacity
      remove(recent, 0)
    endif

    pRecent.Set(recent)
  endif
enddef

class ColorProperty extends react.Property
  def new(this._value, pool: string)
    this.Register(pool)
  enddef

  def Get(): string
    this._value = GetColor(pHiGrp.Get(), pFgBgS.Get())
    return super.Get()
  enddef

  def Set(newValue: string, force = false)
    if newValue == this._value
      return
    endif

    var fgBgS            = pFgBgS.Get()
    var guiAttr          = 'gui' .. fgBgS
    var ctermAttr        = 'cterm' .. SpSuffix(fgBgS, 'cterm')
    var attrs: dict<any> = {name: pHiGrp.Get(), [guiAttr]: newValue}

    if newValue == 'NONE'
      attrs[ctermAttr] = 'NONE'
    else
      attrs[ctermAttr] = string(libcolor.Approximate(newValue).xterm)
    endif

    react.Begin()

    if !Edited(fgBgS)
      SaveToRecent(attrs[guiAttr])
      SetEdited(fgBgS)
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

  def new(this._value, pool: string)
    this.Register(pool)
  enddef

  def Get(): dict<bool>
    const hl = hlget(pHiGrp.Get(), true)[0]
    var style: dict<bool> = get(hl, 'gui', get(hl, 'cterm', {})) # FIXME

    this._value = StyleProperty.styles->extendnew(style, 'force')

    if this._value.undercurl || this._value.underdashed || this._value.underdotted || this._value.underdouble
      this._value.underline = true
    endif

    return super.Get()
  enddef

  def Set(newValue: dict<bool>)
    if newValue != this._value
      var style = filter(newValue, (_, v) => v)

      hlset([{name: pHiGrp.Get(), 'gui': style, 'cterm': style}])
      super.Set(newValue)
    endif
  enddef
endclass

# These are initialized automatically at the first Get() or Set()
var pColor = ColorProperty.new(v:none, POOL) # Value of the current color (e.g., '#fdfdfd')
var pStyle = StyleProperty.new(v:none, POOL) # Dictionary of style attributes (e.g., {bold, true, italic: false, etc...})

def InitProperties(winID: number, hiGrp: string, pane: number)
  react.Clear(POOL)

  pWinID.Set(winID)
  pPane.Set(RGB_PANE)
  pHiGrp.Set(empty(hiGrp) ? HiGroupUnderCursor() : hiGrp)
  pHSBColor.Set((): list<number> => libcolor.Hex2Rgb(pHiGrp.Get())) # FIXME

  if !empty(gFavoritePath)
    pFavorite.Set(LoadPalette(gFavoritePath))
  endif

  # The other properties always have valid values, and not resetting them provides a better UX:

  SwitchPane(pane)()
enddef
# }}}
# Views {{{
type View = func(): list<TextLine>

def RenderView(V: View, bufnr: number, lnum: number): number
  var lnum_ = lnum

  for textLine in V()
    textLine.Draw(bufnr, lnum_)
    ++lnum_
  endfor

  return lnum_
enddef
# TitleView {{{
def TitleView(): list<TextLine>
  var name  = pHiGrp.Get()
  var fgBgS = pFgBgS.Get()
  var style = pStyle.Get()

  var attrs  = 'BIUVSK' # Bold, Italic, Underline, reVerse, Standout, striKethrough
  var width  = sPopupWidth
  var offset = width - len(attrs) + 1
  var spaces = repeat(' ', width - strchars(name) - strchars(fgBgS) - strchars(attrs) - 3)
  var text   = $"{name} [{fgBgS}]{spaces}{attrs}"

  return [Text(text)
    ->WithTitle(1, strchars(name) + strchars(fgBgS) + 3)
    ->WithState(style.bold,          offset,     1)
    ->WithState(style.italic,        offset + 1, 1)
    ->WithState(style.underline,     offset + 2, 1)
    ->WithState(style.reverse,       offset + 3, 1)
    ->WithState(style.standout,      offset + 4, 1)
    ->WithState(style.strikethrough, offset + 5, 1),
    Blank(),
  ]
enddef
# }}}
# StepView {{{
def StepView(): list<TextLine>
  const text = printf('Step  %02d', pStep.Get())
  return [
    Text(text)->WithLabel(1, 4),
    Blank(),
  ]
enddef
# }}}
# ColorInfoView {{{
def ColorInfoView(): list<TextLine>
  var hiGrp       = pHiGrp.Get()
  var fgBgS       = pFgBgS.Get()
  var curColor    = pColor.Get()

  var altColor    = AltColor(hiGrp, fgBgS)
  var approxCol   = libcolor.Approximate(curColor)
  var approxAlt   = libcolor.Approximate(altColor)
  var contrast    = libcolor.ContrastColor(curColor)
  var contrastAlt = libcolor.Approximate(contrast)
  var guiScore    = ComputeScore(curColor, altColor)
  var termScore   = ComputeScore(approxCol.hex, approxAlt.hex)
  var delta       = printf("%.1f", approxCol.delta)[ : 2]
  var guiGuess    = (curColor != HiGroupColorAttr(hiGrp, fgBgS, 'gui') ? '!' : ' ')
  var ctermGuess  = (string(approxCol.xterm) != HiGroupColorAttr(hiGrp, fgBgS, 'cterm') ? '!' : ' ')

  var info = printf(
    $' {guiGuess}   {ctermGuess}   %s %-5S %3d/%s %-5S Δ{delta}',
    curColor[1 : ],
    repeat(gStar, guiScore),
    approxCol.xterm,
    approxCol.hex[1 : ],
    repeat(gStar, termScore)
  )

  execute $'hi stylePickerGuiColor guifg={contrast} guibg={curColor} ctermfg={contrastAlt.xterm} ctermbg={approxCol.xterm}'
  execute $'hi stylePickerTermColor guifg={contrast} guibg={approxCol.hex} ctermfg={contrastAlt.xterm} ctermbg={approxCol.xterm}'

  return [
    Text(info)->WithGuiHighlight(1, 3)->WithCtermHighlight(5, 3),
    Blank(),
  ]
enddef
# }}}
# QuotationView {{{
def QuotationView(): list<TextLine>
  return [
    Text(Center(Quote(), sPopupWidth))->WithCurrentHighlight(),
    Blank(),
  ]
enddef
# }}}
# Grayscale Slider View {{{
def GraySliderView(): list<TextLine>
  const grayLevel  = gray.Get()
  const isSelected = pSelectedID.Get() == ID.GRAYSCALE_SLIDER
  const gutterWidth = strdisplaywidth(Gutter(isSelected), 0)

  return [
    Text('Grayscale')->WithLabel(),
    Blank(sPopupWidth)
    ->WithStyle(Prop.GRAY000, gutterWidth + 6, 2)
    ->WithStyle(Prop.GRAY025, gutterWidth + 14, 2)
    ->WithStyle(Prop.GRAY050, gutterWidth + 22, 2)
    ->WithStyle(Prop.GRAY075, gutterWidth + 30, 2)
    ->WithStyle(Prop.GRAY100, gutterWidth + 38, 2),
    Slider(ID.GRAYSCALE_SLIDER, 'G', grayLevel, isSelected),
  ]
enddef
# }}}
# RecentView and FavoriteView {{{
def BuildPaletteView(
    paletteProperty: react.Property,
    title:           string,
    textPropName:    string, # Prop.RECENT, Prop.FAVORITE
    baseID:          number, # First text property ID for the view (incremented by one for each additional line)
    alwaysVisible = false,
    width         = sPopupWidth
    ): View
  const emptyPaletteText: list<TextLine> = alwaysVisible ? [Text(title)->WithLabel(), Blank(), Blank()] : []

  return (): list<TextLine> => {
    const palette: list<string> = paletteProperty.Get()

    if empty(palette)
      return emptyPaletteText
    endif

    var paletteText = [Text(title)->WithLabel()]
    var i = 0

    while i < len(palette)
      const lineColors  = palette[(i) : (i + NUM_COLORS_PER_LINE - 1)]
      const indexes     = range(len(lineColors))
      const rowNum      = i / NUM_COLORS_PER_LINE
      const id          = baseID + rowNum
      const selectedID  = pSelectedID.Get()
      const gutter      = Gutter(selectedID == id)
      var   colorStrip  = Text(gutter .. repeat(' ', width - strdisplaywidth(gutter)))

      if i == 0
        paletteText->add(
          Text(repeat(' ', strdisplaywidth(gutter) + 1) .. join(indexes, '   '))->WithLabel()
        )
      else
        paletteText->add(Blank())
      endif

      for k in indexes
        const m = i + k
        const propName = $'{textPropName}{m}'
        colorStrip = colorStrip->WithStyle(propName, len(gutter) + 4 * k + 1, 3)
      endfor

      colorStrip = colorStrip->WithTag(textPropName, rowNum)->WithTag(Prop.SELECTABLE, id)
      paletteText->add(colorStrip)
      i += NUM_COLORS_PER_LINE
    endwhile

    return paletteText
  }
enddef

const RecentView   = BuildPaletteView(pRecent,   'Recent Colors',   Prop.RECENT,   ID.RECENT_COLORS,   true)
const FavoriteView = BuildPaletteView(pFavorite, 'Favorite Colors', Prop.FAVORITE, ID.FAVORITE_COLORS, false)
# }}}
# }}}
# Effects {{{
def RenderSlider(bufnr: number, lnum: number, pane: number, id: number, label: string, property: react.Property, max = 255)
  react.CreateEffect(() => {
    if pPane.Get() == pane
      var slider = Slider(id, label, property.Get(), pSelectedID.Get() == id)
      slider.Draw(bufnr, lnum)
    endif
  })
enddef
# RGB Sliders {{{
def RenderRgbSliders(bufnr: number, lnum: number)
  RenderSlider(bufnr, lnum,     RGB_PANE, ID.RED_SLIDER,   'R', red)
  RenderSlider(bufnr, lnum + 1, RGB_PANE, ID.GREEN_SLIDER, 'G', green)
  RenderSlider(bufnr, lnum + 2, RGB_PANE, ID.BLUE_SLIDER,  'B', blue)
enddef
# }}}
# HSB Sliders {{{
def RenderHsbSliders(bufnr: number, lnum: number)
  RenderSlider(bufnr, lnum,     HSB_PANE, ID.HUE_SLIDER,        'H', hue,        359)
  RenderSlider(bufnr, lnum + 1, HSB_PANE, ID.SATURATION_SLIDER, 'S', saturation, 100)
  RenderSlider(bufnr, lnum + 2, HSB_PANE, ID.BRIGHTNESS_SLIDER, 'B', brightness, 100)
enddef
# }}}
# Grayscale Slider {{{
def RenderGrayscaleSlider(bufnr: number, lnum: number)
  react.CreateEffect(() => {
    if pPane.Get() == GRAY_PANE
      RenderView(GraySliderView, bufnr, lnum)
    endif
  })
enddef
# }}}
# ColorPicker {{{
def ColorPicker(winID: number)
  var bufnr = winbufnr(winID)

  def Render(V: View, lnum: number)
    react.CreateEffect(() => {
      if pPane.Get() != HELP_PANE
        RenderView(V, bufnr, lnum)
      endif
    })
  enddef

  def RenderLast(V: View, lnum: number)
    react.CreateEffect(() => {
      if pPane.Get() != HELP_PANE
        var lastLine = RenderView(V, bufnr, lnum)
        deletebufline(bufnr, lastLine, '$')
      endif
    })
  enddef

  Render(TitleView, 1)
  RenderRgbSliders(bufnr, 3)
  RenderHsbSliders(bufnr, 3)
  RenderGrayscaleSlider(bufnr, 3)
  Render(StepView, 6)
  Render(ColorInfoView, 8)
  Render(QuotationView, 10)
  Render(RecentView, 12)
  RenderLast(FavoriteView, 15)
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
    if pPane.Get() == HELP_PANE
      popup_settext(winID, mapnew([
        Text('Keyboard Controls')->WithTitle(),
        Blank(),
        Text('Popup')->WithLabel(),
        Text($'{s[00]} Move up           {s[06]} RGB Pane'),
        Text($'{s[01]} Move down         {s[07]} HSB Pane'),
        Text($'{s[02]} Go to top         {s[08]} Grayscale'),
        Text($'{s[03]} Go to bottom      {s[09]} Close'),
        Text($'{s[04]} fg->bg->sp        {s[10]} Close and reset'),
        Text($'{s[05]} sp->bg->fg        {s[11]} Help pane'),
        Blank(),
        Text('Attributes')->WithLabel(),
        Text($'{s[12]} Toggle boldface   {s[17]} Toggle underline'),
        Text($'{s[13]} Toggle italics    {s[18]} Toggle undercurl'),
        Text($'{s[14]} Toggle reverse    {s[19]} Toggle underdaashed'),
        Text($'{s[15]} Toggle standout   {s[20]} Toggle underdotted'),
        Text($'{s[16]} Toggle strikethr. {s[21]} Toggle underdouble'),
        Blank(),
        Text('Color')->WithLabel(),
        Text($'{s[22]} Increment value   {s[26]} Set value'),
        Text($'{s[23]} Decrement value   {s[27]} Set hi group'),
        Text($'{s[24]} Yank color        {s[28]} Clear color'),
        Text($'{s[25]} Paste color       {s[29]} Add to favorites'),
        Blank(),
        Text('Recent & Favorites')->WithLabel(),
        Text($'{s[30]} Yank color        {s[32]} Pick color'),
        Text($'{s[31]} Delete color'),
      ], (_, textLine: TextLine) => textLine.AsDict()))
    endif
  })
enddef
# }}}

def SyncPaletteHighlight(bufnr: number, textPropName: string, property: react.Property)
  const prefix = $'stylePicker{textPropName}'

  react.CreateEffect(() => {
    var palette: list<string> = property.Get()
    var i = 0

    while i < len(palette)
      const hiGroup  = $'{prefix}{i}'
      const propName = $'{textPropName}{i}'
      const hexCol   = palette[i]
      const approx   = libcolor.Approximate(hexCol)

      execute $'hi {hiGroup} guibg={hexCol} ctermbg={approx.xterm}'
      prop_type_delete(propName, {bufnr: bufnr})
      prop_type_add(propName, {bufnr: bufnr, highlight: hiGroup})
      ++i
    endwhile
  })
enddef

def InitEffects(winID: number, bufnr: number)
  SyncPaletteHighlight(bufnr, Prop.RECENT,   pRecent)
  SyncPaletteHighlight(bufnr, Prop.FAVORITE, pFavorite)

  react.CreateEffect(() => {
    prop_type_change(Prop.CURRENT_HIGHLIGHT, {bufnr: bufnr, highlight: pHiGrp.Get()})
  })

  react.CreateEffect(() => {
    var [r, g, b] = libcolor.Hex2Rgb(pColor.Get())
    red.Set(r)
    green.Set(g)
    blue.Set(b)
  })

  react.CreateEffect(() => {
    pColor.Set(libcolor.Rgb2Hex(red.Get(), green.Get(), blue.Get()))
  })

  react.CreateEffect(() => {
    gray.Set(libcolor.Hex2Gray(pColor.Get()))
  })

  # react.CreateEffect(() => {
  #   pColor.Set(libcolor.Gray2Hex(gray.Get()))
  # })

  react.CreateEffect(() => {
    var HSB = pHSBColor.Get()
    var [h, s, b]  = HSB()
    hue.Set(h)
    saturation.Set(s)
    brightness.Set(b)
  })

  # react.CreateEffect(() => {
  #   pColor.Set(libcolor.Hsv2Hex(hue.Get(), saturation.Get(), brightness.Get()))
  # })

  ColorPicker(winID)
  HelpPane(winID)
enddef
# }}}
# Actions {{{
# Action Helpers {{{
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
    ActionFunc: func(list<string>, number, react.Property)
    ): bool
  var palette: list<string> = Palette.Get()
  var from = rowNum * NUM_COLORS_PER_LINE
  var to = from + NUM_COLORS_PER_LINE - 1

  if to >= len(palette)
    to = len(palette) - 1
  endif

  const n = AskIndex(to - from)

  if n >= 0
    ActionFunc(palette, from + n, Palette)
    return true
  endif

  return false
enddef

def GetPaletteInfo(winID: number): dict<any>
  const id = pSelectedID.Get()

  if IsRecentPalette(winID, id)
    return {rowNum: id - ID.RECENT_COLORS, palette: pRecent}
  endif

  if IsFavoritePalette(winID, id)
    return {rowNum: id - ID.FAVORITE_COLORS, palette: pFavorite}
  endif

  return {}
enddef
# }}}
def Cancel(winID: number): Action
  return (): bool => {
    popup_close(winID)

    # TODO: revert only the changes of the stylepicker
    if exists('g:colors_name') && !empty('g:colors_name')
      execute 'colorscheme' g:colors_name
    endif
    return true
  }
enddef

def Close(winID: number): Action
  return (): bool => {
    popup_close(winID)
    return true
  }
enddef

def FgBgSNext(): Action
  return (): bool => {
    var attr = pFgBgS.Get()
    attr = (attr == 'fg' ? 'bg' : attr == 'bg' ? 'sp' : 'fg')
    pFgBgS.Set(attr)
    return true
  }
enddef

def FgBgSPrev(): Action
  return (): bool => {
    var attr = pFgBgS.Get()
    attr = (attr == 'fg' ? 'sp' : attr == 'sp' ? 'bg' : 'fg')
    pFgBgS.Set(attr)
    return true
  }
enddef

def ToggleStyleAttribute(attr: string): Action
  return (): bool => {
    var currentStyle: dict<bool> = pStyle.Get()

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

    pStyle.Set(currentStyle)
    return true
  }
enddef

def YankColor(winID: number): Action
  const bufnr = winbufnr(winID)
  const Yank = (colors: list<string>, n: number, palette: react.Property) => {
    @" = colors[n] # TODO: allow setting register via user option
  }

  return (): bool => {
    const info = GetPaletteInfo(winID)

    if empty(info)
      @" = pColor.Get()
      Notification(winID, 'Color yanked: ' .. @")
    else
      if ActOnPalette(winID, info.palette, info.rowNum, Yank)
        Notification(winID, 'Color yanked: ' .. @")
      endif
    endif

    return true
  }
enddef

def PasteColor(): Action
  return (): bool => {
    if @" =~ '\m^#\=[A-Fa-f0-9]\{6}$'
      SetUnedited() # Force saving the current color to recent palette
     pColor.Set(@"[0] == '#' ? @" : '#' .. @")
    endif
    return true
  }
enddef

def PickColor(winID: number): Action
  const bufnr = winbufnr(winID)
  const Pick = (colors: list<string>, n: number, palette: react.Property) => {
    pColor.Set(colors[n])
  }

  return (): bool => {
    const info = GetPaletteInfo(winID)

    if !empty(info)
      ActOnPalette(winID, info.palette, info.rowNum, Pick)
    endif

    return !empty(info)
  }
enddef

def RemoveColor(winID: number): Action
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

def AddToFavorite(winID: number): func(): bool
  return (): bool => {
    SaveToFavorite(Color.Get(), gFavoritePath)
    return true
  }
enddef

def IncrementValue(value: number, max: number): number
  const newValue = value + pStep.Get()

  if newValue > max
    return max
  else
    return newValue
  endif
enddef

def DecrementValue(value: number, min: number = 0): number
  const newValue = value - pStep.Get()

  if newValue < min
    return min
  else
    return newValue
  endif
enddef

def Increment(winID: number): Action
  return (): bool => {
    const pane = pPane.Get()
    const selectedID = pSelectedID.Get()

    if pane == RGB_PANE
      if selectedID == ID.RED_SLIDER
        red.Set(IncrementValue(red.Get(), 255))
      elseif selectedID == ID.GREEN_SLIDER
        green.Set(IncrementValue(green.Get(), 255))
      elseif selectedID == ID.BLUE_SLIDER
        blue.Set(IncrementValue(blue.Get(), 255))
      else
        return false
      endif

      return true
    endif

    if pane == HSB_PANE
      if selectedID == ID.HUE_SLIDER
        hue.Set(IncrementValue(hue.Get(), 359))
      elseif selectedID == ID.SATURATION_SLIDER
        saturation.Set(IncrementValue(saturation.Get(), 100))
      elseif selectedID == ID.BRIGHTNESS_SLIDER
        brightness.Set(IncrementValue(brightness.Get(), 100))
      else
        return false
      endif

      return true
    endif

    if pane == GRAY_PANE && selectedID == ID.GRAYSCALE_SLIDER
      gray.Set(IncrementValue(gray.Get(), 255))
      return true
    endif

    return false
  }
enddef

def Decrement(winID: number): func(): bool
  return (): bool => {
    const pane = pPane.Get()
    const selectedID = pSelectedID.Get()

    if pane == RGB_PANE
      if selectedID == ID.RED_SLIDER
        red.Set(DecrementValue(red.Get()))
      elseif selectedID == ID.GREEN_SLIDER
        green.Set(DecrementValue(green.Get()))
      elseif selectedID == ID.BLUE_SLIDER
        blue.Set(DecrementValue(blue.Get()))
      else
        return false
      endif

      return true
    endif

    if pane == HSB_PANE
      if selectedID == ID.HUE_SLIDER
        hue.Set(DecrementValue(hue.Get()))
      elseif selectedID == ID.SATURATION_SLIDER
        saturation.Set(DecrementValue(saturation.Get()))
      elseif selectedID == ID.BRIGHTNESS_SLIDER
        brightness.Set(DecrementValue(brightness.Get()))
      else
        return false
      endif

      return true
    endif

    if pane == GRAY_PANE && selectedID == ID.GRAYSCALE_SLIDER
      gray.Set(DecrementValue(gray.Get()))
      return true
    endif

    return false
  }
enddef

def GoToTop(winID: number): func(): bool
  return (): bool => {
    pSelectedID.Set(FirstSelectable(winID))
    return true
  }
enddef

def GoToBottom(winID: number): func(): bool
  return (): bool => {
    pSelectedID.Set(LastSelectable(winID))
    return true
  }
enddef

def SelectNext(winID: number): func(): bool
  return (): bool => {
    pSelectedID.Set(NextSelectable(winID, pSelectedID.Get()))
    return true
  }
enddef

def SelectPrev(winID: number): func(): bool
  return (): bool => {
    pSelectedID.Set(PrevSelectable(winID, pSelectedID.Get()))
    return true
  }
enddef

def ChooseColor(colorMode = sColorMode): Action
  return (): bool => {
    var newCol: string

    if colorMode == 'gui'
      newCol = ChooseGuiColor()
    else
      newCol = ChooseTermColor()
    endif

    if !empty(newCol)
      pColor.Set(newCol)
    endif

    return true
  }
enddef

def ChooseHiGrp(): Action
  return (): bool => {
    const hiGroup = input('Highlight group: ', '', 'highlight')
    echo "\r"

    if hlexists(hiGroup)
      pHiGrp.Set(hiGroup)
    endif

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

def SwitchToRGBPane()
  react.Transaction(() => {
    pSelectedID.Set(ID.RED_SLIDER)
    pPane.Set(RGB_PANE)
  })
enddef

def SwitchToHSBPane()
  react.Transaction(() => {
    pSelectedID.Set(ID.HUE_SLIDER)
    pHSBColor.Set((): list<number> => libcolor.Hex2Hsv(pColor.Get()))
    pPane.Set(HSB_PANE)
  })
enddef

def SwitchToGrayPane()
  react.Transaction(() => {
    pSelectedID.Set(ID.GRAYSCALE_SLIDER)
    pPane.Set(GRAY_PANE)
  })
enddef

def SwitchToHelpPane()
  pPane.Set(HELP_PANE)
enddef

def SwitchPane(pane: number): func(): bool
  const Switch = {
    [RGB_PANE ]: SwitchToRGBPane,
    [HSB_PANE ]: SwitchToHSBPane,
    [GRAY_PANE]: SwitchToGrayPane,
    [HELP_PANE]: SwitchToHelpPane,
  }

  return (): bool => {
    Switch[pane]()
    return true
  }
enddef
# # }}}
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
  "\<left>":    "←",
  "\<right>":   "→",
  "\<up>":      "↑",
  "\<down>":    "↓",
  "\<tab>":     "↳",
  "\<s-tab>":   "⇧-↳",
  "\<enter>":   "↲",
  "\<s-enter>": "⇧-↲",
}

def KeySymbol(action: string): string
  const key = KEYMAP[action]
  return get(PRETTY_KEY, key, key)
enddef

def SetActionMap(winID: number)
  sActionMap = {
      # [KEYMAP['add-to-favorite'     ]]: AddToFavorite(winID),
      [KEYMAP['bot'                 ]]: GoToBottom(winID),
      [KEYMAP['cancel'              ]]: Cancel(winID),
      # [KEYMAP['clear-color'         ]]: ClearColor(winID),
      [KEYMAP['close'               ]]: Close(winID),
      [KEYMAP['decrement'           ]]: Decrement(winID),
      [KEYMAP['down'                ]]: SelectNext(winID),
      [KEYMAP['fg<bg<sp'            ]]: FgBgSPrev(),
      [KEYMAP['fg>bg>sp'            ]]: FgBgSNext(),
      [KEYMAP['gray-pane'           ]]: SwitchPane(GRAY_PANE),
      [KEYMAP['help'                ]]: SwitchPane(HELP_PANE),
      [KEYMAP['hsb-pane'            ]]: SwitchPane(HSB_PANE),
      [KEYMAP['increment'           ]]: Increment(winID),
      [KEYMAP['paste'               ]]: PasteColor(),
      # [KEYMAP['pick-from-palette'   ]]: PickColor(winID),
      # [KEYMAP['remove-from-palette' ]]: RemoveColor(winID),
      [KEYMAP['rgb-pane'            ]]: SwitchPane(RGB_PANE),
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
# Callbacks {{{
def ClosedCallback(winID: number, result: any = '')
  if exists('#stylepicker')
    autocmd! stylepicker
    augroup! stylepicker
  endif

  sX = popup_getoptions(winID).col
  sY = popup_getoptions(winID).line
  sWinID = -1
enddef

# def HandleDigit(winID: number, digit: number): bool
#   const isSlider = IsSlider(winID, pSelectedID.Get())
#
#   if isSlider
#     var newStep = digit
#     var elapsed = gTimeLastDigitPressed->reltime()
#
#     gTimeLastDigitPressed = reltime()
#
#     if elapsed->reltimefloat() < get(g:, 'stylepicker_step_delay', 1.0)
#       newStep = 10 * Step.Get() + newStep
#
#       if newStep > 99
#         newStep = digit
#       endif
#     endif
#
#     if newStep < 1
#       newStep = 1
#     endif
#
#     Step.Set(newStep)
#   endif
#
#   return isSlider
# enddef

def HandleEvent(winID: number, key: string): bool
  if DisabledKeys()
    return false
  endif

  if pPane.Get() == HELP_PANE && key !~ '\m[RGH?xX]'
    return false
  endif

  var handled = false

  if key =~ '\m\d'
    # handled = HandleDigit(winID, str2nr(key))
  elseif has_key(sActionMap, key)
    handled = sActionMap[key]()
  endif

  return handled
enddef
# }}}
# Style Picker Popup {{{
def StylePicker(
    hiGroup:         string,
    xPos:            number,
    yPos:            number,
    zIndex:          number       = 200,
    background:      string       = gBackground,
    border:          list<string> = gBorder,
    minWidth:        number       = sPopupWidth,
    allowKeyMapping: bool         = gAllowKeyMapping
    ): number
  var winID = popup_create('', {
    border:      [1, 1, 1, 1],
    borderchars: border,
    callback:    ClosedCallback,
    close:       'button',
    col:         xPos,
    cursorline:  0,
    drag:        1,
    filter:      HandleEvent,
    filtermode:  'n',
    hidden:      true,
    highlight:   background,
    line:        yPos,
    mapping:     allowKeyMapping,
    minwidth:    minWidth,
    padding:     [0, 1, 0, 1],
    pos:         'topleft',
    resize:      0,
    scrollbar:   0,
    tabpage:     0,
    title:       '',
    wrap:        0,
    zindex:      zIndex,
  })
  const bufnr = winbufnr(winID)

  echomsg 'bufnr =' bufnr
  setbufvar(bufnr, '&tabstop', &tabstop)  # Inherit global tabstop value

  InitHighlight()
  InitTextPropertyTypes(bufnr)
  InitProperties(winID, hiGroup, RGB_PANE)
  InitEffects(winID, bufnr)
  SetActionMap(winID)

  if empty(hiGroup)
    augroup stylepicker
      autocmd!
      autocmd CursorMoved * pHiGrp.Set(HiGroupUnderCursor())
    augroup END
  endif

  popup_show(winID)

  return winID
enddef
# }}}
# Public interface {{{
export def Open(hiGroup: string = '')
  if sWinID > 0
    popup_close(sWinID)
  endif

  GetOptions()
  InitInternalState()
  sWinID = StylePicker(hiGroup, sX, sY)
enddef
# }}}
