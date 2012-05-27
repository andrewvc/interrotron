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
    'apply' => proc {|fn,arr| fn.call(*arr) },
    'array' => proc {|*args| args},
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
    'max' => proc {|arr| arr.max},
    'min' => proc {|arr| arr.min},
    'first' => proc {|arr| arr.first},
    'last' => proc {|arr| arr.last},
    'nth' => proc {|pos, arr| arr[pos]},
    'length' => proc {|arr| arr.length},
    'member?' => proc {|v,arr| arr.member? v},
    'to_i' => proc {|a| a.to_i},
    'to_f' => proc {|a| a.to_f},
    'rand' => proc {|n| rand n },
    'str' => proc {|*args| args.reduce("") {|m,a| m + a.to_s}},
    'strip' => proc {|s| s.strip},
    'upcase' => proc {|a| a.upcase},
    'downcase' => proc {|a| a.downcase},
    'now' => proc { Time.now },
    'seconds' => proc {|n| n.to_i},
    'minutes' => proc {|n| n.to_i * 60},
    'hours' => proc {|n| n.to_i * 3600 },
    'days' => proc {|n| n.to_i * 86400},
    'months' => proc {|n| n.to_i * 2592000},
    'ago' => proc {|t| Time.now - t},
    'from-now' => proc {|t| Time.now + t}
  })

  def initialize(vars={},max_ops=nil)
    @max_ops = max_ops
    @instance_default_vars = DEFAULT_VARS.merge(vars)
  end

  def reset!
    @op_count = 0
    @stack = [@instance_default_vars]
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
      frame = @stack.reverse.find {|frame| frame.has_key?(token.value) }
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
  
  def iro_eval(expr,max_ops=nil)
    return resolve_token(expr) if expr.is_a?(Token)
    return nil if expr.empty?
    register_op
    
    head = iro_eval(expr[0])
    if head.is_a?(Macro)
      expanded = head.call(self, *expr[1..-1])
      iro_eval(expanded)
    elsif head.is_a?(Proc)
      args = expr[1..-1].map {|e| iro_eval(e) }
      head.call(*args)
    else
      raise InterroArgumentError, "Non FN/macro Value in head position!"
    end
  end

  # Returns a Proc than can be executed with #call
  # Use if you want to repeatedly execute one script, this
  # Will only lex/parse once
  def compile(str)
    tokens = lex(str)
    ast = parse(tokens)

    proc {|vars,max_ops|
      reset!
      @max_ops = max_ops
      @stack = [@instance_default_vars.merge(vars)]
      #iro_eval(ast)
      ast.map {|expr| iro_eval(expr)}.last
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
