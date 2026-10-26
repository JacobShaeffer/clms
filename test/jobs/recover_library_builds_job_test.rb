require "test_helper"
require_relative "../support/library_build_helpers"

class RecoverLibraryBuildsJobTest < ActiveJob::TestCase
  include LibraryBuildHelpers

  setup { setup_build_library }
  teardown { teardown_build_library }

  test "recovers abandoned attempts and removes incomplete and replaced files" do
    build = request_export
    build.update!(status: "exporting")
    LibraryBuilds::Source.call(build:)
    build.update_column(:updated_at, 20.minutes.ago)
    storage = LibraryBuilds::Storage.new(build)
    FileUtils.mkdir_p(storage.root.join("stage-abandoned"))
    clear_enqueued_jobs
    assert_enqueued_with(job: LibraryExportJob, args: [ build.id, 1 ]) do
      RecoverLibraryBuildsJob.perform_now
    end
    assert_empty build.reload.working_files
    refute storage.root.join("stage-abandoned").exist?
    LibraryExportJob.perform_now(build.id, 1)
    assert_predicate build.reload, :ready?
    FileUtils.mkdir_p(storage.generation_path(99))
    RecoverLibraryBuildsJob.perform_now
    refute storage.generation_path(99).exist?
    assert storage.archive_path.exist?
  end

  test "does not clean up an actively locked export or requeue recent attempts" do
    build = request_export
    LibraryBuilds::Source.call(build:)
    clear_enqueued_jobs
    storage = LibraryBuilds::Storage.new(build)
    storage.with_lock do
      assert_no_enqueued_jobs only: LibraryExportJob do
        RecoverLibraryBuildsJob.perform_now
      end
      assert_predicate build.reload.working_files, :attached?
    end
  end
end
