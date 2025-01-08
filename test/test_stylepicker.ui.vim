vim9script

import 'libtinytest.vim'    as tt
import 'libreactive.vim'    as react
import 'libstylepicker.vim' as ui

type TextProperty  = ui.TextProperty
type TextLine      = ui.TextLine
type LeafView      = ui.LeafView
type UpdatableView = ui.UpdatableView
type ContainerView = ui.ContainerView
type View          = ui.View

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
    ui.StartRendering(view, bufnr)

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
    ui.StartRendering(outer, bufnr)

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
    ui.StartRendering(containerView, bufnr)

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
    ui.StartRendering(containerView, bufnr)

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
    ui.StartRendering(containerView, bufnr)

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

tt.Run('StylePicker')

