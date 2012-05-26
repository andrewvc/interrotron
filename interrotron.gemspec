# -*- encoding: utf-8 -*-
require File.expand_path('../lib/interrotron/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Andrew Cholakian"]
  gem.email         = ["andrew@andrewvc.com"]
  gem.description   = %q{TODO: Write a gem description}
  gem.summary       = %q{TODO: Write a gem summary}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "interrotron"
  gem.require_paths = ["lib"]
  gem.version       = Interrotron::VERSION
  gem.add_development_dependency "rspec", "~> 2.6"
end
