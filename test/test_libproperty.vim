vim9script

import 'libtinytest.vim'           as tt
import '../import/libproperty.vim' as libproperty

const AssertFails   = tt.AssertFails
type  Bool          = libproperty.Bool
type  Float         = libproperty.Float
type  Number        = libproperty.Number
type  Observer      = libproperty.Observer
type  String        = libproperty.String
const Transaction   = libproperty.Transaction


class TestObserver implements Observer
  public var count = 0

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

  def NewBool(value: any)
    AssertFails(() => {
      Bool.new(value)
    }, 'E1013')
  enddef

  NewBool('abc')
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

  def NewFloat(value: any)
    AssertFails(() => {
      Float.new(value)
    }, 'E1013')
  enddef

  NewFloat({})
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


  def NewNumber(value: any)
    AssertFails(() => {
      Number.new(value)
    }, 'E1013')
  enddef

  NewNumber('abc')
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

  def NewString(value: any)
    AssertFails(() => {
      String.new(value)
    }, 'E1013')
  enddef

  NewString(42)
enddef


def Test_PR_Transaction()
  var o1 = TestObserver.new()
  var o2 = TestObserver.new()

  var p1 = Number.new(1, o1, o2)
  var p2 = Number.new(10, o1, o2)

  Transaction(() => {
    p1.Set(2)
    p2.Set(20)
  })

  assert_equal(1, o1.count)
  assert_equal(1, o2.count)
enddef

def Test_PR_NestedTransactions()
  var o1 = TestObserver.new()
  var o2 = TestObserver.new()
  var p1 = Number.new(1, o1, o2)
  var p2 = Number.new(10, o1, o2)
  var p3 = Number.new(100, o1, o2)

  Transaction(() => {
    Transaction(() => {
      p1.Set(2)
      p2.Set(20)
    })
    p2.Set(30)
    p3.Set(300)
  })

  assert_equal(1, o1.count)
  assert_equal(1, o2.count)
enddef

tt.Run('_PR_')
