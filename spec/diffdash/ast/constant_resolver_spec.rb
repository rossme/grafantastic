# frozen_string_literal: true

RSpec.describe Diffdash::AST::ConstantResolver do
  subject(:resolver) { described_class.new }

  describe '#scan and #resolve' do
    context 'with Hesiod registration' do
      it 'resolves counter constants' do
        source = <<~RUBY
          module Metrics
            RequestTotal = Hesiod.register_counter("request_total")
          end
        RUBY

        resolver.scan(source, 'metrics.rb')

        result = resolver.resolve('Metrics::RequestTotal')
        expect(result).to eq(name: 'request_total', type: :counter)
      end

      it 'resolves gauge constants' do
        source = <<~RUBY
          module Metrics
            QueueDepth = Hesiod.register_gauge("queue_depth")
          end
        RUBY

        resolver.scan(source, 'metrics.rb')

        result = resolver.resolve('Metrics::QueueDepth')
        expect(result).to eq(name: 'queue_depth', type: :gauge)
      end
    end

    context 'with StatsD registration' do
      it 'resolves counter constants' do
        source = <<~RUBY
          CACHE_HIT = StatsD.counter("cache.hit")
        RUBY

        resolver.scan(source, 'metrics.rb')

        result = resolver.resolve('CACHE_HIT')
        expect(result).to eq(name: 'cache.hit', type: :counter)
      end

      it 'resolves gauge constants' do
        source = <<~RUBY
          ACTIVE_USERS = StatsD.gauge("active_users")
        RUBY

        resolver.scan(source, 'metrics.rb')

        result = resolver.resolve('ACTIVE_USERS')
        expect(result).to eq(name: 'active_users', type: :gauge)
      end
    end

    context 'with nested modules' do
      it 'resolves deeply nested constants' do
        source = <<~RUBY
          module App
            module Metrics
              UserCreated = Hesiod.register_counter("user_created")
            end
          end
        RUBY

        resolver.scan(source, 'metrics.rb')

        result = resolver.resolve('App::Metrics::UserCreated')
        expect(result).to eq(name: 'user_created', type: :counter)
      end
    end

    context 'with class-based definitions' do
      it 'resolves constants in classes' do
        source = <<~RUBY
          class MetricsService
            RequestCounter = Hesiod.register_counter("requests")
          end
        RUBY

        resolver.scan(source, 'metrics.rb')

        result = resolver.resolve('MetricsService::RequestCounter')
        expect(result).to eq(name: 'requests', type: :counter)
      end
    end

    context 'with symbol metric names' do
      it 'resolves symbol names to strings' do
        source = <<~RUBY
          module Metrics
            ErrorCount = Hesiod.register_counter(:error_count)
          end
        RUBY

        resolver.scan(source, 'metrics.rb')

        result = resolver.resolve('Metrics::ErrorCount')
        expect(result).to eq(name: 'error_count', type: :counter)
      end
    end

    context 'with unresolvable constants' do
      it 'returns nil for unknown constants' do
        result = resolver.resolve('Unknown::Constant')
        expect(result).to be_nil
      end

      it 'ignores non-metric constant assignments' do
        source = <<~RUBY
          module Config
            TIMEOUT = 30
            API_URL = "https://api.example.com"
          end
        RUBY

        resolver.scan(source, 'config.rb')

        expect(resolver.resolve('Config::TIMEOUT')).to be_nil
        expect(resolver.resolve('Config::API_URL')).to be_nil
      end
    end

    context 'with multiple files' do
      it 'accumulates constants from multiple scans' do
        resolver.scan('RequestTotal = Hesiod.register_counter("requests")', 'a.rb')
        resolver.scan('ErrorTotal = Hesiod.register_counter("errors")', 'b.rb')

        expect(resolver.resolve('RequestTotal')).to eq(name: 'requests', type: :counter)
        expect(resolver.resolve('ErrorTotal')).to eq(name: 'errors', type: :counter)
      end
    end
  end

  describe '#constant_map' do
    it 'exposes the internal map for debugging' do
      source = <<~RUBY
        module Metrics
          Counter1 = Hesiod.register_counter("c1")
          Counter2 = Hesiod.register_counter("c2")
        end
      RUBY

      resolver.scan(source, 'metrics.rb')

      expect(resolver.constant_map.keys).to contain_exactly('Metrics::Counter1', 'Metrics::Counter2')
    end
  end
end
