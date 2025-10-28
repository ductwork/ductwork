# frozen_string_literal: true

require_relative "lib/ductwork/version"

Gem::Specification.new do |spec|
  spec.name = "ductwork"
  spec.version = Ductwork::VERSION
  spec.authors = ["Tyler Ewing"]
  spec.email = ["tewing10@gmail.com"]
  spec.summary = "A pipeline framework"
  spec.description = "A pipeline framework"
  spec.homepage = "https://github.com/zoso10/ductwork"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/README.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = %w[app config lib]

  rails_version_constraint = [">= 7.1", "< 8.2"]
  spec.add_dependency "activerecord", rails_version_constraint
  spec.add_dependency "activesupport", rails_version_constraint
  spec.add_dependency "railties", rails_version_constraint
  spec.add_dependency "zeitwerk", "~> 2.7"
end
