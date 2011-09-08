# -*- encoding: utf-8 -*-
lib = File.expand_path("../lib", __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'statsy'

Gem::Specification.new do |s|
  s.name        = "statsy"
  s.version     = Statsy::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Sean Treadway"]
  s.email       = ["treadway@gmail.com"]
  s.homepage    = "http://github.com/streadway/statsy"
  s.summary     = "Client network library to Statsd"
  s.description = "Simple way to increment counts and measure variance in timings of everything from requests per second to single espressos"

  s.rubyforge_project         = "statsy"

  s.add_development_dependency "test-unit"

  s.files        = Dir.glob("lib/**/*") + %w(LICENSE README.md)
  s.test_files   = Dir.glob("test/**/*")
  s.executables  = Dir.glob("bin/*")
  s.require_path = 'lib'
end
