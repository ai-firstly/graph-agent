# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "graph_agent"
  spec.version = "0.1.0"
  spec.authors = ["GraphAgent Contributors"]
  spec.summary = "A Ruby framework for building stateful, multi-actor agent workflows"
  spec.description = "Ruby port of LangGraph - build stateful, multi-actor applications " \
                     "with LLMs using a graph-based workflow engine with Pregel execution model"
  spec.homepage = "https://github.com/ai-firstly/graph-agent"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.files = Dir["lib/**/*", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "concurrent-ruby", "~> 1.2"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rubocop", "~> 1.50"
end
