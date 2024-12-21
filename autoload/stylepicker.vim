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
# Types {{{
type ActionCode = string
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
var recent:          number       = get(g:, 'stylepicker_recent',       20                                      )
var star:            string       = get(g:, 'stylepicker_star',         ascii ? '*' : '★'                       )
var stepdelay:       float        = get(g:, 'stylepicker_stepdelay',    1.0                                     )
var zindex:          number       = get(g:, 'stylepicker_zindex',       50                                      )
# }}}
# Internal State {{{
var sEventHandled: bool = false # Set to true if a key or mouse event was handled
var sKeyCode: string = ''       # Last key pressed
var sWinID: number = -1         # ID of the style picker popup
var sX: number = 0              # Horizontal position of the style picker
var sY: number = 0              # Vertical position of the style picker

class Config
  static var Ascii           = () => ascii
  static var Background      = () => background
  static var BorderChars     = () => borderchars
  static var ColorMode       = () => has('gui_running') || (has('termguicolors') && &termguicolors) ? 'gui' : 'cterm'
  static var FavoritePath    = () => favoritepath
  static var KeyAliases      = () => keyaliases
  static var AllowKeyMapping = () => allowkeymapping
  static var Marker          = () => marker
  static var PopupWidth      = () => max([39 + strdisplaywidth(marker), 42])
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
# UI {{{
class TextProperty
  var type: string # Text property type (created with prop_type_add())
  var xl:   number # 0-based start position of the property (in characters) TODO: are composed chars counted as one?
  var xr:   number # One past the end position of the property
  var id:   number = 1
endclass

class FrameBuffer
  var bufnr: number

  def new()
    this.bufnr = bufadd('')
    bufload(this.bufnr)
  enddef

  def InsertText(lnum: number, text: string)
    # Insert at the given line number, shifting text below
    var bufinfo = getbufinfo(this.bufnr)[0]
    var ll = bufinfo.linecount

    while ll < lnum - 1
      appendbufline(this.bufnr, '$', '')
      ++ll
    endwhile

    appendbufline(this.bufnr, lnum - 1, text)
  enddef

  def SetText(lnum: number, text: string)
    # Insert at the given line number, shifting text below
    var bufinfo = getbufinfo(this.bufnr)[0]
    var ll = bufinfo.linecount

    while ll < lnum - 1
      appendbufline(this.bufnr, '$', '')
      ++ll
    endwhile

    appendbufline(this.bufnr, lnum - 1, text)
  enddef

endclass

# }}}
# Highlight Groups {{{
def InitHighlight()
  var mode         = Config.ColorMode()
  var style        = Config.StyleMode()
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

# }}}
# Events {{{
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
  endif
enddef

def ActionKeyPress()
  var event = KeyEvent.new('name goes here')
enddef

# }}}
# Default Key Map {{{
const kKeyMap = {
  "\<LeftMouse>": ActionLeftClick,
  "A":        ActionNoop,
  ">":        ActionNoop,
  "X":        ActionNoop,
  "Z":        ActionNoop,
  "x":        ActionNoop,
  "\<left>":  ActionIntercept,
  "\<down>":  ActionNoop,
  "\<s-tab>": ActionNoop,
  "\<tab>":   ActionNoop,
  "G":        ActionNoop,
  "?":        ActionNoop,
  "H":        ActionNoop,
  "\<right>": ActionNoop,
  "P":        ActionNoop,
  "\<enter>": ActionNoop,
  "D":        ActionNoop,
  "R":        ActionNoop,
  "E":        ActionNoop,
  "N":        ActionNoop,
  "B":        ActionNoop,
  "I":        ActionNoop,
  "V":        ActionNoop,
  "S":        ActionNoop,
  "K":        ActionNoop,
  "T":        ActionNoop,
  "~":        ActionNoop,
  "-":        ActionNoop,
  ".":        ActionNoop,
  "=":        ActionNoop,
  "U":        ActionNoop,
  "<":        ActionNoop,
  "\<up>":    ActionNoop,
  "Y":        ActionNoop,
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
# Helper Functions {{{
def Suffix(attr: string, mode: string): string
  if attr == 'sp' && mode == 'cterm'
    return 'ul'
  endif
  return attr
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
  sX     = popup_getoptions(winid).col
  sY     = popup_getoptions(winid).line
  sWinID = -1
enddef

def HandleEvent(winid: number, rawKeyCode: string): bool
  sEventHandled = false

  sKeyCode = get(Config.KeyAliases(), rawKeyCode, rawKeyCode)

  if kKeyMap->has_key(sKeyCode)
    kKeyMap[sKeyCode]()
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
