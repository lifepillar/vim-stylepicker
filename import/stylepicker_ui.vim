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
    #  # Return the text line as a dictionary suitable for popup_settext().
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

export class View
  #   #
  #  # Base class for all views and containers.
  # #
  ##
  var  parent:    View         = null_object
  var  children:  list<View>   = []
  var _visible: react.Property = react.Property.new(true)

  def Body(): list<TextLine>
    return []
  enddef

  def Height(): number
    return 0
  enddef

  def SetVisible(state: bool)
    this._visible.Set(state)
  enddef

  def IsVisible(): bool
    return this._visible.Get()
  enddef

  def RespondToEvent(lnum: number, keyCode: string): bool
    return false
  enddef
endclass

def LineNumber(view: View): number
  #   # Return the line number where `view` should be drawn.
  #  # Note that this function must be pure: to avoid side effects, it should
  # # not (directly or indirectly) access any property.
  ##
  if view.parent == null
    return 1
  endif

  var i = 0
  var lnum = LineNumber(view.parent)
  var items = view.parent.children

  while i < len(items) && items[i] isnot view
    lnum += items[i].Height()
    ++i
  endwhile

  return lnum
enddef

export class LeafView extends View
  #   #
  #  # A leaf view has actual content that can be drawn in a buffer.
  # #
  ##
  var  _collapsed  = react.Property.new(false)
  var  _content    = react.Property.new([])
  var  _old_height = 0 # Height of the view last time it was rendered
  var  _height     = 0 # Current height of the view

  def Body(): list<TextLine>
    if this._collapsed.Get()
      return []
    endif

    return this._content.Get()
  enddef

  def Height(): number
    #   # Return the height of this view.
    #  #
    # # NOTE: returns the correct height only after the view has been
    ## rendered at least once and only if the view is visible.
    return this._height
  enddef

  def SetVisible(state: bool)
    this._collapsed.Set(!state) # Remove the view from the buffer
    this._visible.Set(state) # Stop observing this.Body()'s properties
  enddef

  def Render(bufnr: number)
    #   # Render a view in a buffer. This method may be called inside
    #  # an effect to automatically re-render a view.
    # # Accesses two properties: this._visible and this._collapsed (the latter
    ##  indirectly via this.Body()).
    if !this._visible.Get()
      return
    endif

    var lnum         = LineNumber(this)
    var body         = this.Body()
    var old_height   = this._old_height
    var this._height = len(this.Body())

    if this._height == old_height # Fast path
      DrawLines(bufnr, lnum, body)
      return
    endif

    # Adjust the vertical space to the new size of the view
    if this._height > old_height
      var linecount  = getbufinfo(bufnr)[0].linecount
      var is_empty = linecount == 1 && empty(getbufoneline(bufnr, 1))

      if !is_empty
        appendbufline(bufnr, lnum, repeat([''], this._height - old_height))
      endif
    else
      deletebufline(bufnr, lnum + this._height, lnum + old_height - 1)
    endif

    this._old_height = this._height

    DrawLines(bufnr, lnum, body)
  enddef
endclass

export class ContainerView extends View
  #   #
  #  # A container for views and other containers.
  # #
  ##
  def Body(): list<TextLine>
    var body: list<TextLine> = []

    for child in this.children
      body += child.Body()
    endfor

    return body
  enddef

  def Height(): number
    var height = 0

    for child in this.children
      height += child.Height()
    endfor

    return height
  enddef

  def SetVisible(state: bool)
    for child in this.children
      child.SetVisible(state)
    endfor

    this._visible.Set(state)
  enddef

  def AddView(view: View)
    view.parent = this
    this.children->add(view)
  enddef

  def RespondToEvent(lnum: number, keyCode: string): bool
    var lnum_   = lnum
    var i       = 0
    var handled = false

    # Find the child containing lnum
    while i < len(this.children)
      var view   = this.children[i]
      var height = view.Height()

      if lnum_ <= height # Forward the event to the child
        handled = view.RespondToEvent(lnum_, keyCode)
        break
      endif

      lnum_ -= height
      ++i
    endwhile

    return handled
  enddef
endclass

export interface IUpdatable
  #   #
  #  # Interface for (leaf) views whose content is not static.
  # #
  ##
  def Update()
endinterface

export interface ISelectable extends IUpdatable
  #   #
  #  # Interface for (leaf) views that can be selected to be updated.
  # #
  ##
  var selected: react.Property # bool
endinterface

export class UpdatableView extends LeafView implements IUpdatable
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

export class SelectableView extends UpdatableView implements ISelectable
  #   #
  #  # An updatable view that can be selected to modify its observed state.
  # # Subclasses should call super.Init() in new() and override Update().
  ##
  var selected = react.Property.new(false)
endclass

export def StartRendering(view: View, bufnr: number)
  if empty(view.children)
    react.CreateEffect(() => (<LeafView>view).Render(bufnr))
    return
  endif

  for child in view.children
    StartRendering(child, bufnr)
  endfor
enddef
