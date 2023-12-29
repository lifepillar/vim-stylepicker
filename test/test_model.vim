vim9script

import 'libtinytest.vim'           as tt
import '../autoload/model.vim'     as model
import '../import/libproperty.vim' as property

type  Color        = model.Color
type  HiGroup      = model.HiGroup
type  HiGroupColor = model.HiGroupColor
type  HiGroupStyle = model.HiGroupStyle
const HlClear      = model.HlClear
const HlGet        = model.HlGet
const HlGetColor   = model.HlGetColor
const HlGetStyle   = model.HlGetStyle
const HlSetColor   = model.HlSetColor
const HlSetStyle   = model.HlSetStyle
const Transaction  = property.Transaction
type  Observer     = property.Observer

# Helper classes and functions {{{
class TestObserver implements Observer
  public var count = 0

  def Update()
    this.count += 1
  enddef
endclass

def TestHlContains(d: dict<any>): bool
  const info = hlget(d.name)[0]

  for key in keys(d)
    const infoHasKey = info->has_key(key)

    if !info->has_key(key) || info[key] != d[key]
      return false
    endif
  endfor

  return true
enddef

def InitTestHiGroup()
  hi StylePickerTest guifg=#000087 guibg=#c6c6c6 ctermfg=18 ctermbg=251 gui=bold,italic cterm=bold,italic
enddef
# }}}


def Test_Model_HlGet()
  hlset([{name: 'StylePickerTest', ctermfg: '231', cterm: {bold: true}}])
  const attrs = HlGet('StylePickerTest')

  assert_true(TestHlContains(attrs))

  tt.AssertFails(() => {
    HlGet('This-Name-Does-Not-Exist')
    }, 'undefined')
enddef

def Test_Model_HlGetColor()
  hlset([{
    name: 'StylePickerTest', ctermfg: '17', ctermbg: '255', guifg: '#00005f', guibg: '#eeeeee'
  }])

  assert_equal('#00005f', HlGetColor('StylePickerTest', 'fg'))
  assert_equal('#eeeeee', HlGetColor('StylePickerTest', 'bg'))
  assert_equal('#00005f', HlGetColor('StylePickerTest', 'sp'))
enddef

def Test_Model_HlSetColor()
  hlset([{
    name: 'StylePickerTest', ctermfg: '17', ctermbg: '255', guifg: '#00005f', guibg: '#eeeeee'
  }])
  # Pick an xterm-color, so that the test is expected to succeed in notermguicolor terminals, too
  HlSetColor('StylePickerTest', 'fg', '#262626')

  assert_equal('#262626', HlGetColor('StylePickerTest', 'fg'))
  assert_equal('#eeeeee', HlGetColor('StylePickerTest', 'bg'))

  HlSetColor('StylePickerTest', 'bg', '#ffd7af') # Pick an xterm-color

  assert_equal('#262626', HlGetColor('StylePickerTest', 'fg'))
  assert_equal('#ffd7af', HlGetColor('StylePickerTest', 'bg'))
enddef

def Test_Model_HlGetStyle()
  hlset([{
    name: 'StylePickerTest', cterm: {bold: true, italic: true}, gui: {bold: true, italic: true}
  }])
  const attrs = HlGetStyle('StylePickerTest')

  assert_true(get(attrs, 'bold', false))
enddef

def Test_Model_HlSetStyle()
  hlset([{name: 'StylePickerTest', cleared: true}])
  HlSetStyle('StylePickerTest', {bold: true, italic: true})
  const attrs = HlGetStyle('StylePickerTest')

  assert_true(get(attrs, 'bold', false))
  assert_true(get(attrs, 'italic', false))
  assert_true(!get(attrs, 'underline', false))
enddef

def Test_Model_HlClear()
  HlClear('StylePickerTest')

  assert_true(get(HlGet('StylePickerTest'), 'cleared', false))
enddef

def Test_Model_Color()
  var c = Color.new('#f54f29')

  assert_equal('#f54f29', c.Get())

  var o = TestObserver.new()
  c.Register(o)

  assert_equal(0, o.count)

  c.Set('#405952')

  assert_equal('#405952', c.Get())
  assert_equal(1, o.count)

  c.red.Set(1)
  c.blue.Set(0)

  assert_equal('#015900', c.Get())
  assert_equal(3, o.count)

  Transaction(() => {
    c.green.Set(0)
    c.blue.Set(255)
  })

  assert_equal('#0100ff', c.Get())
  assert_equal(4, o.count)
enddef

def Test_Model_NewHiGroupColor()
  InitTestHiGroup()
  const obs = TestObserver.new()
  const fgc = HiGroupColor.new('StylePickerTest', 'fg', obs)

  assert_equal('StylePickerTest', fgc.hiGroup)
  assert_equal('fg', fgc.attr)
  assert_equal('#000087', fgc.Get())
  assert_equal(0, obs.count)

  fgc.Set('#262626')

  assert_equal('#262626', fgc.Get())
  assert_equal(1, obs.count)

  fgc.value.red.Set(0)

  assert_equal('#002626', fgc.Get())
  assert_equal(2, obs.count)
enddef

def Test_Model_NewHiGroupStyle()
  InitTestHiGroup()
  const obs = TestObserver.new()
  const sty = HiGroupStyle.new('StylePickerTest', obs)

  assert_equal('StylePickerTest', sty.hiGroup)
  assert_equal({bold: true, italic: true}, sty.Get())
  assert_true(sty.Bold())
  assert_true(sty.Italic())
  assert_false(sty.Reverse())
  assert_false(sty.Standout())
  assert_false(sty.Under('line'))
  assert_false(sty.Under('curl'))
  assert_false(sty.Under('dotted'))
  assert_false(sty.Under('dashed'))
  assert_false(sty.Under('double'))
  assert_false(sty.AnyUnderline())
  assert_false(sty.Strikethrough())

  sty.Set({undercurl: true, bold: true})

  assert_true(sty.Bold())
  assert_false(sty.Under('line'))
  assert_true(sty.Under('curl'))
  assert_true(sty.AnyUnderline())
  assert_equal(1, obs.count)
enddef

def Test_Model_HiGroup()
  InitTestHiGroup()
  const obs = TestObserver.new()
  const hig = HiGroup.new('StylePickerTest', obs)

  assert_equal(hlget('StylePickerTest')[0], hig.Get())

  assert_equal('#000087', hig.color.fg.Get())
  assert_equal('#c6c6c6', hig.color.bg.Get())
  assert_equal('#000087', hig.color.sp.Get()) # Fallback to fg
  assert_true(hig.style.Bold())
  assert_true(hig.style.Italic())
  assert_false(hig.style.AnyUnderline())
  assert_equal(0, obs.count)

  hig.Set({style: {strikethrough: true}})

  assert_equal('#000087', hig.color.fg.Get())
  assert_equal('#c6c6c6', hig.color.bg.Get())
  assert_equal('#000087', hig.color.sp.Get())
  assert_false(hig.style.Bold())
  assert_false(hig.style.Italic())
  assert_false(hig.style.AnyUnderline())
  assert_true(hig.style.Strikethrough())
  assert_equal(1, obs.count)

  hig.Set({guifg: '#005fd7'})

  assert_equal('#005fd7', hig.color.fg.Get())
  assert_equal('#c6c6c6', hig.color.bg.Get())
  assert_equal('#000087', hig.color.sp.Get())
  assert_false(hig.style.Bold())
  assert_false(hig.style.Italic())
  assert_true(hig.style.Strikethrough())
  assert_equal(2, obs.count)

  hig.Set({style: {undercurl: true, standout: true}, guifg: '#d7d787'})

  assert_equal('#d7d787', hig.color.fg.Get())
  assert_false(hig.style.Bold())
  assert_true(hig.style.Standout())
  assert_false(hig.style.Italic())
  assert_false(hig.style.Strikethrough())
  assert_true(hig.style.AnyUnderline())
  assert_true(hig.style.Under('curl'))
  assert_equal(3, obs.count)
enddef


tt.Run('_Model_')
