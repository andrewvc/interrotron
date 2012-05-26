require 'interrotron'

describe "running" do
  
  def run(s,vars={})
    Interrotron.run(s,vars)
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
    it "should execute complex nested exprs correctly" do
      run("(if false (+ 4 -3) (- 10 (+ 2 (+ 1 1))))").should == 6
    end
  end

  describe "custom vars" do
    it "should define custom vars" do
      run("my_var", "my_var" => 123).should == 123
    end
    it "should properly execute proc custom vars" do
      run("(my_proc 4)", "my_proc" => proc {|a| a*2 }).should == 8
    end
  end

  describe "intermediate compilation" do
    # Setup an interrotron obj with some default vals
    tron = Interrotron.new(:is_valid => proc {|a| a.reverse == 'oof'})
    compiled = tron.compile("(is_valid my_param)")
    compiled.call(:my_param => 'foo').should == true
    compiled.call(:my_param => 'bar').should == false
  end

  describe "readme examples" do
    it "should execute the simple custom var one" do
      Interrotron.run('(> 51 custom_var)', 'custom_var' => 10).should == true
    end
  end
end
