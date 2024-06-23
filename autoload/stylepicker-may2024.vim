vim9script

# - Search for FIXME issues
# - Search for TODO issues
# - Hooks
# - Mouse support

# Requirements Check {{{
if !has('popupwin') || !has('textprop') || v:version < 901
  echomsg 'Stylepicker requires Vim 9.1 compiled with popupwin and textprop.'
  finish
endif
# }}}
# User Settings {{{
var ascii:        bool         = get(g:, 'stylepicker_ascii',        false                                   )
var background:   string       = get(g:, 'stylepicker_background',   'Normal'                                )
var borderchars:  list<string> = get(g:, 'stylepicker_borderchars',  ['─', '│', '─', '│', '╭', '╮', '╯', '╰'])
var favoritepath: string       = get(g:, 'stylepicker_favoritepath', ''                                      )
var keymapping:   bool         = get(g:, 'stylepicker_keymapping',   true                                    )
var marker:       string       = get(g:, 'stylepicker_marker',       ascii ? '>> ' : '❯❯ '                   )
var recent:       number       = get(g:, 'stylepicker_recent',       20                                      )
var star:         string       = get(g:, 'stylepicker_star',         ascii ? '*' : '★'                       )
var stepdelay:    float        = get(g:, 'stylepicker_stepdelay',    1.0                                     )
var zindex:       number       = get(g:, 'stylepicker_zindex',       100                                     )

class Config
  static var Ascii        = () => ascii
  static var Background   = () => background
  static var BorderChars  = () => borderchars
  static var FavoritePath = () => favoritepath
  static var KeyMapping   = () => keymapping
  static var Marker       = () => marker
  static var Recent       = () => recent
  static var Star         = () => star
  static var StepDelay    = () => stepdelay
  static var ZIndex       = () => zindex
endclass
# }}}
# Imports {{{
import 'libcolor.vim'    as libcolor
import 'libreactive.vim' as react
# }}}
# Types and constants {{{
type TextPropertyType = dict<any>
type TextProperty     = dict<any>

interface ITextLine
  var text:  string
  var props: list<TextProperty>
  var id:    number

  def AsDict(): dict<any>
endinterface

type View = func(): list<ITextLine>

type Action = func(): bool
type ActionCode = string

const kRGBPane                 = 1
const kHSBPane                 = 2
const kGrayPane                = 3
const kHelpPane                = 99
const kNumColorsPerLine        = 10

# IDs for selectable items
const kLabels                  = 1
const kRedSlider               = 128
const kGreenSlider             = 129
const kBlueSlider              = 130
const kHueSlider               = 131
const kSaturationSlider        = 132
const kBrightnessSlider        = 133
const kGrayscaleSlider         = 134
const kRecentColors            = 1024 # Each recent color line gets a +1 id
const kFavoriteColors          = 8192 # Each favorite color line gets a +1 id
const kFooter                  = 16384

# IDs for actions
const kActionAddToFavorites:    ActionCode = 'atf'
const kActionBot:               ActionCode = 'bot'
const kActionCancel:            ActionCode = 'can'
const kActionClear:             ActionCode = 'clr'
const kActionClose:             ActionCode = 'clo'
const kActionDecrement:         ActionCode = 'dec'
const kActionDown:              ActionCode = 'dwn'
const kActionFgBgSp:            ActionCode = 'fbs'
const kActionSpBgFg:            ActionCode = 'sbf'
const kActionGrayPane:          ActionCode = 'gry'
const kActionHelp:              ActionCode = 'hlp'
const kActionHsbPane:           ActionCode = 'hsb'
const kActionIncrement:         ActionCode = 'inc'
const kActionPaste:             ActionCode = 'pas'
const kActionPick:              ActionCode = 'pck'
const kActionRemove:            ActionCode = 'rem'
const kActionRgbPane:           ActionCode = 'rgb'
const kActionSetColor:          ActionCode = 'scl'
const kActionSetHiGroup:        ActionCode = 'shg'
const kActionToggleBold:        ActionCode = 'tgb'
const kActionToggleItalic:      ActionCode = 'tgi'
const kActionToggleReverse:     ActionCode = 'tgr'
const kActionToggleStandout:    ActionCode = 'tgs'
const kActionToggleStrikeThru:  ActionCode = 'tgk'
const kActionToggleTracking:    ActionCode = 'tgt'
const kActionToggleUndercurl:   ActionCode = 'tg~'
const kActionToggleUnderdotted: ActionCode = 'tg.'
const kActionToggleUnderdashed: ActionCode = 'tg-'
const kActionToggleUnderdouble: ActionCode = 'tg='
const kActionToggleUnderline:   ActionCode = 'tgu'
const kActionTop:               ActionCode = 'top'
const kActionUp:                ActionCode = 'gup'
const kActionYank:              ActionCode = 'ynk'

# Actions allowed in the help pane
const kHelpActions = [
  kActionRgbPane,
  kActionGrayPane,
  kActionHsbPane,
  kActionCancel,
  kActionClose
]

# Constants for text properties
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
const kPropTypeHeader           = '_titl' # Highlight for title section
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
# }}}
# Internal state {{{
# Options {{{
var sASCII:           bool             # Whether the style picker's text should be limited to ASCII
var sAllowKeyMapping: bool             # Allow for key mapping in the popup?
var sBackground:      string           # Highlight group for the popup's background color
var sBorder:          list<string>     # Popup border
var sFavoritePath:    string           # Path to saved favorite colors
var sMarker:          string           # String for the marker of selected item
var sQuotes:          list<string>     # Quotes
var sRecentCapacity:  number           # Maximum number of recent colors
var sStar:            string           # Symbol for stars (must be a single character)
var sStepDelay:       float            # Maximum delay between two consecutive key presses
var sKeymap:          dict<string>     # Associates a key to each action
var sInvertedKeymap:  dict<ActionCode> # Associates an action to each key
var sZ:               number           # The popup's z-index

def GetOptions()
  sASCII           = get(g:, 'stylepicker_ascii',         false)
  sAllowKeyMapping = get(g:, 'stylepicker_key_mapping',   true)
  sBackground      = get(g:, 'stylepicker_background',    'Normal')
  sBorder          = get(g:, 'stylepicker_borderchars',   ['─', '│', '─', '│', '╭', '╮', '╯', '╰'])
  sFavoritePath    = get(g:, 'stylepicker_favorite_path', '')
  sMarker          = get(g:, 'stylepicker_marker',        sASCII ? '>> ' : '❯❯ ')
  sRecentCapacity  = get(g:, 'stylepicker_recent',        20)
  sStar            = get(g:, 'stylepicker_star',          sASCII ? '*' : '★')
  sStepDelay       = get(g:, 'stylepicker_step_delay',    1.0)
  sZ               = get(g:, 'stylepicker_zindex',        100)
  sKeymap          = extend({
    [kActionAddToFavorites   ]: "A",
    [kActionBot              ]: ">",
    [kActionCancel           ]: "X",
    [kActionClear            ]: "Z",
    [kActionClose            ]: "x",
    [kActionDecrement        ]: "\<left>",
    [kActionDown             ]: "\<down>",
    [kActionSpBgFg           ]: "\<s-tab>",
    [kActionFgBgSp           ]: "\<tab>",
    [kActionGrayPane         ]: "G",
    [kActionHelp             ]: "?",
    [kActionHsbPane          ]: "H",
    [kActionIncrement        ]: "\<right>",
    [kActionPaste            ]: "P",
    [kActionPick             ]: "\<enter>",
    [kActionRemove           ]: "D",
    [kActionRgbPane          ]: "R",
    [kActionSetColor         ]: "E",
    [kActionSetHiGroup       ]: "N",
    [kActionToggleBold       ]: "B",
    [kActionToggleItalic     ]: "I",
    [kActionToggleReverse    ]: "V",
    [kActionToggleStandout   ]: "S",
    [kActionToggleStrikeThru ]: "K",
    [kActionToggleTracking   ]: "T",
    [kActionToggleUndercurl  ]: "~",
    [kActionToggleUnderdotted]: "-",
    [kActionToggleUnderdashed]: ".",
    [kActionToggleUnderdouble]: "=",
    [kActionToggleUnderline  ]: "U",
    [kActionTop              ]: "<",
    [kActionUp               ]: "\<up>",
    [kActionYank             ]: "Y",
  }, get(g:, 'stylepicker_keys', {}), 'force')
  sQuotes = get(g:, 'stylepicker_quotes', [
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
  sInvertedKeymap = {}

  for [action, key] in items(sKeymap)
    sInvertedKeymap[key] = action
  endfor
enddef
# }}}
var sActionMap:            dict<Action> # Mapping from keys to actions
var sColorMode:            string       # Prefix for color attributes ('gui' or 'cterm')
var sActionableRegistry:   dict<any>    # Map from text property IDs to widgets that can be acted upon
var sDefaultSliderSymbols: list<string> # List of 9 default symbols to draw the sliders
var sGutter:               string       # Gutter of unselected items
var sGutterWidth:          number       # The gutter's width
var sPopupWidth:           number       # Minimum width of the style picker
var sSliderByID:           dict<any>    # Map from slider IDs to slider objects
var sPrettyKey:            dict<string> # Map to prettify keys for printing
var sStyleMode:            string       # Key for style attributes ('gui' or 'cterm')
var sTimeLastDigitPressed: list<number> # Time since last digit key was pressed
var sWinID:                number = -1  # ID of the currently opened style picker
var sX:                    number = 0   # Horizontal position of the style picker
var sY:                    number = 0   # Vertical position of the style picker

var sPool: list<react.Property> = []    # See :help libreactive-pools

def InitInternalState()
  GetOptions()
  sActionMap            = {}
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
  sPrettyKey            = sASCII
    ? {
      "\<left>":    "<left>",
      "\<right>":   "<right>",
      "\<up>":      "<up>",
      "\<down>":    "<down>",
      "\<tab>":     "<tab>",
      "\<s-tab>":   "<s-tab>",
      "\<enter>":   "<enter>",
      "\<s-enter>": "<s-enter>",
    }
    : {
      "\<left>":    "←",
      "\<right>":   "→",
      "\<up>":      "↑",
      "\<down>":    "↓",
      "\<tab>":     "↳",
      "\<s-tab>":   "⇧-↳",
      "\<enter>":   "↲",
      "\<s-enter>": "⇧-↲",
    }

  for property in sPool
    property.Clear()
  endfor
enddef
# }}}
# Helper Functions {{{
def In(v: any, items: list<any>): bool
  return index(items, v) != -1
enddef

def NotIn(v: any, items: list<any>): bool
  return index(items, v) == -1
enddef

def Int(cond: bool): number
  return cond ? 1 : 0
enddef

def Center(text: string, width: number): string
  const lPad = repeat(' ', (width + 1 - strwidth(text)) / 2)
  const rPad = repeat(' ', (width - strwidth(text)) / 2)
  return $'{lPad}{text}{rPad}'
enddef

def Msg(text: string, error = false)
  if error
    echohl Error
  else
    echohl WarningMsg
  endif

  echomsg $'[StylePicker] {text}.'
  echohl None
enddef

def Error(text: string)
  Msg(text, true)
enddef

def Quote(): string
  return sQuotes[rand() % len(sQuotes)]
enddef

def Gutter(selected: bool): string
  return selected ? sMarker : sGutter
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

def WarningPopup(text: string, duration = 2000, border = sBorder, width = sPopupWidth)
  popup_notification(Center(text, width), {
    pos:         'topleft',
    highlight:   'Normal',
    time:        duration,
    moved:       'any',
    mousemoved:  'any',
    borderchars: border,
  })
enddef

def Suffix(attr: string, mode: string): string
  if attr == 'sp' && mode == 'cterm'
    return 'ul'
  endif
  return attr
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
  var attr = Suffix(fgBgS, mode)
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

def UltimateFallbackColor(fgBgS: string): string
  if fgBgS == 'bg'
    return &bg == 'dark' ? '#000000' : '#ffffff'
  else
    return &bg == 'dark' ? '#ffffff' : '#000000'
  endif
enddef

# Try hard to determine a sensible hex value for the requested color attribute
def GetHighlightColor(hiGroup: string, fgBgS: string, colorMode: string = sColorMode): string
  # Always prefer the GUI definition if it exists
  var value = HiGroupColorAttr(hiGroup, fgBgS, 'gui')

  if value != 'NONE' # Fast path
    return value
  endif

  if colorMode == 'cterm'
    const ctermValue = HiGroupColorAttr(hiGroup, Suffix(fgBgS, 'cterm'), 'cterm')

    if ctermValue != 'NONE'
      const hex = libcolor.ColorNumber2Hex(str2nr(ctermValue))
      execute 'hi' hiGroup $'gui{fgBgS}={hex}'
      return hex
    endif
  endif

  if fgBgS == 'sp'
    return GetHighlightColor(hiGroup, 'fg')
  elseif hiGroup == 'Normal'
    return UltimateFallbackColor(fgBgS)
  endif

  return GetHighlightColor('Normal', fgBgS)
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
def InitHighlight(mode: string, style: string)
  var warnColor    = HiGroupColorAttr('WarningMsg', 'fg', mode)
  var labelColor   = HiGroupColorAttr('Label',      'fg', mode)
  var commentColor = HiGroupColorAttr('Comment',    'fg', mode)

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
    Error($'Could not load favorite colors: {v:exception}')
    palette = []
  endtry

  filter(palette, (_, v) => v =~ '\m^\s*#[A-Fa-f0-9]\{6}\>')

  return palette
enddef

def SavePalette(palette: list<string>, savePath: string)
  try
    if writefile(palette, savePath, 's') < 0
      throw $'failed to write {savePath}'
    endif
  catch /.*/
    Error($'Could not persist favorite colors: {v:exception}')
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
# Autocommands {{{
def ColorschemeChangedAutoCmd()
  augroup StylePicker
    autocmd ColorScheme * InitHighlight(sColorMode, sStyleMode)
  augroup END
enddef

def TrackCursorAutoCmd()
  augroup StylePicker
    autocmd CursorMoved * SetHiGroup(HiGroupUnderCursor())
  augroup END
enddef

def UntrackCursorAutoCmd()
  if exists('#StylePicker')
    autocmd! StylePicker CursorMoved *
  endif
enddef

def DisableAllAutocommands()
  if exists('#StylePicker')
    autocmd! StylePicker
    augroup! StylePicker
  endif
enddef
# }}}
# Text with Properties (:help text-properties) {{{
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
    [kPropTypeHeader          ]: {bufnr: bufnr, highlight: 'Title'                   },
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

def LastSelectable(bufnr: number): TextProperty
  var lastLine = getbufinfo(bufnr)[0].linecount
  return prop_find({bufnr: bufnr, type: kPropTypeSelectable, lnum: lastLine, col: 1}, 'b')
enddef

def NextSelectable(bufnr: number, lnum: number): TextProperty
  var textProp = prop_find({bufnr: bufnr, type: kPropTypeSelectable, lnum: lnum, col: 1, skipstart: true}, 'f')

  if empty(textProp)
    textProp = FirstSelectable(bufnr)
  endif

  return textProp
enddef

def PrevSelectable(bufnr: number, lnum: number): TextProperty
  var textProp = prop_find({bufnr: bufnr, type: kPropTypeSelectable, lnum: lnum, col: 1, skipstart: true}, 'b')

  if empty(textProp)
    textProp = LastSelectable(bufnr)
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

def HasPropertyByLine(bufnr: number, lnum: number, propType: string): bool
  var propTypes = map(prop_list(lnum, {bufnr: bufnr}), (_, v) => v.type)
  return propType->In(propTypes)
enddef

class TextLine implements ITextLine
  var text: string
  var props: list<TextProperty> = []
  var id: number = 0

  def new(this.text, this.id = v:none)
  enddef

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
  return WithStyle(t, kPropTypeHeader, from, length)
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
# Reactive properties {{{
def GetSet(value: any, pool = sPool): list<any>
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

class ColorProperty extends react.Property
  def new(this.value, pool: list<react.Property>)
    pool->add(this)
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
    var ctermAttr        = 'cterm' .. Suffix(fgBgS, 'cterm')
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

  def new(this.value, pool: list<react.Property>)
    pool->add(this)
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
var pColor = ColorProperty.new('#000000', sPool) # Value of the current color
var pStyle = StyleProperty.new({}, sPool) # Dictionary of style attributes
var [Color, SetColor] = [pColor.Get, pColor.Set]
var [Style, SetStyle] = [pStyle.Get, pStyle.Set]

def InitProperties(hiGroup: string, favoritePath: string)
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
interface IView
  def Body(): list<ITextLine>
  def HandleKeyPressed(key: string): bool
  def HandleLeftMouse(line: number, column: number): bool
endinterface
# HeaderView {{{
def HeaderView(): list<TextLine>
  var hiGroup = HiGroup()
  var fgBgS   = FgBgS()
  var aStyle  = Style()

  var attrs   = 'BIUVSK' # Bold, Italic, Underline, reVerse, Standout, striKethrough
  var width   = sPopupWidth
  var offset  = width - len(attrs) + 1
  var spaces  = repeat(' ', width - strchars(hiGroup) - strchars(fgBgS) - strchars(attrs) - 3)
  var text    = $"[{fgBgS}] {hiGroup}{spaces}{attrs}"

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
# SliderView {{{
# NOTE: for a slider to be rendered correctly, ambiwidth must be set to 'single'.
class Slider
  var id:      number
  var name:    string
  var value:   react.Property
  var max:     number = 255
  var min:     number = 0

  def Body(
      prefix: string,
      width = sPopupWidth - sGutterWidth - 6,
      symbols = sDefaultSliderSymbols,
    ): list<TextLine>
    var value     = this.value.Get()
    var range     = this.max + 1 - this.min
    var whole     = value * width / range
    var frac      = value * width / (1.0 * range) - whole
    var bar       = repeat(symbols[-1], whole)
    var part_char = symbols[1 + float2nr(floor(frac * 8))]
    var text      = printf("%s%s %3d %s%s", prefix, this.name, value, bar, part_char)

    return [Text(text, this.id)
      ->Labeled(1, 1)
      ->Tagged(kPropTypeSlider)
      ->Tagged(kPropTypeSelectable, this.id)]
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

def MakeSliderView(
    id:          number,
    name:        string,
    value:       react.Property,
    max:         number = 255,
    min:         number = 0
    ): View
  var slider = Slider.new(id, name, value, max, min)
  sSliderByID[id] = slider  # FIXME: remove this
  sActionableRegistry[id] = slider

  return slider.Body()
enddef
# }}}
# StepView {{{
def StepView(): list<TextLine>
  return [
    Text(printf('Step  %02d', Step()))->Labeled(1, 4),
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
    $' {guiGuess}   {ctermGuess}  %s %-5S %3d/%s %-5S Δ{delta}',
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
    ): func(): list<TextLine>
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
# FooterView {{{
def FooterView(): list<TextLine>
  return [
    Text('TODO', kFooter)->Labeled(1, 4)->Tagged(kPropTypeSelectable, kFooter)
  ]
enddef
# }}}
# Help View {{{
def HelpView(): list<TextLine>
  var s = [
    KeySymbol(kActionUp),                # 00
    KeySymbol(kActionDown),              # 01
    KeySymbol(kActionTop),               # 02
    KeySymbol(kActionBot),               # 03
    KeySymbol(kActionFgBgSp),            # 04
    KeySymbol(kActionSpBgFg),            # 05
    KeySymbol(kActionToggleTracking),    # 06
    KeySymbol(kActionRgbPane),           # 07
    KeySymbol(kActionHsbPane),           # 08
    KeySymbol(kActionGrayPane),          # 09
    KeySymbol(kActionClose),             # 10
    KeySymbol(kActionCancel),            # 11
    KeySymbol(kActionHelp),              # 12
    KeySymbol(kActionToggleBold),        # 13
    KeySymbol(kActionToggleItalic),      # 14
    KeySymbol(kActionToggleReverse),     # 15
    KeySymbol(kActionToggleStandout),    # 16
    KeySymbol(kActionToggleStrikeThru),  # 17
    KeySymbol(kActionToggleUnderline),   # 18
    KeySymbol(kActionToggleUndercurl),   # 19
    KeySymbol(kActionToggleUnderdashed), # 20
    KeySymbol(kActionToggleUnderdotted), # 21
    KeySymbol(kActionToggleUnderdouble), # 22
    KeySymbol(kActionIncrement),         # 23
    KeySymbol(kActionDecrement),         # 24
    KeySymbol(kActionYank),              # 25
    KeySymbol(kActionPaste),             # 26
    KeySymbol(kActionSetColor),          # 27
    KeySymbol(kActionSetHiGroup),        # 28
    KeySymbol(kActionClear),             # 29
    KeySymbol(kActionAddToFavorites),    # 30
    KeySymbol(kActionYank),              # 31
    KeySymbol(kActionRemove),            # 32
    KeySymbol(kActionPick),              # 33
  ]
  const maxSymbolWidth = max(mapnew(s, (_, v) => strdisplaywidth(v)))

  # Pad with spaces, so all symbol strings have the same width
  map(s, (_, v) => v .. repeat(' ', maxSymbolWidth - strdisplaywidth(v)))

  return [
    Text('Keyboard Controls')->WithTitle(),
    Blank(),
    Text('Popup')->Labeled(),
    Text($'{s[00]} Move up           {s[07]} RGB Pane'),
    Text($'{s[01]} Move down         {s[08]} HSB Pane'),
    Text($'{s[02]} Go to top         {s[09]} Grayscale'),
    Text($'{s[03]} Go to bottom      {s[10]} Close'),
    Text($'{s[04]} fg->bg->sp        {s[11]} Close and reset'),
    Text($'{s[05]} sp->bg->fg        {s[12]} Help pane'),
    Text($'{s[06]} Toggle tracking   '),
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
  ]
enddef
# }}}
# VStack {{{
def VStack(...views: list<View>): list<TextLine>
  var text = []

  for V in views
    text += V()
  endfor

  return text
enddef
# }}}
# }}}
# Effects {{{
# RGB Sliders {{{
def RenderRgbSliders(bufnr: number)
  var RedSliderView   = MakeSliderView(kRedSlider,   'R', pRed)
  var GreenSliderView = MakeSliderView(kGreenSlider, 'G', pGreen)
  var BlueSliderView  = MakeSliderView(kBlueSlider,  'B', pBlue)

  var RedSlider   = react.CreateMemo(RedSliderView)
  var GreenSlider = react.CreateMemo(GreenSliderView)
  var BlueSlider  = react.CreateMemo(BlueSliderView)

  RenderSlider(bufnr, kRGBPane, RedSlider,   pSliderY1, pSliderY2)
  RenderSlider(bufnr, kRGBPane, GreenSlider, pSliderY2, pSliderY3)
  RenderSlider(bufnr, kRGBPane, BlueSlider,  pSliderY3, pStep)
enddef
# }}}
# HSB Sliders {{{
def RenderHsbSliders(bufnr: number)
  var HueSliderView        = MakeSliderView(kHueSlider,        'H', pHue,        359)
  var SaturationSliderView = MakeSliderView(kSaturationSlider, 'S', pSaturation, 100)
  var BrightnessSliderView = MakeSliderView(kBrightnessSlider, 'B', pBrightness, 100)

  var HueSlider        = react.CreateMemo(HueSliderView)
  var SaturationSlider = react.CreateMemo(SaturationSliderView)
  var BrightnessSlider = react.CreateMemo(BrightnessSliderView)

  RenderSlider(bufnr, kHSBPane, HueSlider,        pSliderY1, pSliderY2)
  RenderSlider(bufnr, kHSBPane, SaturationSlider, pSliderY2, pSliderY3)
  RenderSlider(bufnr, kHSBPane, BrightnessSlider, pSliderY3, pStep)
enddef
# }}}
# Grayscale Slider {{{
def RenderGrayscaleSlider(bufnr: number)
  var GraySliderView = MakeSliderView(kGrayscaleSlider, 'G', pGray)

  react.CreateEffect(() => {
    if Pane() == kGrayPane
      echomsg 'Rendering GrayscaleView'
      RenderView(GrayscaleView, bufnr, pSliderY1, pSliderY3)
    endif
  })

  var GraySlider = react.CreateMemo(GraySliderView)
  RenderSlider(bufnr, kGrayPane, GraySlider, pSliderY3, pStep)
enddef
# }}}
# Color Pane {{{
def ColorPane(bufnr: number)
  RenderView(HeaderView, bufnr, pHeaderY, pSliderY1)
  RenderRgbSliders(bufnr)
  RenderHsbSliders(bufnr)
  RenderGrayscaleSlider(bufnr)
  RenderView(StepView, bufnr, pStepY, pColorInfoY)
  RenderView(ColorInfoView, bufnr, pColorInfoY, pQuoteY)
  RenderView(QuotationView, bufnr, pQuoteY, pRecentY)

  var CachedRecentView = react.CreateMemo((): list<TextLine> => RecentView())
  var CachedFavoriteView = react.CreateMemo((): list<TextLine> => FavoriteView())

  RenderView(CachedRecentView, bufnr, pRecentY, pFavoriteY)
  RenderView(CachedFavoriteView, bufnr, pFavoriteY, pFooterY)
  RenderView(FooterView, bufnr, pFooterY, v:none, true)
enddef
# }}}
# RGB Pane {{{
def RGBView(): list<TextLine>
  return VStack(
    HeaderView,
    StepView,
    FooterView,
  )
enddef

def RGBPane(winID: number)
  react.CreateEffect(() => {
    if Pane() == kRGBPane
      popup_settext(winID, mapnew(RGBView(), (_, textLine: TextLine) => textLine.AsDict()))
    endif
  })
enddef

# }}}
# Help Pane {{{
def HelpPane(winID: number)
  react.CreateEffect(() => {
    if Pane() == kHelpPane
      popup_settext(winID, mapnew(HelpView(), (_, textLine: TextLine) => textLine.AsDict()))
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
  var recentColors: list<string> = pRecent.value
  var color: string = pColor.value

  if color->NotIn(recentColors)
    recentColors->add(color)

    if len(recentColors) > sRecentCapacity
      remove(recentColors, 0)
    endif

    SetRecent(recentColors, true)
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
    if Pane() == kGrayPane
      SetGray(libcolor.Hex2Gray(Color()))
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
  RGBPane(winID)
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

def GoToBottom(winID: number): Action
  var bufnr = winbufnr(winID)

  return (): bool => {
    SetSelectedID(LastSelectable(bufnr).id)
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

def RemoveColorFromPalette(winID: number): Action
  var bufnr = winbufnr(winID)

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
        SelectPrev(winID)()
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

def SelectPrev(winID: number): Action
  var bufnr = winbufnr(winID)

  return (): bool => {
    var textProp = FindTextPropertyByID(bufnr, SelectedID())
    textProp = PrevSelectable(bufnr, textProp.lnum)
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

def ToggleTrackCursor(): Action
  return (): bool => {
    if exists('#StylePicker#CursorMoved')
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
def KeySymbol(actionCode: ActionCode): string
  const key = sKeymap[actionCode]
  return get(sPrettyKey, key, key)
enddef

def SetActionMap(winID: number, keymap = sKeymap, favoritePath = sFavoritePath)
  var bufnr = winbufnr(winID)

  sActionMap = {
      [keymap[kActionAddToFavorites   ]]: AddToFavorite(winID, favoritePath),
      [keymap[kActionBot              ]]: GoToBottom(winID),
      [keymap[kActionCancel           ]]: Cancel(winID),
      [keymap[kActionClear            ]]: ClearColor(winID),
      [keymap[kActionClose            ]]: Close(winID),
      [keymap[kActionDecrement        ]]: Decrement(winID),
      [keymap[kActionDown             ]]: SelectNext(bufnr),
      [keymap[kActionSpBgFg           ]]: FgBgSPrev(),
      [keymap[kActionFgBgSp           ]]: FgBgSNext(),
      [keymap[kActionGrayPane         ]]: SwitchToGrayPane(),
      [keymap[kActionHelp             ]]: SwitchToHelpPane(),
      [keymap[kActionHsbPane          ]]: SwitchToHSBPane(),
      [keymap[kActionIncrement        ]]: Increment(winID),
      [keymap[kActionPaste            ]]: PasteColor(),
      [keymap[kActionPick             ]]: PickColorFromPalette(bufnr),
      [keymap[kActionRemove           ]]: RemoveColorFromPalette(winID),
      [keymap[kActionRgbPane          ]]: SwitchToRGBPane(),
      [keymap[kActionSetColor         ]]: ChooseColor(),
      [keymap[kActionSetHiGroup       ]]: ChooseHiGrp(),
      [keymap[kActionToggleBold       ]]: ToggleStyleAttribute('bold'),
      [keymap[kActionToggleItalic     ]]: ToggleStyleAttribute('italic'),
      [keymap[kActionToggleReverse    ]]: ToggleStyleAttribute('reverse'),
      [keymap[kActionToggleStandout   ]]: ToggleStyleAttribute('standout'),
      [keymap[kActionToggleStrikeThru ]]: ToggleStyleAttribute('strikethrough'),
      [keymap[kActionToggleTracking   ]]: ToggleTrackCursor(),
      [keymap[kActionToggleUndercurl  ]]: ToggleStyleAttribute('undercurl'),
      [keymap[kActionToggleUnderdashed]]: ToggleStyleAttribute('underdashed'),
      [keymap[kActionToggleUnderdotted]]: ToggleStyleAttribute('underdotted'),
      [keymap[kActionToggleUnderdouble]]: ToggleStyleAttribute('underdouble'),
      [keymap[kActionToggleUnderline  ]]: ToggleStyleAttribute('underline'),
      [keymap[kActionTop              ]]: GoToTop(bufnr),
      [keymap[kActionUp               ]]: SelectPrev(winID),
      [keymap[kActionYank             ]]: YankColor(winID),
      ['0'                             ]: (): bool => HandleDigit(winID, 0),
      ['1'                             ]: (): bool => HandleDigit(winID, 1),
      ['2'                             ]: (): bool => HandleDigit(winID, 2),
      ['3'                             ]: (): bool => HandleDigit(winID, 3),
      ['4'                             ]: (): bool => HandleDigit(winID, 4),
      ['5'                             ]: (): bool => HandleDigit(winID, 5),
      ['6'                             ]: (): bool => HandleDigit(winID, 6),
      ['7'                             ]: (): bool => HandleDigit(winID, 7),
      ['8'                             ]: (): bool => HandleDigit(winID, 8),
      ['9'                             ]: (): bool => HandleDigit(winID, 9),
  }
enddef
# }}}
# Callbacks {{{
def ClosedCallback(winID: number, result: any = '')
  DisableAllAutocommands()

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
  if Pane() == kHelpPane && get(sInvertedKeymap, key, '')->NotIn(kHelpActions)
    return false
  endif

  # TODO: if the popup should be dismissed, dismiss it and finish

  var handled = get(sActionMap, key, (): bool => false)()

  return handled
enddef
# }}}
# Style Picker Popup {{{
def StylePicker(
    hiGroup:         string,
    xPos:            number,
    yPos:            number,
    zIndex:          number       = sZ,
    bg:              string       = sBackground,
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
    highlight:   bg,
    line:        yPos,
    mapping:     allowKeyMapping,
    minwidth:    minWidth,
    padding:     [0, 1, 0, 1],
    pos:         'topleft',
    resize:      0,
    scrollbar:   1,
    tabpage:     0,
    title:       '',
    wrap:        0,
    zindex:      zIndex,
  })
  const bufnr = winbufnr(winID)

  setbufvar(bufnr, '&tabstop', &tabstop)  # Inherit global tabstop value

  InitHighlight(sColorMode, sStyleMode)
  InitTextPropertyTypes(bufnr)
  InitProperties(hiGroup, sFavoritePath)
  InitEffects(winID)
  SetActionMap(winID)

  ColorschemeChangedAutoCmd()

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
