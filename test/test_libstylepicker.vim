vim9script

import 'libtinytest.vim'    as tt
import 'libreactive.vim'    as react
import 'libstylepicker.vim' as ui

type TextProperty  = ui.TextProperty
type TextLine      = ui.TextLine
type ContentView   = ui.ContentView
type UpdatableView = ui.UpdatableView
type VStack        = ui.VStack


def Text(body: list<TextLine>): list<string>
  return mapnew(body, (_, line: TextLine): string => line.text)
enddef

class TestContentView extends ContentView
  def new(content: list<string>)
    var value = mapnew(content, (_, t): TextLine =>  TextLine.new(t))
    this.content.Set(value)
  enddef
endclass

class TestUpdatableView extends UpdatableView
  var state: react.Property # string

  def new(this.state)
    super.Init()
  enddef

  def Update()
    this.content.Set([TextLine.new(this.state.Get())])
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

def Test_StylePicker_CreateContentView()
  var view     = TestContentView.new(['hello', 'world'])
  var expected = [TextLine.new('hello'), TextLine.new('world')]

  assert_equal(expected, view.Body())
  assert_equal(2, view.Height())

  view.Hidden(true)

  assert_equal([], view.Body())
  assert_equal(0,  view.Height())

  view.Hidden(false)

  assert_equal(expected, view.Body())
  assert_equal(2,        view.Height())
enddef

def Test_StylePicker_RenderContentView()
  var content = ['a', 'b', 'c']
  var view    = TestContentView.new(content)
  var bufnr   = bufadd('StylePicker test buffer')

  bufload(bufnr)

  try
    view.Render(bufnr)

    assert_equal(content, getbufline(bufnr, 1, '$'))

    view.Hidden(true)

    assert_equal([''], getbufline(bufnr, 1, '$'))

    view.Hidden(false)

    assert_equal(content, getbufline(bufnr, 1, '$'))
  finally
    execute 'bwipe!' bufnr
  endtry
enddef

def Test_StylePicker_VStack()
  var p1            = react.Property.new('text')
  var contentView   = TestContentView.new(['x', 'y'])
  var updatableView = TestUpdatableView.new(p1)
  var inner         = VStack.new([contentView])
  var outer         = VStack.new([inner, updatableView])
  var bufnr         = bufadd('StylePicker test buffer')

  bufload(bufnr)

  try
    outer.Render(bufnr)

    # :-- outer vstack -----------:
    # | :-- inner vstack -------: |
    # | | :-- content view ---: | |
    # | | |        x          | | |
    # | | |        y          | | |
    # | | :-------------------: | |
    # | :-----------------------: |
    # |   :-- updatable view -:   |
    # |   |       text        |   |
    # |   :-------------------:   |
    # :---------------------------:


    assert_equal(['x', 'y', 'text'], Text(outer.Body()))
    assert_equal(['x', 'y', 'text'], getbufline(bufnr, 1, '$'))

    updatableView.state.Set('new text')

    assert_equal(['x', 'y', 'new text'], Text(outer.Body()))
    assert_equal(['x', 'y', 'new text'], getbufline(bufnr, 1, '$'))

    contentView.Hidden(true)

    assert_equal(['new text'], Text(outer.Body()))
    assert_equal(['new text'], getbufline(bufnr, 1, '$'))

    contentView.Hidden(false)

    assert_equal(['x', 'y', 'new text'], Text(outer.Body()))
    assert_equal(['x', 'y', 'new text'], getbufline(bufnr, 1, '$'))

    inner.Hidden(true)
    assert_equal(['new text'], Text(outer.Body()))
    assert_equal(['new text'], getbufline(bufnr, 1, '$'))

    outer.Hidden(true)
    assert_equal([], Text(outer.Body()))
    assert_equal([''], getbufline(bufnr, 1, '$'))

    inner.Hidden(false)
    assert_equal(['x', 'y'], Text(outer.Body()))
    assert_equal(['x', 'y'], getbufline(bufnr, 1, '$'))

    inner.Hidden(true)
    outer.Hidden(false)
    assert_equal(['x', 'y', 'new text'], Text(outer.Body()))
    assert_equal(['x', 'y', 'new text'], getbufline(bufnr, 1, '$'))
  finally
    execute 'bwipe!' bufnr
  endtry
enddef

def Test_StylePicker_UpdatableView()
  var p1            = react.Property.new('initial text')
  var updatableView = TestUpdatableView.new(p1)
  var containerView = VStack.new([updatableView])
  var bufnr         = bufadd('StylePicker test buffer')

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
  var header        = TestContentView.new(['Header'])
  var r             = TestContentView.new(['r'])
  var g             = TestContentView.new(['g'])
  var b             = TestContentView.new(['b'])
  var rgb           = VStack.new([r, g, b])
  var root          = VStack.new([header, rgb])
  var bufnr         = bufadd('StylePicker test buffer')

  bufload(bufnr)

  try
    root.Render(bufnr)

    assert_equal(['Header', 'r', 'g', 'b'], getbufline(bufnr, 1, '$'))
  finally
    execute 'bwipe!' bufnr
  endtry
enddef

def Test_StylePicker_RespondToKeyEvent()
  var v1    = TestContentView.new(['a', 'b', 'c'])
  var c1    = VStack.new([v1])
  var root  = VStack.new([c1])
  var bufnr = bufadd('StylePicker test buffer')

  v1.OnKeyCode('K', () => true)
  c1.OnKeyCode('C', () => true)

  assert_equal(3, v1.Height())
  assert_equal(3, c1.Height())
  assert_equal(3, root.Height())
  assert_equal(0, root.Offset())
  assert_equal(0, c1.Offset())
  assert_equal(0, v1.Offset())

  bufload(bufnr)

  try
    root.Render(bufnr)

    assert_equal(3, v1.Height())
    assert_equal(['a', 'b', 'c'], getbufline(bufnr, 1, '$'))
    assert_true(v1.RespondToKeyEvent('K'))
    assert_true(v1.RespondToKeyEvent('C'))
    assert_true(c1.RespondToKeyEvent('C'))
    assert_false(v1.RespondToKeyEvent('X'))
    assert_false(c1.RespondToKeyEvent('K'))
    assert_false(root.RespondToKeyEvent('K'))
    assert_false(root.RespondToKeyEvent('C'))
  finally
    execute 'bwipe!' bufnr
  endtry
enddef

def Test_StylePicker_AddViewToContainer()
  var v1 = TestContentView.new(['a', 'b', 'c'])
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

  var bufnr = bufadd('StylePicker test buffer')
  bufload(bufnr)

  try
    c1.Render(bufnr)
  finally
    execute 'bwipe!' bufnr
  endtry
enddef

def Test_StylePicker_RenderLeaf()
  var leafView = TestContentView.new(['Hello', 'world'])

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
  var leaf = TestContentView.new(['hello', 'world'])
  var root = VStack.new([leaf])

  assert_true(root.llink is leaf, 'llink(root) is leaf')
  assert_true(root.rlink is root, 'rlink(root) is root')
  assert_true(root.ltag)
  assert_false(root.rtag)
  assert_true(root.Next() is leaf, 'next(root) is leaf')
  assert_true(root.Previous() is leaf, 'prev(root) is leaf')
  assert_true(leaf.Previous() is root, 'prev(leaf) is root')
  assert_true(leaf.Next() is root, 'next(leaf) is root')

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

  var leaf1 = TestContentView.new(['A'])
  var leaf2 = TestContentView.new(['B', 'C'])
  var leaf3 = TestContentView.new(['D', 'E'])
  var box1  = VStack.new()
  var box2  = VStack.new()
  var root  = VStack.new()

  box1.AddView(leaf1)
  root.AddView(box1)
  box1.AddView(leaf2)
  box2.AddView(leaf3)
  root.AddView(box2)

  assert_true(box1.FirstLeaf() is leaf1, 'firstSubview(box1) is leaf1')
  assert_true(root.llink is box1, 'llink(root) is box1')
  assert_true(root.rlink is root, 'rlink(root) is root')
  assert_true(root.ltag)
  assert_false(root.rtag)
  assert_true(root.Next() is leaf1, 'next(root) is leaf1')
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
