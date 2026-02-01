# frozen_string_literal: true

require_relative 'lib/diffdash/version'

Gem::Specification.new do |spec|
  spec.name          = 'diffdash'
  spec.version       = Diffdash::VERSION
  spec.authors       = ['Ross Buddie']
  spec.email         = ['you@example.com']

  spec.summary       = 'PR-scoped observability signal extractor and Grafana dashboard generator'
  spec.description   = 'Statically analyzes Ruby source code in a Pull Request and generates ' \
                       'a Grafana dashboard JSON containing panels relevant to observability signals.'
  spec.homepage      = 'https://github.com/rossme/diffdash'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.0.0'

  spec.files = Dir.glob('{bin,lib}/**/*') + %w[README.md]
  spec.bindir        = 'bin'
  spec.executables   = ['diffdash']
  spec.require_paths = ['lib']

  spec.add_dependency 'ast', '~> 2.4'
  spec.add_dependency 'dotenv', '>= 2.8'
  spec.add_dependency 'faraday', '>= 2.0'
  spec.add_dependency 'faraday-multipart', '>= 1.0'
  spec.add_dependency 'parser', '~> 3.2'

  spec.add_development_dependency 'rspec', '~> 3.12'
  spec.add_development_dependency 'rubocop', '~> 1.50'
  spec.add_development_dependency 'webmock', '~> 3.18'
end
