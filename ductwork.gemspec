# frozen_string_literal: true

require_relative "lib/ductwork/version"

Gem::Specification.new do |spec|
  spec.name = "ductwork"
  spec.version = Ductwork::VERSION
  spec.authors = ["Tyler Ewing"]
  spec.email = ["tewing10@gmail.com"]
  spec.summary = "A jobs pipeline"
  spec.description = "A jobs pipeline"
  spec.homepage = "https://github.com/zoso10/ductwork"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/README.md"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
