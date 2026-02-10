# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require_relative "lib/graph_agent/version"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

# Custom release task
desc "Release gem to RubyGems"
task release_gem: [:build] do
  sh "gem push graph-agent-#{GraphAgent::VERSION}.gem"
end
