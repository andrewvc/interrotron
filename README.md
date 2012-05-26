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
Interrotron.run("(my_proc 4)", :my_proc => proc {|a| a*2 })
# => 8

# You can even pre-compile scripts to their an AST, creating a callable proc
tron = Interrotron.new(:is_valid => proc {|a| a.reverse == 'oof'})
compiled = tron.compile("(is_valid my_param)")
compiled.call(:my_param => 'foo') # => true
compiled.call(:my_param => 'bar') #=> false
```


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
