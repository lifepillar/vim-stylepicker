vim9script

def IsNotIn(v: any, items: any): bool
  return indexof(items, (_, u) => u is v) == -1
enddef


# An observer is any object interested in watching the changes to some
# property (see below). Any time the observed property changes, all the
# property's observers are notified by calling Update().
export interface Observer
  def Update()
endinterface

# By default, when a property changes, it notifies its observers at once. It
# is possible, however, to perform several changes to one or more properties
# within a transaction, in which case notifications are sent only when the
# transaction commits. The gTransaction flag signals whether a transaction is
# running. The queue is where the observers to be notified are pushed. The
# queue is emptied when the transaction commits (see Commit()).
var gTransaction: bool           = false
var gQueue:       list<Observer> = []


def Begin()
  gTransaction = true
enddef


def Commit()
  if !gTransaction
    Begin() # Implicit transaction
  endif

  for obs in gQueue
    obs.Update()
  endfor

  gTransaction = false
  gQueue       = []
enddef


# Clients use this function to perform changes to properties in an atomic way.
# Notifications are postponed until commit time. Also, each observer of the
# changed properties is notified exactly once, even if several changes to the
# property (or properties) it observes has happened inside the transaction.
export def Transaction(Body: func(): void)
  Begin()
  Body()
  Commit()
enddef


# An observable property allows other objects to monitor its changes.
# Observable properties inherit from this class. Observers (implicitly or
# explcitly) call Register() on an observable property to declare their
# interest in the property's updates.
export class Observable
  this._observer: list<Observer>

  def Register(...observers: list<Observer>)
    # See https://github.com/vim/vim/issues/12081
    this.DoRegister(observers)
  enddef

  def DoRegister(observers: list<Observer>)
    for observer in observers
      this._observer->add(observer)
    endfor
  enddef

  def Notify()
    for obs in this._observer
      if obs->IsNotIn(gQueue)
        gQueue->add(obs)
      endif
    endfor

    if !gTransaction
      Commit()
    endif
  enddef
endclass


# We would like Vim's core data types to be observable, but that is not
# possible. This interface can be used to define thin wrappers around the
# built-in data types—see below—or any other kind of data (properties can even
# be compound, that is, made of other properties).
#
# NOTE: the repetitive verbosity of the properties below is intentional, to
# work around some current limitations of Vim 9 script.
export interface Property
  def Get(): any
  def Set(v: any)
endinterface


export class Bool extends Observable implements Property
  this._value: bool

  def new(this._value, ...observers: list<Observer>)
    this.DoRegister(observers)
  enddef

  def Get(): bool
    return this._value
  enddef

  def Set(v: bool)
    if v != this._value
      this._value = v
      this.Notify()
    endif
  enddef
endclass


export class Float extends Observable implements Property
  this._value: float

  def new(this._value, ...observers: list<Observer>)
    this.DoRegister(observers)
  enddef

  def Get(): float
    return this._value
  enddef

  def Set(v: float)
    if v != this._value
      this._value = v
      this.Notify()
    endif
  enddef
endclass


export class Number extends Observable implements Property
  this._value: number

  def new(this._value, ...observers: list<Observer>)
    this.DoRegister(observers)
  enddef

  def Get(): number
    return this._value
  enddef

  def Set(v: number)
    if v != this._value
      this._value = v
      this.Notify()
    endif
  enddef
endclass


export class String extends Observable implements Property
  this._value: string

  def new(this._value, ...observers: list<Observer>)
    this.DoRegister(observers)
  enddef

  def Get(): string
    return this._value
  enddef

  def Set(v: string)
    if v != this._value
      this._value = v
      this.Notify()
    endif
  enddef
endclass
