# frozen_string_literal: true

require_relative "lib/flipbook/version"

Gem::Specification.new do |spec|
  spec.name = "flipbook"
  spec.version = Flipbook::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]
  spec.summary = "Write and read GIF and APNG animations in Ruby"
  spec.description = "Flipbook encodes animated GIF and APNG files from Tessel RGBA images."
  spec.homepage = "https://github.com/rbgfx/flipbook"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |file|
      file == File.basename(__FILE__) || file.start_with?(*%w[bin/ Gemfile .gitignore .github/ test/])
    end
  end
  spec.require_paths = ["lib"]
  spec.add_dependency "tessel", ">= 0.2.0", "< 1.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "test-unit", "~> 3.6"
end
