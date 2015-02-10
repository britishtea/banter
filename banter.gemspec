$:.unshift File.expand_path("../lib", __FILE__)
require "banter/version"

Gem::Specification.new do |s|
  s.name          = "banter"
  s.version       = Banter::VERSION
  s.summary       = "A small IRC library"
  s.description   = "A small, lightweight and flexible IRC framework"
  s.authors       = ["Jip van Reijsen"]
  s.email         = ["jipvanreijsen@gmail.com"]
  s.homepage      = "https://github.com/britishtea/banter"
  s.license       = "MIT"

  s.files         = `git ls-files lib`.split("\n")
  s.require_paths = ["lib"]

  s.add_dependency "thread_safe", "~> 0.3"
  s.add_dependency "irc-helpers", "~> 0.1"

  s.add_development_dependency "cutest", "~> 1.2"
end
