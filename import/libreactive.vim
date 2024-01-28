vim9script

# A minimal reactive library. Loosely inspired by SolidJS, in particular by this tutorial:
# https://dev.to/ryansolid/building-a-reactive-library-from-scratch-1i0p

# Helper functions {{{
def NotIn(v: any, items: list<any>): bool
  return indexof(items, (_, u) => u is v) == -1
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
  var Execute: func()
  public var dependentSignals: list<any> = []  # List of signals that trigger the effect
endclass

class EffectQueue
  var _q: list<Effect> = []
  var _start: number = 0

  def Items(): list<Effect>
    return this._q[this._start : ]
  enddef

  def Empty(): bool
    return this._start == len(this._q)
  enddef

  def Push(e: Effect)
    if e->NotIn(this._q)
      this._q->add(e)
      return
    endif
    throw 'Recursive effects detected.'
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

var gActiveEffect: Effect = null_object

# Transaction {{{
# By default, when a signal is updated, its effects are triggered
# synchronously. It is possible, however, to perform several changes to one or
# more signals within a transaction, in which case notifications are sent only
# when the transaction commits. The gTransaction counter signals whether
# a (nested) transaction is running. The queue is where the effects to be
# executed are pushed. The queue is emptied when the transaction commits (see
# Commit()).
var gTransaction: number = 0
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
  var effects: list<Effect> = []

  def Read(): any
    if gActiveEffect != null # Set the effect to track changes to this signal
      Bind(this, gActiveEffect)
    endif

    return this._value
  enddef

  def Write(newValue: any)
    this._value = newValue

    Transaction(() => {
      for effect in this.effects
        gQueue.Push(effect)
      endfor
    })
  enddef

  def GetterSetter(): list<func>
    return [this.Read, this.Write]
  enddef
endclass

def AsSignal(s: Signal): Signal
  return s
enddef

def ClearDependencies(effect: Effect)
  for signal in effect.dependentSignals
    effect->RemoveFrom(AsSignal(signal).effects)
  endfor

  effect.dependentSignals = []
enddef

def Bind(signal: Signal, effect: Effect)
  if effect->NotIn(signal.effects)
    signal.effects->add(effect)
    effect.dependentSignals->add(signal)
  endif
enddef

var gInsideCreateEffect = false

export def CreateEffect(Fn: func())
  if gInsideCreateEffect
    throw 'Nested effects detected'
  endif

  gInsideCreateEffect = true

  var runningEffect: Effect

  const Execute = () => {
    ClearDependencies(runningEffect)
    gActiveEffect = runningEffect
    Fn()
    gActiveEffect = null_object
  }

  runningEffect = Effect.new(Execute)
  Execute() # Necessary to bind to dependent signals

  gInsideCreateEffect = false
enddef

export def CreateMemo(Fn: func(): any): func(): any
  const signal = Signal.new()
  CreateEffect(() => signal.Write(Fn()))
  return signal.Read
enddef

export def Property(value: any = null): list<func>
  return Signal.new(value).GetterSetter()
enddef

export def Reinit()
  gQueue.Reset()
  gTransaction = 0
  gActiveEffect = null_object
  gInsideCreateEffect = false
enddef
