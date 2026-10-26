require "test_helper"
require_relative "../support/library_build_helpers"

class LibraryExportJobTest < ActiveJob::TestCase
  include LibraryBuildHelpers

  setup { setup_build_library }
  teardown { teardown_build_library }

  test "executes requested generation and ignores already completed deliveries" do
    build = request_export
    LibraryExportJob.perform_now(build.id, 1)
    assert_predicate build.reload, :ready?
    assert_equal 1, build.published_generation
    LibraryExportJob.perform_now(build.id, 1)
    assert_equal 1, build.reload.published_generation
  end

  test "working attachments protect selected blobs only for the attempt" do
    build = request_export
    source = LibraryBuilds::Source.call(build:)
    blob = @content.file.blob
    @content.file.detach
    blob.update_column(:created_at, 2.days.ago)
    assert_no_enqueued_jobs only: ActiveStorage::PurgeJob do
      PurgeUnattachedBlobsJob.perform_now
    end
    assert source.files.any? { |file| file[:blob].id == blob.id }
    assert ActiveStorage::Blob.exists?(blob.id)
    build.working_files.detach
    assert_enqueued_with(job: ActiveStorage::PurgeJob, args: [ blob ]) do
      PurgeUnattachedBlobsJob.perform_now
    end
  end
end
