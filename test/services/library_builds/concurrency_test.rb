require "test_helper"

class LibraryBuilds::ConcurrencyTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  self.use_transactional_tests = false

  setup do
    @user = User.create!(name: "Build concurrency", email: "build-#{SecureRandom.hex(6)}@example.com",
      password: "password", role: :admin)
    @library = Library.create!(name: "Concurrent Build", user: @user)
    @version = @library.current_version
    LibraryVersions::Create.call(library: @library, version_number: "2.0", user: @user)
    clear_enqueued_jobs
  end

  teardown do
    LibraryBuild.where(library_version_id: @library.library_versions.select(:id)).destroy_all
    @library.update_columns(current_version_id: nil)
    LibraryVersion.where(library_id: @library.id).delete_all
    @library.reload.destroy!
    @user.destroy!
  end

  test "simultaneous requests create one record generation and job after a real commit" do
    ready, start = Queue.new, Queue.new
    threads = 3.times.map do
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          ready << true
          start.pop
          LibraryBuilds::Request.call(library_version: LibraryVersion.find(@version.id), user: User.find(@user.id))
        end
      end
    end
    threads.length.times { ready.pop }
    threads.length.times { start << true }
    builds = threads.map(&:value)
    assert_equal 1, builds.map(&:id).uniq.length
    assert_equal [ 1 ], builds.map(&:generation).uniq
    assert_equal 1, LibraryBuild.where(library_version: @version).count
    assert_enqueued_jobs 1, only: LibraryExportJob
    assert_enqueued_with(job: LibraryExportJob, args: [ builds.first.id, 1 ])
    assert_equal "2.0", @library.reload.current_version.version_number
  ensure
    threads&.each { |thread| thread.join if thread.alive? }
  end

  test "queue failure leaves a durable request for recovery" do
    original_adapter = LibraryExportJob.queue_adapter
    failing_adapter = Object.new
    def failing_adapter.enqueue(_job)
      raise "queue unavailable"
    end
    def failing_adapter.enqueue_at(job, _timestamp)
      enqueue(job)
    end
    LibraryExportJob.queue_adapter = failing_adapter
    build = LibraryBuilds::Request.call(library_version: @version, user: @user)
    assert_predicate build.reload, :queued?
    assert_equal @version.id, build.library_version_id
    assert_no_enqueued_jobs only: LibraryExportJob
    assert_equal "2.0", @library.reload.current_version.version_number
  ensure
    LibraryExportJob.queue_adapter = original_adapter if original_adapter
  end
end
