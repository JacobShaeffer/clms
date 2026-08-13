require "test_helper"

class ContentTablePreferenceConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "simultaneous first saves create one preference" do
    user = User.create!(
      name: "Concurrent Preference User",
      email: "concurrent-preference-#{SecureRandom.hex(6)}@example.com",
      password: "password"
    )
    table_key = "test.concurrent.#{SecureRandom.hex(6)}"
    ready = Queue.new
    start = Queue.new
    states = 3.times.map { |index| { "q" => "query-#{index}" } }
    threads = states.map do |state|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          ContentTablePreference.save_state!(
            user: User.find(user.id),
            table_key:,
            state:
          )
        end
      end
    end

    threads.size.times { ready.pop }
    threads.size.times { start << true }
    saved_preferences = threads.map(&:value)

    assert_equal 1, ContentTablePreference.where(user:, table_key:).count
    assert_equal 1, saved_preferences.map(&:id).uniq.size
    assert_includes states, ContentTablePreference.find_by!(user:, table_key:).state
  ensure
    threads&.each { |thread| thread.join if thread.alive? }
    user&.destroy!
  end
end
