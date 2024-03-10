vim9script

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
# Constants and types {{{
const Center            = util.Center
const ErrMsg            = util.ErrMsg
const In                = util.In
const Int               = util.Int
const Msg               = util.Msg
const NotIn             = util.NotIn
const Quote             = util.Quote

const kRGBPane          = 1
const kHSBPane          = 2
const kGrayPane         = 3
const kHelpPane         = 99
const kNumColorsPerLine = 10
const kPrettyKey        = {
  "\<left>":    "←",
  "\<right>":   "→",
  "\<up>":      "↑",
  "\<down>":    "↓",
  "\<tab>":     "↳",
  "\<s-tab>":   "⇧-↳",
  "\<enter>":   "↲",
  "\<s-enter>": "⇧-↲",
}

# IDs for selectable items
const kLabels           = 1
const kRedSlider        = 128
const kGreenSlider      = 129
const kBlueSlider       = 130
const kHueSlider        = 131
const kSaturationSlider = 132
const kBrightnessSlider = 133
const kGrayscaleSlider  = 134
const kRecentColors     = 1024 # Each recent color line gets a +1 id
const kFavoriteColors   = 8192 # Each favorite color line gets a +1 id

type Action = func(): bool
# }}}
# Internal state {{{
# Options {{{
var sASCII:           bool         # Whether the style picker's text should be limited to ASCII
var sAllowKeyMapping: bool         # Allow for key mapping in the popup?
var sBackground:      string       # Highlight group for the popup's background color
var sBorder:          list<string> # Popup border
var sFavoritePath:    string       # Path to saved favorite colors
var sMarker:          string       # String for the marker of selected item
var sRecentCapacity:  number       # Maximum number of recent colors
var sStar:            string       # Symbol for stars (must be a single character)
var sStepDelay:       float        # Maximum delay between two consecutive key presses
var sKeymap:          dict<string> # Associates a key to each action
var sZ:               number       # The popup's z-index

def GetOptions()
  sASCII           = get(g:, 'stylepicker_ascii', false)
  sAllowKeyMapping = get(g:, 'stylepicker_key_mapping', true)
  sBackground      = get(g:, 'stylepicker_background', 'Normal')
  sBorder          = get(g:, 'stylepicker_borderchars', ['─', '│', '─', '│', '┌', '┐', '┘', '└'])
  sFavoritePath    = get(g:, 'stylepicker_favorite_path', '')
  sMarker          = get(g:, 'stylepicker_marker', '❯❯ ')
  sRecentCapacity  = get(g:, 'stylepicker_recent', 20)
  sStar            = get(g:, 'stylepicker_star', '*')
  sStepDelay       = get(g:, 'stylepicker_step_delay', 1.0)
  sZ               = get(g:, 'stylepicker_zindex', 100)
  sKeymap          = extend({
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
    'toggle-tracking':      "T",
    'toggle-undercurl':     "~",
    'toggle-underdashed':   "-",
    'toggle-underdotted':   ".",
    'toggle-underdouble':   "=",
    'toggle-underline':     "U",
    'top':                  "<",
    'up':                   "\<up>",
    'yank':                 "Y",
  }, get(g:, 'stylepicker_keys', {}), 'force')
enddef

def DisabledKeys(): bool
  return get(g:, 'stylepicker_disable_keys', false)
enddef
# }}}

var sActionMap:            dict<Action>  # Mapping from keys to actions
var sColorMode:            string        # Prefix for color attributes ('gui' or 'cterm')
var sDefaultSliderSymbols: list<string>  # List of 9 default symbols to draw the sliders
var sGutter:               string        # Gutter of unselected items
var sGutterWidth:          number        # The gutter's width
var sPopupWidth:           number        # Minimum width of the style picker
var sSliderByID:           dict<any>     # Map from slider IDs to slider objects
var sStyleMode:            string        # Key for style attributes ('gui' or 'cterm')
var sTimeLastDigitPressed: list<number>  # Time since last digit key was pressed
var sX:                    number = 0    # Horizontal position of the style picker
var sY:                    number = 0    # Vertical position of the style picker
var sWinID:                number = -1   # ID of the currently opened style picker

def InitInternalState()
  GetOptions()
  sColorMode            = (has('gui_running') || (has('termguicolors') && &termguicolors)) ? 'gui' : 'cterm'
  sGutter               = repeat(' ', strdisplaywidth(sMarker, 0))
  sGutterWidth          = strchars(sGutter)
  sPopupWidth           = max([39 + strdisplaywidth(sMarker), 42])
  sSliderByID           = {}
  sStyleMode            = has('gui_running') ? 'gui' : 'cterm'
  sTimeLastDigitPressed = reltime()
  sDefaultSliderSymbols = sASCII
    ? [" ", ".", ":", "!", "|", "/", "-", "=", "#"]
    : [" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", '█']
enddef
# }}}
# Helper Functions {{{
def Gutter(selected: bool): string
  return selected ? sMarker : sGutter
enddef

def SpecialSuffix(attr: string, mode: string): string
  if attr == 'sp' && mode == 'cterm'
    return 'ul'
  endif
  return attr
enddef

def Notification(winID: number, text: string, duration = 2000, width = sPopupWidth, border = sBorder)
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

def Warn(text: string, duration = 2000, border = sBorder, width = sPopupWidth)
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
# the highlight group cannot be determined.
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
  var attr = SpecialSuffix(fgBgS, mode)
  var value = synIDattr(synIDtrans(hlID(hiGroup)), $'{attr}#', mode)

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
def GetHighlightColor(hiGroup: string, what: string, colorMode = sColorMode): string
  # Always prefer the GUI definition if it exists
  var value = HiGroupColorAttr(hiGroup, what, 'gui')

  if value != 'NONE' # Fast path
    return value
  endif

  if colorMode == 'cterm'
    const ctermValue = HiGroupColorAttr(hiGroup, SpecialSuffix(what, 'cterm'), 'cterm')

    if ctermValue != 'NONE'
      const hex = libcolor.ColorNumber2Hex(str2nr(ctermValue))
      execute 'hi' hiGroup $'gui{what}={hex}'
      return hex
    endif
  endif

  if what == 'sp'
    return GetHighlightColor(hiGroup, 'fg')
  elseif hiGroup == 'Normal'
    return UltimateFallbackColor(what)
  endif

  return GetHighlightColor('Normal', what)
enddef

# Return the 'opposite' color of the current color attribute. That is the
# background color if the input color attribute is foreground; otherwise, it
# is the foreground color.
def AltColor(hiGrp: string, fgBgS: string): string
  if fgBgS == 'bg'
    return GetHighlightColor(hiGrp, 'fg')
  else
    return GetHighlightColor(hiGrp, 'bg')
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

const kPropTypeNormal           = '_norm' # Normal text
const kPropTypeOn               = '_on__' # Property for 'enabled' stuff
const kPropTypeOff              = '_off_' # Property for 'disabled' stuff
const kPropTypeSelectable       = '_slct' # Mark line as an item that can be selected
const kPropTypeLabel            = '_labl' # Mark line as a label
const kPropTypeSlider           = '_levl' # Mark line as a level bar (slider)
const kPropTypeRecent           = '_mru_' # Mark line as a 'recent colors' line
const kPropTypeFavorite         = '_fav_' # Mark line as a 'favorite colors' line
const kPropTypeCurrentHighlight = '_curh' # To highlight text with the currently selected highglight group
const kPropTypeWarning          = '_warn' # Highlight for warning symbols
const kPropTypeTitle            = '_titl' # Highlight for title section
const kPropTypeGuiHighlight     = '_gcol' # Highlight for the current GUI color
const kPropTypeCtermHighlight   = '_tcol' # Highlight for the current cterm color
const kPropTypeBold             = '_bold' # Highlight for bold attribute
const kPropTypeItalic           = '_ital' # Highlight for italic attribute
const kPropTypeUnderline        = '_ulin' # Highlight for underline attribute
const kPropTypeUndercurl        = '_curl' # Highlight for undercurl attribute
const kPropTypeStandout         = '_stnd' # Highlight for standout attribute
const kPropTypeInverse          = '_invr' # Highlight for inverse attribute
const kPropTypeStrikethrough    = '_strk' # Highlight for strikethrough attribute
const kPropTypeGray             = '_gray' # Grayscale blocks
const kPropTypeGray000          = '_g000' # Grayscale blocks
const kPropTypeGray025          = '_g025' # Grayscale blocks
const kPropTypeGray050          = '_g050' # Grayscale blocks
const kPropTypeGray075          = '_g075' # Grayscale blocks
const kPropTypeGray100          = '_g100' # Grayscale blocks

# Define the property types for the style picker buffer
def InitTextPropertyTypes(bufnr: number)
  const propTypes = {
    [kPropTypeNormal          ]: {bufnr: bufnr, highlight: 'Normal'                  },
    [kPropTypeOn              ]: {bufnr: bufnr, highlight: 'stylePickerOn'           },
    [kPropTypeOff             ]: {bufnr: bufnr, highlight: 'stylePickerOff'          },
    [kPropTypeSelectable      ]: {bufnr: bufnr                                       },
    [kPropTypeLabel           ]: {bufnr: bufnr, highlight: 'Label'                   },
    [kPropTypeSlider          ]: {bufnr: bufnr                                       },
    [kPropTypeRecent          ]: {bufnr: bufnr                                       },
    [kPropTypeFavorite        ]: {bufnr: bufnr                                       },
    [kPropTypeCurrentHighlight]: {bufnr: bufnr                                       },
    [kPropTypeWarning         ]: {bufnr: bufnr, highlight: 'stylePickerWarning'      },
    [kPropTypeTitle           ]: {bufnr: bufnr, highlight: 'Title'                   },
    [kPropTypeGuiHighlight    ]: {bufnr: bufnr, highlight: 'stylePickerGuiColor'     },
    [kPropTypeCtermHighlight  ]: {bufnr: bufnr, highlight: 'stylePickerTermColor'    },
    [kPropTypeBold            ]: {bufnr: bufnr, highlight: 'stylePickerBold'         },
    [kPropTypeItalic          ]: {bufnr: bufnr, highlight: 'stylePickerItalic'       },
    [kPropTypeUnderline       ]: {bufnr: bufnr, highlight: 'stylePickerUnderline'    },
    [kPropTypeUndercurl       ]: {bufnr: bufnr, highlight: 'stylePickerUndercurl'    },
    [kPropTypeStandout        ]: {bufnr: bufnr, highlight: 'stylePickerStandout'     },
    [kPropTypeInverse         ]: {bufnr: bufnr, highlight: 'stylePickerInverse'      },
    [kPropTypeStrikethrough   ]: {bufnr: bufnr, highlight: 'stylePickerStrikethrough'},
    [kPropTypeGray            ]: {bufnr: bufnr                                       },
    [kPropTypeGray000         ]: {bufnr: bufnr, highlight: 'stylePickerGray000'      },
    [kPropTypeGray025         ]: {bufnr: bufnr, highlight: 'stylePickerGray025'      },
    [kPropTypeGray050         ]: {bufnr: bufnr, highlight: 'stylePickerGray050'      },
    [kPropTypeGray075         ]: {bufnr: bufnr, highlight: 'stylePickerGray075'      },
    [kPropTypeGray100         ]: {bufnr: bufnr, highlight: 'stylePickerGray100'      },
  }

  for [propType, propValue] in items(propTypes)
    prop_type_add(propType, propValue)
  endfor
enddef

def FindTextPropertyByID(bufnr: number, textPropID: number): TextProperty
  return prop_find({bufnr: bufnr, id: textPropID, lnum: 1, col: 1}, 'f')
enddef

def FirstSelectable(bufnr: number): TextProperty
  return prop_find({bufnr: bufnr, type: kPropTypeSelectable, lnum: 1, col: 1}, 'f')
enddef

def LastSelectable(bufnr: number, lastLine: number): TextProperty
  return prop_find({bufnr: bufnr, type: kPropTypeSelectable, lnum: lastLine, col: 1}, 'b')
enddef

def NextSelectable(bufnr: number, lnum: number): TextProperty
  var textProp = prop_find({bufnr: bufnr, type: kPropTypeSelectable, lnum: lnum, col: 1, skipstart: true}, 'f')

  if empty(textProp)
    textProp = FirstSelectable(bufnr)
  endif

  return textProp
enddef

def PrevSelectable(bufnr: number, lnum: number, lastLine: number): TextProperty
  var textProp = prop_find({bufnr: bufnr, type: kPropTypeSelectable, lnum: lnum, col: 1, skipstart: true}, 'b')

  if empty(textProp)
    textProp = LastSelectable(bufnr, lastLine)
  endif

  return textProp
enddef

def HasProperty(bufnr: number, textPropID: number, propType: string): bool
  var textProp = FindTextPropertyByID(bufnr, textPropID)

  if empty(textProp)
    return false
  endif

  var propTypes = map(prop_list(textProp.lnum, {bufnr: bufnr}), (_, v) => v.type)
  return propType->In(propTypes)
enddef

class TextLine
  var text: string
  var props: list<TextProperty> = []
  var id: number = 0

  def new(this.text, this.id = v:none)
  enddef

  def Draw(bufnr: number, lnum: number, gutter = '')
    setbufline(bufnr, lnum, gutter .. this.text)
    var gutterBytes = len(gutter)

    for p in this.props
      p.bufnr = bufnr
      if p.length == 0 && p.col == 1 # These are tags, they must not be shifted
        prop_add(lnum, p.col, p)
      else
        prop_add(lnum, p.col + gutterBytes, p)
      endif
    endfor
  enddef

  def AsDict(): dict<any>
    return {text: this.text, props: this.props}
  enddef
endclass

def Text(text: string, id = 0): TextLine
  return TextLine.new(text, id)
enddef

def Blank(width = 0, id = 0): TextLine
  return TextLine.new(repeat(' ', width), id)
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

def Tagged(t: TextLine, propType: string, id = 0): TextLine
  return WithStyle(t, propType, 1, 0, id)
enddef

def Labeled(t: TextLine, from = 1, length = strchars(t.text)): TextLine
  return WithStyle(t, kPropTypeLabel, from, length)
enddef

def WithTitle(t: TextLine, from = 1, length = strchars(t.text)): TextLine
  return WithStyle(t, kPropTypeTitle, from, length)
enddef

def WithState(t: TextLine, enabled: bool, from = 1, length = strchars(t.text)): TextLine
  return WithStyle(t, enabled ? kPropTypeOn : kPropTypeOff, from, length)
enddef

def WithGuiHighlight(t: TextLine, from = 1, length = strchars(t.text)): TextLine
  return WithStyle(t, kPropTypeGuiHighlight, from, length)
enddef

def WithCtermHighlight(t: TextLine, from = 1, length = strchars(t.text)): TextLine
  return WithStyle(t, kPropTypeCtermHighlight, from, length)
enddef

def WithCurrentHighlight(t: TextLine, from = 1, length = strchars(t.text)): TextLine
  return WithStyle(t, kPropTypeCurrentHighlight, from, length)
enddef
# }}}
# Sliders {{{
# NOTE: for a slider to be rendered correctly, ambiwidth must be set to 'single'.
class Slider
  var id:      number
  var name:    string
  var value:   react.Property
  var max:     number = 255
  var min:     number = 0

  def Body(width = sPopupWidth - sGutterWidth - 6, symbols = sDefaultSliderSymbols): TextLine
    var value     = this.value.Get()
    var range     = this.max + 1 - this.min
    var whole     = value * width / range
    var frac      = value * width / (1.0 * range) - whole
    var bar       = repeat(symbols[-1], whole)
    var part_char = symbols[1 + float2nr(floor(frac * 8))]
    var text      = printf("%s %3d %s%s", this.name, value, bar, part_char)

    return Text(text, this.id)
      ->Labeled(1, 1)
      ->Tagged(kPropTypeSlider)
      ->Tagged(kPropTypeSelectable, this.id)
  enddef

  def Increment(by: number)
    var newValue = this.value.Get() + by

    if newValue > this.max
      newValue = this.max
    endif

    this.value.Set(newValue)
  enddef

  def Decrement(by: number)
    var newValue = this.value.Get() - by

    if newValue < this.min
      newValue = this.min
    endif

    this.value.Set(newValue)
  enddef
endclass

def MakeSlider(
    id:          number,
    name:        string,
    value:       react.Property,
    max:         number = 255,
    min:         number = 0
    ): Slider
  var slider = Slider.new(id, name, value, max, min)
  sSliderByID[id] = slider

  return slider
enddef
# }}}
# Reactive properties {{{
const POOL = 'stylepicker_pool'

react.Clear(POOL, true) # Hard-reset when sourcing the script

def GetSet(value: any, pool = POOL): list<any>
  var p_ = react.Property.new(value, pool)
  return [p_, p_.Get, p_.Set]
enddef

var [pPane,       Pane,         SetPane      ] = GetSet(0)     # ID of the current pane
var [pSelectedID, SelectedID,   SetSelectedID] = GetSet(0)     # Text property ID of the currently selected line
var [pRed,        Red,          SetRed       ] = GetSet(0)     # Red level of the current color
var [pGreen,      Green,        SetGreen     ] = GetSet(0)     # Green level of the current color
var [pBlue,       Blue,         SetBlue      ] = GetSet(0)     # Blue level of the current color
var [pHiGroup,    HiGroup,      SetHiGroup   ] = GetSet('')    # Current highlight group
var [pRecent,     Recent,       SetRecent    ] = GetSet([])    # List of recent colors
var [pFavorite,   Favorite,     SetFavorite  ] = GetSet([])    # List of favorite colors
var [pFgBgS,      FgBgS,        SetFgBgS     ] = GetSet('fg')  # Current color attribute ('fg', 'bg', or 'sp')
var [pStep,       Step,         SetStep      ] = GetSet(1)     # Current increment/decrement step
var [pGray,       Gray,         SetGray      ] = GetSet(0)     # Gray level of the current color
var [pHue,        Hue,          SetHue       ] = GetSet(0)     # Hue of the current color
var [pSaturation, Saturation,   SetSaturation] = GetSet(0)     # Saturation of the current color
var [pBrightness, Brightness,   SetBrightness] = GetSet(0)     # Brightness of the current color
var [pEdited,     Edited,       SetEdited    ] = GetSet(false) # Was the current color attribute modified by the style picker?

# Caches for views
var redSliderMemo        = react.Memo(POOL)
var greenSliderMemo      = react.Memo(POOL)
var blueSliderMemo       = react.Memo(POOL)
var hueSliderMemo        = react.Memo(POOL)
var saturationSliderMemo = react.Memo(POOL)
var brightnessSliderMemo = react.Memo(POOL)
var graySliderMemo       = react.Memo(POOL)
var recentViewMemo       = react.Memo(POOL)
var favoriteViewMemo     = react.Memo(POOL)

class ColorProperty extends react.Property
  def new(this.value, pool: string)
    this.Register(pool)
  enddef

  def Get(): string
    this.value = GetHighlightColor(HiGroup(), FgBgS())
    return super.Get()
  enddef

  def Set(newValue: string, force = false)
    if !force && newValue == this.value
      return
    endif

    var fgBgS            = FgBgS()
    var guiAttr          = 'gui' .. fgBgS
    var ctermAttr        = 'cterm' .. SpecialSuffix(fgBgS, 'cterm')
    var attrs: dict<any> = {name: HiGroup(), [guiAttr]: newValue}

    if newValue == 'NONE'
      attrs[ctermAttr] = 'NONE'
    else
      attrs[ctermAttr] = string(libcolor.Approximate(newValue).xterm)
    endif

    hlset([attrs])
    super.Set(newValue, force)
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

  def new(this.value, pool: string)
    this.Register(pool)
  enddef

  def Get(): dict<bool>
    var hl = hlget(HiGroup(), true)[0]
    var style: dict<bool> = extendnew(
      StyleProperty.styles, get(hl, 'gui', get(hl, 'cterm', {})), 'force' # FIXME
    )

    if style.undercurl || style.underdashed || style.underdotted || style.underdouble
      style.underline = true
    endif

    this.value = style

    return super.Get()
  enddef

  def Set(value: dict<bool>, force = true)
    var style = filter(value, (_, v) => v)

    hlset([{name: HiGroup(), 'gui': style, 'cterm': style}])
    super.Set(value, force)
  enddef
endclass

# These are initialized automatically at the first Get() or Set()
var pColor = ColorProperty.new(v:none, POOL) # Value of the current color (e.g., '#fdfdfd')
var pStyle = StyleProperty.new(v:none, POOL) # Dictionary of style attributes (e.g., {bold, true, italic: false, etc...})
var [Color, SetColor] = [pColor.Get, pColor.Set]
var [Style, SetStyle] = [pStyle.Get, pStyle.Set]

def InitProperties(hiGroup: string, favoritePath = sFavoritePath)
  react.Clear(POOL)

  SetHiGroup(empty(hiGroup) ? HiGroupUnderCursor() : hiGroup)
  SetEdited(false)
  SetPane(kRGBPane)
  SetSelectedID(kRedSlider)

  if !empty(favoritePath)
    SetFavorite(LoadPalette(favoritePath))
  endif
enddef
# }}}
# Views {{{
# Render views {{{
type View = func(): list<TextLine>

def RenderView(V: func(): any, bufnr: number, lnum: number): number
  var lnum_ = lnum
  var text: list<TextLine> = V()

  for textLine in text
    var gutter: string

    if textLine.id == 0
      gutter = ''
    else
      gutter = (SelectedID() == textLine.id ? sMarker : sGutter)
    endif

    textLine.Draw(bufnr, lnum_, gutter)
    ++lnum_
  endfor

  return lnum_
enddef
# }}}
# TitleView {{{
def TitleView(): list<TextLine>
  var hiGroup = HiGroup()
  var fgBgS   = FgBgS()
  var aStyle  = Style()

  var attrs   = 'BIUVSK' # Bold, Italic, Underline, reVerse, Standout, striKethrough
  var width   = sPopupWidth
  var offset  = width - len(attrs) + 1
  var spaces  = repeat(' ', width - strchars(hiGroup) - strchars(fgBgS) - strchars(attrs) - 3)
  var text    = $"{hiGroup} [{fgBgS}]{spaces}{attrs}"

  return [Text(text)
    ->WithTitle(1, strchars(hiGroup) + strchars(fgBgS) + 3)
    ->WithState(aStyle.bold,          offset,     1)
    ->WithState(aStyle.italic,        offset + 1, 1)
    ->WithState(aStyle.underline,     offset + 2, 1)
    ->WithState(aStyle.reverse,       offset + 3, 1)
    ->WithState(aStyle.standout,      offset + 4, 1)
    ->WithState(aStyle.strikethrough, offset + 5, 1),
    Blank(),
  ]
enddef
# }}}
# StepView {{{
def StepView(): list<TextLine>
  const text = printf('Step  %02d', Step())
  return [
    Text(text)->Labeled(1, 4),
    Blank(),
  ]
enddef
# }}}
# ColorInfoView {{{
def ColorInfoView(): list<TextLine>
  var hiGrp       = HiGroup()
  var fgBgS       = FgBgS()
  var curColor    = Color()

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
    repeat(sStar, guiScore),
    approxCol.xterm,
    approxCol.hex[1 : ],
    repeat(sStar, termScore)
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
# Grayscale View {{{
def GrayscaleView(): list<TextLine>
  return [
    Text('Grayscale')->Labeled(),
    Blank(sPopupWidth)
    ->WithStyle(kPropTypeGray000, sGutterWidth +  6, 2)
    ->WithStyle(kPropTypeGray025, sGutterWidth + 14, 2)
    ->WithStyle(kPropTypeGray050, sGutterWidth + 22, 2)
    ->WithStyle(kPropTypeGray075, sGutterWidth + 30, 2)
    ->WithStyle(kPropTypeGray100, sGutterWidth + 38, 2),
  ]
enddef
# }}}
# RecentView and FavoriteView {{{
def ColorItemTextProperty(textPropType: string, id: number, k: number): string
  return $'stylePicker{textPropType}{id}_{k}'
enddef

def ColorStripLabels(indexes: list<number>): TextLine
  return Text(' ' .. join(indexes, '   '), kLabels)->Labeled()
enddef

def MakeColorStrip(
    size:         number, # Number of colors
    id:           number, # Unique ID of this strip
    textPropType: string, # Text property identifying the palette this strip belongs to
    width:        number, # Space occupied by this color strip
    ): TextLine
  var colorStrip = Blank(width, id)

  for k in range(size)
    var textProp = ColorItemTextProperty(textPropType, id, k)
    colorStrip->WithStyle(textProp, 4 * k + 1, 3)
  endfor

  return colorStrip
enddef

def MakePaletteView(
    Palette:         func(): any,
    title:           string,   # Title of the palette
    textPropType:    string,   # Property type of associated to the palette
    baseID:          number,   # First text property ID for the grid (incremented by one for each additional line)
    alwaysVisible:   bool,     # If true, hide the palette's title when there are no colors
    colors_per_line: number = kNumColorsPerLine,
    ): View
  return (): list<TextLine> => {
    var size = len(Palette())
    var paletteText = [Text(title)->Labeled()]

    if size == 0
      if alwaysVisible
        paletteText->add(Blank())->add(Blank())
      else
        paletteText = []
      endif

      return paletteText
    endif

    var width = sPopupWidth - sGutterWidth
    var rowNumber = 0
    var i = 0

    while i < size
      var id = baseID + rowNumber
      var n = size - i < colors_per_line ? size - i : colors_per_line
      var strip = MakeColorStrip(n, id, textPropType, width)
      strip->Tagged(kPropTypeSelectable, id)
      strip->Tagged(textPropType, rowNumber)

      if i == 0
        paletteText->add(ColorStripLabels(range(n)))
      else
        paletteText->add(Blank())
      endif

      paletteText->add(strip)
      rowNumber += 1
      i += n
    endwhile

    paletteText->add(Blank())

    return paletteText
  }
enddef

const RecentView   = MakePaletteView(Recent,   'Recent Colors',   kPropTypeRecent,   kRecentColors,   true)
const FavoriteView = MakePaletteView(Favorite, 'Favorite Colors', kPropTypeFavorite, kFavoriteColors, false)
# }}}
# }}}
# Effects {{{
# Render Slider {{{
def RenderSliderEffect(
    bufnr: number, lnum: number, pane: number, slider: react.Property,
    )
  react.CreateEffect(() => {
    if Pane() == pane
      var sliderLine: TextLine = slider.Get()
      var gutter = SelectedID() == sliderLine.id ? sMarker : sGutter
      sliderLine.Draw(bufnr, lnum, gutter)
    endif
  })
enddef
# }}}
# RGB Sliders {{{
def RenderRgbSliders(bufnr: number, lnum: number)
  var redSlider   = MakeSlider(kRedSlider,   'R', pRed)
  var greenSlider = MakeSlider(kGreenSlider, 'G', pGreen)
  var blueSlider  = MakeSlider(kBlueSlider,  'B', pBlue)

  react.CreateMemo(redSliderMemo,   (): TextLine => redSlider.Body())
  react.CreateMemo(greenSliderMemo, (): TextLine => greenSlider.Body())
  react.CreateMemo(blueSliderMemo,  (): TextLine => blueSlider.Body())

  RenderSliderEffect(bufnr, lnum,     kRGBPane, redSliderMemo)
  RenderSliderEffect(bufnr, lnum + 1, kRGBPane, greenSliderMemo)
  RenderSliderEffect(bufnr, lnum + 2, kRGBPane, blueSliderMemo)
enddef
# }}}
# HSB Sliders {{{
def RenderHsbSliders(bufnr: number, lnum: number)
  var hueSlider        = MakeSlider(kHueSlider,        'H', pHue,        359)
  var saturationSlider = MakeSlider(kSaturationSlider, 'S', pSaturation, 100)
  var brightnessSlider = MakeSlider(kBrightnessSlider, 'B', pBrightness, 100)

  react.CreateMemo(hueSliderMemo,        (): TextLine => hueSlider.Body())
  react.CreateMemo(saturationSliderMemo, (): TextLine => saturationSlider.Body())
  react.CreateMemo(brightnessSliderMemo, (): TextLine => brightnessSlider.Body())

  RenderSliderEffect(bufnr, lnum,     kHSBPane, hueSliderMemo)
  RenderSliderEffect(bufnr, lnum + 1, kHSBPane, saturationSliderMemo)
  RenderSliderEffect(bufnr, lnum + 2, kHSBPane, brightnessSliderMemo)
enddef
# }}}
# Grayscale Slider {{{
def RenderGrayscaleSlider(bufnr: number, lnum: number)
  var graySlider = MakeSlider(kGrayscaleSlider, 'G', pGray)

  react.CreateEffect(() => {
    if Pane() == kGrayPane
      RenderView(GrayscaleView, bufnr, lnum)
    endif
  })

  react.CreateMemo(graySliderMemo, (): TextLine => graySlider.Body())
  RenderSliderEffect(bufnr, lnum + 2, kGrayPane, graySliderMemo)
enddef
# }}}
# Color Picker {{{
def ColorPicker(bufnr: number)
  def Render(V: func(): any, lnum: number): number
    var lnum_ = lnum

    react.CreateEffect(() => {
      if Pane() != kHelpPane
        lnum_ = RenderView(V, bufnr, lnum)
      endif
    })

    return lnum_
  enddef

  def RenderLast(V: func(): any, lnum: number)
    react.CreateEffect(() => {
      if Pane() != kHelpPane
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

  var CachedRecentView = react.CreateMemo(recentViewMemo, (): list<TextLine> => RecentView())
  var CachedFavoriteView = react.CreateMemo(favoriteViewMemo, (): list<TextLine> => FavoriteView())

  var lnum_ = Render(CachedRecentView, 12)
  RenderLast(CachedFavoriteView, lnum_)
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
    KeySymbol('toggle-tracking'),      # 06
    KeySymbol('rgb-pane'),             # 07
    KeySymbol('hsb-pane'),             # 08
    KeySymbol('gray-pane'),            # 09
    KeySymbol('close'),                # 10
    KeySymbol('cancel'),               # 11
    KeySymbol('help'),                 # 12
    KeySymbol('toggle-bold'),          # 13
    KeySymbol('toggle-italic'),        # 14
    KeySymbol('toggle-reverse'),       # 15
    KeySymbol('toggle-standout'),      # 16
    KeySymbol('toggle-strikethrough'), # 17
    KeySymbol('toggle-underline'),     # 18
    KeySymbol('toggle-undercurl'),     # 19
    KeySymbol('toggle-underdashed'),   # 20
    KeySymbol('toggle-underdotted'),   # 21
    KeySymbol('toggle-underdouble'),   # 22
    KeySymbol('increment'),            # 23
    KeySymbol('decrement'),            # 24
    KeySymbol('yank'),                 # 25
    KeySymbol('paste'),                # 26
    KeySymbol('set-color'),            # 27
    KeySymbol('set-higroup'),          # 28
    KeySymbol('clear-color'),          # 29
    KeySymbol('add-to-favorite'),      # 30
    KeySymbol('yank'),                 # 31
    KeySymbol('remove-from-palette'),  # 32
    KeySymbol('pick-from-palette'),    # 33
  ]
  const maxSymbolWidth = max(mapnew(s, (_, v) => strdisplaywidth(v)))

  # Pad with spaces, so all symbol strings have the same width
  map(s, (_, v) => v .. repeat(' ', maxSymbolWidth - strdisplaywidth(v)))

  react.CreateEffect(() => {
    if Pane() == kHelpPane
      popup_settext(winID, mapnew([
        Text('Keyboard Controls')->WithTitle(),
        Blank(),
        Text('Popup')->Labeled(),
        Text($'{s[00]} Move up           {s[07]} RGB Pane'),
        Text($'{s[01]} Move down         {s[08]} HSB Pane'),
        Text($'{s[02]} Go to top         {s[09]} Grayscale'),
        Text($'{s[03]} Go to bottom      {s[10]} Close'),
        Text($'{s[04]} fg->bg->sp        {s[11]} Close and reset'),
        Text($'{s[05]} sp->bg->fg        {s[12]} Help pane'),
        Text($'{s[06]} Toggle tracking'),
        Blank(),
        Text('Attributes')->Labeled(),
        Text($'{s[13]} Toggle boldface   {s[18]} Toggle underline'),
        Text($'{s[14]} Toggle italics    {s[19]} Toggle undercurl'),
        Text($'{s[15]} Toggle reverse    {s[20]} Toggle underdashed'),
        Text($'{s[16]} Toggle standout   {s[21]} Toggle underdotted'),
        Text($'{s[17]} Toggle strikethru {s[22]} Toggle underdouble'),
        Blank(),
        Text('Color')->Labeled(),
        Text($'{s[23]} Increment value   {s[27]} Set value'),
        Text($'{s[24]} Decrement value   {s[28]} Set hi group'),
        Text($'{s[25]} Yank color        {s[29]} Clear color'),
        Text($'{s[26]} Paste color       {s[30]} Add to favorites'),
        Blank(),
        Text('Recent & Favorites')->Labeled(),
        Text($'{s[31]} Yank color        {s[33]} Pick color'),
        Text($'{s[32]} Delete color'),
      ], (_, textLine: TextLine) => textLine.AsDict()))
    endif
  })
enddef
# }}}
# Palette Highlighting {{{
def SyncPaletteHighlight(
    bufnr: number, textPropType: string, baseID: number, Palette: func(): any, colors_per_line = kNumColorsPerLine
    )
  react.CreateEffect(() => {
    var palette: list<string> = Palette()
    var i = 0

    while i < len(palette)
      var hiGroup   = $'stylePicker{textPropType}{i}'
      var rowNumber = i / colors_per_line
      var k         = i % colors_per_line
      var textProp  = ColorItemTextProperty(textPropType, baseID + rowNumber, k)
      var hexCol    = palette[i]
      var approx    = libcolor.Approximate(hexCol)

      execute $'hi {hiGroup} guibg={hexCol} ctermbg={approx.xterm}'
      prop_type_delete(textProp, {bufnr: bufnr})
      prop_type_add(textProp, {bufnr: bufnr, highlight: hiGroup})
      ++i
    endwhile
  })
enddef
# }}}
# InitEffects {{{
def SaveToRecent()
  var recent: list<string> = pRecent.value
  var color: string = pColor.value

  if color->NotIn(recent)
    recent->add(color)

    if len(recent) > sRecentCapacity
      remove(recent, 0)
    endif

    SetRecent(recent, true)
  endif
enddef

def InitEffects(winID: number)
  var bufnr = winbufnr(winID)

  # Sync the text property for the current highlight group
  react.CreateEffect(() => {
    prop_type_change(kPropTypeCurrentHighlight, {bufnr: bufnr, highlight: HiGroup()})
  })

  # Sync the highlight groups for the text properties of the color palettes
  SyncPaletteHighlight(bufnr, kPropTypeRecent, kRecentColors, Recent)
  SyncPaletteHighlight(bufnr, kPropTypeFavorite, kFavoriteColors, Favorite)

  # Keep the color in sync with the RGB components, grayscale and HSB values
  react.CreateEffect(() => {
    var [r, g, b] = libcolor.Hex2Rgb(Color())
    SetRed(r)
    SetGreen(g)
    SetBlue(b)
  })
  react.CreateEffect(() => {
    SetColor(libcolor.Rgb2Hex(Red(), Green(), Blue()))
  })

  react.CreateEffect(() => {
    if Pane() == kGrayPane
      var gray = Gray()

      if Edited()
        SetColor(libcolor.Gray2Hex(gray))
      endif
    endif
  })

  react.CreateEffect(() => {
    if Pane() == kHSBPane
      SetColor(libcolor.Hsv2Hex(Hue(), Saturation(), Brightness()))
    endif
  })

  # Save a color to the recent palette when it's edited
  react.CreateEffect(() => {
    if Edited()
      SaveToRecent()
    endif
  })

  # Reset the edited status when highlight group changes
  react.CreateEffect(() => {
    HiGroup()
    SetEdited(false)
  })

  # Create effects to render the UI
  ColorPicker(bufnr)
  HelpPane(winID)
enddef
# }}}
# }}}
# Actions {{{
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
    palette:         react.Property,
    rowNumber:       number,
    Do:              func(list<string>, number, react.Property),
    colors_per_line: number = kNumColorsPerLine,
    ): bool
  var colorStrip: list<string> = palette.Get()
  var from = rowNumber * colors_per_line
  var to = from + colors_per_line - 1

  if to >= len(colorStrip)
    to = len(colorStrip) - 1
  endif

  var n = AskIndex(to - from)

  if n >= 0
    Do(colorStrip, from + n, palette)
    return true
  endif

  return false
enddef

def AddToFavorite(winID: number, savePath: string): Action
  return (): bool => {
    var color = Color()
    var favorite: list<string> = Favorite()

    if color->NotIn(favorite)
      favorite->add(color)
      SetFavorite(favorite, true)

      if !empty(savePath)
        SavePalette(favorite, savePath)
      endif
    endif

    return true
  }
enddef

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

def ChooseColor(colorMode = sColorMode): Action
  return (): bool => {
    var newCol: string

    if colorMode == 'gui'
      newCol = ChooseGuiColor()
    else
      newCol = ChooseTermColor()
    endif

    if !empty(newCol)
      SetColor(newCol)
    endif

    return true
  }
enddef

def ChooseHiGrp(): Action
  return (): bool => {
    const hiGroup = input('Highlight group: ', '', 'highlight')
    echo "\r"

    if hlexists(hiGroup)
      UntrackCursorAutoCmd()
      SetHiGroup(hiGroup)
    endif

    return true
  }
enddef

def ClearColor(winID: number): Action
  return (): bool => {
    SaveToRecent()
    SetColor('NONE')
    Notification(winID, $'[{FgBgS()}] Color cleared')
    return true
  }
enddef

def Close(winID: number): Action
  return (): bool => {
    popup_close(winID)

    return true
  }
enddef

def Decrement(winID: number): Action
  return (): bool => {
    var slider: Slider = get(sSliderByID, SelectedID(), null_object)
    var isSlider = (slider != null)

    if isSlider
      slider.Decrement(Step())
      SetEdited(true)
    endif

    return isSlider
  }
enddef

def FgBgSNext(): Action
  return (): bool => {
    var attr = FgBgS()
    attr = (attr == 'fg' ? 'bg' : attr == 'bg' ? 'sp' : 'fg')
    SetFgBgS(attr)
    SetEdited(false)

    return true
  }
enddef

def FgBgSPrev(): Action
  return (): bool => {
    var attr = FgBgS()
    attr = (attr == 'fg' ? 'sp' : attr == 'sp' ? 'bg' : 'fg')
    SetFgBgS(attr)
    SetEdited(false)

    return true
  }
enddef

def GoToBottom(bufnr: number, lastLine: number): Action
  return (): bool => {
    SetSelectedID(LastSelectable(bufnr, lastLine).id)
    return true
  }
enddef

def GoToTop(bufnr: number): Action
  return (): bool => {
    SetSelectedID(FirstSelectable(bufnr).id)
    return true
  }
enddef

def Increment(winID: number): Action
  return (): bool => {
    var slider: Slider = get(sSliderByID, SelectedID(), null_object)
    var isSlider = (slider != null)

    if isSlider
      slider.Increment(Step())
      SetEdited(true)
    endif

    return isSlider
  }
enddef

def PaletteInfo(bufnr: number): dict<any>
  var id = SelectedID()

  if HasProperty(bufnr, id, kPropTypeRecent)
    return {rowNum: id - kRecentColors, palette: pRecent}
  endif

  if HasProperty(bufnr, id, kPropTypeFavorite)
    return {rowNum: id - kFavoriteColors, palette: pFavorite}
  endif

  return {}
enddef

def PasteColor(): Action
  return (): bool => {
    if @" =~ '\m^#\=[A-Fa-f0-9]\{6}$'
      SaveToRecent()
      SetColor(@"[0] == '#' ? @" : '#' .. @")
    endif

    return true
  }
enddef

def PickColorFromPalette(bufnr: number): Action
  def Pick(colors: list<string>, n: number, palette: react.Property)
    SaveToRecent()
    SetColor(colors[n])
  enddef

  return (): bool => {
    var info = PaletteInfo(bufnr)

    if empty(info)
      return false
    endif

    return ActOnPalette(info.palette, info.rowNum, Pick)
  }
enddef

def RemoveColorFromPalette(bufnr: number, lastLine: number): Action
  def Remove(colors: list<string>, n: number, palette: react.Property)
    remove(colors, n)
    palette.Set(colors, true)
  enddef

  return (): bool => {
    var info = PaletteInfo(bufnr)

    if empty(info)
      return false
    endif

    var palette: react.Property = info.palette

    react.Transaction(() => {
      ActOnPalette(palette, info.rowNum, Remove)

      if empty(palette.Get())
        SelectPrev(bufnr, lastLine)()
      endif
    })

    if palette is pFavorite && !empty(sFavoritePath)
      SavePalette(palette.Get(), sFavoritePath)
    endif

    return true
  }
enddef

def SelectNext(bufnr: number): Action
  return (): bool => {
    var textProp = FindTextPropertyByID(bufnr, SelectedID())
    textProp = NextSelectable(bufnr, textProp.lnum)
    SetSelectedID(textProp.id)
    return true
  }
enddef

def SelectPrev(bufnr: number, lastLine: number): Action
  return (): bool => {
    var textProp = FindTextPropertyByID(bufnr, SelectedID())
    textProp = PrevSelectable(bufnr, textProp.lnum, lastLine)
    SetSelectedID(textProp.id)
    return true
  }
enddef

def SwitchToGrayPane(): Action
  return (): bool => {
    react.Transaction(() => {
      SaveToRecent()
      SetGray(libcolor.Hex2Gray(Color()))
      SetEdited(false)
      SetSelectedID(kGrayscaleSlider)
      SetPane(kGrayPane)
    })
    return true
  }
enddef

def SwitchToHelpPane(): Action
  return (): bool => {
    SetPane(kHelpPane)
    return true
  }
enddef

def SwitchToHSBPane(): Action
  return (): bool => {
    react.Transaction(() => {
      SetEdited(false)
      SetSelectedID(kHueSlider)
      var [h, s, b] = libcolor.Hex2Hsv(Color())
      SetHue(h)
      SetSaturation(s)
      SetBrightness(b)
      SetPane(kHSBPane)
    })
    return true
  }
enddef

def SwitchToRGBPane(): Action
  return (): bool => {
    react.Transaction(() => {
      SetEdited(false)
      SetSelectedID(kRedSlider)
      SetPane(kRGBPane)
    })
    return true
  }
enddef

def ToggleStyleAttribute(attr: string): Action
  return (): bool => {
    var currentStyle: dict<bool> = Style()

    if attr[0 : 4] == 'under'
      var wasOn = currentStyle[attr]

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

    SetStyle(currentStyle, true)

    return true
  }
enddef

def TrackCursorAutoCmd()
  augroup StylePicker
    autocmd!
    autocmd CursorMoved * SetHiGroup(HiGroupUnderCursor())
  augroup END
enddef

def UntrackCursorAutoCmd()
  if exists('#StylePicker')
    autocmd! StylePicker
    augroup! StylePicker
  endif
enddef

def ToggleTrackCursor(): Action
  return (): bool => {
    if exists('#StylePicker')
      UntrackCursorAutoCmd()
    else
      TrackCursorAutoCmd()
    endif

    return true
  }
enddef

def YankColor(winID: number): Action
  var bufnr = winbufnr(winID)

  def Yank(colors: list<string>, n: number, palette: react.Property)
    @" = colors[n] # TODO: allow setting register via user option
  enddef

  return (): bool => {
    var info = PaletteInfo(bufnr)

    if empty(info)
      @" = Color()
      Notification(winID, 'Color yanked: ' .. @")
    else
      if ActOnPalette(info.palette, info.rowNum, Yank)
        Notification(winID, 'Color yanked: ' .. @")
      endif
    endif

    return true
  }
enddef
# }}}
# Key map {{{
def KeySymbol(action: string): string
  const key = sKeymap[action]
  return get(kPrettyKey, key, key)
enddef

def SetActionMap(winID: number, keymap = sKeymap, favoritePath = sFavoritePath)
  var bufnr = winbufnr(winID)

  sActionMap = {
      [keymap['add-to-favorite'     ]]: AddToFavorite(winID, favoritePath),
      [keymap['bot'                 ]]: GoToBottom(bufnr, line('$', winID)),
      [keymap['cancel'              ]]: Cancel(winID),
      [keymap['clear-color'         ]]: ClearColor(winID),
      [keymap['close'               ]]: Close(winID),
      [keymap['decrement'           ]]: Decrement(winID),
      [keymap['down'                ]]: SelectNext(bufnr),
      [keymap['fg<bg<sp'            ]]: FgBgSPrev(),
      [keymap['fg>bg>sp'            ]]: FgBgSNext(),
      [keymap['gray-pane'           ]]: SwitchToGrayPane(),
      [keymap['help'                ]]: SwitchToHelpPane(),
      [keymap['hsb-pane'            ]]: SwitchToHSBPane(),
      [keymap['increment'           ]]: Increment(winID),
      [keymap['paste'               ]]: PasteColor(),
      [keymap['pick-from-palette'   ]]: PickColorFromPalette(bufnr),
      [keymap['remove-from-palette' ]]: RemoveColorFromPalette(bufnr, line('$', winID)),
      [keymap['rgb-pane'            ]]: SwitchToRGBPane(),
      [keymap['set-color'           ]]: ChooseColor(),
      [keymap['set-higroup'         ]]: ChooseHiGrp(),
      [keymap['toggle-bold'         ]]: ToggleStyleAttribute('bold'),
      [keymap['toggle-italic'       ]]: ToggleStyleAttribute('italic'),
      [keymap['toggle-reverse'      ]]: ToggleStyleAttribute('reverse'),
      [keymap['toggle-standout'     ]]: ToggleStyleAttribute('standout'),
      [keymap['toggle-strikethrough']]: ToggleStyleAttribute('strikethrough'),
      [keymap['toggle-tracking'     ]]: ToggleTrackCursor(),
      [keymap['toggle-undercurl'    ]]: ToggleStyleAttribute('undercurl'),
      [keymap['toggle-underdashed'  ]]: ToggleStyleAttribute('underdashed'),
      [keymap['toggle-underdotted'  ]]: ToggleStyleAttribute('underdotted'),
      [keymap['toggle-underdouble'  ]]: ToggleStyleAttribute('underdouble'),
      [keymap['toggle-underline'    ]]: ToggleStyleAttribute('underline'),
      [keymap['top'                 ]]: GoToTop(bufnr),
      [keymap['up'                  ]]: SelectPrev(bufnr, line('$', winID)),
      [keymap['yank'                ]]: YankColor(winID),
  }
enddef
# }}}
# Callbacks {{{
def ClosedCallback(winID: number, result: any = '')
  UntrackCursorAutoCmd()

  sX = popup_getoptions(winID).col
  sY = popup_getoptions(winID).line
  sWinID = -1
enddef

def HandleDigit(winID: number, digit: number): bool
  var isSlider = (get(sSliderByID, SelectedID(), null_object) != null)

  if isSlider
    var newStep = digit
    var elapsed = sTimeLastDigitPressed->reltime()

    sTimeLastDigitPressed = reltime()

    if elapsed->reltimefloat() <= sStepDelay
      newStep = 10 * Step() + newStep

      if newStep > 99
        newStep = digit
      endif
    endif

    if newStep < 1
      newStep = 1
    endif

    SetStep(newStep)
  endif

  return isSlider
enddef

def HandleEvent(winID: number, key: string): bool
  if Pane() == kHelpPane && key !~ '\m[RGH?xX]'
    return false
  endif

  var handled = false

  if key =~ '\m\d'
    handled = HandleDigit(winID, str2nr(key))
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
    zIndex:          number       = sZ,
    background:      string       = sBackground,
    border:          list<string> = sBorder,
    minWidth:        number       = sPopupWidth,
    allowKeyMapping: bool         = sAllowKeyMapping
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

  setbufvar(bufnr, '&tabstop', &tabstop)  # Inherit global tabstop value

  InitHighlight()
  InitTextPropertyTypes(bufnr)
  InitProperties(hiGroup)
  InitEffects(winID)
  SetActionMap(winID)

  if empty(hiGroup)
    TrackCursorAutoCmd()
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

  InitInternalState()
  sWinID = StylePicker(hiGroup, sX, sY)
enddef
# }}}
