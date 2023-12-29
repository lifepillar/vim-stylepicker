vim9script

import 'libcolor.vim'              as libcolor
import '../import/libproperty.vim' as libproperty
import autoload './util.vim'       as util

type  Number      = libproperty.Number
type  Observable  = libproperty.Observable
type  Observer    = libproperty.Observer
type  Property    = libproperty.Property
const Transaction = libproperty.Transaction

const Attr        = util.Attr
const ColorMode   = util.ColorMode
const StyleMode   = util.StyleMode
const Msg         = util.Msg

# Helper functions {{{
def EmptyColorToHex(): string
    return &background == 'dark' ? '#000000' : '#ffffff'
enddef

def ColorName2Hex(colorName: string, mode: string): string
  try
    if mode == 'cterm'
      return libcolor.CtermName2Hex(colorName)
    else
      return libcolor.RgbName2Hex(colorName)
    endif
  catch
    Msg(v:exception)
  endtry

  return EmptyColorToHex()
enddef

def ConvertToHexValue(value: string, mode: string): string
  if empty(value)
    return EmptyColorToHex()
  endif

  if value[0] == '#'
    return value
  endif

  if value =~ '^\a'
    return ColorName2Hex(value, mode)
  endif

  if mode == 'cterm' && value =~ '^\d\+$'
    return libcolor.ColorNumber2Hex(str2nr(value))
  endif

  # This should never happen
  Msg($"Cannot convert {mode} '{value}' to a hexadecimal color value")
  return EmptyColorToHex()
enddef

def FallbackColor(hiGroupName: string, attr: string, mode: string): string
  if attr == 'sp'
    return HlGetColor(hiGroupName, 'fg')
  endif

  return get(HlGet('Normal'), mode .. attr, '')
enddef

export def HlGet(name: string): dict<any>
  const info = get(hlget(name, true), 0, {})

  if empty(info)
    throw $"Highlight group '{name}' is undefined"
  endif

  return info
enddef

export def HlClear(name: string)
  hlset([{name: name, cleared: true}])
enddef

export def HlGetColor(hiGroupName: string, attr: string): string
  const info = HlGet(hiGroupName)
  const mode = ColorMode()
  const hlColor = get(
    info, Attr(mode, attr), FallbackColor(hiGroupName, attr, mode)
  )

  return ConvertToHexValue(hlColor, mode)
enddef

export def HlSetColor(hiGroupName: string, attr: string, hexValue: string)
  const mode = ColorMode()
  const info = HlGet(hiGroupName)

  if mode == 'cterm'
    const approx = libcolor.Approximate(hexValue)
    hlset([{
      name:                  hiGroupName,
      [Attr('gui',   attr)]: hexValue,
      [Attr('cterm', attr)]: string(approx.xterm),
    }])
  else
    hlset([{name: hiGroupName, [Attr(mode, attr)]: hexValue}])
  endif
enddef

export def HlGetStyle(hiGroupName: string): dict<bool>
  const mode = StyleMode()
  const info = HlGet(hiGroupName)

  return get(info, mode, {})
enddef

export def HlSetStyle(hiGroupName: string, style: dict<bool>)
  hlset([{name: hiGroupName, 'cterm': style, 'gui': style}])
enddef
# }}}

export class Color extends Observable implements Property, Observer
  var red:           Number
  var green:         Number
  var blue:          Number

  def new(hexValue: string, ...observers: list<Observer>)
    const [red, green, blue] = libcolor.Hex2Rgb(hexValue)

    this.red   = Number.new(red,   this)
    this.green = Number.new(green, this)
    this.blue  = Number.new(blue,  this)

    this.DoRegister(observers)
  enddef

  def Get(): string
    const r = this.red.Get()
    const g = this.green.Get()
    const b = this.blue.Get()
    return libcolor.Rgb2Hex(r, g, b)
  enddef

  def Set(hexValue: string)
    const [red, green, blue] = libcolor.Hex2Rgb(hexValue)

    Transaction(() => {
      this.red.Set(red)
      this.green.Set(green)
      this.blue.Set(blue)
    })
  enddef

  def Update()
    this.Notify()
  enddef
endclass

export class HiGroupColor extends Observable implements Property, Observer
  var hiGroup:  string
  var attr:  string # 'fg', 'bg', 'sp'
  var value: Color

  def new(this.hiGroup, this.attr, ...observers: list<Observer>)
    const c = HlGetColor(this.hiGroup, this.attr)
    this.value = Color.new(c, this)
    this.DoRegister(observers)
  enddef

  def Get(): string
    return this.value.Get()
  enddef

  def Set(hexValue: string)
    HlSetColor(this.hiGroup, this.attr, hexValue)
    this.value.Set(hexValue)
  enddef

  def Update()
    this.Notify()
  enddef
endclass


export class HiGroupStyle extends Observable implements Property
  var hiGroup: string
  var _value: dict<bool>

  def new(this.hiGroup, ...observers: list<Observer>)
    this._value = HlGetStyle(this.hiGroup)
    this.DoRegister(observers)
  enddef

  def Get(): dict<bool>
    return this._value
  enddef

  def Set(v: dict<bool>)
    HlSetStyle(this.hiGroup, v)

    const newValue = HlGetStyle(this.hiGroup)

    if newValue != this._value
      this._value = newValue
      this.Notify()
    endif
  enddef

  def Bold(): bool
    return get(this._value, 'bold', false)
  enddef

  def Italic(): bool
    return get(this._value, 'italic', false)
  enddef

  def Reverse(): bool
    return get(this._value, 'reverse', false)
  enddef

  def Standout(): bool
    return get(this._value, 'standout', false)
  enddef

  def Under(kind: string): bool
    return get(this._value, 'under' .. kind, false)
  enddef

  def AnyUnderline(): bool
    return get(this._value, 'underline',   false)
      ||   get(this._value, 'undercurl',   false)
      ||   get(this._value, 'underdotted', false)
      ||   get(this._value, 'underdashed', false)
      ||   get(this._value, 'underdouble', false)
  enddef

  def Strikethrough(): bool
    return get(this._value, 'strikethrough', false)
  enddef
endclass

export class HiGroup extends Observable implements Property, Observer
  var name:    string
  var color:   dict<HiGroupColor>
  var style:   HiGroupStyle

  def new(this.name, ...observers: list<Observer>)
    this.color = {
      fg: HiGroupColor.new(this.name, 'fg', this),
      bg: HiGroupColor.new(this.name, 'bg', this),
      sp: HiGroupColor.new(this.name, 'sp', this),
    }
    this.style = HiGroupStyle.new(this.name, this)
    this.DoRegister(observers)
  enddef

  def Get(): dict<any>
    return HlGet(this.name)
  enddef

  def Set(v: dict<any>)
    const mode  = ColorMode()

    Transaction(() => {
      for attr in ['fg', 'bg', 'sp']
        const key = Attr(mode, attr)
        if v->has_key(key)
          this.color[attr].Set(v[key])
        endif
      endfor

      if v->has_key('style')
        this.style.Set(v.style)
      endif
    })
  enddef

  def Update()
    this.Notify()
  enddef
endclass
