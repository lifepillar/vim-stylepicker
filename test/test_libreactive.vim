vim9script

import 'libtinytest.vim'           as tt
import '../import/libreactive.vim' as react

def Test_React_SimplePropertyAccess()
  const [Count, SetCount] = react.Property(2)
  const DoubleCount = () => Count() * 2

  assert_equal(DoubleCount(), 4)

  SetCount(3)

  assert_equal(DoubleCount(), 6)

  SetCount(Count() + 2)

  assert_equal(DoubleCount(), 10)
enddef


def Test_React_SimpleEffect()
  const [Count, SetCount] = react.Property(1)
  var result = 0

  react.CreateEffect(() => {
    result = Count()
  })

  assert_equal(1, result)

  SetCount(2)

  assert_equal(2, result)

  SetCount(Count() * 3)

  assert_equal(6, result)
enddef

def Test_React_SetWithTimer()
  const [Count, SetCount] = react.Property(2)
  const [Multiplier, _] = react.Property(3)
  const Product = (): number => Count() * Multiplier()
  var result = 0

  react.CreateEffect(() => {
    result += Product()
  })

  react.CreateEffect(() => {
    result *= Count()
  })

  assert_equal(result, 12)

  timer_start(20, (_) => SetCount(Count() + 1), {repeat: 3})
  sleep 80m
  assert_equal(1575, result)
enddef

def Test_React_Effect()
  var flag = false
  const [Count, SetCount] = react.Property(2)
  const DoubleCount = (): number => {
    flag = !flag
    return Count() * 2
  }

  react.CreateEffect(() => {
    DoubleCount()
  })

  assert_true(flag)

  SetCount(-4)

  assert_false(flag)
  assert_equal(DoubleCount(), -8)
enddef

def Test_React_MultipleSignals()
  const [FirstName, SetFirstName] = react.Property('John')
  const [LastName, SetLastName] = react.Property('Smith')
  var name1 = ''
  var name2 = ''

  const FullName = (): string => {
    return $'{FirstName()} {LastName()}'
  }

  react.CreateEffect(() => {
    name1 = FullName()
  })

  react.CreateEffect(() => {
    name2 = FullName()
  })

  SetFirstName("Jacob")

  assert_equal('Jacob Smith', name1)
  assert_equal('Jacob Smith', name2)

  SetLastName('Doe')

  assert_equal('Jacob Doe', name1)
  assert_equal('Jacob Doe', name2)
enddef

def Test_React_CachedComputation()
  const [FirstName, SetFirstName] = react.Property('John')
  const [LastName, SetLastName] = react.Property('Smith')
  var run = 0
  var name = ''

  const FullName = react.CreateMemo((): string => {
    ++run
    return $'{FirstName()} {LastName()}'
  })

  assert_equal(1, run) # The lambda is executed once upon creation
  assert_equal('John Smith', FullName())
  assert_equal(1, run) # The name has been cached, so the lambda is not re-run

  react.CreateEffect(() => {
    name = FullName()
  })

  assert_equal('John Smith', name) # The effect is initially run once
  assert_equal(1, run) # The name is cached, so the lambda is not re-run

  SetFirstName('Jacob')

  assert_equal('Jacob Smith', name)
  assert_equal(2, run) # The name has changed, the lambda has been re-run

  assert_equal('Jacob Smith', FullName())
  assert_equal(2, run)

  SetLastName('Doe')

  assert_equal('Jacob Doe', name)
  assert_equal(3, run) # The name has changed, the lambda has been re-run

  assert_equal('Jacob Doe', FullName())
  assert_equal(3, run)
enddef

def Test_React_FineGrainedReaction()
  const [FirstName, SetFirstName] = react.Property('John')
  const [LastName, SetLastName] = react.Property('Smith')
  const [ShowFullName, SetShowFullName] = react.Property(true)
  var name = ''
  var run = 0

  const DisplayName = react.CreateMemo((): string => {
    ++run
    if !ShowFullName() # When ShowFullName() is false, only first name is tracked
      return FirstName()
    endif

    return $'{FirstName()} {LastName()}'
  })

  assert_equal('John Smith', DisplayName())
  assert_equal(1, run)

  react.CreateEffect(() => {
    name = DisplayName()
  })

  assert_equal('John Smith', name) # Effect is executed once upon creation
  assert_equal(1, run) # But it reads the cached value, lambda is not run

  SetShowFullName(false) # Affects display name, recomputation needed

  assert_equal(2, run) # Display name changed, lambda re-run
  assert_equal('John', DisplayName())
  assert_equal(2, run) # DisplayName() used cached value
  assert_equal('John', name) # Effect has been triggered, too
  assert_equal(2, run) # Effect used cached value

  SetLastName("Legend") # No side effect because right now last name is not tracked

  assert_equal('John', DisplayName())
  assert_equal('John', name)
  assert_equal(2, run)

  SetShowFullName(true) # Affects display name, recomputation needed

  assert_equal(3, run) # Display name changed, lambda re-run
  assert_equal('John Legend', DisplayName())
  assert_equal(3, run)
  assert_equal('John Legend', name) # Effect has been triggered, too

  SetLastName("Denver") # Full name is now tracked, so side effect is triggered

  assert_equal(4, run) # Display name changed, lambda re-run
  assert_equal('John Denver', DisplayName())
  assert_equal(4, run)
  assert_equal('John Denver', name) # Effect has been triggered, too
  assert_equal(4, run)
enddef


tt.Run('_React_')
