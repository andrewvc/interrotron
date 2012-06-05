require 'interrotron'

describe "running" do
  
  def run(s,vars={},max_ops=nil)
    Interrotron.run(s,vars,max_ops)
  end
  
  it "should exec identity correctly" do
    run("(identity 2)").should == 2
  end

  describe "and" do
    it "should return true if all truthy" do
      run("(and 1 true 'ohai')").should be_true
    end
    it "should return false if not all truthy" do
      run("(and 1 true false)").should be_false
    end
  end

  describe "or" do
    it "should return true if all truthy" do
      run("(or 1 true 'ohai')").should be_true
    end
    it "should return true if some truthy" do
      run("(or 1 true false)").should be_true
    end
    it "should return false if all falsey" do
      run("(or nil false)").should be_false
    end
  end

  describe "evaluating a single tokens outside on sexpr" do
    it "simple values should return themselves" do
      run("28").should == 28
    end
    it "vars should dereference" do
      run("true").should == true
    end
  end

  describe "nested expressions" do
    it "should execute a simple nested expr correctly" do
      run("(+ (* 2 2) (% 5 4))").should == 5
    end
    
    it "should execute complex nested exprs correctly" do
      run("(if false (+ 4 -3) (- 10 (+ 2 (+ 1 1))))").should == 6
    end
  end

  describe "custom vars" do
    it "should define custom vars" do
      run("my_var", "my_var" => 123).should == 123
    end
    it "should properly execute proc custom vars" do
      run("(my_proc 4)", "my_proc" => proc {|i, a| a*2 }).should == 8
    end
  end

  describe "times" do
    it "should parse and compare them properly" do
      run('(> #t{2010-09-04} start_date)', start_date: DateTime.parse('2012-12-12').to_time)
    end
    it "should understand days, minutes, seconds, and hours, as integers" do
      run("(+ (days 1) (minutes 1) (hours 1) (seconds 1))").should == 90061
    end

    it "should add the time using from-now" do
      n = Time.now
      Time.should_receive(:now).twice().and_return(n)
      run("(from-now (minutes 1))").to_i.should == (Time.now + 60).to_i
    end

    it "should compare times using convenience multipliers correctly" do
      run('(> (now) (ago (hours 12)))').should be_true
    end
  end

  describe "cond" do
    it "should work for a simple case where there is a match" do
      run("(cond (> 1 2) (* 2 2)
                 (< 5 10) 'ohai')").should == 'ohai'
    end
    it "should return nil when no matches available" do
      run("(cond (> 1 2) (* 2 2)
                 false 'ohai')").should == nil
    end
    it "should support true as a fallthrough clause" do
      run("(cond (> 1 2) (* 2 2)
                 false 'ohai'
                 true  'backup')").should == 'backup'
    end
  end

  describe "intermediate compilation" do
    it "should support compiled scripts" do
      # Setup an interrotron obj with some default vals
      tron = Interrotron.new(:is_valid => proc {|i, a| a.reverse == 'oof'})
      compiled = tron.compile("(is_valid my_param)")
      compiled.call(:my_param => 'foo').should == true
      compiled.call(:my_param => 'bar').should == false
    end
  end

  describe "higher order functions" do
    it "should support calculating a fn at the head" do
      run('((or * +) 5 5)').should == 25
    end
  end

  describe "array" do
    it "should return a ruby array" do
      run("(array 1 2 3)").should == [1, 2, 3]
    end

    it "should detect max vals correctly" do
      run("(max (array 82 10 100 99.5))").should == 100
    end

    it "should detect min vals correctly" do
      run("(min (array 82 10 100 99.5))").should == 10
    end
    
    it "should let you get the head" do
      run("(first (array 1 2 3))").should == 1
    end

    it "should let you get the tail" do
      run("(last (array 1 2 3))").should == 3
    end

    it "should let you get the length" do
      run("(length (array 1 2 3 'bob'))").should == 4
    end

    describe "checking membership" do
      it "should work in the false case" do
        run("(member? 5 (array 10 20 30))").should be_false
      end
      it "should work in the true case" do
        run("(member? 5 (array 10 5 30))").should be_true
      end
    end
  end

  describe "readme examples" do
    it "should execute the simple custom var one" do
      Interrotron.run('(> 51 custom_var)', 'custom_var' => 10).should == true
    end
  end

  describe "op counter" do
    it "should not stop scripts under or at the threshold" do
      run("(str (+ 1 2) (+ 3 4) (+ 5 7))", {}, 5)
    end
    it "should terminate with the proper exception if over the threshold" do
      proc {
        run("(str (+ 1 2) (+ 3 4) (+ 5 7))", {}, 3)
      }.should raise_exception(Interrotron::OpsThresholdError)
    end
  end

  describe "multiple forms at the root" do
    it "should return the second form" do
      run("(+ 1 1) (+ 2 2)").should == 4
    end

    it "should raise an exception if a number is in a fn pos" do
      proc { run("(1)") }.should raise_exception(Interrotron::InterroArgumentError)
    end
  end

  describe "empty input" do
    it "should return nil" do
      run("").should be_nil
    end
  end
  
  describe "apply macro" do
    it "should spat an array into another function" do
      run("(apply + 1 2 3)").should == 6
    end
  end
  
  describe "conversions" do
    it "should convert ints" do
      res = run("(int '2')")
      res.should == 2
      res.should be_a(Fixnum)
    end

    it "should convert floats" do
      res = run("(float '2.5')")
      res.should == 2.5
      res.should be_a(Float)
    end

    it "should parse dates and times" do
      run("(time '2012-05-01')").should == DateTime.parse("2012-05-01").to_time
    end
  end
  
  describe "expr" do
    it "should allow multiple expressions to be executed and return the last value" do
      run("(expr (+ 4 3) (+ 4 3))").should == 7
    end
    
    it "should return the value of the last expression" do
       run("(expr (+ 4 3) (+ 2 3))").should == 5
    end
  end
  
  describe "lambda" do
    it "should have access to vars it's bound" do
      run("(apply (lambda (x) (* x 2)) 2)").should == 4
    end
    
    it "should return the last expression" do
      run("(apply (lambda (x) (* x 2) (* x 3)) 2)").should == 6
    end
  end
  
  describe "let" do
    it "should have access to vars it's bound" do
      run("(let (x 2) x)").should == 2
    end
    
    it "should allow multiple variable bindings" do
      run("(let (x 2 y 4) (* x y))").should == 8
    end
        
    it "should return the last expression" do
      run("(let (x 3 z 5) (* x z) (+ x z))").should == 8
    end

    it "should raise an InterroArgumentError when given an uneven # of args" do
      lambda { run("(let (x 1 y) 1 2)") }.should raise_exception(Interrotron::InterroArgumentError)
    end
  end
  
  describe "defn" do
    it "should be able to call the new function" do
      run("(defn say_hi (name) (+ 'hi there, ' name '!'))\n\n(say_hi 'Justin')").should == "hi there, Justin!"
    end
    
    it "should be able to call the returned function right away" do
      run("(apply (defn say_hi (name) (+ 'hi there, ' name '!')) 'Andrew')").should == "hi there, Andrew!"
    end
  end
  
  describe "setglobal" do
    it "should allow you to call the variable" do
      run("(setglobal x 5) x").should == 5
    end
    
    it "should allow you to call the variable when it's declared in a closure" do
      run("(apply (lambda () (setglobal y 4))) y").should == 4
    end
  end
end

describe Interrotron do
  describe "#execute_expressions" do
    it "should allow multiple expressions to be executed and return the last value" do
      i = Interrotron.new()
      i.reset!
      ast = i.parse(i.lex("(+ 4 3)(+ 4 3)"))
      i.execute_expressions(ast).should == 7
    end
    
    it "should return the value of the last expression" do
      i = Interrotron.new()
      i.reset!
      ast = i.parse(i.lex("(+ 4 3)(+ 2 3)"))
      i.execute_expressions(ast).should == 5
    end
  end
  
  describe "#closure" do
    it "should allow for variables to be modified" do
      i = Interrotron.new()
      my_proc = i.compile("(apply (lambda (x) x) 5)")
      my_proc.call({'x' => 2, 'y' => 3}, nil).should == 5
    end
    
    it "variables in the parent closure should not be overridden" do
      i = Interrotron.new()
      my_proc = i.compile("(apply (lambda (x) x) 5)")
      my_proc.call({x: 2, y: 3}, nil)
      i.stack_value('x').should == 2
    end
  end
  
  describe "#set_root_value" do
    it "should set the value of the root stack frame" do
      i = Interrotron.new({'x' => 2, 'y' => 3})
      i.reset!
      i.instance_variable_get(:@stack).unshift({'x' => 5})
      i.stack_root_value('x').should == 2
    end
  end
  
  describe "#stack_root_value" do
    it "should grab the stack root frame value" do
      i = Interrotron.new({'x' => 2, 'y' => 3})
      i.reset!
      i.instance_variable_get(:@stack).unshift({'x' => 5})
      i.stack_root_value('x').should == 2
    end
  end
  
  describe "stack_value" do
    it "should grab the current stack frame's value" do
      i = Interrotron.new({'x' => 2, 'y' => 3})
      i.reset!
      i.instance_variable_get(:@stack).unshift({'x' => 5})
      i.stack_value('x').should == 5
    end
  end
  
  describe "#set_value" do
    it "should set the value of the current stack frame" do
      i = Interrotron.new({'x' => 2, 'y' => 3})
      i.reset!
      i.instance_variable_get(:@stack).unshift({'x' => 5})
      i.set_value('y', 6)
      i.stack_value('y').should == 6
    end
  end
end
