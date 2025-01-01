vim9script

# Requirements Check {{{
if !has('popupwin') || !has('textprop') || v:version < 901
  echomsg 'Stylepicker requires Vim 9.1 compiled with popupwin and textprop.'
  finish
endif
# }}}
# Imports {{{
import 'libcolor.vim'    as libcolor
import 'libreactive.vim' as react
# }}}
# Types and Constants {{{
type ActionCode   = string
type HexColor     = string

const kMainPane                = 0
const kRGBPane                 = 1
const kHSBPane                 = 2
const kGrayPane                = 3
const kHelpPane                = 99
const kNumColorsPerLine        = 10

# Selectable items
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

# Events
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
const kActionLeftClick:         ActionCode = 'clk'
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

# Actions in the help pane
const kHelpAction = [
  kActionRgbPane,
  kActionGrayPane,
  kActionHsbPane,
  kActionCancel,
  kActionClose
]

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
var sEventHandled: bool                 = false # Set to true if a key or mouse event was handled
var sKeyCode:      string               = ''    # Last key pressed
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

def Init()
enddef
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
# Global Reactive State {{{
def GetSet(value: any, pool = sPool): list<any>
  var p_ = react.Property.new(value, pool)
  return [p_, p_.Get, p_.Set]
enddef

var [pPaneID,     PaneID,       SetPaneID    ] = GetSet(0)        # ID of the current pane
var [pSelectedID, SelectedID,   SetSelectedID] = GetSet(0)        # Text property ID of the currently selected line
var [pHiGroup,    HiGroup,      SetHiGroup   ] = GetSet('Normal') # Current highlight group
var [pRecent,     Recent,       SetRecent    ] = GetSet([])       # List of recent colors
var [pFavorite,   Favorite,     SetFavorite  ] = GetSet([])       # List of favorite colors
var [pFgBgSp,     FgBgSp,       SetFgBgSp    ] = GetSet('fg')     # Current color attribute ('fg', 'bg', or 'sp')
var [pEdited,     Edited,       SetEdited    ] = GetSet(false)    # Was the current color attribute modified by the style picker?

class ColorProperty extends react.Property
  #   #
  #  # A color property is backed by a Vim's highlight group, hence it needs
  # #  special Get/Set methods. That's why react.Property is specialized.
  ##
  def new(this.value, pool: list<react.Property>)
    super.Init(pool)
  enddef

  def Get(): string
    this.value = GetHiGroupColor(HiGroup(), FgBgSp())
    return super.Get()
  enddef

  def Set(newValue: string, force = false)
    if !force && newValue == this.value
      return
    endif

    var fgBgSp           = FgBgSp()
    var guiAttr          = 'gui' .. fgBgSp
    var ctermAttr        = 'cterm' .. NormalizeAttr(fgBgSp, 'cterm')
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

def InitReactiveState(hiGroup: string)
  SetHiGroup(empty(hiGroup) ? HiGroupUnderCursor() : hiGroup)
  SetEdited(false)
  SetPaneID(kMainPane)
  SetSelectedID(kRedSlider)

  if !empty(Config.FavoritePath())
    SetFavorite(LoadPalette(Config.FavoritePath()))
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
class TextProperty
  var type: string     # Text property type (created with prop_type_add())
  var xl:   number     # 0-based start position of the property, in characters (composed chars not counted separately)
  var xr:   number     # One past the end position of the property
  var id:   number = 1 # Optional property ID

  def new(this.type, this.xl, this.xr, this.id = v:none)
    if this.xr < this.xl
      throw $'Invalid text property range: [{this.xl},{this.xr}] (type = {this.type})'
    endif
  enddef
endclass

class TextLine
  var text: string
  var props: list<TextProperty> = []

  def Format(): dict<any>
    var props: list<dict<any>> = []

    for prop in this.props
      var xl = byteidx(this.text, prop.xl)
      var xr = byteidx(this.text, prop.xr)
      props->add({col: 1 + xl, length: xr - xl, type: prop.type, id: prop.id})
    endfor

    return {text: this.text, props: props}
  enddef
endclass

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
# Views {{{
interface IView
  def Body(): list<TextLine>
endinterface

interface IUpdatableView
  def Update()
endinterface

interface ISelectableView
  def Selected(state: bool)
endinterface

class BaseView implements IView
  var hidden   = react.Property.new(false)
  var _content = react.Property.new([])

  def Hidden(state: bool)
    this.hidden.Set(state)
  enddef

  def Body(): list<TextLine>
    if this.hidden.Get()
      return []
    endif

    return this._content.Get()
  enddef
endclass

class BaseUpdatableView extends BaseView implements IUpdatableView
  def Init()
    react.CreateEffect(this.Update)
  enddef

  def Update()
  enddef
endclass

class BaseSelectableView extends BaseUpdatableView implements ISelectableView
  var selected = react.Property.new(false)

  def Selected(state: bool)
    this.selected.Set(state)
  enddef
endclass

# BlankView {{{
class BlankView extends BaseView
  def new(height = 1)
    this._content.Set(repeat([BlankLine()], height))
  enddef
endclass
# }}}
# HeaderView {{{
class HeaderView extends BaseUpdatableView
  def new()
    super.Init()
  enddef

  def Update()
    var hiGroup = HiGroup()
    var fgBgSp  = FgBgSp()
    var aStyle  = Style()

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
      BlankLine(),
    ])
  enddef
endclass
# }}}
# SectionTitleView {{{
class SectionTitleView extends BaseView
  #   #
  #  #
  # # A static line with a Label highlight.
  ##
  def new(title: string)
    this._content.Set([TextLine.new(title)->Labeled()])
  enddef
endclass
# }}}
# GrayscaleSectionView {{{
class GrayscaleSectionView extends BaseView
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
class SliderView extends BaseSelectableView
  var name:     string               # The name of the slider (appears next to the slider)
  var value:    react.Property       # The value displayed by the slider
  var max:      number         = 255 # Maximum value of the slider
  var min:      number         = 0   # Minimum value of the slider

  def new(this.name, this.max = v:none, this.min = v:none)
    this.value = react.Property.new(this.min)
    super.Init()
  enddef

  def Update()
    var value       = this.value.Get()
    var gutter      = this.selected.Get() ? Config.Marker() : Config.Gutter()
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
class StepView extends BaseUpdatableView
  var value: react.Property

  def new()
    this.value = react.Property.new(1)
    super.Init()
  enddef

  def Update()
    this._content.Set([
      TextLine.new(printf('Step  %02d', this.value.Get()))->Labeled(0, 4),
      BlankLine(),
    ])
  enddef
endclass
# }}}
# ColorInfoView {{{
class ColorInfoView extends BaseUpdatableView
  def new()
    super.Init()
  enddef

  def Update()
    var hiGrp       = HiGroup()
    var fgBgSp      = FgBgSp()
    var curColor    = Color()

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
      BlankLine(),
    ])
  enddef
endclass
# }}}
# QuotationView {{{
class QuotationView extends BaseView
  def Update()
    this._content.Set([
      TextLine.new(Center(Config.RandomQuotation(), Config.PopupWidth()))->WithCurrentHighlight(),
      BlankLine(),
    ])
  enddef
endclass
# }}}
# ColorSliceView {{{
class ColorSliceView extends BaseSelectableView
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

  static var sliceID = 0

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

    sliceID += 1
  enddef

  def Update()
    var palette = this._paletteRef.Get()

    if this._from >= len(palette)
      return
    endif

    var content: list<TextLine> = []
    var selected                = this.selected.Get()
    var gutter                  = selected ? Config.Marker() : Config.Gutter()
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
      var textProp = $'stylePickerPalette_{sliceID}_{k}'
      var column   = gutterWidth + 4 * k

      colorsLine->WithStyle(textProp, column, column + 3)
      colorsLine->Tagged(kPropTypeSelectable, sliceID)

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
class FooterView extends BaseUpdatableView
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
# }}}

# Rendering {{{
class FrameBuffer
  var bufnr: number

  def Expand(lnum: number)
    var bufinfo = getbufinfo(this.bufnr)[0]

    if lnum <= bufinfo.linecount
      return
    endif

    var lines = repeat([''], lnum - bufinfo.linecount)

    appendbufline(this.bufnr, '$', lines)
  enddef

  def AddTextProperties(lnum: number, line: TextLine)
    for prop in line.props
      var xl = byteidx(line.text, prop.xl)
      var xr = byteidx(line.text, prop.xr)

      prop_add(lnum, 1 + xl, {
        type:   prop.type,
        length: xr - xl,
        bufnr:  this.bufnr,
        id:     prop.id,
      })
    endfor
  enddef

  def DrawLines(lnum: number, lines: list<TextLine>)
    this.Expand(lnum + len(lines) - 1)

    var i = lnum

    for line in lines
      setbufline(this.bufnr, i, line.text)
      this.AddTextProperties(i, line)
      ++i
    endfor
  enddef

  def Shift(lnum: number, amount: number)
    appendbufline(this.bufnr, lnum, repeat([''], amount))
  enddef

  def DeleteLines(first: number, last: number = first)
    deletebufline(this.bufnr, first, last)
  enddef
endclass

class Pane
  var id:           number
  var _framebuffer: FrameBuffer
  var _heights:     list<number> = [0] # Current height of each member view (first view has index 1)

  def Bufnr(): number
    return this._framebuffer.bufnr
  enddef

  def Render(view: IView, viewNumber: number)
    if PaneID() != this.id
      return
    endif

    var lnum       = 1 + reduce(this._heights[0 : (viewNumber - 1)], (acc, val) => acc + val)
    var body       = view.Body()
    var old_height = this._heights[viewNumber]
    var new_height = len(body)

    if new_height != old_height # Adjust the vertical space to the new size of the view
      if new_height > old_height
        this._framebuffer.Shift(lnum, new_height - old_height)
      else
        this._framebuffer.DeleteLines(lnum, 1 + lnum + new_height - old_height)
      endif

      this._heights[viewNumber] = new_height
    endif

    this._framebuffer.DrawLines(lnum, body)
  enddef

  def Add(view: IView)
    this._heights->add(len(view.Body()))

    var n = len(this._heights) - 1

    react.CreateEffect(() => this.Render(view, n))
  enddef
endclass
# }}}

# UI Components {{{
class RgbSliderGroup implements IView
  var colorRef:    react.Property
  var redSlider:   SliderView
  var greenSlider: SliderView
  var blueSlider:  SliderView
  var visible:     react.Property = react.Property.new(false)

  def new(this.colorRef, visible = false)
    this.redSlider   = SliderView.new('R')
    this.greenSlider = SliderView.new('G')
    this.blueSlider  = SliderView.new('B')
    this.visible.Set(visible)

    # Keep the color in sync with the RGB components
    react.CreateEffect(() => {
      if this.visible.Get()
        var [r, g, b] = libcolor.Hex2Rgb(this.colorRef.Get())
        this.redSlider.value.Set(r)
        this.greenSlider.value.Set(g)
        this.blueSlider.value.Set(b)
      endif
    })

    react.CreateEffect(() => {
      if this.visible.Get()
        this.colorRef.Set(
          libcolor.Rgb2Hex(
          this.redSlider.value.Get(),
          this.greenSlider.value.Get(),
          this.blueSlider.value.Get()
          )
        )
      endif
    })

    this.Hidden(!visible)
  enddef

  def Body(): list<TextLine>
    return this.redSlider.Body() + this.greenSlider.Body() + this.blueSlider.Body()
  enddef

  def Hidden(state: bool)
    this.redSlider.Hidden(state)
    this.greenSlider.Hidden(state)
    this.blueSlider.Hidden(state)
    this.visible.Set(!state)
  enddef
endclass

class HsbSliderGroup implements IView
  var colorRef:         react.Property
  var hueSlider:        SliderView
  var saturationSlider: SliderView
  var brightnessSlider: SliderView
  var visible:          react.Property = react.Property.new(false)

  def new(this.colorRef, visible = false)
    this.hueSlider        = SliderView.new('H')
    this.saturationSlider = SliderView.new('S')
    this.brightnessSlider = SliderView.new('B')
    this.visible.Set(visible)

    # Keep the color in sync with the HSB components
    react.CreateEffect(() => {
      if this.visible.Get()
        var [h, s, b] = libcolor.Hex2Hsv(this.colorRef.Get())
        this.hueSlider.value.Set(h)
        this.saturationSlider.value.Set(s)
        this.brightnessSlider.value.Set(b)
      endif
    })

    react.CreateEffect(() => {
      if this.visible.Get()
        this.colorRef.Set(
          libcolor.Hsv2Hex(
          this.hueSlider.value.Get(),
          this.saturationSlider.value.Get(),
          this.brightnessSlider.value.Get()
          )
        )
      endif
    })

    this.Hidden(!visible)
  enddef

  def Body(): list<TextLine>
    return this.hueSlider.Body() + this.saturationSlider.Body() + this.brightnessSlider.Body()
  enddef

  def Hidden(state: bool)
    this.hueSlider.Hidden(state)
    this.saturationSlider.Hidden(state)
    this.brightnessSlider.Hidden(state)
    this.visible.Set(!state)
  enddef
endclass

class GrayscaleSliderGroup implements IView
  var colorRef:        react.Property
  var header:          GrayscaleSectionView
  var grayscaleSlider: SliderView
  var visible:         react.Property = react.Property.new(false)

  def new(this.colorRef, visible = false)
    this.header           = GrayscaleSectionView.new()
    this.grayscaleSlider  = SliderView.new('G')

    # Keep the color in sync with the grayscale level
    react.CreateEffect(() => {
      if this.visible.Get()
        var gray = libcolor.Hex2Gray(this.colorRef.Get())
        this.grayscaleSlider.value.Set(gray)
      endif
    })

    # FIXME; this "greyfies" everything (must execute only if Edited())
    # react.CreateEffect(() => {
    #   if this.visible.Get()
    #     this.colorRef.Set(libcolor.Gray2Hex(this.grayscaleSlider.value.Get()))
    #   endif
    # })

    this.Hidden(!visible)
  enddef

  def Body(): list<TextLine>
    return this.header.Body() + this.grayscaleSlider.Body()
  enddef

  def Hidden(state: bool)
    this.header.Hidden(state)
    this.grayscaleSlider.Hidden(state)
    this.visible.Set(!state)
  enddef
endclass

class ColorPaletteGroup implements IView
  var paletteRef:       react.Property # List of (recent or favorite) colors
  var bufnr:            number
  var titleView:        SectionTitleView
  var colorSliceViews:  list<ColorSliceView> = []
  var numColorsPerLine: number               = kNumColorsPerLine

  def new(
      this.paletteRef,
      title: string,
      this.bufnr,
      this.numColorsPerLine = v:none
      )
    this.titleView = SectionTitleView.new(title)
    this.AddColorSlices_()
  enddef

  def Body(): list<TextLine>
    var content: list<TextLine> = []

    content += this.titleView.Body()

    this.AddColorSlices_()

    for view in this.colorSliceViews
      content += view.Body()
    endfor

    return content
  enddef

  def Hidden(state: bool)
    this.titleView.Hidden(state)

    for view in this.colorSliceViews
      view.Hidden(state)
    endfor
  enddef

  def AddColorSlices_() # Dynamically add slices to accommodate all the colors
    var palette   = this.paletteRef.Get()
    var numColors = len(palette)
    var numSlots  = len(this.colorSliceViews) * this.numColorsPerLine

    while numSlots < numColors
      this.colorSliceViews->add(ColorSliceView.new(
        this.paletteRef,
        numSlots,
        numSlots + this.numColorsPerLine,
        this.bufnr
      ))
      numSlots += this.numColorsPerLine
    endwhile
  enddef
endclass

class MainPane
  var colorRef:            react.Property
  var recentColorsRef:     react.Property
  var favoriteColorsRef:   react.Property
  var favoriteSliceViews:  react.Property
  var pane:                Pane
  var headerView:          HeaderView
  var rgbSliderGroup:      RgbSliderGroup
  var hsbSliderGroup:      HsbSliderGroup
  var graySliderGroup:     GrayscaleSliderGroup
  var stepView:            StepView
  var colorInfoView:       ColorInfoView
  var quotationView:       QuotationView
  var recentColorsGroup:   ColorPaletteGroup
  var favoriteColorsGroup: ColorPaletteGroup
  var footerView:          FooterView

  var numColorsPerLine = kNumColorsPerLine

  def new(framebuffer: FrameBuffer, this.colorRef, this.favoriteColorsRef)
    this.pane                = Pane.new(kMainPane, framebuffer)
    this.headerView          = HeaderView.new()
    this.rgbSliderGroup      = RgbSliderGroup.new(this.colorRef, true)
    this.hsbSliderGroup      = HsbSliderGroup.new(pColor, true)
    this.graySliderGroup     = GrayscaleSliderGroup.new(pColor, false)
    this.stepView            = StepView.new()
    this.colorInfoView       = ColorInfoView.new()
    this.quotationView       = QuotationView.new()
    this.footerView          = FooterView.new()
    this.recentColorsGroup   = ColorPaletteGroup.new(
      pRecent, 'Recent colors', framebuffer.bufnr
    )
    this.favoriteColorsGroup = ColorPaletteGroup.new(
      pFavorite, 'Favorite colors', framebuffer.bufnr
    )
    var blankView = BlankView.new()

    this.pane.Add(this.headerView)
    this.pane.Add(this.rgbSliderGroup.redSlider)
    this.pane.Add(this.rgbSliderGroup.greenSlider)
    this.pane.Add(this.rgbSliderGroup.blueSlider)
    this.pane.Add(this.hsbSliderGroup.hueSlider)
    this.pane.Add(this.hsbSliderGroup.saturationSlider)
    this.pane.Add(this.hsbSliderGroup.brightnessSlider)
    this.pane.Add(this.graySliderGroup.grayscaleSlider)
    this.pane.Add(this.stepView)
    this.pane.Add(this.colorInfoView)
    this.pane.Add(this.quotationView)
    this.pane.Add(this.recentColorsGroup)
    this.pane.Add(blankView)
    this.pane.Add(this.favoriteColorsGroup)
    this.pane.Add(blankView)
    this.pane.Add(this.footerView)

    this.rgbSliderGroup.redSlider.Selected(true)
  enddef
endclass
# }}}
# Effects {{{
def InitEffects(bufnr: number)
  # Sync the text property for the current highlight group
  react.CreateEffect(() => {
    prop_type_change(kPropTypeCurrentHighlight, {bufnr: bufnr, highlight: HiGroup()})
  })
enddef
# }}}
# Actions {{{
def ActionNoop()
enddef

def ActionIntercept()
  sEventHandled = true
enddef

def ActionLeftClick()
  var mousepos = getmousepos()

  if mousepos.winid == sWinID
    # TODO: dispatch event
    echo $'Mouse pressed at line {mousepos.line}, column {mousepos.column}'
    # sEventHandled = true
  endif
enddef

def ActionKeyPress()
  var event = KeyEvent.new('name goes here')
enddef
# }}}
# Default Key Map {{{
const kDefaultKeyMap = {
  "\<LeftMouse>": ActionLeftClick,
  "A":            ActionNoop,
  ">":            ActionNoop,
  "X":            ActionNoop,
  "Z":            ActionNoop,
  "x":            ActionNoop,
  "\<left>":      ActionIntercept,
  "\<down>":      ActionNoop,
  "\<s-tab>":     ActionNoop,
  "\<tab>":       ActionNoop,
  "G":            ActionNoop,
  "?":            ActionNoop,
  "H":            ActionNoop,
  "\<right>":     ActionNoop,
  "P":            ActionNoop,
  "\<enter>":     ActionNoop,
  "D":            ActionNoop,
  "R":            ActionNoop,
  "E":            ActionNoop,
  "N":            ActionNoop,
  "B":            ActionNoop,
  "I":            ActionNoop,
  "V":            ActionNoop,
  "S":            ActionNoop,
  "K":            ActionNoop,
  "T":            ActionNoop,
  "~":            ActionNoop,
  "-":            ActionNoop,
  ".":            ActionNoop,
  "=":            ActionNoop,
  "U":            ActionNoop,
  "<":            ActionNoop,
  "\<up>":        ActionNoop,
  "Y":            ActionNoop,
}
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
# }}}
# Sliders {{{
# NOTE: for a slider to be rendered correctly, ambiwidth must be set to 'single'.
class Slider
  var id:       number
  var name:     string
  var value:    react.Property
  var max:      number = 255
  var min:      number = 0
  var selected: bool   = false
  var prefix:   string = ''
  var width:    Config.PopupWidth() - 6  # - sGutterWidth  FIXME
  var symbols:  Config.SliderSymbols()

  def new(this.id, this.name, this.value)
    react.CreateEffect(() => {
      if self.selected
        if sKeyCode == "\<left>"
          self.Decrement(1)
        elseif sKeyCode == "\<right>"
          self.Increment(1)
        endif
      endif
    })
  enddef

  def Body(): list<string>
    var value     = this.value.Get()
    var range     = this.max + 1 - this.min
    var whole     = value * this.width / range
    var frac      = value * this.width / (1.0 * range) - whole
    var bar       = repeat(this.symbols[-1], whole)
    var part_char = this.symbols[1 + float2nr(floor(frac * 8))]
    var text      = printf("%s%s %3d %s%s", this.prefix, this.name, value, bar, part_char)

    return text
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
# Event Processing {{{
def ClosedCallback(winid: number, result: any = '')
  DisableAllAutocommands()

  sX     = popup_getoptions(winid).col
  sY     = popup_getoptions(winid).line
  sWinID = -1
enddef

def HandleEvent(winid: number, rawKeyCode: string): bool
  sEventHandled = false

  sKeyCode = get(Config.KeyAliases(), rawKeyCode, rawKeyCode)

  if kDefaultKeyMap->has_key(sKeyCode)
    kDefaultKeyMap[sKeyCode]()
  endif

  return sEventHandled
enddef
# }}}
# Style Picker Popup {{{
def StylePicker(
    hiGroup:         string,
    xPos:            number,
    yPos:            number,
    zIndex:          number       = Config.ZIndex(),
    bg:              string       = Config.Background(),
    borderChars:     list<string> = Config.BorderChars(),
    minWidth:        number       = Config.PopupWidth(),
    allowKeyMapping: bool         = Config.AllowKeyMapping(),
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

  InitHighlight()
  InitTextPropertyTypes(bufnr)
  InitReactiveState(hiGroup)
  InitEffects(bufnr)

  var framebuffer = FrameBuffer.new(bufnr)

  MainPane.new(framebuffer, pColor, pFavorite)

  if empty(hiGroup)
    TrackCursorAutoCmd()
  endif

  popup_show(winid)

  return winid
enddef
# }}}
# Public Interface {{{
export def Open(hiGroup = '')
  if sWinID > 0
    popup_close(sWinID)
  endif

  Init()
  sWinID = StylePicker(hiGroup, sX, sY)
enddef
# }}}
# Tests {{{
if !get(g:, 'test_mode', false)
  finish
endif

import 'libtinytest.vim' as tt


def Test_StylePicker_CreateLine()
  var l0 = TextLine.new('hello')

  assert_equal('hello', l0.text)
  assert_equal([], l0.props)

  var p0 = TextProperty.new('stylepicker_foo', 0, 5, 42)

  l0.props->add(p0)

  var textWithProperty = l0.Format()
  var expected = {text: 'hello', props: [{col: 1, length: 5, type: 'stylepicker_foo', id: 42}]}

  assert_equal(expected, l0.Format())
enddef

def Test_StylePicker_TextProperty()
  var text = "❯❯ XYZ"
  var l0 = TextLine.new(text)->WithStyle('foo', 3, 4, 42)
  var textWithProperty = l0.Format()

  var expected = {text: text, props: [{col: 8, length: 1, type: 'foo', id: 42}]}

  assert_equal(expected, l0.Format())
enddef

tt.Run('StylePicker')
