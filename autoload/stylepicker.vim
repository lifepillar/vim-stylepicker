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
import 'libstylepicker.vim' as libui

type ReactiveView = libui.ReactiveView
type StaticView   = libui.StaticView
type TextLine     = libui.TextLine
type TextProperty = libui.TextProperty
type VStack       = libui.VStack
type View         = libui.View
type ViewContent  = libui.ViewContent
# }}}
# Constants {{{
const kNumColorsPerLine = 10

const kUltimateFallbackColor = {
  'bg': {'dark': '#000000', 'light': '#ffffff'},
  'fg': {'dark': '#ffffff', 'light': '#000000'},
  'sp': {'dark': '#ffffff', 'light': '#000000'},
  'ul': {'dark': '#ffffff', 'light': '#000000'},
}

const kFgBgSp = {
  'fg': 'bg',
  'bg': 'sp',
  'sp': 'fg',
}

const kSpBgFg = {
  'sp': 'bg',
  'bg': 'fg',
  'fg': 'sp',
}

const kBorderChars        = ['─', '│', '─', '│', '╭', '╮', '╯', '╰']
const kAsciiBorderChars   = ['-', '|', '-', '|', ':', ':', ':', ':']
const kSliderSymbols      = [" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", '█']
const kAsciiSliderSymbols = [" ", ".", ":", "!", "|", "/", "-", "=", "#"]
const kAsciiDigits        = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']
const kDigits             = []

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
const kFgBgSpKey            = "\<tab>"
const kSpBgFgKey            = "\<s-tab>"
const kGrayPaneKey          = "G"
const kHelpKey              = "?"
const kHsbPaneKey           = "H"
const kIncrementKey         = "\<right>"
const kLeftClickKey         = "\<leftmouse>"
const kPasteKey             = "P"
const kChooseKey            = "\<enter>"
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
const kToggleUnderdottedKey = "."
const kToggleUnderdashedKey = "-"
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

const kASCIIKey = {
  "\<left>":    "Left",
  "\<right>":   "Right",
  "\<up>":      "Up",
  "\<down>":    "Down",
  "\<tab>":     "Tab",
  "\<s-tab>":   "S-Tab",
  "\<enter>":   "Enter",
  "\<s-enter>": "S-Enter",
}
# }}}
# User Settings {{{
# TODO: export user settings
var allowkeymapping: bool         = get(g:, 'stylepicker_keymapping',   true                                    )
var ascii:           bool         = get(g:, 'stylepicker_ascii',        false                                   )
var background:      string       = get(g:, 'stylepicker_background',   'Normal'                                )
var borderchars:     list<string> = get(g:, 'stylepicker_borderchars',  ascii ? kAsciiBorderChars : kBorderChars)
var favoritepath:    string       = get(g:, 'stylepicker_favoritepath', ''                                      )
var keyaliases:      dict<string> = get(g:, 'stylepicker_keyaliases',   {}                                      )
var marker:          string       = get(g:, 'stylepicker_marker',       ascii ? '>> ' : '❯❯ '                   )
var quotes:          list<string> = get(g:, 'stylepicker_quotes',       kDefaultQuotes                          )
var num_recent:      number       = get(g:, 'stylepicker_num_recent',   20                                      )
var recentpath:      string       = get(g:, 'stylepicker_recentpath',   ''                                      )
var star:            string       = get(g:, 'stylepicker_star',         ascii ? '*' : '★'                       )
var stepdelay:       float        = get(g:, 'stylepicker_stepdelay',    1.0                                     )
var zindex:          number       = get(g:, 'stylepicker_zindex',       50                                      )
# }}}
# Internal State {{{
var sHiGroup:  react.Property                          # Reference to the current highlight group for autocommands
var sX:        number         = 0                      # Horizontal position of the style picker
var sY:        number         = 0                      # Vertical position of the style picker
var sRecent:   react.Property = react.Property.new([]) # Cached recent colors to persist across close/reopen
var sFavorite: react.Property = react.Property.new([]) # Cached favorite colors to persist across close/reopen

class Config
  static var AllowKeyMapping = () => allowkeymapping
  static var Ascii           = () => ascii
  static var Background      = () => background
  static var BorderChars     = () => borderchars
  static var ColorMode       = () => has('gui_running') || (has('termguicolors') && &termguicolors) ? 'gui' : 'cterm'
  static var FavoritePath    = () => favoritepath
  static var Gutter          = () => repeat(' ', strcharlen(marker))
  static var GutterWidth     = () => strcharlen(marker)
  static var KeyAliases      = () => keyaliases
  static var Marker          = () => marker
  static var NumRecent       = () => num_recent
  static var PopupWidth      = () => max([39 + strdisplaywidth(marker), 42])
  static var RandomQuotation = () => quotes[rand() % len(quotes)]
  static var RecentPath      = () => recentpath
  static var SliderSymbols   = () => ascii ? kAsciiSliderSymbols : kSliderSymbols
  static var Star            = () => star
  static var StepDelay       = () => stepdelay
  static var StyleMode       = () => has('gui_running') ? 'gui' : 'cterm'
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

def KeySymbol(defaultKeyCode: string): string
  var userKeyCode = get(Config.KeyAliases(), defaultKeyCode, defaultKeyCode)

  if Config.Ascii()
    return get(kASCIIKey, userKeyCode, userKeyCode)
  endif

  return get(kPrettyKey, userKeyCode, userKeyCode)
enddef

def Center(text: string, width: number): string
  var lPad = repeat(' ', (width + 1 - strwidth(text)) / 2)
  var rPad = repeat(' ', (width - strwidth(text)) / 2)

  return $'{lPad}{text}{rPad}'
enddef

def Msg(text: string, highlight = 'Normal', log = true)
  execute 'echohl' highlight

  if log
    echomsg $'[StylePicker] {text}'
  else
    echo $'[StylePicker] {text}'
  endif

  echohl None
enddef

def Error(text: string)
  Msg(text, 'Error')
enddef

def Notification(
    winid:    number,
    text:     string,
    duration: number       = 2000,
    width:    number       = Config.PopupWidth(),
    border:   list<string> = Config.BorderChars(),
    )
  popup_notification(Center(text, width), {
    pos:         'topleft',
    line:        get(popup_getoptions(winid), 'line', 1),
    col:         get(popup_getoptions(winid), 'col', 1),
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

def CtermAttr(attr: string, mode: string): string
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
  var attr = CtermAttr(fgBgSp, mode)
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
  #  # color attribute. Always prefer the GUI definition if it exists,
  # # regardless of current mode (GUI vs terminal), otherwise infer
  ## a hex value in other ways. Always returns a hex color value.
  var value = HiGroupColorValue(hiGroup, fgBgSp, 'gui') # Try to get a GUI color

  if value != 'NONE' # Fast path
    return value
  endif

  # Try to infer a hex color value from the cterm definition
  if colorMode == 'cterm'
    var ctermValue = HiGroupColorValue(
      hiGroup, CtermAttr(fgBgSp, 'cterm'), 'cterm'
    )

    if ctermValue != 'NONE'
      var hex = libcolor.ColorNumber2Hex(str2nr(ctermValue))

      # Enable fast path for future calls
      execute 'hi' hiGroup $'gui{fgBgSp}={hex}'

      return hex
    endif
  endif

  # Fallback strategy
  if fgBgSp == 'sp'
    return GetHiGroupColor(hiGroup, 'fg')
  elseif hiGroup == 'Normal'
    return kUltimateFallbackColor[fgBgSp][&bg]
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

def ChooseIndex(max: number): number
  Msg($'Which color (0-{max})? ')

  var key = getcharstr()
  echo "\r"

  if key =~ '\m^\d\+$'
    var n = str2nr(key)

    if n <= max
      return n
    endif
  endif

  return -1
enddef

def ChooseGuiColor(): string
  #   #
  #  # Prompt the user to enter a hex value for a color.
  # #  Return an empty string if the input is invalid.
  ##
  var newCol = input('[StylePicker] New color: #', '')
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
  # # return the value as a hex color string.
  ## Return an empty string if the input is invalid.
  var newCol = input('[StylePicker] New terminal color [16-255]: ', '')
  echo "\r"
  var numCol = str2nr(newCol)

  if 16 <= numCol && numCol <= 255
    return libcolor.Xterm2Hex(numCol)
  endif

  return ''
enddef

def ChooseHiGroup(): string
  #   #
  #  # Prompt the user to enter a the name of a highlight group.
  # # Return an empty string if the input is invalid.
  ##
  var hiGroup = input('[StylePicker] Highlight group: ', '', 'highlight')
  echo "\r"

  if hlexists(hiGroup)
    return hiGroup
  endif

  return ''
enddef
# }}}
# Reactive State {{{
enum ColorState
  New,        # The color was just set (e.g., highlight group changed)
  Edited,     # The color has been modified via UI, but it is unsaved
  Saved       # The color has been saved to recent color palette
endenum

class ColorProperty extends react.Property
  #   # A color property is backed by a Vim's highlight group,
  #  # hence, it needs special management.
  # # A color property stores the hexadecimal value of the color.
  ##
  var colorState: react.Property = react.Property.new(ColorState.New)
  var _hiGroup:   string
  var _fgBgSp:    string
  var _guiAttr:   string # 'guifg', 'guibg', or 'guisp'
  var _ctermAttr: string # 'ctermfg', 'ctermbg', or 'ctermul'

  def new(hiGroup: react.Property, fgBgSp: react.Property, args: dict<any> = {})
    super.Init(args)

    # Reinitialize this property's value every time the highlight group changes
    react.CreateEffect(() => {
      this._hiGroup   = hiGroup.Get()
      this._fgBgSp    = fgBgSp.Get()
      this._guiAttr   = $'gui{this._fgBgSp}'
      this._ctermAttr = 'cterm' .. CtermAttr(this._fgBgSp, 'cterm')

      this.colorState.Set(ColorState.New)
      this.Set_(GetHiGroupColor(this._hiGroup, this._fgBgSp)) # `super` does not compile in a lambda in some Vim versions
    })
  enddef

  def Set(newValue: string, args: dict<any> = {})
    if !args->get('force', false) && newValue == this.value
      return
    endif

    var attrs: dict<any> = {name: this._hiGroup, [this._guiAttr]: newValue}
    var newValue_ = newValue

    if newValue_ == 'NONE'
      attrs[this._ctermAttr] = 'NONE'
      newValue_ = kUltimateFallbackColor[this._fgBgSp][&bg]
    else
      attrs[this._ctermAttr] = string(libcolor.Approximate(newValue).xterm)
    endif

    hlset([attrs])

    react.Transaction(() => {
      if this.colorState.value == ColorState.New
        this.colorState.Set(ColorState.Edited)
      endif

      this.Set_(newValue_)
    })
  enddef

  def Set_(newValue: string)
    super.Set(newValue)
  enddef
endclass

class StyleProperty extends react.Property
  #   #
  #  # A style property is backed by a Vim's highlight group,
  # # hence it needs special management.
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
  var _hiGroup: string

  def new(hiGroup: react.Property, args: dict<any> = {})
    super.Init(args)

    # Reinitialize this property's value every time the highlight group changes
    react.CreateEffect(() => {
      this._hiGroup = hiGroup.Get()
      var hl        = hlget(this._hiGroup, true)[0]
      var mode      = Config.StyleMode()
      var style     = extendnew(StyleProperty.styles, get(hl, mode, {}), 'force')

      if style.undercurl || style.underdashed || style.underdotted || style.underdouble
        style.underline = true
      endif

      this.Set_(style) # `super` cannot appear inside a lambda
    })
  enddef

  def Set(value: dict<bool>, args: dict<any> = {})
    var style = filter(value, (_, v) => v)
    var mode  = Config.StyleMode()

    hlset([{name: this._hiGroup, [mode]: style}])
    super.Set(extendnew(StyleProperty.styles, value, 'force'), args)
  enddef

  def ToggleAttribute(attr: string)
    var style = this.value

    if attr[0 : 4] == 'under'
      var wasOn = style[attr]

      style.underline   = false
      style.undercurl   = false
      style.underdashed = false
      style.underdotted = false
      style.underdouble = false

      if !wasOn
        style[attr]     = true
        style.underline = true
      endif
    else
      style[attr] = !style[attr]
    endif

    this.Set(style)
  enddef

  def Set_(newStyle: dict<bool>)
    super.Set(newStyle)
  enddef
endclass

class State
  #   #
  #  # The reactive state of this script.
  # #
  ##
  var hiGroup:  react.Property # The current highlight group
  var fgBgSp:   react.Property # The current color attribute ('fg', 'bg', or 'sp')
  var recent:   react.Property # List of recent colors
  var favorite: react.Property # List of favorite colors
  var color:    ColorProperty  # The hex value of the current color
  var style:    StyleProperty  # The current style attributes (bold, italic, etc.)

  var step     = react.Property.new(1)           # Current increment/decrement step
  var pane     = react.Property.new(kRgbPaneKey) # Current pane (rgb, hsb, grayscale, help)
  var rgb      = react.Property.new([0, 0, 0])
  var red      = react.Property.new(0)
  var green    = react.Property.new(0)
  var blue     = react.Property.new(0)
  var gray     = react.Property.new(0)
  # HSB values must be cached, because RGB -> HSB and HSB -> RGB are not
  # inverse to each other. For instance, HSB(1,1,1) -> RGB(3,3,3), but when
  # converting back, RGB(3,3,3) -> HSB(0,0,1). We don't want the sliders to
  # jump around randomly.
  var cachedHsb  = react.Property.new([-1, -1, -1])
  var cachedHex  = '#000000'
  var hsb        = react.Property.new([-1, -1, -1])
  var hue        = react.Property.new(-1)
  var saturation = react.Property.new(-1)
  var brightness = react.Property.new(-1)

  var _timeSinceLastDigitPressed: list<number> = reltime() # Time since last digit key was pressed

  def new(hiGroup: string, fgBgSp: string)
    this.hiGroup = react.Property.new(hiGroup)
    this.fgBgSp  = react.Property.new(fgBgSp)
    this.color   = ColorProperty.new(this.hiGroup, this.fgBgSp)
    this.style   = StyleProperty.new(this.hiGroup)

    if !empty(Config.RecentPath())
      sRecent.Set(LoadPalette(Config.RecentPath()))
    endif

    if !empty(Config.FavoritePath())
      sFavorite.Set(LoadPalette(Config.FavoritePath()))
    endif

    this.recent   = sRecent
    this.favorite = sFavorite
    sHiGroup      = this.hiGroup # Allows setting the highlight group from an autocommand

    react.CreateEffect(() => { # Recompute value when this.color or this.cachedHsb changes
      var color = this.color.Get()
      var pane  = this.pane.Get()

      if pane == kHsbPaneKey
        var [h, s, b] = this.cachedHsb.Get()

        if color == this.cachedHex
          this.hsb.Set([h, s, b])
        else
          this.hsb.Set(libcolor.Hex2Hsv(color))
        endif

        this.hue.Set(this.hsb.value[0])
        this.saturation.Set(this.hsb.value[1])
        this.brightness.Set(this.hsb.value[2])
      else
        this.rgb.Set(libcolor.Hex2Rgb(color))
        this.red.Set(this.rgb.value[0])
        this.green.Set(this.rgb.value[1])
        this.blue.Set(this.rgb.value[2])

        if pane == kGrayPaneKey
          this.gray.Set(libcolor.Rgb2Gray(this.red.value, this.green.value, this.blue.value))
        endif
      endif
    })

    react.CreateEffect(() => { # Save to recent palette when a color is modified
      if this.color.colorState.Get() == ColorState.Edited
        this.SaveToRecent()
      endif
    })
  enddef

  def SetStep(digit: number)
    var newStep = digit
    var elapsed = this._timeSinceLastDigitPressed->reltime()

    this._timeSinceLastDigitPressed = reltime()

    if elapsed->reltimefloat() <= Config.StepDelay()
      newStep = 10 * this.step.Get() + newStep

      if newStep > 99
        newStep = digit
      endif
    endif

    if newStep < 1
      newStep = 1
    endif

    this.step.Set(newStep)
  enddef

  def SetRgb(r: number, g: number, b: number)
    this.color.Set(libcolor.Rgb2Hex(r, g, b))
  enddef

  def SetRed(red: number)
    var [_, g, b] = this.rgb.Get()
    this.SetRgb(red, g, b)
  enddef

  def SetGreen(green: number)
    var [r, _, b] = this.rgb.Get()
    this.SetRgb(r, green, b)
  enddef

  def SetBlue(blue: number)
    var [r, g, _] = this.rgb.Get()
    this.SetRgb(r, g, blue)
  enddef

  def SetHSB(h: number, s: number, b: number)
    react.Transaction(() => {
      this.cachedHsb.Set([h, s, b])
      this.cachedHex = libcolor.Hsv2Hex(h, s, b)
      this.color.Set(this.cachedHex)
    })
  enddef

  def SetHue(hue: number)
    var hsb = this.hsb.Get()
    this.SetHSB(hue, hsb[1], hsb[2])
  enddef

  def SetSaturation(saturation: number)
    var hsb = this.hsb.Get()
    this.SetHSB(hsb[0], saturation, hsb[2])
  enddef

  def SetBrightness(brightness: number)
    var hsb = this.hsb.Get()
    this.SetHSB(hsb[0], hsb[1], brightness)
  enddef

  def SetGrayLevel(gray: number)
    this.color.Set(libcolor.Gray2Hex(gray))
  enddef

  def SaveToRecent()
    react.Transaction(() => {
      var recentColors: list<string> = this.recent.value
      var color = this.color.Get()

      if color->NotIn(recentColors)
        recentColors->add(color)

        if len(recentColors) > Config.NumRecent()
          remove(recentColors, 0)
        endif

        this.recent.Set(recentColors, {force: true})
      endif

      this.color.colorState.Set(ColorState.Saved)
    })
  enddef
endclass
# }}}
# Text with Properties {{{
const kPropTypeOn               = '_on__' # Property for 'enabled' stuff
const kPropTypeOff              = '_off_' # Property for 'disabled' stuff
const kPropTypeLabel            = '_labl' # Mark line as a label
const kPropTypeCurrentHighlight = '_curh' # To highlight text with the currently selected highglight group
const kPropTypeHeader           = '_titl' # Highlight for title section
const kPropTypeGuiHighlight     = '_gcol' # Highlight for the current GUI color
const kPropTypeCtermHighlight   = '_tcol' # Highlight for the current cterm color
const kPropTypeGray             = '_gray' # Grayscale blocks
const kPropTypeGray000          = '_g000' # Grayscale blocks
const kPropTypeGray025          = '_g025' # Grayscale blocks
const kPropTypeGray050          = '_g050' # Grayscale blocks
const kPropTypeGray075          = '_g075' # Grayscale blocks
const kPropTypeGray100          = '_g100' # Grayscale blocks

def InitTextPropertyTypes(bufnr: number)
  var propTypes = {
    [kPropTypeOn              ]: {bufnr: bufnr, highlight: 'stylePickerOn'       },
    [kPropTypeOff             ]: {bufnr: bufnr, highlight: 'stylePickerOff'      },
    [kPropTypeLabel           ]: {bufnr: bufnr, highlight: 'Label'               },
    [kPropTypeCurrentHighlight]: {bufnr: bufnr                                   },
    [kPropTypeHeader          ]: {bufnr: bufnr, highlight: 'Title'               },
    [kPropTypeGuiHighlight    ]: {bufnr: bufnr, highlight: 'stylePickerGuiColor' },
    [kPropTypeCtermHighlight  ]: {bufnr: bufnr, highlight: 'stylePickerTermColor'},
    [kPropTypeGray            ]: {bufnr: bufnr                                   },
    [kPropTypeGray000         ]: {bufnr: bufnr, highlight: 'stylePickerGray000'  },
    [kPropTypeGray025         ]: {bufnr: bufnr, highlight: 'stylePickerGray025'  },
    [kPropTypeGray050         ]: {bufnr: bufnr, highlight: 'stylePickerGray050'  },
    [kPropTypeGray075         ]: {bufnr: bufnr, highlight: 'stylePickerGray075'  },
    [kPropTypeGray100         ]: {bufnr: bufnr, highlight: 'stylePickerGray100'  },
  }

  for [propType, propValue] in items(propTypes)
    prop_type_delete(propType, {bufnr: bufnr})
    prop_type_add(propType, propValue)
  endfor
enddef

def BlankLine(width = 0): TextLine
  return TextLine.new(repeat(' ', width))
enddef

def WithStyle(line: TextLine, propType: string, from = 0, to = strcharlen(line.Text()), id = 1): TextLine
  line.Add(TextProperty.new(propType, from, to, id))
  return line
enddef

def WithTitle(line: TextLine, from = 0, to = strcharlen(line.Text())): TextLine
  return WithStyle(line, kPropTypeHeader, from, to)
enddef

def WithState(line: TextLine, enabled: bool, from = 0, to = strcharlen(line.Text())): TextLine
  return WithStyle(line, enabled ? kPropTypeOn : kPropTypeOff, from, to)
enddef

def WithGuiHighlight(line: TextLine, from = 0, to = strcharlen(line.Text())): TextLine
  return WithStyle(line, kPropTypeGuiHighlight, from, to)
enddef

def WithCtermHighlight(line: TextLine, from = 0, to = strcharlen(line.Text())): TextLine
  return WithStyle(line, kPropTypeCtermHighlight, from, to)
enddef

def WithCurrentHighlight(line: TextLine, from = 0, to = strcharlen(line.Text())): TextLine
  return WithStyle(line, kPropTypeCurrentHighlight, from, to)
enddef

def Labeled(line: TextLine, from = 0, to = strcharlen(line.Text())): TextLine
  return WithStyle(line, kPropTypeLabel, from, to)
enddef
# }}}
# Autocommands {{{
def ColorschemeChangedAutoCmd()
  augroup StylePicker
    autocmd ColorScheme * InitHighlight()
  augroup END
enddef

def TrackCursorAutoCmd()
  augroup StylePicker
    autocmd CursorMoved * sHiGroup.Set(HiGroupUnderCursor())
  augroup END
enddef

def UntrackCursorAutoCmd()
  if exists('#StylePicker')
    autocmd! StylePicker CursorMoved *
      endif
enddef

def ToggleTrackCursor()
  if exists('#StylePicker#CursorMoved')
    UntrackCursorAutoCmd()
  else
    TrackCursorAutoCmd()
  endif
enddef

def DisableAllAutocommands()
  if exists('#StylePicker')
    autocmd! StylePicker
    augroup! StylePicker
  endif
enddef
# }}}
# BlankView {{{
def BlankView(height = 1, width = 0): View
  return StaticView.new(repeat([BlankLine(width)], height))
enddef
# }}}
# HeaderView {{{
def HeaderView(rstate: State, pane: string): View
  const attrs   = 'BIUVSK' # Bold, Italic, Underline, reVerse, Standout, striKethrough
  const width   = Config.PopupWidth()
  const offset  = width - strcharlen(attrs)

  return ReactiveView.new(() => {
    if rstate.pane.Get() == pane
      var hiGroup = rstate.hiGroup.Get()
      var style   = rstate.style.Get()
      var text    = $'BIUVSK [{rstate.fgBgSp.Get()}] {hiGroup}'

      return [TextLine.new(text)
        ->WithState(style.bold,          0, 1)
        ->WithState(style.italic,        1, 2)
        ->WithState(style.underline,     2, 3)
        ->WithState(style.reverse,       3, 4)
        ->WithState(style.standout,      4, 5)
        ->WithState(style.strikethrough, 5, 6)
        ->WithTitle(7, 12 + strcharlen(hiGroup)),
        BlankLine(),
      ]
    endif

    return []
  })
enddef
# }}}
# FooterView {{{
def FooterView(rstate: State): View
  return StaticView.new([])
enddef
# }}}
# SectionTitleView {{{
def SectionTitleView(title: string): View
  #   #
  #  # A static line with a Label highlight.
  # #
  ##
  return StaticView.new([TextLine.new(title)->Labeled()])
enddef
# }}}
# GrayscaleSectionView {{{
def GrayscaleSectionView(): View
  #   #
  #  #
  # # A static line with grayscale markers.
  ##
  const gutterWidth = Config.GutterWidth()
  const width       = Config.PopupWidth()

  return StaticView.new([
    TextLine.new('Grayscale')->Labeled(),
    BlankLine(width)
    ->WithStyle(kPropTypeGray000, gutterWidth +  5, gutterWidth + 7)
    ->WithStyle(kPropTypeGray025, gutterWidth + 13, gutterWidth + 15)
    ->WithStyle(kPropTypeGray050, gutterWidth + 21, gutterWidth + 23)
    ->WithStyle(kPropTypeGray075, gutterWidth + 29, gutterWidth + 31)
    ->WithStyle(kPropTypeGray100, gutterWidth + 37, gutterWidth + 39),
  ])
enddef
# }}}
# StepView {{{
def StepView(rstate: State, pane: string): View
  return ReactiveView.new(() => {
    if rstate.pane.Get() == pane
      return [
        TextLine.new(printf('Step  %02d', rstate.step.Get()))->Labeled(0, 4),
        BlankLine(),
      ]
    endif

    return []
  })
enddef
# }}}
# SliderView {{{
# NOTE: for a slider to be rendered correctly, ambiwidth must be set to 'single'.
def SliderView(
    rstate:      State,
    name:        string,         # The name of the slider (appears next to the slider)
    sliderValue: react.Property, # Observed value
    Set:         func(number),   # Used for updating when the slider's value changes
    max:         number = 255,   # Maximum value of the slider
    min:         number = 0,     # Minimum value of the slider
    ): View
  const gutterWidth = Config.GutterWidth()
  const width       = Config.PopupWidth() - gutterWidth - 6
  const symbols     = Config.SliderSymbols()
  const range       = max + 1.0 - min
  const gutter      = react.Property.new(Config.Gutter())

  var sliderView = ReactiveView.new(() => {
    var value       = sliderValue.Get()
    var valuewidth  = value * width / range
    var whole       = float2nr(valuewidth)
    var frac        = valuewidth - whole
    var bar         = repeat(symbols[-1], whole)
    var part_char   = symbols[1 + float2nr(floor(frac * 8))]
    var text        = printf("%s%s %3d %s%s", gutter.Get(), name, value, bar, part_char)

    return [TextLine.new(text)->Labeled(gutterWidth, gutterWidth + 1)]
  })
  .Focusable(true)

  react.CreateEffect(() => {
    if sliderView.focused.Get()
      gutter.Set(Config.Marker())
    else
      gutter.Set(Config.Gutter())
    endif
  })

  sliderView.OnKeyPress(kIncrementKey, () => {
    var newValue = sliderValue.Get() + rstate.step.Get()

    if newValue > max
      newValue = max
    endif

    Set(newValue)
  })

  sliderView.OnKeyPress(kDecrementKey, () => {
    var newValue = sliderValue.Get() - rstate.step.Get()

    if newValue < min
      newValue = min
    endif

    Set(newValue)
  })

  sliderView.OnMouseEvent(kLeftClickKey, (_, col) => {
    var value = (width + gutterWidth + 6) * col
    echo col width range gutterWidth value
  })

  return sliderView
enddef
# }}}
# SliderGroupView {{{
def SliderGroupView(rstate: State, ...sliders: list<View>): View
  var sliderGroupView = VStack.new(sliders)

  sliderGroupView.OnKeyPress('0', () => rstate.SetStep(0))
  sliderGroupView.OnKeyPress('1', () => rstate.SetStep(1))
  sliderGroupView.OnKeyPress('2', () => rstate.SetStep(2))
  sliderGroupView.OnKeyPress('3', () => rstate.SetStep(3))
  sliderGroupView.OnKeyPress('4', () => rstate.SetStep(4))
  sliderGroupView.OnKeyPress('5', () => rstate.SetStep(5))
  sliderGroupView.OnKeyPress('6', () => rstate.SetStep(6))
  sliderGroupView.OnKeyPress('7', () => rstate.SetStep(7))
  sliderGroupView.OnKeyPress('8', () => rstate.SetStep(8))
  sliderGroupView.OnKeyPress('9', () => rstate.SetStep(9))

  return sliderGroupView
enddef
# }}}
# RgbSliderView {{{
def RgbSliderView(rstate: State): View
  return SliderGroupView(rstate,
    SliderView(rstate, 'R', rstate.red,   rstate.SetRed),
    SliderView(rstate, 'G', rstate.green, rstate.SetGreen),
    SliderView(rstate, 'B', rstate.blue,  rstate.SetBlue),
  )
enddef
# }}}
# HsbSliderView {{{
def HsbSliderView(rstate: State): View
  return SliderGroupView(rstate,
    SliderView(rstate, 'H', rstate.hue,        rstate.SetHue,        359),
    SliderView(rstate, 'S', rstate.saturation, rstate.SetSaturation, 100),
    SliderView(rstate, 'B', rstate.brightness, rstate.SetBrightness, 100),
  )
enddef
# }}}
# GrayscaleSliderView {{{
def GrayscaleSliderView(rstate: State): View
  return SliderGroupView(rstate,
    GrayscaleSectionView(),
    SliderView(rstate, 'G', rstate.gray, rstate.SetGrayLevel),
  )
enddef
# }}}
# ColorInfoView {{{
def ColorInfoView(rstate: State, pane: string): View
  return ReactiveView.new(() => {
    if rstate.pane.Get() == pane
      var hiGroup = rstate.hiGroup.Get()
      var fgBgSp  = rstate.fgBgSp.Get()
      var color   = rstate.color.Get()

      var altColor    = AltColor(hiGroup, fgBgSp)
      var approxCol   = libcolor.Approximate(color)
      var approxAlt   = libcolor.Approximate(altColor)
      var contrast    = libcolor.ContrastColor(color)
      var contrastAlt = libcolor.Approximate(contrast)
      var guiScore    = ComputeScore(color, altColor)
      var termScore   = ComputeScore(approxCol.hex, approxAlt.hex)
      var delta       = printf("%.1f", approxCol.delta)[ : 2]
      var guiGuess    = (color != HiGroupColorValue(hiGroup, fgBgSp, 'gui') ? '!' : ' ')
      var ctermGuess  = (string(approxCol.xterm) != HiGroupColorValue(hiGroup, fgBgSp, 'cterm') ? '!' : ' ')

      var info = printf(
        $' {guiGuess}   {ctermGuess}  %s %-5S %3d/%s %-5S Δ{delta}',
        color[1 : ],
        repeat(Config.Star(), guiScore),
        approxCol.xterm,
        approxCol.hex[1 : ],
        repeat(Config.Star(), termScore)
      )

      execute $'hi stylePickerGuiColor guifg={contrast} guibg={color} ctermfg={contrastAlt.xterm} ctermbg={approxCol.xterm}'
      execute $'hi stylePickerTermColor guifg={contrast} guibg={approxCol.hex} ctermfg={contrastAlt.xterm} ctermbg={approxCol.xterm}'

      return [
        TextLine.new(info)->WithGuiHighlight(0, 3)->WithCtermHighlight(4, 7),
        BlankLine(),
      ]
    endif

    return []
  })
enddef
# }}}
# QuotationView {{{
def QuotationView(): View
  return StaticView.new([
    TextLine.new(Center(Config.RandomQuotation(), Config.PopupWidth()))->WithCurrentHighlight(),
  ])
enddef
# }}}
# ColorSliceView {{{
def ColorSliceView(
    identifier: string,
    bufnr:      number,
    pane:       string,
    rstate:     State,
    colorSet:   react.Property,
    from:       number,
    to:         number,
    hasHeader:  bool = true,
    ):         View
  #   #
  #  # A view of a segment of a color palette as a strip of colored cells:
  # #
  ##    0   1   2   3   4   5   6   7   8   9
  ##   ███ ███ ███ ███ ███ ███ ███ ███ ███ ███

  const gutterWidth = Config.GutterWidth()
  const width       = Config.PopupWidth() - gutterWidth
  const gutter      = react.Property.new(Config.Gutter())

  var sliceView = ReactiveView.new(() => {
    if rstate.pane.Get() == pane
      var palette: list<string> = colorSet.Get()

      if from >= len(palette)
        return []
      endif

      var content: list<TextLine> = []
      var to_                     = Min(to, len(palette))

      if hasHeader
        content->add(TextLine.new(
          Config.Gutter() .. ' ' .. join(range(to_ - from), '   ')
        )->Labeled())
      endif

      var colorsLine = TextLine.new(gutter.Get() .. repeat(' ', width))
      var k = 0

      while k < to_ - from
        var hexCol   = palette[from + k]
        var approx   = libcolor.Approximate(hexCol)
        var textProp = $'stylePicker{identifier}_{from + k}'
        var column   = gutterWidth + 4 * k

        colorsLine->WithStyle(textProp, column, column + 3)

        execute $'hi {textProp} guibg={hexCol} ctermbg={approx.xterm}'

        prop_type_delete(textProp, {bufnr: bufnr})
        prop_type_add(textProp, {bufnr: bufnr, highlight: textProp})

        ++k
      endwhile

      content->add(colorsLine)
      return content
    endif

    return []
  })
  .Focusable(true)

  sliceView.OnKeyPress(kChooseKey, () => {
    var palette = colorSet.Get()
    var n = Min(to, len(palette)) - from
    var k = ChooseIndex(n - 1)

    if 0 <= k && k <= n
      react.Transaction(() => {
        rstate.SaveToRecent()
        rstate.color.Set(palette[from + k])
      })
    endif
  })

  sliceView.OnKeyPress(kRemoveKey, () => {
    var palette = colorSet.Get()
    var n = Min(to, len(palette)) - from
    var k = ChooseIndex(n - 1)

    if 0 <= k && k <= n
      palette->remove(from + k)
      react.Transaction(() => {
        colorSet.Set(palette, {force: true})

        if empty(palette)
          sliceView.FocusPrevious()
        endif
      })
    endif
  })

  react.CreateEffect(() => {
    if sliceView.focused.Get()
      gutter.Set(Config.Marker())
    else
      gutter.Set(Config.Gutter())
    endif
  })

  return sliceView
enddef
# }}}
# ColorPaletteView {{{
class ColorPaletteView extends VStack
  var identifier:       string
  var palette:          react.Property
  var rstate:           State
  var bufnr:            number
  var pane:             string
  var minHeight:        number # Minimum height in lines, excluding top blank line and title
  var hideIfEmpty:      bool   # Collapse view if there are no colors to display
  var numColorsPerLine: number # Number of colors of a slice

  def new(this.identifier, title: string, this.palette, this.rstate, args: dict<any>)
    this.bufnr            = args['bufnr']
    this.pane             = args['pane']
    this.minHeight        = args->get('minHeight', 0)
    this.hideIfEmpty      = args->get('hide', true)
    this.numColorsPerLine = args->get('numColorsPerLine', kNumColorsPerLine)

    this.AddView(BlankView())
    this.AddView(SectionTitleView(title))
  enddef

  def Body(): ViewContent
    if this.rstate.pane.Get() == this.pane
      # Dynamically add slices to accommodate all the colors
      var numColors = len(this.palette.Get())
      var numSlices = this.NumChildren() - 2  # First two children are always blank line and title
      var numSlots  = numSlices * this.numColorsPerLine

      while numSlots < numColors
        this.AddView(ColorSliceView(
          this.identifier,
          this.bufnr,
          this.pane,
          this.rstate,
          this.palette,
          numSlots,
          numSlots + this.numColorsPerLine,
        ))
        numSlots += this.numColorsPerLine
      endwhile

      var body   = super.Body()
      var height = len(body) - 2 # Do not count blank line and title

      if this.hideIfEmpty && height == 0
        return []
      endif

      if height < this.minHeight
        body += repeat(BlankView().Body(), this.minHeight - height)
      endif

      return body
    endif

    return []
  enddef
endclass
# }}}
# StylePickerView {{{
def StylePickerView(winid: number, pane: string, rstate: State, MakeSlidersView: func(State): View): View
  var stylePickerView = VStack.new([
    HeaderView(rstate, pane),
    MakeSlidersView(rstate),
    StepView(rstate, pane),
    ColorInfoView(rstate, pane),
    QuotationView(),
    ColorPaletteView.new('Recent', 'Recent Colors',   rstate.recent,   rstate, {bufnr: winbufnr(winid), pane: pane, minHeight: 2, hide: false}),
    ColorPaletteView.new('Fav',    'Favorite Colors', rstate.favorite, rstate, {bufnr: winbufnr(winid), pane: pane}),
    FooterView(rstate),
  ])
  stylePickerView.OnKeyPress(kUpKey,                stylePickerView.FocusPrevious)
  stylePickerView.OnKeyPress(kDownKey,              stylePickerView.FocusNext)
  stylePickerView.OnKeyPress(kTopKey,               stylePickerView.FocusFirst)
  stylePickerView.OnKeyPress(kBotKey,               stylePickerView.FocusLast)
  stylePickerView.OnKeyPress(kFgBgSpKey,            () => rstate.fgBgSp.Set(kFgBgSp[rstate.fgBgSp.Get()]))
  stylePickerView.OnKeyPress(kSpBgFgKey,            () => rstate.fgBgSp.Set(kSpBgFg[rstate.fgBgSp.Get()]))
  stylePickerView.OnKeyPress(kToggleBoldKey,        () => rstate.style.ToggleAttribute('bold'))
  stylePickerView.OnKeyPress(kToggleItalicKey,      () => rstate.style.ToggleAttribute('italic'))
  stylePickerView.OnKeyPress(kToggleReverseKey,     () => rstate.style.ToggleAttribute('reverse'))
  stylePickerView.OnKeyPress(kToggleStandoutKey,    () => rstate.style.ToggleAttribute('standout'))
  stylePickerView.OnKeyPress(kToggleStrikeThruKey,  () => rstate.style.ToggleAttribute('strikethrough'))
  stylePickerView.OnKeyPress(kToggleUndercurlKey,   () => rstate.style.ToggleAttribute('undercurl'))
  stylePickerView.OnKeyPress(kToggleUnderdashedKey, () => rstate.style.ToggleAttribute('underdashed'))
  stylePickerView.OnKeyPress(kToggleUnderdottedKey, () => rstate.style.ToggleAttribute('underdotted'))
  stylePickerView.OnKeyPress(kToggleUnderdoubleKey, () => rstate.style.ToggleAttribute('underdouble'))
  stylePickerView.OnKeyPress(kToggleUnderlineKey,   () => rstate.style.ToggleAttribute('underline'))

  stylePickerView.OnKeyPress(kAddToFavoritesKey, () => {
    var color    = rstate.color.Get()
    var favorite = rstate.favorite.Get()

    if color->NotIn(favorite)
      favorite->add(color)
      rstate.favorite.Set(favorite, {force: true})
    endif
  })

  stylePickerView.OnKeyPress(kSetColorKey, () => {
    var color = Config.ColorMode() == 'gui' ? ChooseGuiColor() : ChooseTermColor()

    if !empty(color)
      rstate.color.Set(color)
    endif
  })

  stylePickerView.OnKeyPress(kSetHiGroupKey, () => {
    var hiGroup = ChooseHiGroup()

    if !empty(hiGroup)
      UntrackCursorAutoCmd()
      rstate.hiGroup.Set(hiGroup)
    endif
  })

  stylePickerView.OnKeyPress(kClearKey, () => {
    rstate.color.Set('NONE')
    Notification(winid, 'Color cleared')
  })

  return stylePickerView
enddef
# }}}
# HelpView {{{
def HelpView(): View
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
    KeySymbol(kChooseKey),            # 33
  ]
  var maxSymbolWidth = max(mapnew(s, (_, v) => strdisplaywidth(v)))

  # Pad with spaces, so all symbol strings have the same width
  map(s, (_, v) => v .. repeat(' ', maxSymbolWidth - strdisplaywidth(v)))

  var helpView = StaticView.new([
    TextLine.new('Keyboard Controls')->WithTitle(),
    BlankLine(),
    TextLine.new('Popup')->Labeled(),
    TextLine.new($'{s[00]} Move up           {s[07]} RGB Pane'),
    TextLine.new($'{s[01]} Move down         {s[08]} HSB Pane'),
    TextLine.new($'{s[02]} Go to top         {s[09]} Grayscale Pane'),
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
  ], true)
  helpView.focused.Set(true)

  return helpView
enddef
# }}}
# Highlight {{{
def InitHighlight()
  #   #
  #  # Initialize the highlight groups used by the style picker.
  # #
  ##
  var mode         = Config.ColorMode()
  var style        = Config.StyleMode()
  var warnColor    = HiGroupColorValue('WarningMsg', 'fg', mode)
  var labelColor   = HiGroupColorValue('Label',      'fg', mode)
  var commentColor = HiGroupColorValue('Comment',    'fg', mode)

  execute $'highlight stylePickerOn      {mode}fg={labelColor}   {style}=bold term=bold'
  execute $'highlight stylePickerOff     {mode}fg={commentColor} {style}=NONE term=NONE'
  execute $'highlight stylePickerWarning {mode}fg={warnColor}    {style}=bold term=bold'

  highlight stylePickerGray000 guibg=#000000 ctermbg=16
  highlight stylePickerGray025 guibg=#404040 ctermbg=238
  highlight stylePickerGray050 guibg=#7f7f7f ctermbg=244
  highlight stylePickerGray075 guibg=#bfbfbf ctermbg=250
  highlight stylePickerGray100 guibg=#ffffff ctermbg=231
  highlight clear stylePickerGuiColor
  highlight clear stylePickerTermColor
enddef
# }}}
# UI {{{
class UI
  var rstate: State
  var rootView: react.ComputedProperty

  def new(this.rstate)
    this.rootView = react.ComputedProperty.new(() => StaticView.new([]))
  enddef

  def Init(winid: number, initialPane: string)
    InitHighlight()
    InitTextPropertyTypes(winbufnr(winid))

    var rgbView       = StylePickerView(winid, kRgbPaneKey,  this.rstate, RgbSliderView)
    var hsbView       = StylePickerView(winid, kHsbPaneKey,  this.rstate, HsbSliderView)
    var grayscaleView = StylePickerView(winid, kGrayPaneKey, this.rstate, GrayscaleSliderView)
    var helpView      = HelpView()

    this.rstate.pane.Set(initialPane)

    this.rootView = react.ComputedProperty.new(() => {
      var pane = this.rstate.pane.Get()

      this.rstate.color.colorState.Set(ColorState.New)

      if pane == kRgbPaneKey
        return rgbView
      elseif pane == kHsbPaneKey
        return hsbView
      elseif pane == kGrayPaneKey
        return grayscaleView
      else
        return helpView
      endif
    }, {force: true})

    react.CreateEffect(() => { # Reset the focus when the root view changes
      this.rootView.Get().FocusFirst()
    })
  enddef

  def RootView(): View
    return this.rootView.Get()
  enddef

  def ViewWithFocus(): View
    return this.rootView.Get().SubViewWithFocus()
  enddef
endclass
# }}}
# Actions {{{
def Cancel(winid: number)
  popup_close(winid)

  # TODO: revert only the changes of the stylepicker
  if exists('g:colors_name') && !empty('g:colors_name')
    execute 'colorscheme' g:colors_name
  endif
enddef
# }}}
# Event Handling {{{
def ClosedCallback(winid: number, result: any = '')
  DisableAllAutocommands()
  sX = popup_getoptions(winid).col
  sY = popup_getoptions(winid).line
enddef

def MakeEventHandler(ui: UI): func(number, string): bool
  return (winid: number, rawKeyCode: string): bool => {
    var keyCode = get(Config.KeyAliases(), rawKeyCode, rawKeyCode)

    if keyCode == kCancelKey
      Cancel(winid)
      return true
    endif

    if keyCode == kCloseKey
      popup_close(winid)
      return true
    endif

    if keyCode->In([kHelpKey, kRgbPaneKey, kHsbPaneKey, kGrayPaneKey])
      ui.rstate.pane.Set(keyCode)
      return true
    endif

    if keyCode == kToggleTrackingKey
      ToggleTrackCursor()
      return true
    endif

    if keyCode == "\<LeftMouse>"
      var mousepos = getmousepos()

      if mousepos.winid != winid
        return false
      endif

      return ui.RootView().RespondToMouseEvent(keyCode, mousepos.line, mousepos.column)
    endif

    return ui.ViewWithFocus().RespondToKeyEvent(keyCode)
  }
enddef
# }}}
# Style Picker Popup {{{
def StylePickerPopup(hiGroup: string, xPos: number, yPos: number): number
  var _hiGroup     = empty(hiGroup) ? HiGroupUnderCursor() : hiGroup
  var rstate       = State.new(_hiGroup, 'fg')
  var ui           = UI.new(rstate)
  var EventHandler = MakeEventHandler(ui)

  var winid         = popup_create('', {
    border:      [1, 1, 1, 1],
    borderchars: Config.BorderChars(),
    callback:    ClosedCallback,
    close:       'button',
    col:         xPos,
    cursorline:  false,
    drag:        true,
    filter:      EventHandler,
    filtermode:  'n',
    hidden:      true,
    highlight:   Config.Background(),
    line:        yPos,
    mapping:     Config.AllowKeyMapping(),
    minwidth:    Config.PopupWidth(),
    padding:     [0, 1, 0, 1],
    pos:         'topleft',
    resize:      false,
    scrollbar:   true,
    tabpage:     0,
    title:       '',
    wrap:        false,
    zindex:      Config.ZIndex(),
  })
  ui.Init(winid, kRgbPaneKey)

  if empty(hiGroup)
    TrackCursorAutoCmd()
  endif

  react.CreateEffect(() => {
    prop_type_change(kPropTypeCurrentHighlight,
      {bufnr: winbufnr(winid), highlight: rstate.hiGroup.Get()}
    )
  })

  var counter = 0

  def Redraw()
    ++counter
    popup_settext(winid, ui.rootView.Get().Body() + [{text: string(counter), props: []}])
  enddef

  react.CreateEffect(() => Redraw(), {weight: 100})

  popup_show(winid)

  return winid
enddef
# }}}
# Public Interface {{{
export def Open(hiGroup = '')
  StylePickerPopup(hiGroup, sX, sY)
enddef
# }}}
