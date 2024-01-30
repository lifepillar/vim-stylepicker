vim9script

# A minimal reactive library. Loosely inspired by this tutorial:
# https://dev.to/ryansolid/building-a-reactive-library-from-scratch-1i0p

# Helper functions {{{
def NotIn(v: any, items: list<any>): bool
  return indexof(items, (_, u) => u is v) == -1
enddef

def In(v: any, items: list<any>): bool
  return indexof(items, (_, u) => u is v) != -1
enddef

def RemoveFrom(v: any, items: list<any>)
  const i = indexof(items, (_, e) => e is v)

  if i == -1
    return
  endif

  items->remove(i)
enddef
# }}}

class Effect
  var Fn: func()
  var _dependentSignals: list<any> = []  # List of signals that trigger the effect

  public static var active: any = null_object

  def Execute()
    var prevActive = Effect.active
    Effect.active = this
    this.ClearDependencies()
    Begin()
    this.Fn()
    Commit()
    Effect.active = prevActive
  enddef

  def ClearDependencies()
    for signal in this._dependentSignals
      AsSignal(signal).RemoveEffect(this)
    endfor

    this._dependentSignals = []
  enddef

  def AddSignal(signal: any)
    this._dependentSignals->add(signal)
  enddef

  def AsString(): string
    return printf('Effect: %s', this.Fn)
  enddef
endclass

class EffectQueue
  var _q: list<Effect> = []
  var _start: number = 0

  static var max_size = 10000 # TODO: make a setting

  def Items(): list<Effect>
    return this._q[this._start : ]
  enddef

  def Empty(): bool
    return this._start == len(this._q)
  enddef

  def Push(effect: Effect)
    if effect->NotIn(this._q[this._start : ])
      this._q->add(effect)
    endif

    if len(this._q) > EffectQueue.max_size
      throw $'[Reactive] Potentially recursive effects detected (effects max size = {EffectQueue.max_size}).'
    endif
  enddef

  def Pop(): Effect
    ++this._start
    return this._q[this._start - 1]
  enddef

  def Reset()
    this._q = []
    this._start = 0
  enddef
endclass

# Transaction {{{
# By default, when a signal is updated, its effects are triggered
# synchronously. It is possible, however, to perform several changes to one or
# more signals within a transaction, in which case notifications are sent only
# when the transaction commits. The gTransaction counter signals whether
# a (nested) transaction is running. The queue is where the effects to be
# executed are pushed. The queue is emptied when the transaction commits (see
# Commit()).
var gTransaction = 0 # 0 = not in a transaction, ≥1 = inside transaction, >1 = in nested transaction
var gQueue = EffectQueue.new()

def Begin()
  gTransaction += 1
enddef

def Commit()
  if gTransaction == 1
    while !gQueue.Empty()
      gQueue.Pop().Execute()
    endwhile

    gQueue.Reset()
  endif

  gTransaction -= 1
enddef

# Clients use this function to perform changes to signals in an atomic way.
# Notifications are postponed until commit time. Also, each effect is notified
# exactly once, even if several changes to the signal (or signals) it observes
# have happened inside the transaction.
export def Transaction(Body: func())
  Begin()
  Body()
  Commit()
enddef
# }}}

export class Signal
  var _value: any = null
  var _effects: list<Effect> = []

  def Read(): any
    if Effect.active != null # Set the effect to track changes to this signal
      this.AddEffect(Effect.active)
    endif

    return this._value
  enddef

  def Write(newValue: any)
    this._value = newValue

    Begin()

    for effect in this._effects
      gQueue.Push(effect)
    endfor

    Commit()
  enddef

  def AddEffect(effect: Effect)
    if effect->NotIn(this._effects)
      this._effects->add(effect)
      effect.AddSignal(this)
    endif
  enddef

  def RemoveEffect(effect: Effect)
    effect->RemoveFrom(this._effects)
  enddef

  def GetterSetter(): list<func>
    return [this.Read, this.Write]
  enddef

  def AsString(): string
    return string(this._value)
  enddef
endclass

def AsSignal(s: Signal): Signal
  return s
enddef

var gInsideCreateEffect = false

export def CreateEffect(Fn: func())
  if gInsideCreateEffect
    throw 'Nested CreateEffect() calls detected'
  endif

  gInsideCreateEffect = true

  var runningEffect = Effect.new(Fn)

  runningEffect.Execute() # Necessary to bind to dependent signals

  gInsideCreateEffect = false
enddef

export def CreateMemo(Fn: func(): any): func(): any
  var signal = Signal.new()
  CreateEffect(() => signal.Write(Fn()))
  return signal.Read
enddef

export def Property(value: any = null): list<func>
  return Signal.new(value).GetterSetter()
enddef

export def Reinit()
  gQueue.Reset()
  gTransaction = 0
  Effect.active = null_object
  gInsideCreateEffect = false
enddef
