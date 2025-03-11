vim9script

#   # A simple line-oriented UI library.
#  # "Line-oriented" means that the rendering unit is a full horizontal line
# # rather than a single character. Views can be vertically stacked, but not
## horizontally. This works fine for the style picker UI.

import 'libreactive.vim' as react

export type Action = func(): bool

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
  var  parent:     View = this  # Container view
  var  llink:      View = this  # Left subtree
  var  rlink:      View = this  # Right subtree
  var  ltag:       bool = false # false=thread, true=link to first child
  var  rtag:       bool = false # false=thread, true=link to right sibling
  var  focusable:  bool = false

  var _hidden:    react.Property = react.Property.new(false)
  var _action:    dict<Action>   = {}

  def string(): string
    return '[View]'
  enddef

  def Body(): list<TextLine>
    return []
  enddef

  def IsHidden(): bool
    return this._hidden.Get()
  enddef

  def Hidden(isHidden: bool)
    this._hidden.Set(isHidden)
  enddef

  def Height(): number
    return len(this.Body())
  enddef

  def IsRoot(): bool
    return this.parent is this
  enddef

  def IsLeaf(): bool
    return !this.ltag
  enddef

  def Next(): View
    if this.rlink is this
      return this.FirstLeaf()
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

  def FirstLeaf(): View
    return this
  enddef

  def OnKeyCode(keyCode: string, F: Action): View
    this._action[keyCode] = F
    return this
  enddef

  def RespondToKeyEvent(keyCode: string): bool
    if this._action->has_key(keyCode) && this._action[keyCode]()
      return true
    endif

    if this.IsRoot()
      return false
    endif

    return this.parent.RespondToKeyEvent(keyCode)
  enddef

  def RespondToMouseEvent(keyCode: string, lnum: number, col: number): bool
    if this._action->has_key(keyCode) && this._action[keyCode]()
      return true
    endif

    if this.IsLeaf()
      return false
    endif

    # Find the child containing lnum
    var lnum_ = lnum
    var child = this.llink

    while true
      var height = child.Height()

      if lnum_ <= height # Forward the event to the child
        return child.RespondToMouseEvent(keyCode, lnum_, col)
      endif

      if !child.rtag
        break
      endif

      lnum_ -= height
      child = child.rlink
    endwhile

    return false
  enddef

  def Offset(): number
    #   #
    #  # Return the offset of this view with respect to the root container.
    # #
    ##
    if this.IsRoot()
      return 0
    endif

    var offset = this.parent.Offset()
    var node = this.parent.llink

    while node isnot this
      offset += node.Height()
      node = node.rlink
    endwhile

    return offset
  enddef

  def Paint(bufnr: number)
  enddef

  def Unpaint(bufnr: number)
  enddef

  def Render(bufnr: number)
    react.CreateEffect(() => {
      if this.IsHidden()
        this.Unpaint(bufnr)
      else
        this.Paint(bufnr)
      endif
    })
  enddef
endclass

export class ContentView extends View
  #   #
  #  # A leaf view that has actual content that can be drawn in a buffer.
  # #
  ##
  var  content    = react.Property.new([])
  var _old_height = 0 # Height of the view last time it was rendered

  def string(): string
    return join(mapnew(this.Body(), (_, line: TextLine) => line.text))
  enddef

  def Body(): list<TextLine>
    if this._hidden.Get()
      return []
    endif

    return this.content.Get()
  enddef

  def Unpaint(bufnr: number)
    var lnum = 1 + this.Offset()
    deletebufline(bufnr, lnum, lnum + this._old_height - 1)
    this._old_height = 0
  enddef

  def Paint(bufnr: number)
    var body       = this.Body()
    var height     = this.Height()
    var lnum       = 1 + this.Offset()
    var old_height = this._old_height

    if height == old_height # Fast path
      DrawLines(bufnr, lnum, body)
      return
    endif

    # Adjust the vertical space to the new size of the view
    if height > old_height
      var linecount  = getbufinfo(bufnr)[0].linecount
      var is_empty = linecount == 1 && empty(getbufoneline(bufnr, 1))

      if !is_empty
        appendbufline(bufnr, lnum, repeat([''], height - old_height))
      endif
    else
      deletebufline(bufnr, lnum + height, lnum + old_height - 1)
    endif

    this._old_height = height

    DrawLines(bufnr, lnum, body)
  enddef
endclass

export class VStack extends View
  #   #
  #  # A container to vertically stack other views.
  # #
  ##
  def new(views: list<View> = [])
    for view in views
      this.AddView(view)
    endfor
  enddef

  def string(): string
    if this.IsRoot()
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

    while true
      F(node)

      if !node.rtag
        break
      endif

      node = node.rlink
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

  def Hidden(isHidden: bool)
    this.ApplyToChildren((child: View) => {
      child.Hidden(isHidden)
    })
    this._hidden.Set(isHidden)
  enddef

  def FirstLeaf(): View
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
      var leaf = view.FirstLeaf()

      leaf.llink = this.llink
      leaf.ltag  = this.ltag
      this.llink = view
      this.ltag  = true
      view.rlink = this
      view.rtag  = false
    else # Add view as the right subtree of the rightmost child of this
      var node = this.Previous() # Rightmost child of this
      var leaf = view.FirstLeaf()

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
endclass

export class UpdatableView extends ContentView
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

