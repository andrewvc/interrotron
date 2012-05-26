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

  TOKENS = [
            [:lpar, /\(/],
            [:rpar, /\)/],
            [:var, /[A-Za-z_><\+\>\<\!\=\*\/\%\-]+/],
            [:num, /(\-?[0-9]+(\.[0-9]+)?)/],
            [:datetime, /#dt\{([^\{]+)\}/, {capture: 1}],
            [:spc, /\s+/, {discard: true}],
            [:str, /"([^"\\]*(\\.[^"\\]*)*)"/, {capture: 1}],
            [:str, /'([^'\\]*(\\.[^'\\]*)*)'/, {capture: 1}]
           ]

  # Either passes a value through or invokes call() if passed a proc
  def self.mat(v)
    v.class == Proc ? v.call() : v
  end
  
  DEFAULT_VARS = Hashie::Mash.new({
    'if' => [proc {|pred,t_clause,f_clause| mat(pred) ? mat(t_clause) : mat(f_clause) }, :lazy_args],
    'cond' => [proc {|*args|
                 raise InterroArgumentError, "Cond requires at least args" unless args.length >= 3
                 raise InterroArgumentError, "Cond requires an even # of args!" unless args.length.even?
                 res = nil
                 args.each_slice(2).any? {|slice|
                   pred, expr = slice
                   res = mat(expr) if mat(pred)
                 }
                 res
               }, :lazy_args],
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
  })

  # Takes 2 opts:
  # vars => {}, a hash of variables to introduce. Vars can act as either functions
  # (if they're procs) or as simple values
  # max_ops => 29, takes an integer which can be used to set a maximum number of expressions
  # to evaluate. It's a crude way to cap execution time
  def initialize(vars={},max_ops=nil)
    @vars = DEFAULT_VARS.merge(vars)
    @max_ops = max_ops
  end
  
  def lex(str)
    return [] if str.nil?
    tokens = []
    while str.length > 0
      matched_any = TOKENS.any? {|name,matcher,opts|
        opts ||= {}
        matches = matcher.match(str)
        if !matches || !matches.pre_match.empty?
          false
        else
          mlen = matches[0].length
          str = str[mlen..-1]
          m = matches[opts[:capture] || 0]
          tokens << [name, m] unless opts[:discard] == true
          true
        end
      }
      raise InvalidTokenError, "Invalid token at: #{str}" unless matched_any
    end
    tokens
  end
  
  # Transforms token values to ruby types
  def cast(t)
    type, val = t
    new_val = case t[0]
              when :num
                val =~ /\./ ? val.to_f : val.to_i
              when :datetime
                DateTime.parse(val)
              else
                val
              end
    [type, new_val]
  end
  
  def parse(tokens)
    return [] if tokens.empty?
    expr = []
    t = tokens.shift
    if t[0] == :lpar
      expr << :expr
      while t = tokens[0]
        if t[0] == :lpar
          expr << parse(tokens)
        else
          tokens.shift
          break if t[0] == :rpar
          expr << cast(t)
        end
      end
    elsif t[0] != :rpar
      tokens.shift
      expr += cast(t)
      #raise SyntaxError, "Expected :lparen, got #{t} while parsing #{tokens}"
    end
    expr
  end
  
  def resolve(token,vars)
    type, val = token
    return val unless type == :var
    raise SyntaxError, "Unbalanced lparen!" if val.is_a?(Array)
    raise UndefinedVarError, "Var '#{val}' is undefined!" unless vars.has_key?(val)
    vars[val]
  end
  
  def run_expr(expr,vars=DEFAULT_VARS,max_ops=nil,ops_cnt=0)
    return nil if expr.empty?
    raise OpsThresholdError, "Exceeded max ops(#{max_ops}) allowed!" if max_ops && ops_cnt > max_ops
    
    # Handle bare expressions (outside of an sexpr) if they're at the
    # root of the file by executing a proc that simply returns it
    fn = expr[0] == :expr ? resolve(expr[1], vars) :  proc { resolve(expr, vars)}
    
    # Most FNs get materialized args. For control flow though (like OR and AND), we don't want this, but we pass in procs representing the future value instead
    lazy_args = (fn.class == Array && fn[1] == :lazy_args)
    fn = fn[0] if lazy_args
    
    args = expr[2..-1].map {|token|
      type, val = token
      if type == :expr
        ops_cnt += 1
        lazy_args ?
          proc { run_expr(token,vars,max_ops,ops_cnt) } :
          run_expr(token,vars,max_ops,ops_cnt)
      else
        resolve(token,vars)
      end
    }
    res = fn.call(*args)
    res
  end

  # Returns a Proc than can be executed with #call
  # Use if you want to repeatedly execute one script, this
  # Will only lex/parse once
  def compile(str)
    tokens = lex(str)
    ast = parse(tokens)

    proc {|vars| 
      run_vars = @vars.merge(vars || {})
      run_expr(ast, run_vars, @max_ops)
    }
  end

  def self.compile(str)
    Interrotron.new().compile(str)
  end

  def run(str,vars={})
    compile(str).call(vars)
  end

  def self.run(str,vars={})
    Interrotron.new().run(str,vars)
  end
end
