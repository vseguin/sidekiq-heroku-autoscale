# frozen_string_literal: true

require 'test_helper'

describe 'Sidekiq::HerokuAutoscale::Process' do
  before do
    Sidekiq.redis(&:flushdb)
    @config = { app_name: 'test-this', name: 'sidekiq' }
    @subject = ::Sidekiq::HerokuAutoscale::Process.new(**@config)
    @subject2 = ::Sidekiq::HerokuAutoscale::Process.new(**@config)
  end

  describe 'throttled?' do
    it 'returns false when last update is blank' do
      @subject.updated_at = nil
      refute @subject.throttled?
    end

    it 'returns false when last update falls outside the throttle' do
      @subject.updated_at = Time.now.utc - 11
      refute @subject.throttled?
    end

    it 'returns true when last update falls within the throttle' do
      @subject.updated_at = Time.now.utc - 9
      assert @subject.throttled?
    end
  end

  describe 'updated_since_last_activity?' do
    it 'returns false when last activity is blank' do
      @subject.active_at = nil
      @subject.updated_at = Time.now.utc - 1
      refute @subject.updated_since_last_activity?
    end

    it 'returns false when last update is blank' do
      @subject.active_at = Time.now.utc - 1
      @subject.updated_at = nil
      refute @subject.updated_since_last_activity?
    end

    it 'returns false when last update is before inquiry' do
      @subject.active_at = Time.now.utc - 10
      @subject.updated_at = @subject.active_at - 1
      refute @subject.updated_since_last_activity?
    end

    it 'returns true when last update is after inquiry' do
      @subject.active_at = Time.now.utc - 10
      @subject.updated_at = @subject.active_at + 1
      assert @subject.updated_since_last_activity?
    end
  end

  describe 'quieting?' do
    it 'returns false when quieting values not set' do
      @subject.quieted_to = nil
      @subject.quieted_at = nil
      refute @subject.quieting?

      @subject.quieted_to = 0
      @subject.quieted_at = nil
      refute @subject.quieting?

      @subject.quieted_to = nil
      @subject.quieted_at = Time.now.utc
      refute @subject.quieting?
    end

    it 'returns true when quieting values are set' do
      @subject.quieted_to = 0
      @subject.quieted_at = Time.now.utc
      assert @subject.quieting?
    end
  end

  describe 'shutting_down?' do
    it 'true when quieted to zero' do
      @subject.quieted_to = 1
      @subject.quieted_at = Time.now.utc
      assert @subject.quieting?
      refute @subject.shutting_down?

      @subject.quieted_to = 0
      assert @subject.shutting_down?
    end
  end

  describe 'fulfills_quietdown?' do
    it 'returns false without a quietdown time' do
      @subject.quieted_at = nil
      refute @subject.fulfills_quietdown?
    end

    it 'checks if last quietdown exceeds the buffer' do
      @subject.quiet_buffer = 10

      @subject.quieted_at = Time.now.utc - 9
      refute @subject.fulfills_quietdown?

      @subject.quieted_at = Time.now.utc - 11
      assert @subject.fulfills_quietdown?
    end
  end

  describe 'set_attributes' do
    it 'sets dyno count with a startup time' do
      @subject.set_attributes(dynos: 2)
      cached = Sidekiq.redis { |c| c.hgetall(@subject.cache_key) }

      assert_equal 2, @subject.dynos
      assert_equal '2', cached['dynos']
    end

    it 'sets and clears a quieted-to count' do
      @subject.set_attributes(quieted_to: 1)
      cached = Sidekiq.redis { |c| c.hgetall(@subject.cache_key) }
      assert_equal 1, @subject.quieted_to
      assert_equal '1', cached['quieted_to']

      @subject.set_attributes(quieted_to: nil)
      cached = Sidekiq.redis { |c| c.hgetall(@subject.cache_key) }
      assert_nil @subject.quieted_to
      refute cached.key?('quieted_to')
    end

    it 'sets and clears a quieted-at time' do
      @subject.set_attributes(quieted_at: Time.now.utc)
      cached = Sidekiq.redis { |c| c.hgetall(@subject.cache_key) }
      assert @subject.quieted_at
      assert_equal @subject.quieted_at.to_i.to_s, cached['quieted_at']

      @subject.set_attributes(quieted_at: nil)
      cached = Sidekiq.redis { |c| c.hgetall(@subject.cache_key) }
      assert_nil @subject.quieted_at
      refute cached.key?('quieted_at')
    end

    it 'sets and clears an updated-at time' do
      @subject.set_attributes(updated_at: Time.now.utc)
      cached = Sidekiq.redis { |c| c.hgetall(@subject.cache_key) }
      assert @subject.updated_at
      assert_equal @subject.updated_at.to_i.to_s, cached['updated_at']

      @subject.set_attributes(updated_at: nil)
      cached = Sidekiq.redis { |c| c.hgetall(@subject.cache_key) }
      assert_nil @subject.updated_at
      refute cached.key?('updated_at')
    end
  end

  describe 'sync_attributes' do
    it 'syncs attributes with cached values' do
      dynos = 2
      quieted_to = 1
      quieted_at = Time.now.utc - 10
      updated_at = quieted_at + 1
      @subject2.set_attributes(dynos: dynos,
                               quieted_to: quieted_to,
                               quieted_at: quieted_at,
                               updated_at: updated_at)
      @subject.sync_attributes

      assert_equal dynos, @subject.dynos
      assert_equal quieted_to.to_i, @subject.quieted_to.to_i
      assert_equal updated_at.to_i, @subject.updated_at.to_i
    end

    it 'syncs empty attributes from the cache' do
      @subject2.set_attributes(dynos: 2,
                               quieted_to: 2,
                               quieted_at: Time.now.utc,
                               updated_at: Time.now.utc)
      @subject.sync_attributes
      assert @subject.dynos
      assert @subject.quieted_to
      assert @subject.quieted_at
      assert @subject.updated_at

      @subject2.set_attributes(dynos: nil, quieted_to: nil, quieted_at: nil, updated_at: nil)
      @subject.sync_attributes
      assert_equal 0, @subject.dynos
      refute @subject.quieted_to
      refute @subject.quieted_at
      refute @subject.updated_at
    end
  end

  describe 'quietdown' do
    it 'assigns a downscale target' do
      @subject.quietdown(1)
      assert_equal 1, @subject.quieted_to
      assert @subject.quieted_at
    end

    it 'enables quietdown buffer after quieting workers' do
      @subject.queue_system.stub(:quietdown!, true) do
        @subject.quietdown(0)
        refute @subject.fulfills_quietdown?
      end
    end

    it 'skips quietdown buffer when there was nothing to quiet' do
      @subject.queue_system.stub(:quietdown!, false) do
        @subject.quietdown(0)
        assert @subject.fulfills_quietdown?
      end
    end

    it 'does not scale below zero' do
      @subject.quietdown(-1)
      assert_equal 0, @subject.quieted_to
    end
  end

  describe 'wait_for_update!' do
    it 'returns true when updated since last activity' do
      @subject.updated_at = Time.now.utc - 10
      @subject.active_at = @subject.updated_at - 1
      assert @subject.wait_for_update!
    end

    it 'returns false when throttled' do
      @subject.updated_at = Time.now.utc - 9
      refute @subject.wait_for_update!
    end

    it 'returns true when a syncronized update is newer than last activity' do
      @subject.active_at = Time.now.utc - 10
      @subject2.set_attributes(updated_at: @subject.active_at + 1)
      assert @subject.wait_for_update!
    end

    it 'returns false when a syncronized update is throttled' do
      @subject2.set_attributes(updated_at: Time.now.utc - 9)
      refute @subject.wait_for_update!
      assert_equal @subject.updated_at.to_i, @subject2.updated_at.to_i
    end

    it 'returns true when updated' do
      mock_update = MiniTest::Mock.new.expect(:call, 0)
      @subject.stub(:update!, mock_update) do
        assert @subject.wait_for_update!
      end
      mock_update.verify
    end
  end

  describe 'wait_for_shutdown!' do
    it 'returns false when throttled' do
      @subject.updated_at = Time.now.utc - 9
      refute @subject.wait_for_shutdown!
    end

    it 'returns false when a syncronized update is throttled' do
      @subject.updated_at = Time.now.utc - 15
      @subject2.set_attributes(updated_at: Time.now.utc - 9)

      refute @subject.wait_for_shutdown!
      assert_equal @subject.updated_at.to_i, @subject2.updated_at.to_i
    end

    it 'returns false when update returns dynos' do
      mock_update = MiniTest::Mock.new.expect(:call, 1)
      @subject.stub(:update!, mock_update) do
        refute @subject.wait_for_shutdown!
      end
      mock_update.verify
    end

    it 'returns true when update returns no dynos' do
      mock_update = MiniTest::Mock.new.expect(:call, 0)
      @subject.stub(:update!, mock_update) do
        assert @subject.wait_for_shutdown!
      end
      mock_update.verify
    end
  end

  describe 'update!' do
    it 'sets fetched dyno count and update timestamp' do
      assert_equal 0, @subject.dynos
      refute @subject.updated_at

      @subject.update!(1, 1)
      assert_equal 1, @subject.dynos
      assert @subject.updated_at
    end

    it 'returns current dynos while in statis with target threshold' do
      assert_equal 2, @subject.update!(2, 2)
    end

    it 'returns target dynos when upscaling' do
      mock_set_dynos = MiniTest::Mock.new.expect(:call, 2, [2])
      @subject.stub(:set_dyno_count!, mock_set_dynos) do
        assert_equal 2, @subject.update!(1, 2)
      end
      mock_set_dynos.verify
    end

    it 'starts quietdown when downscaling' do
      @subject.queue_system.stub(:quietdown!, true) do
        refute @subject.quieting?
        assert_equal 1, @subject.update!(1, 0)
        assert_equal 0, @subject.quieted_to
        refute @subject.fulfills_quietdown?
        assert @subject.quieting?
      end
    end

    it 'immedaitely downscales when nothing was quieted' do
      @subject.queue_system.stub(:quietdown!, false) do
        assert_equal 0, @subject.update!(1, 0)
        refute @subject.quieting?
      end
    end

    it 'downscales when quietdown is complete' do
      @subject.quiet_buffer = 10
      @subject.set_attributes(dynos: 1, quieted_to: 0, quieted_at: Time.now.utc - 11)

      assert @subject.quieting?
      assert_equal 0, @subject.update!(1, 0)
      refute @subject.quieting?
    end
  end

  describe 'fetch_dyno_count' do
    before do
      @subject = ::Sidekiq::HerokuAutoscale::Process.new(
        **@config.merge(client: TestClient.new)
      )
    end

    it 'fetches total dynos for a process type via PlatformAPI' do
      @subject.client
              .formation
              .stub(:list, JSON.parse(File.read("#{FIXTURES_PATH}/formation_list.json"))) do
        assert_equal 2, @subject.fetch_dyno_count
      end
    end

    it 'handles errors with the universal exception handler' do
      called = false
      ::Sidekiq::HerokuAutoscale.exception_handler = ->(_ex) { called = true }
      @subject.fetch_dyno_count
      assert called
    end
  end

  describe 'set_dyno_count!' do
    before do
      @subject = ::Sidekiq::HerokuAutoscale::Process.new(
        **@config.merge(client: TestClient.new)
      )
    end

    it 'sets total dynos for a process type via PlatformAPI, and syncs count' do
      @subject.client.formation.stub(:update, nil) do
        assert_equal 2, @subject.set_dyno_count!(2)

        assert_equal 0, @subject2.dynos
        @subject2.sync_attributes
        assert_equal 2, @subject2.dynos
      end
    end

    it 'handles errors with the universal exception handler' do
      called = false
      ::Sidekiq::HerokuAutoscale.exception_handler = ->(_ex) { called = true }
      @subject.set_dyno_count!(2)
      assert called
    end
  end
end
