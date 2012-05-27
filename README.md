# Interrotron

[![Build Status](https://secure.travis-ci.org/andrewvc/interrotron.png?branch=master)](http://travis-ci.org/andrewvc/interrotron)

A simple non-turing complete lisp meant to be embedded in apps as a rules engine. It is intentionally designed to limit the harm evaluated code can do (in contrast to a straight ruby 'eval') and is constrained to:

* Be totally sandboxed by default
* Always finish executing (no infinite loops)
* Let you easily add variables and functions (simply pass in a hash defining them)
* Be a small, single file

## Installation

Either add the `interrotron` gem, or just copy and paste [interratron.rb](https://github.com/andrewvc/interrotron/blob/master/lib/interrotron.rb)

## Usage

```ruby
# Injecting a variable and evaluating a function is easy!
Interrotron.run('(> 51 custom_var)', :custom_var => 10) 
# => true

#You can inject functions just as easily
Interrotron.run("(doubler (+ 2 2))", :doubler => proc {|a| a*2 })
# => 8

# You can even pre-compile scripts for speed / re-use!
tron = Interrotron.new(:is_valid => proc {|a| a.reverse == 'oof'})
compiled = tron.compile("(is_valid my_param)")
compiled.call(:my_param => 'foo')
# => true
compiled.call(:my_param => 'bar')
#=> false

# Since interrotron is meant for business rules, it handles dates as a 
# native type as instances of ruby's DateTime class. You can use literals
# for that like so:
Interrotron.run('(> #dt{2010-09-04} start_date)', start_date: DateTime.parse('2012-12-12'))
# => true

# You can, of course, create arbitarily complex exprs
Interrotron.run("(if false
                     (+ 4 -3)
                     (- 10 (+ 2 (+ 1 1))))")
# => 6

# Additionally, it is possible to constrain execution to a maximum number of
# operations by passing in a third argument
Interrotron.run("str (+ 1 2) (+ 3 4) (+ 5 7))", {}, 4)
# => raises Interrotron::OpsThresholdError since 4 operations were executed

```

The following functions and variables are built in to Interrotron (and more are on the way!):
```clojure
(if pred then else) ; it's an if / else statement
(cond pred1 clause1 pred2 clause2 true fallbackclause) ; like a case statement
(and e1, e2, ...) ; logical and, returns last arg if true
(or e1, e2, ...) ; logical or, returns first true arg
(not expr) ; negates
(! expr) ; negates
(identity expr) ; returns its argument
(str s1, s2, ...) ; converts its args to strings, also concatenates them
(floor expr) ; equiv to num.floor
(ceil expr) ; equiv to num.ceil
(round expr) ; equiv to num.round
(max lst) ; returns the largest element in a list
(min lst) ; returns the smallest element in a list
(to_i expr) ; int conversion
(to_f expr) ; float conversion
(rand) ; returns a random float between 0 and 1
(upcase str) ; uppercases a string
(downcase) ; lowercases a string
(now) ; returns the current DateTime
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
