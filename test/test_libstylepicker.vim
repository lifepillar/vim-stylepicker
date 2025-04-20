vim9script

import 'libtinytest.vim'    as tt
import 'libreactive.vim'    as react
import 'libstylepicker.vim' as ui

type TextProperty  = ui.TextProperty
type TextLine      = ui.TextLine
type ViewContent   = ui.ViewContent
type StaticView    = ui.StaticView
type ReactiveView  = ui.ReactiveView
type VStack        = ui.VStack
type View          = ui.View


def Text(body: ViewContent): list<string>
  return mapnew(body, (_, item: dict<any>): string => item.text)
enddef


def Test_StylePicker_TextLineFormat()
  var l0 = TextLine.new('hello')

  assert_equal('hello', l0.value.text)
  assert_equal([],      l0.value.props)

  var p0 = TextProperty.new('stylepicker_foo', 0, 5, 42)

  l0.Add(p0)

  var expected = {
    text: 'hello',
    props: [{col: 1, length: 5, type: 'stylepicker_foo', id: 42}]
  }

  assert_equal(expected, l0.value)
enddef

def Test_StylePicker_SimpleStaticView()
  var view = StaticView.new([
    TextLine.new('A'),
    TextLine.new('B')
  ])

  assert_equal([
    {text: 'A', props: []},
    {text: 'B', props: []},
  ], view.Body())

  assert_false(view.focusable)
  assert_false(view.focused.Get())
  assert_equal(2, view.Height())
  assert_equal(0, view.NumChildren())
  assert_true(view.IsRoot())
  assert_true(view.IsLeaf())
  assert_true(view.Next() is view)
  assert_true(view.Previous() is view)
enddef

def Test_StylePicker_EmptyVStack()
  var vstack = VStack.new()

  assert_equal(0, vstack.NumChildren())
  assert_equal(0, vstack.Height())
enddef

def Test_StylePicker_SimpleVStack()
  var p1            = react.Property.new('initial text')
  var leafView      = ReactiveView.new(() => [TextLine.new($'p1 = {p1.Get()}')])
  var containerView = VStack.new([leafView])

  assert_false(containerView.focusable)
  assert_false(containerView.focused.Get())
  assert_equal(1, containerView.NumChildren())
  assert_true(containerView.Child(0) is leafView)
  assert_equal([{text: 'p1 = initial text', props: []}], containerView.Body())

  p1.Set('updated text')

  assert_equal([{text: 'p1 = updated text', props: []}], containerView.Body())
enddef

def Test_StylePicker_SimpleReactiveView()
  var a = react.Property.new('A')

  var view = ReactiveView.new(() => [
    TextLine.new(a.Get()),
    TextLine.new('B')
  ])

  assert_equal(2, view.Height())
  assert_false(view.focusable)
  assert_equal(0, view.NumChildren())
  assert_false(view.focused.Get())
  assert_true(view.IsRoot())
  assert_true(view.IsLeaf())
  assert_true(view.Next() is view)
  assert_true(view.Previous() is view)

  assert_equal([
    {text: 'A', props: []},
    {text: 'B', props: []},
  ], view.Body())

  a.Set('X')

  assert_equal([
    {text: 'X', props: []},
    {text: 'B', props: []},
  ], view.Body())
enddef

def Test_StylePicker_NodeLinks()
  var v1 = ReactiveView.new(() => [
    TextLine.new('a'),
    TextLine.new('b'),
    TextLine.new('c'),
  ])
  var c1 = VStack.new([v1])

  assert_true(c1.llink is v1, '1')
  assert_true(c1.ltag, '2')
  assert_true(c1.rlink is c1, '3')
  assert_false(c1.rtag, '4')
  assert_true(v1.parent is c1, '5')
  assert_true(v1.rlink is c1, '6')
  assert_false(v1.rtag, '7')
  assert_true(v1.llink is c1, '8')
  assert_false(v1.ltag, '9')

  var leafView = ReactiveView.new(() => [TextLine.new('Hello'), TextLine.new('world')])

  assert_true(leafView.llink is leafView)
  assert_false(leafView.ltag)
  assert_true(leafView.rlink is leafView)
  assert_false(leafView.rtag)
  assert_true(leafView.Next() is leafView)
  assert_true(leafView.Previous() is leafView)

  var root = VStack.new([leafView])

  assert_true(root.llink is leafView, 'llink(root) is leaf')
  assert_true(root.rlink is root, 'rlink(root) is root')
  assert_true(root.ltag)
  assert_false(root.rtag)
  assert_true(root.Next() is leafView, 'next(root) is leaf')
  assert_true(root.Previous() is leafView, 'prev(root) is leaf')
  assert_true(leafView.Previous() is root, 'prev(leaf) is root')
  assert_true(leafView.Next() is root, 'next(leaf) is root')
enddef

def Test_StylePicker_NestedViews()
  var p1            = react.Property.new('text')
  var staticView    = StaticView.new([TextLine.new('x'), TextLine.new('y')])
  var updatableView = ReactiveView.new(() => [TextLine.new(p1.Get())])
  var inner         = VStack.new([staticView])
  var outer         = VStack.new([inner, updatableView])

  # :-- outer vstack -----------:
  # | :-- inner vstack -------: |
  # | | :-- static view ----: | |
  # | | |        x          | | |
  # | | |        y          | | |
  # | | :-------------------: | |
  # | :-----------------------: |
  # |   :-- updatable view -:   |
  # |   |       text        |   |
  # |   :-------------------:   |
  # :---------------------------:

  assert_equal(['x', 'y'], Text(staticView.Body()))
  assert_equal(['x', 'y'], Text(inner.Body()))
  assert_equal(['x', 'y', 'text'], Text(outer.Body()))

  p1.Set('new text')

  assert_equal(['x', 'y', 'new text'], Text(outer.Body()))
  assert_equal(2, outer.NumChildren())
  assert_equal(1, inner.NumChildren())
  assert_equal(0, staticView.NumChildren())
  assert_equal(0, updatableView.NumChildren())
enddef

def Test_StylePicker_UnicodeTextLine()
  var text = "❯❯ XYZ"
  var l0 = TextLine.new(text, [TextProperty.new('foo', 3, 4, 42)])
  var view = StaticView.new([l0])

  var expected = [{
    text: text,
    props: [{col: 8, length: 1, type: 'foo', id: 42}]
  }]

  assert_equal(expected, view.Body())
enddef

def Test_StylePicker_ViewFollowedByContainer()
  var header = StaticView.new([TextLine.new('Header')])
  var r      = StaticView.new([TextLine.new('r')])
  var g      = StaticView.new([TextLine.new('g')])
  var b      = StaticView.new([TextLine.new('b')])
  var rgb    = VStack.new([r, g, b])
  var root   = VStack.new([header, rgb])

  assert_equal(['Header', 'r', 'g', 'b'], Text(root.Body()))
  assert_equal(['r', 'g', 'b'], Text(rgb.Body()))
  assert_equal(['r'], Text(r.Body()))
  assert_equal(['g'], Text(g.Body()))
  assert_equal(['b'], Text(b.Body()))
  assert_equal(['Header'], Text(header.Body()))
enddef

def Test_StylePicker_ViewHierarchy()
#                    ┌─────┐..............
#  ..........▶ ┌─────│root │ ◀.........  .
#  .           │     └─────┘          .  .
#  .        ┌──▼──┐           ┌─────┐..  .
#  .    ┌───│box1 │──────────►│box2 │    .
#  .    │   └─────┘ ◀........ └──┬──┘◀.  .
#  .    │      ▲            .    │    .  .
#  .    ▼      ......       .    ▼    .  .
#  . ┌─────┐       ┌─────┐  . ┌─────┐ .  .
#  ..│leaf1│──────►│leaf2│  ..│leaf3│..  .
#    └─────┘       └─────┘    └─────┘    .
#       ▲             .                  .
#       ..................................

  var leaf1 = ReactiveView.new(() => [TextLine.new('A')])
  var leaf2 = ReactiveView.new(() => [TextLine.new('B'), TextLine.new('C')])
  var leaf3 = ReactiveView.new(() => [TextLine.new('D'), TextLine.new('E')])
  var box1  = VStack.new()
  var box2  = VStack.new()
  var root  = VStack.new()

  box1.AddView(leaf1)
  root.AddView(box1)
  box1.AddView(leaf2)
  box2.AddView(leaf3)
  root.AddView(box2)

  assert_equal([
    {text: 'A', props: []},
    {text: 'B', props: []},
    {text: 'C', props: []},
    {text: 'D', props: []},
    {text: 'E', props: []},
  ], root.Body())

  assert_true(box1.FirstLeaf() is leaf1, 'firstSubview(box1) is leaf1')
  assert_true(root.llink is box1, 'llink(root) is box1')
  assert_true(root.rlink is root, 'rlink(root) is root')
  assert_true(root.ltag)
  assert_false(root.rtag)
  assert_true(root.Next() is leaf1, 'next(root) is leaf1')
  assert_true(root.Previous() is box2, 'prev(root) is box2')

  assert_true(box1.llink is leaf1, 'llink(box1) is leaf1')
  assert_true(box1.rlink is box2, 'rlink(box1) is box2')
  assert_true(box1.ltag)
  assert_true(box1.rtag)
  assert_true(box1.Next() is leaf3, 'next(box1) is leaf3')
  assert_true(box1.Previous() is leaf2, 'prev(box1) is leaf2')

  assert_true(leaf1.llink is root, 'llink(leaf1) is root')
  assert_true(leaf1.rlink is leaf2, 'rlink(leaf1) is leaf2')
  assert_false(leaf1.ltag)
  assert_true(leaf1.rtag)
  assert_true(leaf1.Next() is leaf2, 'next(leaf1) is leaf2')
  assert_true(leaf1.Previous() is root, 'prev(leaf1) is root')

  assert_true(leaf2.llink is leaf1, 'llink(leaf2) is leaf1')
  assert_true(leaf2.rlink is box1, 'rlink(leaf2) is box1')
  assert_false(leaf2.ltag)
  assert_false(leaf2.rtag)
  assert_true(leaf2.Next() is box1, 'next(leaf2) is box1')
  assert_true(leaf2.Previous() is leaf1, 'prev(leaf2) is leaf1')

  assert_true(box2.llink is leaf3, 'llink(box2) is leaf3')
  assert_true(box2.rlink is root, 'rlink(box2) is root')
  assert_true(box2.ltag)
  assert_false(box2.rtag)
  assert_true(box2.Next() is root, 'next(box2) is root')
  assert_true(box2.Previous() is leaf3, 'prev(box2) is leaf3')

  assert_true(leaf3.llink is box1, 'llink(leaf3) is box1')
  assert_true(leaf3.rlink is box2, 'rlink(leaf3) is box2')
  assert_false(leaf3.ltag)
  assert_false(leaf3.rtag)
  assert_true(leaf3.Next() is box2, 'next(leaf3) is box2')
  assert_true(leaf3.Previous() is box1, 'prev(leaf3) is box1')
enddef

def Test_StylePicker_RespondToKeyEvent()
  var v1    = StaticView.new(mapnew(['a', 'b', 'c'], (_, t) => TextLine.new(t)))
  var c1    = VStack.new([v1])
  var root  = VStack.new([c1])

  def Act()
  enddef

  v1.OnKeyPress('K', Act)
  c1.OnKeyPress('C', Act)

  assert_equal(3, v1.Height())
  assert_equal(3, c1.Height())
  assert_equal(3, root.Height())

  # Key events are forwarded to parent
  assert_true(v1.RespondToKeyEvent('K'))
  assert_true(v1.RespondToKeyEvent('C'))
  assert_true(c1.RespondToKeyEvent('C'))
  assert_false(v1.RespondToKeyEvent('X'))
  assert_false(c1.RespondToKeyEvent('K'))
  assert_false(root.RespondToKeyEvent('K'))
  assert_false(root.RespondToKeyEvent('C'))
enddef

def Test_StylePicker_RespondToMouseEvent()
  var v1    = StaticView.new(mapnew(['a', 'b', 'c'], (_, t) => TextLine.new(t)))
  var c1    = VStack.new([v1])
  var root  = VStack.new([c1])

  def Act(lnum: number, col: number)
  enddef

  root.OnMouseEvent("\<LeftMouse>", Act)
  c1.OnMouseEvent("\<RightMouse>",  Act)
  v1.OnMouseEvent("\<LeftRelease>", Act)

  # Mouse events are forwarded to children
  for lnum in [1, 2, 3]
    assert_true(root.RespondToMouseEvent("\<LeftMouse>", lnum, 1))
    assert_false(c1.RespondToMouseEvent("\<LeftMouse>", lnum, 1))
    assert_false(v1.RespondToMouseEvent("\<LeftMouse>", lnum, 1))
    assert_true(root.RespondToMouseEvent("\<RightMouse>", lnum, 1))
    assert_true(c1.RespondToMouseEvent("\<RightMouse>", lnum, 1))
    assert_false(v1.RespondToMouseEvent("\<RightMouse>", lnum, 1))
    assert_true(root.RespondToMouseEvent("\<LeftRelease>", lnum, 1))
    assert_true(c1.RespondToMouseEvent("\<LeftRelease>", lnum, 1))
    assert_true(v1.RespondToMouseEvent("\<LeftRelease>", lnum, 1))
  endfor
enddef

def Test_StylePicker_FocusedModifier()
  var view = ReactiveView.new(() => [TextLine.new('A')])
  var isFocused = view.focused.Get()

  assert_false(isFocused)

  react.CreateEffect(() => {
    isFocused = view.focused.Get()
  })

  view.Focused(true)

  assert_true(isFocused)

  var result = view.Focused(false).Focused(true)

  assert_true(isFocused)
  assert_true(result is view)
enddef


tt.Run('_StylePicker_')
