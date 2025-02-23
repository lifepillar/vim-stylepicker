vim9script

#   # A simple line-oriented UI library.
#  # "Line-oriented" means that the rendering unit is a full horizontal line
# # rather than a single character. Views can be vertically stacked, but not
## horizontally. This works fine for the style picker UI.

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
  # # The view hierarchy is grounded on the *natural correspondence* between
  ## forests and binary trees. See TAOCP, §2.3.2.
  var  parent:    View           = this
  var  llink:     View           = this # Left subtree
  var  rlink:     View           = this # Right subtree
  var  ltag:      bool           = false # false=thread, true=link to first child
  var  rtag:      bool           = false # false=thread, true=link to right sibling
  var _visible:   react.Property = react.Property.new(true)

  def string(): string
    return '[Base view]'
  enddef

  def Body(): list<TextLine>
    return []
  enddef

  def Height(): number
    return 0
  enddef

  def IsRoot(): bool
    return this.parent is this
  enddef

  def IsLeaf(): bool
    return !this.ltag
  enddef

  def Next(): View
    if this.rlink is this
      return this.FirstLeafView()
    endif

    var nextView = this.rlink

    if !this.rtag
      return nextView
    endif

    while nextView.ltag
      nextView = nextView.llink
    endwhile

    return nextView
  enddef

  def Previous(): View
    var prevView = this.llink

    if !this.ltag
      return prevView
    endif

    while prevView.rtag
      prevView = prevView.rlink
    endwhile

    return prevView
  enddef

  def FirstLeafView(): View
    return this
  enddef

  def SetVisible(state: bool)
    this._visible.Set(state)
  enddef

  def IsVisible(): bool
    return this._visible.Get()
  enddef

  def IsSelectable(): bool
    return false
  enddef

  def RespondToKeyEvent(keyCode: string): bool
    if this.IsRoot()
      return false
    endif

    return this.parent.RespondToKeyEvent(keyCode)
  enddef

  def RespondToMouseEvent(lnum: number, col: number, keyCode: string): bool
    return false
  enddef

  def Render(bufnr: number)
  enddef
endclass

def LineNumber(view: View): number
  #   # Return the line number where `view` should be drawn.
  #  # Note that this function must be pure: to avoid side effects, it should
  # # not (directly or indirectly) access any property.
  ##
  if view.parent is view
    return 1
  endif

  var lnum = LineNumber(view.parent)
  var node = view.parent.llink

  while node isnot view
    lnum += node.Height()
    node = node.rlink
  endwhile

  return lnum
enddef

export class LeafView extends View
  #   #
  #  # A leaf view has actual content that can be drawn in a buffer.
  # #
  ##
  var _collapsed  = react.Property.new(false)
  var _content    = react.Property.new([])
  var _old_height = 0 # Height of the view last time it was rendered
  var _height     = 0 # Current height of the view

  def string(): string
    return join(mapnew(this._content.Get(), (_, line: TextLine) => line.text))
  enddef

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
    react.CreateEffect(() => this.Render_(bufnr))
  enddef

  def Render_(bufnr: number)
    #   # Render a view in a buffer. This method may be called inside
    #  # an effect to automatically re-render a view.
    # # Accesses two properties: this._visible and this._collapsed (the latter
    ##  indirectly via this.Body()).
    if !this._visible.Get()
      return
    endif

    var lnum       = LineNumber(this)
    var body       = this.Body()
    var old_height = this._old_height

    this._height = len(this.Body())

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
  def string(): string
    if this.parent is this
      return '[Root view]'
    endif

    return $'[Subview of {this.parent.string()}]'
  enddef

  def Child(index: number): View
    var i = 0
    var child = this.llink

    while i < index
      child = child.rlink
      ++i
    endwhile

    return child
  enddef

  def NumChildren(): number
    if this.IsLeaf()
      return 0
    endif

    var i = 1
    var child = this.llink

    while child.rtag
      ++i
      child = child.rlink
    endwhile

    return i
  enddef

  def ApplyToChildren(F: func(View))
    if this.IsLeaf()
      return
    endif

    var node = this.llink

    F(node)

    while node.rtag
      node = node.rlink
      F(node)
    endwhile
  enddef

  def Body(): list<TextLine>
    var body: list<TextLine> = []

    this.ApplyToChildren((child: View) => {
      body += child.Body()
    })

    return body
  enddef

  def Height(): number
    var height = 0

    this.ApplyToChildren((child: View) => {
      height += child.Height()
    })

    return height
  enddef

  def SetVisible(state: bool)
    this.ApplyToChildren((child: View) => {
      child.SetVisible(state)
    })
    this._visible.Set(state)
  enddef

  def FirstLeafView(): View
    var node: View = this

    while node.ltag
      node = node.llink
    endwhile

    return node
  enddef

  def AddView(view: View)
    view.parent = this

    # Adapted from TAOCP, §2.3.1 (Traversing Binary Trees), Algorithm I
    if this.IsLeaf() # Add view as the left subtree of this
      var leaf = view.FirstLeafView()

      leaf.llink = this.llink
      leaf.ltag  = this.ltag
      this.llink = view
      this.ltag  = true
      view.rlink = this
      view.rtag  = false
    else # Add view as the right subtree of the rightmost child of this
      var node = this.Previous() # Rightmost child of this
      var leaf = view.FirstLeafView()

      view.rlink = node.rlink
      view.rtag  = node.rtag
      node.rlink = view
      node.rtag  = true
      leaf.llink = node
      leaf.ltag  = false
    endif
  enddef

  def Render(bufnr: number)
    this.ApplyToChildren((child: View) => child.Render(bufnr))
  enddef

  def RespondToMouseEvent(lnum: number, col: number, keyCode: string): bool
    if this.IsLeaf()
      return false
    endif

    var lnum_   = lnum
    var handled = false

    # Find the child containing lnum
    var child = this.llink

    while true
      var height = child.Height()

      if lnum_ <= height # Forward the event to the child
        handled = child.RespondToMouseEvent(lnum_, col, keyCode)
        break
      endif

      if !child.rtag
        break
      endif

      lnum_ -= height
      child = child.rlink
    endwhile

    return handled
  enddef
endclass

export class UpdatableView extends LeafView
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

export class SelectableView extends UpdatableView
  #   #
  #  # An updatable view that can be selected to modify its observed state.
  # # Subclasses should call super.Init() in new() and override Update().
  ##
  var _selected = react.Property.new(false)

  def SetSelected(state: bool)
    this._selected.Set(state)
  enddef

  def IsSelected(): bool
    return this._selected.Get()
  enddef

  def IsSelectable(): bool
    return true
  enddef
endclass
