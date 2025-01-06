vim9script

import 'libreactive.vim' as react

export class TextProperty
  #   #
  #  # A simple abstraction on a Vim text property, working with characters
  # # instead of byte indexes. See :help text-properties.
  ##
  var type: string     # Text property type (created with prop_type_add())
  var xl:   number     # 0-based start position of the property, in characters (composed chars not counted separately)
  var xr:   number     # One past the last character of the property
  var id:   number = 1 # Optional property ID
endclass

export class TextLine
  #   #
  #  # A string with attached text properties.
  # #
  ##
  var text:  string
  var props: list<TextProperty> = []

  def Format(): dict<any>
    #   #
    #  # Return the text line as a dictionary suitable for a popup.
    # #
    ##
    var props: list<dict<any>> = []

    for prop in this.props
      var xl = byteidx(this.text, prop.xl)
      var xr = byteidx(this.text, prop.xr)
      props->add({col: 1 + xl, length: xr - xl, type: prop.type, id: prop.id})
    endfor

    return {text: this.text, props: props}
  enddef
endclass

def AddTextProperties(bufnr: number, lnum: number, line: TextLine)
  #   #
  #  # Add the text properties of a text line to the buffer.
  # #
  ##
  for prop in line.props
    var xl = byteidx(line.text, prop.xl)
    var xr = byteidx(line.text, prop.xr)

    prop_add(lnum, 1 + xl, {
      type:   prop.type,
      length: xr - xl,
      bufnr:  bufnr,
      id:     prop.id,
    })
  endfor
enddef

def DrawLines(bufnr: number, lnum: number, lines: list<TextLine>)
  #   #
  #  # Draw the given lines on the buffer starting at `lnum`.
  # #
  ##

  # Make sure the buffer has enough lines
  var max_lnum = lnum + len(lines) - 1
  var linecount  = getbufinfo(bufnr)[0].linecount

  if max_lnum > linecount
    appendbufline(bufnr, '$', repeat([''], max_lnum - linecount))
  endif

  # Draw the lines
  var i = lnum

  for line in lines
    setbufline(bufnr, i, line.text)
    AddTextProperties(bufnr, i, line)
    ++i
  endfor
enddef

export interface IView
  #   #
  #  # Interface for hierarchical views.
  # #
  ##
  var parent:   IView
  var children: list<IView>

  def Body(): list<TextLine>
  def SetVisible(state: bool)
  def IsVisible(): bool
endinterface

def Height(view: IView): number
  return len(view.Body())
enddef

export interface IUpdatableView
  #   #
  #  # Interface for (leaf) views whose content is not static.
  # #
  ##
  def Update()
endinterface

export interface ISelectableView extends IUpdatableView
  #   #
  #  # Interface for (leaf) views that can be selected to be updated.
  # #
  ##
  var selected: react.Property # bool
endinterface

def LineNumber(view: IView): number
  if view.parent == null
    return 1
  endif

  var i = 0
  var items = view.parent.children
  var lnum = LineNumber(view.parent)

  while i < len(items) && items[i] isnot view
    lnum += Height(items[i])
    ++i
  endwhile

  return lnum
enddef

export abstract class LeafView implements IView
  #   #
  #  # A leaf view has actual content that can be drawn in a buffer.
  # #
  ##
  var   parent:   IView = null_object
  const children: list<IView> = []

  var  _visible   = react.Property.new(true)
  var  _collapsed = react.Property.new(false)
  var  _content   = react.Property.new([])
  # The height of the view last time it was rendered: it may be different from
  # len(this.Body()).
  var  _height  = 0

  def Body(): list<TextLine>
    if this._collapsed.Get()
      return []
    endif

    return this._content.Get()
  enddef

  def SetVisible(state: bool)
    this._collapsed.Set(!state)
    this._visible.Set(state)
  enddef

  def IsVisible(): bool
    return this._visible.Get()
  enddef

  def Render(bufnr: number)
    #   # Render a view in a buffer. This method may be called inside
    #  # an effect to automatically re-render a view.
    # # Accesses two properties: visible and (indirectly) _collapsed.
    ##
    if !this._visible.Get()
      return
    endif

    var lnum       = LineNumber(this)
    var body       = this.Body()
    var old_height = this._height
    var new_height = len(body)

    if new_height == old_height # Fast path
      DrawLines(bufnr, lnum, body)
      return
    endif

    # Adjust the vertical space to the new size of the view
    if new_height > old_height
      var linecount  = getbufinfo(bufnr)[0].linecount
      var is_empty = linecount == 1 && empty(getbufoneline(bufnr, 1))

      if !is_empty
        appendbufline(bufnr, lnum, repeat([''], new_height - old_height))
      endif
    else
      deletebufline(bufnr, lnum + new_height, lnum + old_height - 1)
    endif

    this._height = new_height

    DrawLines(bufnr, lnum, body)
  enddef
endclass

export class UpdatableView extends LeafView implements IUpdatableView
  #   # A leaf view which is automatically updated when its observed state
  #  # changes. Subclasses should call super.Init() in new() and override
  # # Update().
  ##
  def Init()
    react.CreateEffect(this.Update)
  enddef

  def Update()
  enddef
endclass

export class SelectableView extends UpdatableView implements ISelectableView
  #   #
  #  # An updatable view that can be selected to modify its observed state.
  # # Subclasses should call super.Init() in new() and override Update().
  ##
  var selected = react.Property.new(false)
endclass

export class ContainerView implements IView
  #   #
  #  # A container for views and other containers.
  # #
  ##
  var  parent:   IView          = null_object
  var  children: list<IView>    = []
  var _visible:  react.Property = react.Property.new(true)

  def Body(): list<TextLine>
    var body: list<TextLine> = []

    for child in this.children
      body += child.Body()
    endfor

    return body
  enddef

  def SetVisible(state: bool)
    for child in this.children
      child.SetVisible(state)
    endfor

    this._visible.Set(state)
  enddef

  def IsVisible(): bool
    return this._visible.Get()
  enddef

  def AddView(view: IView)
    view.parent = this
    this.children->add(view)
  enddef
endclass

export def StartRendering(view: IView, bufnr: number)
  if empty(view.children)
    react.CreateEffect(() => (<LeafView>view).Render(bufnr))
    return
  endif

  for child in view.children
    StartRendering(child, bufnr)
  endfor
enddef
