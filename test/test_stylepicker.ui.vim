vim9script

import 'libtinytest.vim'    as tt
import 'libreactive.vim'    as react
import 'libstylepicker.vim' as ui

type TextProperty  = ui.TextProperty
type TextLine      = ui.TextLine
type LeafView      = ui.LeafView
type UpdatableView = ui.UpdatableView
type ContainerView = ui.ContainerView


def Text(body: list<TextLine>): list<string>
  return mapnew(body, (_, line: TextLine): string => line.text)
enddef

var sp0 = react.Property.new('')

class TestLeafView extends LeafView
  var eventTarget = ''

  def new(content: list<string>)
    var value = mapnew(content, (_, t): TextLine =>  TextLine.new(t))
    this._content.Set(value)
  enddef

  def RespondToEvent(lnum: number, keyCode: string): bool
    var handled = (keyCode == 'K')

    if handled
      var content: list<TextLine> = this._content.Get()
      this.eventTarget = content[lnum - 1].text
    endif

    return handled
  enddef
endclass

class TestUpdatableView extends UpdatableView
  var state: react.Property # string

  def new(this.state)
    super.Init()
  enddef

  def Update()
    this._content.Set([TextLine.new(this.state.Get())])
  enddef
endclass

def Test_StylePicker_TextLineFormat()
  var l0 = TextLine.new('hello')

  assert_equal('hello', l0.text)
  assert_equal([],      l0.props)

  var p0 = TextProperty.new('stylepicker_foo', 0, 5, 42)

  l0.props->add(p0)

  var textWithProperty = l0.Format()
  var expected = {
    text: 'hello',
    props: [{col: 1, length: 5, type: 'stylepicker_foo', id: 42}]
  }

  assert_equal(expected, l0.Format())
enddef

def Test_StylePicker_UnicodeTextLine()
  var text = "❯❯ XYZ"
  var l0 = TextLine.new(text, [TextProperty.new('foo', 3, 4, 42)])
  var textWithProperty = l0.Format()

  var expected = {
    text: text,
    props: [{col: 8, length: 1, type: 'foo', id: 42}]
  }

  assert_equal(expected, l0.Format())
enddef

def Test_StylePicker_LeafView()
  var leafView = TestLeafView.new(['hello', 'world'])
  var expected = [TextLine.new('hello'), TextLine.new('world')]

  assert_equal(expected, leafView.Body())

  leafView.SetVisible(false)

  assert_equal([], leafView.Body())

  leafView.SetVisible(true)

  assert_equal(expected, leafView.Body())
enddef

def Test_StylePicker_RenderView()
  var content = ['a', 'b', 'c']
  var view = TestLeafView.new(content)

  var bufnr = bufadd('StylePicker test buffer')
  bufload(bufnr)

  try
    view.Render(bufnr)

    assert_equal(content, getbufline(bufnr, 1, '$'))
  finally
    execute 'bwipe!' bufnr
  endtry
enddef

def Test_StylePicker_ContainerView()
  var outer = ContainerView.new()
  var inner = ContainerView.new()
  var view = TestLeafView.new(['x', 'y'])
  var p1 = react.Property.new('text')
  var updatableView = TestUpdatableView.new(p1)

  assert_equal([], inner.Body())

  inner.AddView(view)

  assert_equal(['x', 'y'], Text(view.Body()))
  assert_equal(['x', 'y'], Text(inner.Body()))

  outer.AddView(inner)

  assert_equal(['x', 'y'], Text(outer.Body()))

  var bufnr = bufadd('StylePicker test buffer')
  bufload(bufnr)

  try
    outer.Render(bufnr)

    # :-- outer ------------------:
    # | :-- inner --------------: |
    # | |         view          | |
    # | :-----------------------: |
    # |       updatableView       |
    # :---------------------------:

    assert_equal(['x', 'y'], getbufline(bufnr, 1, '$'))

    outer.AddView(updatableView)

    assert_equal(['x', 'y', 'text'], Text(outer.Body()))

    updatableView.state.Set('new text')

    assert_equal(['x', 'y', 'new text'], Text(outer.Body()))

    # Hiding views
    view.SetVisible(false)
    assert_equal(['new text'], Text(outer.Body()))

    view.SetVisible(true)
    assert_equal(['x', 'y', 'new text'], Text(outer.Body()))

    inner.SetVisible(false)
    assert_equal(['new text'], Text(outer.Body()))

    outer.SetVisible(false)
    assert_equal([], Text(outer.Body()))

    inner.SetVisible(true)
    assert_equal(['x', 'y'], Text(outer.Body()))

    inner.SetVisible(false)
    outer.SetVisible(true)
    assert_equal(['x', 'y', 'new text'], Text(outer.Body()))
  finally
    execute 'bwipe!' bufnr
  endtry
enddef

def Test_StylePicker_UpdatableView()
  var p1 = react.Property.new('initial text')
  var updatableView = TestUpdatableView.new(p1)
  var containerView = ContainerView.new()

  containerView.AddView(updatableView)

  var bufnr = bufadd('StylePicker test buffer')
  bufload(bufnr)

  try
    containerView.Render(bufnr)

    assert_equal(['initial text'], getbufline(bufnr, 1, '$'))

    p1.Set('final text')

    assert_equal(['final text'], getbufline(bufnr, 1, '$'))
  finally
    execute 'bwipe!' bufnr
  endtry
enddef

def Test_StylePicker_ViewFollowedByContainer()
  var header        = TestLeafView.new(['Header'])
  var r             = TestLeafView.new(['r'])
  var g             = TestLeafView.new(['g'])
  var b             = TestLeafView.new(['b'])
  var rgb           = ContainerView.new()
  var containerView = ContainerView.new()

  rgb.AddView(r)
  rgb.AddView(g)
  rgb.AddView(b)
  containerView.AddView(header)
  containerView.AddView(rgb)

  var bufnr = bufadd('StylePicker test buffer')
  bufload(bufnr)

  try
    containerView.Render(bufnr)

    assert_equal(['Header', 'r', 'g', 'b'], getbufline(bufnr, 1, '$'))
  finally
    execute 'bwipe!' bufnr
  endtry
enddef

def Test_StylePicker_RespondToEvent()
  var v1             = TestLeafView.new(['a', 'b', 'c'])
  var v2             = TestLeafView.new(['d', 'e'])
  var v3             = TestLeafView.new(['f', 'g', 'h', 'i'])
  var innerContainer = ContainerView.new()
  var containerView  = ContainerView.new()

  innerContainer.AddView(v1)
  innerContainer.AddView(v2)
  containerView.AddView(innerContainer)
  containerView.AddView(v3)

  # Until the views are rendered, their height is not set
  assert_equal(0, v1.Height())
  assert_equal(0, v2.Height())
  assert_equal(0, v3.Height())

  var bufnr = bufadd('StylePicker test buffer')
  bufload(bufnr)

  try
    containerView.Render(bufnr)

    assert_equal(3, v1.Height())
    assert_equal(2, v2.Height())
    assert_equal(4, v3.Height())

    var handled = containerView.RespondToEvent(2, 'N')

    assert_false(handled)
    assert_equal('', v1.eventTarget)

    handled = containerView.RespondToEvent(2, 'K')

    assert_true(handled)
    assert_equal('b', v1.eventTarget)
    assert_equal('',  v2.eventTarget)

    handled = containerView.RespondToEvent(5, 'K')

    assert_true(handled)
    assert_equal('e', v2.eventTarget)
    assert_equal('b',  v1.eventTarget)

    handled = containerView.RespondToEvent(6, 'K')

    assert_true(handled)
    assert_equal('f', v3.eventTarget)
  finally
    execute 'bwipe!' bufnr
  endtry
enddef

def Test_StylePicker_AddViewToContainer()
  var c1 = ContainerView.new()
  var v1 = TestLeafView.new(['a', 'b', 'c'])

  c1.AddView(v1)

  assert_true(c1.llink is v1, '1')
  assert_true(c1.ltag, '2')
  assert_true(c1.rlink is c1, '3')
  assert_false(c1.rtag, '4')
  assert_true(v1.parent is c1, '5')
  assert_true(v1.rlink is c1, '6')
  assert_false(v1.rtag, '7')
  assert_true(v1.llink is c1, '8')
  assert_false(v1.ltag, '9')

  var bufnr = bufadd('StylePicker test buffer')
  bufload(bufnr)

  try
    c1.Render(bufnr)
  finally
    execute 'bwipe!' bufnr
  endtry
enddef

def Test_StylePicker_RenderLeaf()
  var leafView = TestLeafView.new(['Hello', 'world'])

  assert_true(leafView.llink is leafView)
  assert_false(leafView.ltag)
  assert_true(leafView.rlink is leafView)
  assert_false(leafView.rtag)
  assert_true(leafView.Next() is leafView)
  assert_true(leafView.Previous() is leafView)

  var bufnr = bufadd('StylePicker test buffer')
  bufload(bufnr)

  try
    leafView.Render(bufnr)

    assert_equal(['Hello', 'world'], getbufline(bufnr, 1, '$'))
  finally
    execute 'bwipe!' bufnr
  endtry
enddef

def Test_StylePicker_RenderLeafInsideContainer()
  var leaf = TestLeafView.new(['hello', 'world'])
  var root = ContainerView.new()

  root.AddView(leaf)

  assert_true(root.llink is leaf, 'llink(root) is leaf')
  assert_true(root.ltag)
  assert_true(root.Next() is root, 'next(root) is leaf')
  assert_false(root.rtag)
  assert_true(leaf.Previous() is root, 'prev(leaf) is root')
  assert_true(leaf.Next() is root, 'next(leaf) is root')
  assert_true(root.Previous() is leaf, 'prev(root) is leaf')
  assert_true(root.Next() is root, 'next(root) is root')

  var bufnr = bufadd('StylePicker test buffer')
  bufload(bufnr)

  try
    root.Render(bufnr)

    assert_equal(['hello', 'world'], getbufline(bufnr, 1, '$'))
  finally
    execute 'bwipe!' bufnr
  endtry
enddef


def Test_StylePicker_RenderHierarchy()
#                       ......
#                       ▼    .
#                    ┌─────┐..
#  ..........▶ ┌─────│root │ ◀.........
#  .           │     └─────┘          .
#  .        ┌──▼──┐           ┌─────┐..
#  .    ┌───│box1 │──────────►│box2 │
#  .    │   └─────┘ ◀........ └──┬──┘◀.
#  .    │      ▲            .    │    .
#  .    ▼      ......       .    ▼    .
#  . ┌─────┐       ┌─────┐  . ┌─────┐ .
#  ..│leaf1│──────►│leaf2│  ..│leaf3│..
#    └─────┘       └─────┘    └─────┘
#       ▲             .
#       ...............

  var leaf1 = TestLeafView.new(['A'])
  var leaf2 = TestLeafView.new(['B', 'C'])
  var leaf3 = TestLeafView.new(['D', 'E'])
  var box1  = ContainerView.new()
  var box2  = ContainerView.new()
  var root  = ContainerView.new()

  box1.AddView(leaf1)
  root.AddView(box1)
  box1.AddView(leaf2)
  box2.AddView(leaf3)
  root.AddView(box2)

  assert_true(box1.FirstLeafView() is leaf1, 'firstSubview(box1) is leaf1')
  assert_true(root.llink is box1, 'llink(root) is box1')
  assert_true(root.rlink is root, 'rlink(root) is root')
  assert_true(root.ltag)
  assert_false(root.rtag)
  assert_true(root.Next() is root, 'next(root) is root')
  assert_true(root.Previous() is box2, 'prev(root) is box2')
  assert_equal(2, root.NumChildren())
  assert_true(root.Child(0) is box1, 'child(0) is box1')
  assert_true(root.Child(1) is box2, 'child(1) is box2')

  assert_true(box1.llink is leaf1, 'llink(box1) is leaf1')
  assert_true(box1.rlink is box2, 'rlink(box1) is box2')
  assert_true(box1.ltag)
  assert_true(box1.rtag)
  assert_true(box1.Next() is leaf3, 'next(box1) is leaf3')
  assert_true(box1.Previous() is leaf2, 'prev(box1) is leaf2')
  assert_equal(2, box1.NumChildren())
  assert_true(box1.Child(0) is leaf1, 'child(0) is leaf1')
  assert_true(box1.Child(1) is leaf2, 'child(1) is leaf2')

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
  assert_equal(1, box2.NumChildren())
  assert_true(box2.Child(0) is leaf3, 'child(0) is leaf3')

  var bufnr = bufadd('StylePicker test buffer')
  bufload(bufnr)

  try
    root.Render(bufnr)

    assert_equal(['A', 'B', 'C', 'D', 'E'], getbufline(bufnr, 1, '$'))
  finally
    execute 'bwipe!' bufnr
  endtry
enddef

tt.Run('_StylePicker_')
