# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'sidekiq/heroku_autoscale/version'

Gem::Specification.new do |s|
  s.name        = 'sidekiq-heroku-autoscale'
  s.version     = Sidekiq::HerokuAutoscale::VERSION

  s.required_ruby_version = '~> 2.5'
  s.require_paths         = %w[lib]
  s.files                 = Dir['README.md', 'lib/**/*']

  s.authors     = ['Greg MacWilliam', 'Justin Love', 'Alex Yarotsky']
  s.summary     = 'Start, stop, and scale Sidekiq dynos on Heroku based on workload'
  s.description = s.summary
  s.homepage    = 'https://github.com/ayarotsky/sidekiq-heroku-autoscale'
  s.licenses    = ['MIT']

  s.add_runtime_dependency 'platform-api', '~> 3.3'
  s.add_runtime_dependency 'sidekiq', '>= 5.0'

  s.add_development_dependency 'bundler', '~> 2.0'
  s.add_development_dependency 'minitest', '~> 5.14'
  s.add_development_dependency 'mock_redis', '~> 0.28'
  s.add_development_dependency 'rake', '~> 12.0'
  s.add_development_dependency 'rubocop', '~> 1.18'
  s.add_development_dependency 'rubocop-minitest', '~> 0.13'
  s.add_development_dependency 'rubocop-performance', '~> 1.11'
  s.add_development_dependency 'rubocop-rake', '~> 0.6'
end
