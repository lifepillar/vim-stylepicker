vim9script

# Requirements Check {{{
if !has('popupwin') || !has('textprop') || v:version < 901
  echomsg 'Stylepicker requires Vim 9.1 compiled with popupwin and textprop.'
  finish
endif
# }}}
# Imports {{{
import 'libcolor.vim'       as libcolor
import 'libreactive.vim'    as react
import 'libstylepicker.vim' as ui
# }}}
# Types and Constants {{{
type TextProperty   = ui.TextProperty
type TextLine       = ui.TextLine
type LeafView       = ui.LeafView
type UpdatableView  = ui.UpdatableView
type SelectableView = ui.SelectableView
type ContainerView  = ui.ContainerView

const kNumColorsPerLine = 10

const kUltimateFallbackColor = {
  'bg': {'dark': '#000000', 'light': '#ffffff'},
  'fg': {'dark': '#ffffff', 'light': '#000000'},
  'sp': {'dark': '#ffffff', 'light': '#000000'},
  'ul': {'dark': '#ffffff', 'light': '#000000'},
}

const kDefaultQuotes = [
  'Absentem edit cum ebrio qui litigat.',
  'Accipere quam facere praestat iniuriam',
  'Amicum cum vides obliviscere miserias.',
  'Diligite iustitiam qui iudicatis terram.',
  'Etiam capillus unus habet umbram suam.',
  'Impunitas semper ad deteriora invitat.',
  'Mala tempora currunt sed peiora parantur',
  'Nec quod fuimusve sumusve, cras erimus',
  'Nec sine te, nec tecum vivere possum',
  'Quis custodiet ipsos custodes?',
  'Quod non vetat lex, hoc vetat fieri pudor.',
  'Vim vi repellere licet',
  'Vana gloria spica ingens est sine grano.',
]

const kAddToFavoritesKey    = "A"
const kBotKey               = ">"
const kCancelKey            = "X"
const kClearKey             = "Z"
const kCloseKey             = "x"
const kDecrementKey         = "\<left>"
const kDownKey              = "\<down>"
const kFgBgSpKey            = "\<s-tab>"
const kSpBgFgKey            = "\<tab>"
const kGrayPaneKey          = "G"
const kHelpKey              = "?"
const kHsbPaneKey           = "H"
const kIncrementKey         = "\<right>"
const kLeftClickKey         = "\<leftmouse>"
const kPasteKey             = "P"
const kPickKey              = "\<enter>"
const kRemoveKey            = "D"
const kRgbPaneKey           = "R"
const kSetColorKey          = "E"
const kSetHiGroupKey        = "N"
const kToggleBoldKey        = "B"
const kToggleItalicKey      = "I"
const kToggleReverseKey     = "V"
const kToggleStandoutKey    = "S"
const kToggleStrikeThruKey  = "K"
const kToggleTrackingKey    = "T"
const kToggleUndercurlKey   = "~"
const kToggleUnderdottedKey = "-"
const kToggleUnderdashedKey = "."
const kToggleUnderdoubleKey = "="
const kToggleUnderlineKey   = "U"
const kTopKey               = "<"
const kUpKey                = "\<up>"
const kYankKey              = "Y"

const kPrettyKey = {
  "\<left>":    "←",
  "\<right>":   "→",
  "\<up>":      "↑",
  "\<down>":    "↓",
  "\<tab>":     "↳",
  "\<s-tab>":   "⇧-↳",
  "\<enter>":   "↲",
  "\<s-enter>": "⇧-↲",
}
# }}}
# User Settings {{{
# TODO: export user settings
var allowkeymapping: bool         = get(g:, 'stylepicker_keymapping',   true                                    )
var ascii:           bool         = get(g:, 'stylepicker_ascii',        false                                   )
var background:      string       = get(g:, 'stylepicker_background',   'Normal'                                )
var borderchars:     list<string> = get(g:, 'stylepicker_borderchars',  ['─', '│', '─', '│', '╭', '╮', '╯', '╰'])
var favoritepath:    string       = get(g:, 'stylepicker_favoritepath', ''                                      )
var keyaliases:      dict<string> = get(g:, 'stylepicker_keyaliases',   {}                                      )
var marker:          string       = get(g:, 'stylepicker_marker',       ascii ? '>> ' : '❯❯ '                   )
var quotes:          list<string> = get(g:, 'stylepicker_quotes',       kDefaultQuotes                          )
var recent:          number       = get(g:, 'stylepicker_recent',       20                                      )
var star:            string       = get(g:, 'stylepicker_star',         ascii ? '*' : '★'                       )
var stepdelay:       float        = get(g:, 'stylepicker_stepdelay',    1.0                                     )
var zindex:          number       = get(g:, 'stylepicker_zindex',       50                                      )
# }}}
# Internal State {{{
var sRootView:     ContainerView                # The top view of the style picker
var sWinID:        number               = -1    # ID of the style picker popup
var sX:            number               = 0     # Horizontal position of the style picker
var sY:            number               = 0     # Vertical position of the style picker
var sPool:         list<react.Property> = []    # Global property pool. See :help libreactive-pools

class Config
  static var Ascii           = () => ascii
  static var Background      = () => background
  static var BorderChars     = () => borderchars
  static var ColorMode       = () => has('gui_running') || (has('termguicolors') && &termguicolors) ? 'gui' : 'cterm'
  static var FavoritePath    = () => favoritepath
  static var Gutter          = () => repeat(' ', strcharlen(marker))
  static var GutterWidth     = () => strcharlen(marker)
  static var KeyAliases      = () => keyaliases
  static var AllowKeyMapping = () => allowkeymapping
  static var Marker          = () => marker
  static var PopupWidth      = () => max([39 + strdisplaywidth(marker), 42])
  static var RandomQuotation = () => quotes[rand() % len(quotes)]
  static var Recent          = () => recent
  static var SliderSymbols   = () => ascii ? [" ", ".", ":", "!", "|", "/", "-", "=", "#"] : [" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", '█']
  static var Star            = () => star
  static var StyleMode       = () => has('gui_running') ? 'gui' : 'cterm'
  static var StepDelay       = () => stepdelay
  static var ZIndex          = () => zindex
endclass
# }}}
# Helper Functions {{{
def In(v: any, items: list<any>): bool
  return index(items, v) != -1
enddef

def NotIn(v: any, items: list<any>): bool
  return index(items, v) == -1
enddef

def Min(a: number, b: number): number
  if a < b
    return a
  endif
  return b
enddef

def Int(cond: bool): number
  return cond ? 1 : 0
enddef

def Prettify(key: string): string
  if Config.Ascii()
    return key
  endif

  return get(kPrettyKey, key, key)
enddef

def KeySymbol(defaultKeyCode: string): string
  var userKeyCode = get(Config.KeyAliases(), defaultKeyCode, defaultKeyCode)

  return Prettify(userKeyCode)
enddef

def Center(text: string, width: number): string
  var lPad = repeat(' ', (width + 1 - strwidth(text)) / 2)
  var rPad = repeat(' ', (width - strwidth(text)) / 2)

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

def Notification(
    winID: number,
    text: string,
    duration = 2000,
    width = Config.PopupWidth(),
    border = sBorder
    )
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

def WarningPopup(
    text: string, duration = 2000, border = sBorder, width = Config.PopupWidth()
    )
  popup_notification(Center(text, width), {
    pos:         'topleft',
    highlight:   'Normal',
    time:        duration,
    moved:       'any',
    mousemoved:  'any',
    borderchars: border,
  })
enddef

def ComputeScore(hexCol1: string, hexCol2: string): number
  #   #
  #  # Assign an integer score from zero to five to a pair of colors according
  # #  to how many criteria the pair satifies.
  ##   Thresholds follow W3C guidelines.
  var cr = libcolor.ContrastRatio(hexCol1, hexCol2)
  var cd = libcolor.ColorDifference(hexCol1, hexCol2)
  var bd = libcolor.BrightnessDifference(hexCol1, hexCol2)

  return Int(cr >= 3.0) + Int(cr >= 4.5) + Int(cr >= 7.0) + Int(cd >= 500) + Int(bd >= 125)
enddef

def HiGroupUnderCursor(): string
  #   #
  #  # Return the name of the highlight group under the cursor.
  # #  Return 'Normal' if the highlight group cannot be determined.
  ##
  var hiGrp: string = synIDattr(synIDtrans(synID(line('.'), col('.'), true)), 'name')

  if empty(hiGrp)
    return 'Normal'
  endif

  return hiGrp
enddef

def NormalizeAttr(attr: string, mode: string): string
  #   #
  #  # Vim does not have "ctermsp", but "ctermul". Since internally, this
  # #  script always uses "sp", the attribute's name must be converted for
  ##   cterm attributes.
  if attr == 'sp' && mode == 'cterm'
    return 'ul'
  endif

  return attr
enddef

def HiGroupColorValue(hiGroup: string, fgBgSp: string, mode: string): string
  #   #
  #  # When mode is 'gui', return either a hex value or 'NONE'.
  # #  When mode is 'cterm', return either a numeric string or 'NONE'.
  ##
  var attr = NormalizeAttr(fgBgSp, mode)
  var value = synIDattr(synIDtrans(hlID(hiGroup)), $'{attr}#', mode)

  if empty(value)
    return 'NONE'
  endif

  if mode == 'gui'
    if value[0] != '#' # In terminals, `value` may be a color name
      value = libcolor.RgbName2Hex(value, '')
    endif

    return value
  endif

  if value !~ '\m^\d\+$' # Try converting color name to number
    var num = libcolor.CtermColorNumber(value, 16)

    if num >= 0
      value = string(num)
    else
      value = 'NONE'
    endif
  endif

  return value
enddef

#
def GetHiGroupColor(
    hiGroup: string, fgBgSp: string, colorMode: string = Config.ColorMode()
    ): string
  #   # Try hard to determine a sensible hex value for the requested
  #  #  color attribute. Always prefer the GUI definition if it exists,
  # #   otherwise infer a hex value in other ways.
  ##    Always returns a hex color value.
  var value = HiGroupColorValue(hiGroup, fgBgSp, 'gui') # Try to get a GUI color

  if value != 'NONE' # Fast path
    return value
  endif

  # Try to infer a hex color value from the cterm definition
  if colorMode == 'cterm'
    var ctermValue = HiGroupColorValue(
      hiGroup, NormalizeAttr(fgBgSp, 'cterm'), 'cterm'
    )

    if ctermValue != 'NONE'
      var hex = libcolor.ColorNumber2Hex(str2nr(ctermValue))

      # Enable fast path for future calls (TODO: check for side effects)
      execute 'hi' hiGroup $'gui{fgBgSp}={hex}'

      return hex
    endif
  endif

  # Fallback strategy
  if fgBgSp == 'sp'
    return GetHiGroupColor(hiGroup, 'fg')
  elseif hiGroup == 'Normal'
    return kUltimateFallbackColor[&bg][fgBgSp]
  endif

  return GetHiGroupColor('Normal', fgBgSp)
enddef

def AltColor(hiGrp: string, fgBgSp: string): string
  #   #
  #  # Return the color 'opposite' to the current color attribute.
  # #  That is the background color if the input color attribute is
  ##   foreground; otherwise, it is the foreground color.
  if fgBgSp == 'bg'
    return GetHiGroupColor(hiGrp, 'fg')
  else
    return GetHiGroupColor(hiGrp, 'bg')
  endif
enddef

def LoadPalette(loadPath: string): list<string>
  var palette: list<string>

  try
    palette = readfile(loadPath)
  catch /.*/
    Error($'Could not load favorite colors: {v:exception}')
    palette = []
  endtry

  # Keep only lines matching hex colors
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

def ChooseGuiColor(): string
  #   #
  #  # Prompt the user to enter a hex value for a color.
  # #  Return an empty string if the input is invalid.
  ##
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
  #   #
  #  # Prompt the user to enter a numeric value for a terminal color and
  # #  return the value as a string.
  ##   Return an empty string if the input is invalid.
  var newCol = input('New terminal color [16-255]: ', '')
  echo "\r"
  const numCol = str2nr(newCol)

  if 16 <= numCol && numCol <= 255
    return libcolor.Xterm2Hex(numCol)
  endif

  return ''
enddef
# }}}
# Global Reactive State {{{
var pSelectedID = react.Property.new(0,        sPool) # Text property ID of the currently selected line
var pHiGroup    = react.Property.new('Normal', sPool) # Current highlight group
var pRecent     = react.Property.new([],       sPool) # List of recent colors
var pFavorite   = react.Property.new([],       sPool) # List of favorite colors
var pFgBgSp     = react.Property.new('fg',     sPool) # Current color attribute ('fg', 'bg', or 'sp')
var pEdited     = react.Property.new(false,    sPool) # Was the current color attribute modified by the style picker?

class ColorProperty extends react.Property
  #   #
  #  # A color property is backed by a Vim's highlight group, hence it needs
  # #  special Get/Set methods. That's why react.Property is specialized.
  ##
  def new(this.value, pool: list<react.Property>)
    super.Init(pool)
  enddef

  def Get(): string
    this.value = GetHiGroupColor(pHiGroup.Get(), pFgBgSp.Get())
    return super.Get()
  enddef

  def Set(newValue: string, force = false)
    if !force && newValue == this.value
      return
    endif

    var fgBgSp           = pFgBgSp.Get()
    var guiAttr          = 'gui' .. fgBgSp
    var ctermAttr        = 'cterm' .. NormalizeAttr(fgBgSp, 'cterm')
    var attrs: dict<any> = {name: pHiGroup.Get(), [guiAttr]: newValue}

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
  #   #
  #  # A style property is backed by a Vim's highlight group, hence it needs
  # #  special Get/Set methods. That's why react.Property is specialized.
  ##
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
    super.Init(pool)
  enddef

  def Get(): dict<bool>
    var hl = hlget(pHiGroup.Get(), true)[0]
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

    hlset([{name: pHiGroup.Get(), 'gui': style, 'cterm': style}])
    super.Set(value, force)
  enddef
endclass

# These are initialized automatically at the first Get() or Set()
var pColor = ColorProperty.new('#000000', sPool) # Value of the current color
var pStyle = StyleProperty.new({}, sPool) # Dictionary of style attributes
# }}}
# Autocommands {{{
def ColorschemeChangedAutoCmd()
  augroup StylePicker
    autocmd ColorScheme * InitHighlight(sColorMode, sStyleMode)
  augroup END
enddef

def TrackCursorAutoCmd()
  augroup StylePicker
    autocmd CursorMoved * pHiGroup.Set(HiGroupUnderCursor())
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
# Highlight Groups {{{
def InitHighlight()
  #   #
  #  #
  # #  Initialize the highlight groups used by the style picker.
  ##
  var mode         = Config.ColorMode()
  var style        = Config.StyleMode()
  var warnColor    = HiGroupColorValue('WarningMsg', 'fg', mode)
  var labelColor   = HiGroupColorValue('Label',      'fg', mode)
  var commentColor = HiGroupColorValue('Comment',    'fg', mode)

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
# }}}
# Text with Properties {{{
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

def InitTextPropertyTypes(bufnr: number)
  var propTypes = {
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
    prop_type_delete(propType, {bufnr: bufnr})
    prop_type_add(propType, propValue)
  endfor

  # Sync the text property with the current highlight group
  react.CreateEffect(() => {
    prop_type_change(kPropTypeCurrentHighlight, {bufnr: bufnr, highlight: pHiGroup.Get()})
  })
enddef

def BlankLine(width = 0): TextLine
  return TextLine.new(repeat(' ', width))
enddef

def WithStyle(line: TextLine, propType: string, from = 0, to = strcharlen(line.text), id = 1): TextLine
  line.props->add(TextProperty.new(propType, from, to, id))
  return line
enddef

def WithTitle(line: TextLine, from = 0, to = strcharlen(line.text)): TextLine
  return WithStyle(line, kPropTypeHeader, from, to)
enddef

def WithState(line: TextLine, enabled: bool, from = 0, to = strcharlen(line.text)): TextLine
  return WithStyle(line, enabled ? kPropTypeOn : kPropTypeOff, from, to)
enddef

def WithGuiHighlight(line: TextLine, from = 0, to = strcharlen(line.text)): TextLine
  return WithStyle(line, kPropTypeGuiHighlight, from, to)
enddef

def WithCtermHighlight(line: TextLine, from = 0, to = strcharlen(line.text)): TextLine
  return WithStyle(line, kPropTypeCtermHighlight, from, to)
enddef

def WithCurrentHighlight(line: TextLine, from = 0, to = strcharlen(line.text)): TextLine
  return WithStyle(line, kPropTypeCurrentHighlight, from, to)
enddef

def Tagged(line: TextLine, propType: string, id = 0): TextLine
  return WithStyle(line, propType, 0, 0, id)
enddef

def Labeled(line: TextLine, from = 0, to = strcharlen(line.text)): TextLine
  return WithStyle(line, kPropTypeLabel, from, to)
enddef
# }}}
# BlankView {{{
class BlankView extends LeafView
  def new(height = 1)
    this._content.Set(repeat([BlankLine()], height))
  enddef
endclass
# }}}
# HeaderView {{{
class HeaderView extends UpdatableView
  def new()
    super.Init()
  enddef

  def Update()
    var hiGroup = pHiGroup.Get()
    var fgBgSp  = pFgBgSp.Get()
    var aStyle  = pStyle.Get()

    var attrs   = 'BIUVSK' # Bold, Italic, Underline, reVerse, Standout, striKethrough
    var width   = Config.PopupWidth()
    var offset  = width - strcharlen(attrs)
    var spaces  = repeat(' ', width - strcharlen(hiGroup) - strcharlen(fgBgSp) - strcharlen(attrs) - 3)
    var text    = $"[{fgBgSp}] {hiGroup}{spaces}{attrs}"

    this._content.Set([TextLine.new(text)
      ->WithTitle(0, strcharlen(hiGroup) + strcharlen(fgBgSp) + 3)
      ->WithState(aStyle.bold,          offset,     offset + 1)
      ->WithState(aStyle.italic,        offset + 1, offset + 2)
      ->WithState(aStyle.underline,     offset + 2, offset + 3)
      ->WithState(aStyle.reverse,       offset + 3, offset + 4)
      ->WithState(aStyle.standout,      offset + 4, offset + 5)
      ->WithState(aStyle.strikethrough, offset + 5, offset + 6),
    ])
  enddef
endclass
# }}}
# SectionTitleView {{{
class SectionTitleView extends LeafView
  #   #
  #  # A static line with a Label highlight.
  # #
  ##
  def new(title: string)
    this._content.Set([TextLine.new(title)->Labeled()])
  enddef
endclass
# }}}
# GrayscaleSectionView {{{
class GrayscaleSectionView extends LeafView
  #   #
  #  #
  # # A static line with grayscale markers.
  ##
  def new()
    var gutterWidth = Config.GutterWidth()

    this._content.Set([
      TextLine.new('Grayscale')->Labeled(),
      BlankLine(Config.PopupWidth())
      ->WithStyle(kPropTypeGray000, gutterWidth +  5, gutterWidth + 7)
      ->WithStyle(kPropTypeGray025, gutterWidth + 13, gutterWidth + 15)
      ->WithStyle(kPropTypeGray050, gutterWidth + 21, gutterWidth + 23)
      ->WithStyle(kPropTypeGray075, gutterWidth + 29, gutterWidth + 31)
      ->WithStyle(kPropTypeGray100, gutterWidth + 37, gutterWidth + 39),
    ])
  enddef
endclass
# }}}
# SliderView {{{
# NOTE: for a slider to be rendered correctly, ambiwidth must be set to 'single'.
class SliderView extends SelectableView
  var name:     string               # The name of the slider (appears next to the slider)
  var step:     react.Property       # Increment/decrement step
  var value:    react.Property       # The value displayed by the slider
  var max:      number         = 255 # Maximum value of the slider
  var min:      number         = 0   # Minimum value of the slider

  def new(this.name, this.step, this.max = v:none, this.min = v:none)
    this.value = react.Property.new(this.min)
    super.Init()
  enddef

  def Update()
    var value       = this.value.Get()
    var gutter      = this.IsSelected() ? Config.Marker() : Config.Gutter()
    var gutterWidth = Config.GutterWidth()
    var width       = Config.PopupWidth() - gutterWidth - 6
    var symbols     = Config.SliderSymbols()
    var range       = this.max + 1 - this.min
    var whole       = value * width / range
    var frac        = value * width / (1.0 * range) - whole
    var bar         = repeat(symbols[-1], whole)
    var part_char   = symbols[1 + float2nr(floor(frac * 8))]
    var text        = printf("%s%s %3d %s%s", gutter, this.name, value, bar, part_char)

    this._content.Set([
      TextLine.new(text)
      ->Labeled(gutterWidth, gutterWidth + 1)
      ->Tagged(kPropTypeSlider)
      ->Tagged(kPropTypeSelectable)
    ])
  enddef

  def RespondToEvent(lnum: number, keyCode: string): bool
    if keyCode == kIncrementKey
      this.Increment(this.step.Get())

      return true
    endif

    if keyCode == kDecrementKey
      this.Decrement(this.step.Get())

      return true
    endif

    return false
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
# }}}
# StepView {{{
class StepView extends UpdatableView
  var value: react.Property

  def new()
    this.value = react.Property.new(1)
    super.Init()
  enddef

  def Update()
    this._content.Set([
      TextLine.new(printf('Step  %02d', this.value.Get()))->Labeled(0, 4),
    ])
  enddef
endclass
# }}}
# ColorInfoView {{{
class ColorInfoView extends UpdatableView
  def new()
    super.Init()
  enddef

  def Update()
    var hiGrp       = pHiGroup.Get()
    var fgBgSp      = pFgBgSp.Get()
    var curColor    = pColor.Get()

    var altColor    = AltColor(hiGrp, fgBgSp)
    var approxCol   = libcolor.Approximate(curColor)
    var approxAlt   = libcolor.Approximate(altColor)
    var contrast    = libcolor.ContrastColor(curColor)
    var contrastAlt = libcolor.Approximate(contrast)
    var guiScore    = ComputeScore(curColor, altColor)
    var termScore   = ComputeScore(approxCol.hex, approxAlt.hex)
    var delta       = printf("%.1f", approxCol.delta)[ : 2]
    var guiGuess    = (curColor != HiGroupColorValue(hiGrp, fgBgSp, 'gui') ? '!' : ' ')
    var ctermGuess  = (string(approxCol.xterm) != HiGroupColorValue(hiGrp, fgBgSp, 'cterm') ? '!' : ' ')

    var info = printf(
      $' {guiGuess}   {ctermGuess}  %s %-5S %3d/%s %-5S Δ{delta}',
      curColor[1 : ],
      repeat(Config.Star(), guiScore),
      approxCol.xterm,
      approxCol.hex[1 : ],
      repeat(Config.Star(), termScore)
    )

    execute $'hi stylePickerGuiColor guifg={contrast} guibg={curColor} ctermfg={contrastAlt.xterm} ctermbg={approxCol.xterm}'
    execute $'hi stylePickerTermColor guifg={contrast} guibg={approxCol.hex} ctermfg={contrastAlt.xterm} ctermbg={approxCol.xterm}'

    this._content.Set([
      TextLine.new(info)->WithGuiHighlight(0, 3)->WithCtermHighlight(4, 7),
    ])
  enddef
endclass
# }}}
# QuotationView {{{
class QuotationView extends LeafView
  def new()
    this._content.Set([
      TextLine.new(Center(Config.RandomQuotation(), Config.PopupWidth()))->WithCurrentHighlight(),
    ])
  enddef
endclass
# }}}
# ColorSliceView {{{
class ColorSliceView extends SelectableView
  #   #
  #  # A view of a segment of a color palette as a strip of colored cells:
  # #
  ##    0   1   2   3   4   5   6   7   8   9
  ##   ███ ███ ███ ███ ███ ███ ███ ███ ███ ███

  var _paletteRef: react.Property
  var _from:       number
  var _to:         number
  var _bufnr:      number
  var _header:     bool = true

  def new(
      this._paletteRef,
      this._from,
      this._to,
      this._bufnr,
      this._header = v:none
      )
    if this._from >= this._to
      Error($'Invalid color slice: from={this._from} >= to={this._to}')
      this._from = this._to
    endif

    super.Init()
  enddef

  def Update()
    var palette = this._paletteRef.Get()

    if this._from >= len(palette)
      this._content.Set([])
      return
    endif

    var content: list<TextLine> = []
    var gutter                  = this.IsSelected() ? Config.Marker() : Config.Gutter()
    var gutterWidth             = Config.GutterWidth()
    var from                    = this._from
    var to                      = Min(this._to, len(palette))

    if this._header
      var header = Config.Gutter() .. ' ' .. join(range(to - from), '   ')

      content->add(TextLine.new(header)->Labeled())
    endif

    var colorsLine = TextLine.new(
      gutter .. repeat(' ', Config.PopupWidth() - gutterWidth)
    )

    var k = 0

    while k < to - from
      var hexCol   = palette[from + k]
      var approx   = libcolor.Approximate(hexCol)
      var textProp = $'stylePickerPalette_{hexCol[1 : ]}_{k}' # FIXME: optimize name
      var column   = gutterWidth + 4 * k

      colorsLine->WithStyle(textProp, column, column + 3)
      # colorsLine->Tagged(kPropTypeSelectable, sliceID)

      # TODO: use hlset()?
      execute $'hi {textProp} guibg={hexCol} ctermbg={approx.xterm}'

      prop_type_delete(textProp, {bufnr: this._bufnr})
      prop_type_add(textProp, {bufnr: this._bufnr, highlight: textProp})

      ++k
    endwhile

    content->add(colorsLine)
    this._content.Set(content)
  enddef
endclass
# }}}
# FooterView {{{
class FooterView extends UpdatableView
  def new()
    super.Init()
  enddef

  def Update()
    this._content.Set([
      TextLine.new('TODO: this will be the footer')->Labeled(0, 5),
    ])
  enddef
endclass
# }}}
# HelpView {{{
class HelpView extends LeafView
  def new(visible = false)
    var s = [
      KeySymbol(kUpKey),                # 00
      KeySymbol(kDownKey),              # 01
      KeySymbol(kTopKey),               # 02
      KeySymbol(kBotKey),               # 03
      KeySymbol(kFgBgSpKey),            # 04
      KeySymbol(kSpBgFgKey),            # 05
      KeySymbol(kToggleTrackingKey),    # 06
      KeySymbol(kRgbPaneKey),           # 07
      KeySymbol(kHsbPaneKey),           # 08
      KeySymbol(kGrayPaneKey),          # 09
      KeySymbol(kCloseKey),             # 10
      KeySymbol(kCancelKey),            # 11
      KeySymbol(kHelpKey),              # 12
      KeySymbol(kToggleBoldKey),        # 13
      KeySymbol(kToggleItalicKey),      # 14
      KeySymbol(kToggleReverseKey),     # 15
      KeySymbol(kToggleStandoutKey),    # 16
      KeySymbol(kToggleStrikeThruKey),  # 17
      KeySymbol(kToggleUnderlineKey),   # 18
      KeySymbol(kToggleUndercurlKey),   # 19
      KeySymbol(kToggleUnderdashedKey), # 20
      KeySymbol(kToggleUnderdottedKey), # 21
      KeySymbol(kToggleUnderdoubleKey), # 22
      KeySymbol(kIncrementKey),         # 23
      KeySymbol(kDecrementKey),         # 24
      KeySymbol(kYankKey),              # 25
      KeySymbol(kPasteKey),             # 26
      KeySymbol(kSetColorKey),          # 27
      KeySymbol(kSetHiGroupKey),        # 28
      KeySymbol(kClearKey),             # 29
      KeySymbol(kAddToFavoritesKey),    # 30
      KeySymbol(kYankKey),              # 31
      KeySymbol(kRemoveKey),            # 32
      KeySymbol(kPickKey),              # 33
    ]
    var maxSymbolWidth = max(mapnew(s, (_, v) => strdisplaywidth(v)))

    # Pad with spaces, so all symbol strings have the same width
    map(s, (_, v) => v .. repeat(' ', maxSymbolWidth - strdisplaywidth(v)))

    this._content.Set([
      TextLine.new('Keyboard Controls')->WithTitle(),
      BlankLine(),
      TextLine.new('Popup')->Labeled(),
      TextLine.new($'{s[00]} Move up           {s[07]} RGB Pane'),
      TextLine.new($'{s[01]} Move down         {s[08]} HSB Pane'),
      TextLine.new($'{s[02]} Go to top         {s[09]} Grayscale'),
      TextLine.new($'{s[03]} Go to bottom      {s[10]} Close'),
      TextLine.new($'{s[04]} fg->bg->sp        {s[11]} Close and reset'),
      TextLine.new($'{s[05]} sp->bg->fg        {s[12]} Help pane'),
      TextLine.new($'{s[06]} Toggle tracking   '),
      BlankLine(),
      TextLine.new('Attributes')->Labeled(),
      TextLine.new($'{s[13]} Toggle boldface   {s[18]} Toggle underline'),
      TextLine.new($'{s[14]} Toggle italics    {s[19]} Toggle undercurl'),
      TextLine.new($'{s[15]} Toggle reverse    {s[20]} Toggle underdashed'),
      TextLine.new($'{s[16]} Toggle standout   {s[21]} Toggle underdotted'),
      TextLine.new($'{s[17]} Toggle strikethru {s[22]} Toggle underdouble'),
      BlankLine(),
      TextLine.new('Color')->Labeled(),
      TextLine.new($'{s[23]} Increment value   {s[27]} Set value'),
      TextLine.new($'{s[24]} Decrement value   {s[28]} Set hi group'),
      TextLine.new($'{s[25]} Yank color        {s[29]} Clear color'),
      TextLine.new($'{s[26]} Paste color       {s[30]} Add to favorites'),
      BlankLine(),
      TextLine.new('Recent & Favorites')->Labeled(),
      TextLine.new($'{s[31]} Yank color        {s[33]} Pick color'),
      TextLine.new($'{s[32]} Delete color'),
    ])
    this.SetVisible(visible)
  enddef
endclass
# }}}
# RgbContainerView {{{
class RgbContainerView extends ContainerView
  var colorRef: ColorProperty

  def new(this.colorRef, step: react.Property, visible = true)
    this.AddView(SliderView.new('R', step))
    this.AddView(SliderView.new('G', step))
    this.AddView(SliderView.new('B', step))
    this.SetVisible(visible)

    # Keep the color in sync with the RGB components
    react.CreateEffect(() => {
      if this.IsVisible()
        var [r, g, b] = libcolor.Hex2Rgb(this.colorRef.Get())
        (<SliderView>this.children[0]).value.Set(r)
        (<SliderView>this.children[1]).value.Set(g)
        (<SliderView>this.children[2]).value.Set(b)
      endif
    })

    react.CreateEffect(() => {
      if this.IsVisible()
        this.colorRef.Set(
          libcolor.Rgb2Hex(
          (<SliderView>this.children[0]).value.Get(),
          (<SliderView>this.children[1]).value.Get(),
          (<SliderView>this.children[2]).value.Get()
          )
        )
      endif
    })
  enddef
endclass
# }}}
# HsbContainerView {{{
class HsbContainerView extends ContainerView
  var colorRef: ColorProperty

  def new(this.colorRef, step: react.Property, visible = true)
    this.AddView(SliderView.new('H', step))
    this.AddView(SliderView.new('S', step))
    this.AddView(SliderView.new('B', step))
    this.SetVisible(visible)

    # Keep the color in sync with the RGB components
    react.CreateEffect(() => {
      if this.IsVisible()
        var [h, s, b] = libcolor.Hex2Hsv(this.colorRef.Get())
        (<SliderView>this.children[0]).value.Set(h)
        (<SliderView>this.children[1]).value.Set(s)
        (<SliderView>this.children[2]).value.Set(b)
      endif
    })

    react.CreateEffect(() => {
      if this.IsVisible()
        this.colorRef.Set(
          libcolor.Hsv2Hex(
          (<SliderView>this.children[0]).value.Get(),
          (<SliderView>this.children[1]).value.Get(),
          (<SliderView>this.children[2]).value.Get()
          )
        )
      endif
    })
  enddef
endclass
# }}}
# GrayscaleContainerView {{{
class GrayscaleContainerView extends ContainerView
  var colorRef: ColorProperty

  def new(this.colorRef, step: react.Property, visible = false)
    this.AddView(GrayscaleSectionView.new())
    this.AddView(SliderView.new('G', step))
    this.SetVisible(visible)

    # Keep the color in sync with the grayscale level
    react.CreateEffect(() => {
      if this.IsVisible()
        var gray = libcolor.Hex2Gray(this.colorRef.Get())
        (<SliderView>this.children[1]).value.Set(gray)
      endif
    })

    # The grayscale level is synced back to the color value only if the user
    # explicitly edits the grayscale color (otherwise everything would
    # eventually become gray).
    react.CreateEffect(() => {
      if this.IsVisible() && pEdited.Get()
        var sliderValue: number = (<SliderView>this.children[1]).value.Get()
        this.colorRef.Set(libcolor.Gray2Hex(sliderValue))
      endif
    })
  enddef
endclass
# }}}
# ColorPaletteContainerView {{{
class ColorPaletteContainerView extends ContainerView
  var paletteRef: react.Property # List of (recent or favorite) colors
  var titleView:  SectionTitleView
  var bufnr:      number
  var numColorsPerLine = kNumColorsPerLine

  def new(
      this.paletteRef,
      title: string,
      this.bufnr,
      this.numColorsPerLine = v:none
      )
    this.AddView(SectionTitleView.new(title))

    react.CreateEffect(() => {
      this.AddColorSlices_()
    })
  enddef

  def AddColorSlices_() # Dynamically add slices to accommodate all the colors
    var palette   = this.paletteRef.Get()
    var numColors = len(palette)
    var numSlots  = (len(this.children) - 1) * this.numColorsPerLine

    while numSlots < numColors
      var new_slice = ColorSliceView.new(
        this.paletteRef,
        numSlots,
        numSlots + this.numColorsPerLine,
        this.bufnr
      )

      this.AddView(new_slice)
      ui.StartRendering(new_slice, this.bufnr)
      numSlots += this.numColorsPerLine
    endwhile
  enddef
endclass
# }}}
# StylePickerContainerView {{{
class StylePickerContainerView extends ContainerView
  var _rgbSliderContainerView:       RgbContainerView
  var _hsbSliderContainerView:       HsbContainerView
  var _grayscaleSliderContainerView: GrayscaleContainerView

  def new(
      bufnr: number,
      colorRef: ColorProperty,
      pRecentRef: react.Property,
      pFavoriteRef: react.Property
      )
    var stepView = StepView.new()

    this._rgbSliderContainerView       = RgbContainerView.new(colorRef, stepView.value)
    this._hsbSliderContainerView       = HsbContainerView.new(colorRef, stepView.value, false)
    this._grayscaleSliderContainerView = GrayscaleContainerView.new(colorRef, stepView.value, false)

    this.AddView(HeaderView.new())
    this.AddView(BlankView.new())
    this.AddView(this._rgbSliderContainerView)
    this.AddView(this._hsbSliderContainerView)
    this.AddView(this._grayscaleSliderContainerView)
    this.AddView(stepView)
    this.AddView(BlankView.new())
    this.AddView(ColorInfoView.new())
    this.AddView(BlankView.new())
    this.AddView(QuotationView.new())
    this.AddView(BlankView.new())
    this.AddView(ColorPaletteContainerView.new(pRecentRef,   'Recent Colors',   bufnr))
    this.AddView(ColorPaletteContainerView.new(pFavoriteRef, 'Favorite Colors', bufnr))
  enddef

  def ShowRgb()
    this.SetVisible(true)
    this._hsbSliderContainerView.SetVisible(false)
    this._grayscaleSliderContainerView.SetVisible(false)
  enddef

  def ShowHsb()
    this.SetVisible(true)
    this._grayscaleSliderContainerView.SetVisible(false)
    this._rgbSliderContainerView.SetVisible(false)
  enddef

  def ShowGrayscale()
    this.SetVisible(true)
    this._rgbSliderContainerView.SetVisible(false)
    this._hsbSliderContainerView.SetVisible(false)
  enddef

  def RespondToEvent(lnum: number, keyCode: string): bool
    if keyCode == kRgbPaneKey
      this.ShowRgb()

      return true
    endif

    if keyCode == kHsbPaneKey
      this.ShowHsb()

      return true
    endif

    if keyCode == kGrayPaneKey
      this.ShowGrayscale()

      return true
    endif

    return super.RespondToEvent(lnum, keyCode)
  enddef
endclass
# }}}
# RootContainerView {{{
class RootContainerView extends ContainerView
  var _stylePickerContainerView: StylePickerContainerView
  var _helpView:                 HelpView
  var _actionMap:                dict<func()>

  def new(
      bufnr:       number,
      colorRef:    ColorProperty,
      recentRef:   react.Property,
      favoriteRef: react.Property
      )
    this._stylePickerContainerView = StylePickerContainerView.new(
      bufnr, colorRef, recentRef, favoriteRef
    )
    this._helpView = HelpView.new()
    this.AddView(this._stylePickerContainerView)
    this.AddView(this._helpView)
  enddef

  def RespondToEvent(lnum: number, keyCode: string): bool
    if keyCode == kCancelKey
      ActionCancel()

      return true
    endif

    if keyCode == kHelpKey
      this._stylePickerContainerView.SetVisible(false)
      this._helpView.SetVisible(true)

      return true
    endif

    if keyCode == kUpKey
    endif

    if keyCode->In([kRgbPaneKey, kHsbPaneKey, kGrayPaneKey])
      this._helpView.SetVisible(false)
    endif

    return this._stylePickerContainerView.RespondToEvent(lnum, keyCode)
  enddef
endclass
# }}}

# Event Processing {{{
def ActionCancel()
  popup_close(sWinID)

  # TODO: revert only the changes of the stylepicker
  if exists('g:colors_name') && !empty('g:colors_name')
    execute 'colorscheme' g:colors_name
  endif
enddef

def ActionLeftClick()
  var mousepos = getmousepos()

  if mousepos.winid == sWinID
    # TODO: dispatch event
    echo $'Mouse pressed at line {mousepos.line}, column {mousepos.column}'
  endif
enddef

def ClosedCallback(winid: number, result: any = '')
  DisableAllAutocommands()

  sX     = popup_getoptions(winid).col
  sY     = popup_getoptions(winid).line
  sWinID = -1
enddef

def HandleEvent(winid: number, rawKeyCode: string): bool
  var keyCode = get(Config.KeyAliases(), rawKeyCode, rawKeyCode)

  return sRootView.RespondToEvent(3, keyCode)
enddef
# }}}

# Style Picker Popup {{{
def StylePickerPopup(
    hiGroup:         string,
    xPos:            number,
    yPos:            number,
    zIndex:          number       = Config.ZIndex(),
    bg:              string       = Config.Background(),
    borderChars:     list<string> = Config.BorderChars(),
    minWidth:        number       = Config.PopupWidth(),
    allowKeyMapping: bool         = Config.AllowKeyMapping()
    ): number
  var winid = popup_create('', {
    border:      [1, 1, 1, 1],
    borderchars: borderChars,
    callback:    ClosedCallback,
    close:       'button',
    col:         xPos,
    cursorline:  false,
    drag:        true,
    filter:      HandleEvent,
    filtermode:  'n',
    hidden:      true,
    highlight:   bg,
    line:        yPos,
    mapping:     allowKeyMapping,
    minwidth:    minWidth,
    padding:     [0, 1, 0, 1],
    pos:         'topleft',
    resize:      false,
    scrollbar:   true,
    tabpage:     0,
    title:       '',
    wrap:        false,
    zindex:      zIndex,
  })
  const bufnr = winbufnr(winid)

  setbufvar(bufnr, '&tabstop', &tabstop)  # Inherit global tabstop value

  for property in sPool
    property.Clear()
  endfor

  InitHighlight()
  InitTextPropertyTypes(bufnr)
  pHiGroup.Set(empty(hiGroup) ? HiGroupUnderCursor() : hiGroup)
  pEdited.Set(false)

  if !empty(Config.FavoritePath())
    pFavorite.Set(LoadPalette(Config.FavoritePath()))
  endif

  sRootView = RootContainerView.new(bufnr, pColor, pRecent, pFavorite)

  ui.StartRendering(sRootView, bufnr)

  if empty(hiGroup)
    TrackCursorAutoCmd()
  endif

  popup_show(winid)

  return winid
enddef
# }}}
# Public Interface {{{
export def Open(hiGroup = '')
  if sWinID > 0 # FIXME: && the popup still exists
    popup_show(sWinID)
    return
  endif

  sWinID = StylePickerPopup(hiGroup, sX, sY)
enddef
# }}}
