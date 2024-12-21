vim9script

type Char         = string
type ScanLine     = list<Char>
type PropertyType = string

class TextProp
  var type:   string
  var xl:     number # included
  var xr:     number # excluded
  var id:     number = 1
endclass

def FrameBuffer(width: number, height: number): list<ScanLine>
  var lines: list<ScanLine> = []
  var line:       ScanLine  = repeat([' '], width)
  var i = 0

  while i < height
    lines->add(copy(line))
    ++i
  endwhile

  return lines
enddef

class Context
  var lines: list<ScanLine>
  var props: list<list<TextProp>> = []

  def new(width: number, height: number)
    this.Clear(width, height)
  enddef

  def Width(): number
    return len(this.lines[0])
  enddef

  def Height(): number
    return len(this.lines)
  enddef

  def Clear(width: number, height: number)
    this.lines = FrameBuffer(width, height)
    var i = 0

    while i < height
      this.props->add([])
      ++i
    endwhile
  enddef

  def PropAdd(ypos: number, prop: TextProp)
    this.props[ypos]->add(prop)
  enddef

  def Text(): list<string>
    return mapnew(this.lines, (_, line: ScanLine): string => join(line, ''))
  enddef

  def TextWithProperties(): list<dict<any>>
    var textProps: list<dict<any>> = []
    var yy = 0

    while yy < len(this.lines)
      var text = join(this.lines[yy], '')
      var props: list<dict<any>> = []

      for prop in this.props[yy]
        var xl = byteidx(text, prop.xl)
        var xr = byteidx(text, prop.xr)
        props->add({col: 1 + xl, length: xr - xl, type: prop.type, id: prop.id})
      endfor

      textProps->add({text: text, props: props})
      ++yy
    endwhile

    return textProps
  enddef

  def FillRect(
      xpos:      number,
      ypos:      number,
      width:     number,
      height:    number,
      fillChar:  Char         = ' ',
      propTypes: list<string> = []
      )
    var yy:   number = ypos
    var xmax: number = xpos + width
    var ymax: number = ypos + height

    if xmax > this.Width()
      xmax = this.Width()
    endif

    if ymax > this.Height()
      ymax = this.Height()
    endif

    while yy < ymax
      var xx = xpos

      while xx < xmax
        this.lines[yy][xx] = fillChar
        ++xx
      endwhile

      for propType in propTypes
        this.PropAdd(yy, TextProp.new(propType, xpos, xmax))
      endfor

      ++yy
    endwhile
  enddef

  def DrawText(xpos: number, ypos: number, text: string, props: list<TextProp> = [])
    var encoded: ScanLine = split(text, '\zs')
    var line:    ScanLine = this.lines[ypos]
    var xmax:    number   = xpos + len(encoded)

    if xmax > this.Width()
      xmax = this.Width()
      encoded = encoded[ : (xmax - xpos - 1)]
    endif

    line[xpos : (xmax - 1)] = encoded

    for prop in props
      this.PropAdd(ypos, TextProp.new(prop.type, prop.xl + xpos, prop.xr + xpos, prop.id))
    endfor
  enddef
endclass


class View
  public var xpos: number
  public var ypos: number

  var width:    number
  var height:   number
  var context:  Context
  var fillChar: Char = nr2char(41 + rand() % 60)

  def Paint()
    this.context.FillRect(this.xpos, this.ypos, this.width, this.height, this.fillChar)
  enddef
endclass


prop_type_delete('orange')
prop_type_add('orange', {highlight: 'DiffChange', priority: 2})
var ctx0 = Context.new(60, 24)
var view0 = View.new(20, 12, 10, 10, ctx0)
view0.Paint()
ctx0.DrawText(7, 16, ' Hello 🍺 world 🌗 💥 ', [TextProp.new('orange', 1, 6)])

popup_create(ctx0.Text(), {})

