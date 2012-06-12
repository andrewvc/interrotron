require "interrotron/version"
require 'date'
require 'hashie/mash'

# This is a Lispish DSL meant to define business rules
# in environments where you do *not* want a turing complete language.
# It comes with a very small number of builtin functions, all overridable.
#
# It is meant to aid in creating a DSL that can be executed in environments
# where code injection could be dangerous.
#
# To compile and run, you could, for example:
#     Interrotron.new().compile('(+ a_custom_var 2)').call("a_custom_var" => 4)
#     Interrotron.new().compile.run('(+ a_custom_var 4)', :vars => {"a_custom_var" => 2})
#     => 6
# You can inject your own custom functions and constants via the :vars option.
#
# Additionally, you can cap the number of operations exected with the :max_ops option
# This is of limited value since recursion is not a feature
#
class Interrotron
  class ParserError < StandardError; end
  class InvalidTokenError < ParserError; end
  class SyntaxError < ParserError; end
  class UndefinedVarError < ParserError; end
  class OpsThresholdError < StandardError; end
  class InterroArgumentError < StandardError; end

  class Macro
    def initialize(&block)
      @block = block
    end
    def call(*args)
      @block.call(*args)
    end
  end

  class Token
    attr_accessor :type, :value
    def initialize(type,value)
      @type = type
      @value = value
    end
  end
  
  attr_reader :stack
  
  TOKENS = [
            [:lpar, /\A\(/],
            [:rpar, /\A\)/],
            [:fn, /\Afn/],
            [:var, /\A[A-Za-z_><\+\>\<\!\=\*\/\%\-\?]+/],
            [:num, /\A(\-?[0-9]+(\.[0-9]+)?)/, 
             {cast: proc {|v| v =~ /\./ ? v.to_f : v.to_i }}],
            [:time, /\A#t\{([^\{]+)\}/,
             {capture: 1, cast: proc {|v| DateTime.parse(v).to_time }}],
            [:spc, /\A\s+/, {discard: true}],
            [:str, /\A"([^"\\]*(\\.[^"\\]*)*)"/, {capture: 1}],
            [:str, /\A'([^'\\]*(\\.[^'\\]*)*)'/, {capture: 1}]
           ]

  # Quote a ruby variable as a interrotron one
  def self.qvar(val)
    Token.new(:var, val.to_s)
  end

  # Converts Token objs to their values. If given a non-token, returns the obj
  def self.reify(obj)
    obj.is_a?(Token) ? obj.value : obj
  end
  
  DEFAULT_VARS = Hashie::Mash.new({
    'if' => Macro.new {|i,pred,t_clause,f_clause| i.iro_eval(pred) ? t_clause : f_clause },
    'cond' => Macro.new {|i,*args|
                 raise InterroArgumentError, "Cond requires at least 3 args" unless args.length >= 3
                 raise InterroArgumentError, "Cond requires an even # of args!" unless args.length.even?
                 res = qvar('nil')
                 args.each_slice(2).any? {|slice|
                   pred, expr = slice
                   res = expr if i.iro_eval(pred)
                 }
                 res
    },
    'and' => Macro.new {|i,*args| args.all? {|a| i.iro_eval(a)} ? args.last : qvar('false')  },
    'or' => Macro.new {|i,*args| args.detect {|a| i.iro_eval(a) } || qvar('false') },
    'let' => Macro.new {|i, variables, *expressions|
        raise InterroArgumentError, "let takes an even # of bindings!" unless variables.length.even?
        i.new_closure.execute(expressions) do |new_stack_frame|
          variables.each_slice(2) do |binding,v|
            new_stack_frame[binding.value] = i.iro_eval(v)
          end
        end
    },
    'lambda' => Macro.new {|i, arg_bindings, *expressions|
      lambda_frame = i.new_closure
      Macro.new {|i, *args|
        raise InterroArgumentError, "lambda requires #{arguments.length} args" unless args.length == arg_bindings.length
        
        lambda_frame.execute(expressions) do |new_stack_frame|
          arg_bindings.each_with_index do |binding, j|
            v = args[j]
            lambda_frame[binding.value] = Interrotron.reify(v)
          end
        end
      }
    },
    'defn' => Macro.new {|i, name, arguments, *expressions|
      macro = i.interrotron.stack_root_value('lambda').call(i, arguments, *expressions)
      # add function to the existing @stack
      i.interrotron.stack_root_value('setglobal').call(i, name, macro)
      macro
    },
    'setglobal' => Macro.new {|i, name, value|
      # add function to the existing @stack
      i.interrotron.set_root_value(name.value, value)
    },
    'expr' => proc {|i, *args| i.execute(args) },
    'apply' => proc {|i, fn, *args| fn.call(i, *args) },
    'array' => proc {|i, *args| args},
    'identity' => proc {|i, a| a},
    'not' => proc {|i, a| !a},
    '!' => proc {|i, a| !a},
    '>' => proc {|i, a,b| a > b},
    '<' => proc {|i, a,b| a < b},
    '>=' => proc {|i, a,b| a >= b},
    '<=' => proc {|i, a,b| a <= b},
    '='  => proc {|i, a,b| a == b},
    '!=' => proc {|i, a,b| a != b},
    'true' => true,
    'false' => false,
    'nil' => nil,
    '+' => proc {|i, *args| args.reduce(&:+)},
    '-' => proc {|i, *args| args.reduce(&:-)},
    '*' => proc {|i, *args| args.reduce(&:*)},
    '/' => proc {|i, a,b| a / b},
    '%' => proc {|i, a,b| a % b},
    'floor' =>  proc {|i, a| a.floor},
    'ceil' => proc {|i, a| a.ceil},
    'round' => proc {|i, a| a.round},
    'max' => proc {|i, arr| arr.max},
    'min' => proc {|i, arr| arr.min},
    'first' => proc {|i, arr| arr.first},
    'last' => proc {|i, arr| arr.last},
    'nth' => proc {|i, pos, arr| arr[pos]},
    'length' => proc {|i, arr| arr.length},
    'member?' => proc {|i, v,arr| arr.member? v},
    'int' => proc {|i, a| a.to_i},
    'float' => proc {|i, a| a.to_f},
    'time' => proc {|i, s| DateTime.parse(s).to_time},
    'rand' => proc {|i, n| rand n },
    'str' => proc {|i, *args| args.reduce("") {|m,a| m + a.to_s}},
    'strip' => proc {|i, s| s.strip},
    'upcase' => proc {|i, a| a.upcase},
    'downcase' => proc {|i, a| a.downcase},
    'now' => proc { |i| Time.now },
    'seconds' => proc {|i, n| n.to_i},
    'minutes' => proc {|i, n| n.to_i * 60},
    'hours' => proc {|i, n| n.to_i * 3600 },
    'days' => proc {|i, n| n.to_i * 86400},
    'months' => proc {|i, n| n.to_i * 2592000},
    'ago' => proc {|i, t| Time.now - t},
    'from-now' => proc {|i, t| Time.now + t}
  })

  def initialize(vars={},max_ops=nil)
    @max_ops = max_ops
    @instance_default_vars = DEFAULT_VARS.merge(vars)
  end

  def reset!
    @op_count = 0
    @stack = StackFrame.new(self, default_vars: @instance_default_vars)
  end
  
  # Converts a string to a flat array of Token objects
  def lex(str)
    return [] if str.nil?
    tokens = []
    while str.length > 0
      matched_any = TOKENS.any? {|name,matcher,opts|
        opts ||= {}
        matches = matcher.match(str)
        if !matches
          false
        else
          str = str[matches[0].length..-1]
          unless opts[:discard] == true
            val = matches[opts[:capture] || 0]
            val = opts[:cast].call(val) if opts[:cast]
            tokens << Token.new(name, val)
          end
          true
        end
      }
      raise InvalidTokenError, "Invalid token at: #{str}" unless matched_any
    end
    tokens
  end
  
  def parse(tokens)
    return [] if !tokens || tokens.empty?
    
    expr = []
    while !tokens.empty?
      t = tokens.shift
      case t.type
      when :lpar
        expr << parse(tokens)
      when :rpar
        return expr
      else
        expr << t
      end
    end
    expr
  end
  
  def resolve_token(token)
    if  token.type == :var
      frame = @stack.find {|frame| frame.has_key?(token.value) }
      raise UndefinedVarError, "Var '#{token.value}' is undefined!" unless frame
      frame[token.value]
    else
      token.value
    end
  end
  
  def register_op
    return unless @max_ops # noop when op counting disabled
    if  (@op_count+=1) > @max_ops
      raise OpsThresholdError, "Exceeded max ops(#{@max_ops}) allowed!"
    end
  end
  
  class StackFrame
    
    attr_reader :interrotron, :parent
    
    def initialize(interrotron, opts={})
      @parent = opts[:parent]
      @values = opts[:default_vars] || {}
      @interrotron = interrotron
    end
    
    def [](name)
      key = Interrotron.reify(name)
      if @values.has_key?(key)
        @values[key]
      elsif parent
        parent[key]
      else
        raise UndefinedVarError, "Var '#{key}' is undefined!"
      end
    end
    
    def []=(key, value)
      v = Interrotron.reify(value)
      @values[Interrotron.reify(key)] = v
      v
    end
    
    def new_closure()
      StackFrame.new(interrotron, parent: self)
    end
    
    def execute(expressions=[], &block)
      # create new stack frame for the function
      yield self if block
      
      # evaluate the expressions inside the closure and 
      value = execute_expressions(expressions)
      
      # return the value
      value
    end
    
    def iro_eval(expr)
      return expr if [Fixnum, NilClass, String, Float, TrueClass, FalseClass].include?(expr.class)
      return resolve_token(expr) if expr.is_a?(Token)
      return nil if expr.is_a?(Array) and expr.empty?
      interrotron.register_op
      
      head = iro_eval(expr[0])
      if head.is_a?(Macro)
        expanded = head.call(self, *expr[1..-1])
        
        # no longer evaling if the expanded macro is empty
        if expanded.is_a?(Array) or expanded.is_a?(Token)
          iro_eval(expanded) 
        else
          expanded
        end
      elsif head.is_a?(Proc)
        args = expr[1..-1].map {|e| iro_eval(e) }
        head.call(self, *args)
      else
        raise InterroArgumentError, "Non FN/macro Value in head position!\n  => #{head}"
      end
    end
    
    def execute_expressions(expressions=[])
      expressions.map {|expr| iro_eval(expr) }.last
    end
    
    def resolve_token(token)
      if  token.type == :var
        self[token.value]
      else
        token.value
      end
    end

  end
  
  def set_root_value(name, value)
    v = Interrotron.reify(value)
    @stack[Interrotron.reify(name)] = v
    v
  end
  
  def stack_root_value(name)
    @stack[Interrotron.reify(name)]
  end

  # Returns a Proc than can be executed with #call
  # Use if you want to repeatedly execute one script, this
  # Will only lex/parse once
  def compile(str)
    ast = parse(lex(str))
    proc {|vars,max_ops|
      reset!
      @max_ops = max_ops
      @stack = StackFrame.new(self, default_vars: @instance_default_vars.merge(vars))
      ast.map {|expr| @stack.iro_eval(expr)}.last
    }
  end

  def self.compile(str)
    Interrotron.new().compile(str)
  end

  def run(str,vars={},max_ops=nil)
    compile(str).call(vars,max_ops)
  end

  def self.run(str,vars={},max_ops=nil)
    Interrotron.new().run(str,vars,max_ops)
  end
end
