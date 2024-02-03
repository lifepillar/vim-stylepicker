vim9script

# A minimal reactive library. Loosely inspired by this tutorial:
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

interface ISignal
endinterface

class Effect
  var Fn: func()
  public var dependentSignals: list<ISignal> = []

  def Execute()
    var prevActive = gActiveEffect
    gActiveEffect = this
    this.ClearDependencies()
    Begin()
    this.Fn()
    Commit()
    gActiveEffect = prevActive
  enddef

  def ClearDependencies()
    for signal in this.dependentSignals
      AsSignal(signal).RemoveEffect(this)
    endfor
    this.dependentSignals = []
  enddef
endclass

class EffectQueue
  var _q: list<Effect> = []
  var _start: number = 0

  static var max_size = get(g:, 'libreactive_queue_size', 10000)

  def Items(): list<Effect>
    return this._q[this._start : ]
  enddef

  def Empty(): bool
    return this._start == len(this._q)
  enddef

  def Push(effect: Effect)
    this._q->add(effect)

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

# Global state {{{
var gActiveEffect: Effect = null_object
var gQueue = EffectQueue.new()
var gTransaction = 0
var gInsideCreateEffect = false

export def Reinit()
  gActiveEffect = null_object
  gQueue.Reset()
  gTransaction = 0
  gInsideCreateEffect = false
enddef
# }}}

# Transaction {{{
# By default, when a signal is updated, its effects are triggered
# synchronously. It is possible, however, to perform several changes to one or
# more signals within a transaction, in which case notifications are sent only
# when the transaction commits. The gTransaction counter signals whether
# a (nested) transaction is running. The queue is where the effects to be
# executed are pushed. The queue is emptied when the transaction commits (see
# Commit()).

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

export class Signal implements ISignal
  var _value: any = null
  var _effects: list<Effect> = []

  def Read(): any
    if gActiveEffect != null && gActiveEffect->NotIn(this._effects)
      this._effects->add(gActiveEffect)
      gActiveEffect.dependentSignals->add(this)
    endif

    return this._value
  enddef

  def Write(newValue: any)
    this._value = newValue

    Begin()
    for effect in this._effects
      if effect->NotIn(gQueue.Items())
        gQueue.Push(effect)
      endif
    endfor
    Commit()
  enddef

  def RemoveEffect(effect: Effect)
    effect->RemoveFrom(this._effects)
  enddef

  def Clear()
    this._effects = []
  enddef
endclass

def AsSignal(s: any): Signal
  return s
enddef

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
