# frozen_string_literal: true

require_relative "lib/ductwork/version"

Gem::Specification.new do |spec|
  spec.name = "ductwork"
  spec.version = Ductwork::VERSION
  spec.authors = ["Tyler Ewing"]
  spec.email = ["contact@getductwork.io"]
  spec.summary = "A Ruby pipeline framework"
  spec.description = "Ductwork lets you build complex pipelines quickly and " \
                     "easily using intuitive Ruby tooling and a natural DSL."
  spec.homepage = "https://github.com/ductwork/ductwork"
  spec.license = "LGPL-3.0-or-later"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["documentation_uri"] = "https://docs.getductwork.io/"

  gemspec = File.basename(__FILE__)
  excludes = %w[
    bin/ log/ gemfiles/ spec/ .git .github .rspec .rubocop.yml .ruby-version
    Gemfile Appraisals CODE_OF_CONDUCT.md config.ru
  ]
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) || f.start_with?(*excludes)
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
