# Interrotron

A simple non-turing complete lisp meant to be embedded in apps as a rules engine. It is intentionally designed to limit the harm evaluated code can do (in contrast to a straight ruby 'eval') and is constrained to:

* Be totally sandboxed by default
* Always finish executing (no infinite loops)
* Let you easily add variables and functions (simply pass in a hash defining them)

## Installation

Add this line to your application's Gemfile:
    gem 'interrotron'

## Usage

```ruby
# Injecting a variable and evaluating a function is easy!
Interrotron.run('(> 51 custom_var)', :custom_var => 10) 
# => true

#You can inject functions just as easily
Interrotron.run("(my_proc (+ 2 2))", :my_proc => proc {|a| a*2 })
# => 8

# You can even pre-compile scripts to their an AST, creating a callable proc
tron = Interrotron.new(:is_valid => proc {|a| a.reverse == 'oof'})
compiled = tron.compile("(is_valid my_param)")
compiled.call(:my_param => 'foo') # => true
compiled.call(:my_param => 'bar') #=> false

# Since interrotron is meant for business rules, it handles dates as a 
# native type as instances of ruby's DateTime class. You can use literals
# for that like so:
Interrotron.run('(> #dt{2010-09-04} start_date)', start_date: DateTime.parse('2012-12-12'))
# => true
```

The following functions and variables are built in to Interrotron (though since its a lisp they're all just vars!):
```clojure
(if pred then else) # it's an if / else statement
(cond pred1 clause1 pred2 clause2 true fallbackclause) # like a case statement
(and e1, e2, ...) # logical and, returns last arg if true
(or e1, e2, ...) # logical or, returns first true arg
(not expr) # negates
(! expr) # negates
(identity expr) # returns its argument
(str s1, s2, ...) # converts its args to strings, also concatenates them
(floor expr) # equiv to num.floor
(ceil expr) # equiv to num.ceil
(round expr) # equiv to num.round
(max e1, e2, ...) # equiv to [e1, e2, ...].max
(min e1, e2, ...) # equiv to [e1, e2, ...].min
(to_i expr) # int conversion
(to_f expr) # float conversion
(rand) # returns a random float between 0 and 1
(upcase str) # uppercases a string
(downcase) # lowercases a string
(now) # returns the current DateTime
    'if' => [proc {|pred,t_clause,f_clause| mat(pred) ? mat(t_clause) : mat(f_clause) }, :lazy_args],
    'and' => [proc {|*args| args.reduce {|m,a| m && mat(a)}}, :lazy_args],
    'or' => [proc {|*args| r = nil; args.detect {|a| r = mat(a) }; r}, :lazy_args],
    'identity' => proc {|a| a},
    'not' => proc {|a| !a},
    '!' => proc {|a| !a},
    '>' => proc {|a,b| a > b},
    '<' => proc {|a,b| a < b},
    '>=' => proc {|a,b| a >= b},
    '<=' => proc {|a,b| a <= b},
    '='  => proc {|a,b| a == b},
    '!=' => proc {|a,b| a != b},
    'true' => true,
    'false' => false,
    'nil' => nil,
    '+' => proc {|*args| args.reduce(&:+)},
    '-' => proc {|*args| args.reduce(&:-)},
    '*' => proc {|*args| args.reduce(&:*)},
    '/' => proc {|a,b| a / b},
    '%' => proc {|a,b| a % b},
    'floor' =>  proc {|a| a.floor},
    'ceil' => proc {|a| a.ceil},
    'round' => proc {|a| a.round},
    'max' => proc {|*args| args.max},
    'min' => proc {|*args| args.min},
    'to_i' => proc {|a| a.to_i},
    'to_f' => proc {|a| a.to_f},
    'rand' => proc { rand },
    'upcase' => proc {|a| a.upcase},
    'downcase' => proc {|a| a.downcase},
    'now' => proc { DateTime.now },
    'str' => proc {|*args| args.reduce("") {|m,a| m + a.to_s}}
``

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
