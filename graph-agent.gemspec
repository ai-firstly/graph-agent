# frozen_string_literal: true

require_relative "lib/graph_agent/version"

Gem::Specification.new do |spec|
  spec.name          = "graph-agent"
  spec.version       = GraphAgent::VERSION
  spec.authors       = ["GraphAgent Contributors"]
  spec.email         = ["richard.sun@ai-firstly.com"]
  spec.summary       = "A Ruby framework for building stateful, multi-actor agent workflows"
  spec.description   = "Ruby port of LangGraph - build stateful, multi-actor applications " \
                       "with LLMs using a graph-based workflow engine with Pregel execution model"
  spec.homepage      = "https://github.com/ai-firstly/graph-agent"
  spec.license       = "MIT"
  spec.required_ruby_version = [">= 3.1.0", "< 5.0"]

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ai-firstly/graph-agent"
  spec.metadata["changelog_uri"] = "https://github.com/ai-firstly/graph-agent/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://rubydoc.info/gems/graph-agent"
  spec.metadata["bug_tracker_uri"] = "https://github.com/ai-firstly/graph-agent/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    if File.exist?(".git")
      `git ls-files -z`.split("\x0").reject do |f|
        f.match(%r{\A(?:test|spec|features)/})
      end
    else
      Dir.glob("**/*").reject do |f|
        File.directory?(f) ||
          f.match(%r{\A(?:test|spec|features)/}) ||
          f.match(/\A\./) ||
          f.match(/\.gem$/)
      end
    end
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "concurrent-ruby", "~> 1.2"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rubocop", "~> 1.50"
end
