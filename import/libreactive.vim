vim9script

# A minimal reactive library inspired by SolidJS, in particular this tutorial:
# https://dev.to/ryansolid/building-a-reactive-library-from-scratch-1i0p
#
# Note that nested effects are not supported.

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

var gActiveEffect: Effect = null_object

class Signal
  var _value: any = null
  var effects: list<Effect> = []

  def Read(): any
    if gActiveEffect != null # Set the effect to track changes to this signal
      Bind(this, gActiveEffect)
    endif

    return this._value
  enddef

  def Write(newValue: any)
    if newValue == this._value
      return
    endif

    this._value = newValue

    # A copy must be made because this.effects is altered by executing effects
    # in the loop below (the first thing an effect does when executing is to
    # clear its own dependency graph).
    const currentEffects: list<Effect> = copy(this.effects)

    for effect in currentEffects
      effect.Execute()
    endfor
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

export def CreateEffect(Fn: func())
  var runningEffect: Effect

  const Execute = () => {
    ClearDependencies(runningEffect)
    gActiveEffect = runningEffect
    Fn()
    gActiveEffect = null_object
  }

  runningEffect = Effect.new(Execute)
  Execute() # Necessary to bind to dependent signals
enddef

export def CreateMemo(Fn: func(): any): func(): any
  const signal = Signal.new()
  CreateEffect(() => signal.Write(Fn()))
  return signal.Read
enddef

export def Property(value: any = null): list<func>
  var signal = Signal.new(value)
  return [signal.Read, signal.Write]
enddef
