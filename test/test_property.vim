vim9script

import          'libtinytest.vim'    as tt
import autoload 'property.vim'       as property

const AssertFails   = tt.AssertFails
const Bool          = property.Bool
const Float         = property.Float
const Number        = property.Number
const Observer      = property.Observer
const String        = property.String


class TestObserver implements Observer
  public this.count = 0

  def Update()
    this.count += 1
  enddef
endclass

def Test_PR_Bool()
  var o = TestObserver.new()
  var v = Bool.new(true) # No observer

  assert_true(v.Get())
  assert_equal(0, o.count)

  v.Set(false)

  assert_false(v.Get())
  assert_equal(0, o.count)

  v = Bool.new(true, o) # Register o as v's observer

  assert_true(v.Get())
  assert_equal(0, o.count)

  v.Set(false)

  assert_equal(1, o.count)

  v.Set(false)

  assert_equal(1, o.count)

  v.Set(true)

  assert_equal(2, o.count)

  AssertFails(() => {
    Bool.new('abc')
  }, 'E1012') # Type mismatch
enddef

def Test_PR_Float()
  var o = TestObserver.new()
  var v = Float.new(3.14)

  assert_equal(3.14, v.Get())
  assert_equal(0, o.count)

  v.Set(0.1)

  assert_equal(0.1, v.Get())
  assert_equal(0, o.count)

  v = Float.new(6.28, o)

  assert_equal(6.28, v.Get())
  assert_equal(0, o.count)

  v.Set(0.2)

  assert_equal(0.2, v.Get())
  assert_equal(1, o.count)

  v.Set(0.2)

  assert_equal(0.2, v.Get())
  assert_equal(1, o.count)

  v.Set(1.2)

  assert_equal(1.2, v.Get())
  assert_equal(2, o.count)

  AssertFails(() => {
    Float.new({})
  }, 'E1012')
enddef

def Test_PR_Number()
  var o = TestObserver.new()
  var v = Number.new(42)

  assert_equal(42, v.Get())
  assert_equal(0, o.count)

  v.Set(12)

  assert_equal(12, v.Get())
  assert_equal(0, o.count)

  v = Number.new(8, o)

  assert_equal(8, v.Get())
  assert_equal(0, o.count)

  v.Set(9)

  assert_equal(9, v.Get())
  assert_equal(1, o.count)

  v.Set(9)

  assert_equal(9, v.Get())
  assert_equal(1, o.count)

  v.Set(22)

  assert_equal(22, v.Get())
  assert_equal(2, o.count)


  AssertFails(() => {
    Number.new('abc')
  }, 'E1012') # Type mismatch
enddef

def Test_PR_String()
  var o = TestObserver.new()
  var v = String.new('hello')

  assert_equal('hello', v.Get())
  assert_equal(0, o.count)

  v.Set('world')

  assert_equal('world', v.Get())
  assert_equal(0, o.count)

  v = String.new('now', o)

  assert_equal('now', v.Get())
  assert_equal(0, o.count)

  v.Set('here')

  assert_equal('here', v.Get())
  assert_equal(1, o.count)

  v.Set('here')

  assert_equal('here', v.Get())
  assert_equal(1, o.count)

  v.Set('nowhere')

  assert_equal('nowhere', v.Get())
  assert_equal(2, o.count)

  AssertFails(() => {
    String.new(42)
  }, 'E1012')
enddef


tt.Run('_PR_')
