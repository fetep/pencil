# -*- ruby -*-
require File.expand_path('../lib/pencil/version', __FILE__)

Gem::Specification.new do |spec|
  files = []
  dirs = %w(lib docs examples)
  dirs.each do |dir|
    files += Dir["#{dir}/**/*"]
  end

  spec.name = "pencil"
  spec.version = Pencil::VERSION
  spec.summary = "pencil -- Graphite dashboard system"
  spec.description = "Graphite dashboard frontend"
  spec.license = "Mozilla Public License (1.1)"

  spec.add_dependency("map")
  spec.add_dependency("rack")
  spec.add_dependency("sinatra", "= 1.2.6")
  spec.add_dependency("json")
  spec.add_dependency("chronic")
  spec.add_dependency("chronic_duration")

  spec.files = files
  spec.bindir = "bin"
  spec.executables << "pencil"

  spec.authors = ["Pete Fritchman", "Wesley Dawson"]
  spec.email = ["petef@databits.net", "wdawson@mozilla.com"]
  spec.homepage = "https://github.com/fetep/pencil"
end
