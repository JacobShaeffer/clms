require "test_helper"
require_relative "../../support/library_build_helpers"

class LibraryBuilds::RequestTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include LibraryBuildHelpers

  setup { setup_build_library }
  teardown { teardown_build_library }

  test "any locked version can be requested without rotating the library" do
    current = LibraryVersions::Create.call(library: @library, version_number: "3.0", user: @user)
    assert_no_difference("LibraryVersion.count") do
      build = request_export
      assert_equal @version.id, build.library_version_id
      assert_equal 1, build.generation
      assert_predicate build, :queued?
    end
    assert_equal current.id, @library.reload.current_version_id
  end

  test "editable versions are rejected without creating a build" do
    assert_no_difference("LibraryBuild.count") do
      error = assert_raises(LibraryBuilds::Error) { request_export(@library.current_version) }
      assert_equal "version_not_locked", error.code
    end
  end

  test "queued and exporting requests coalesce and completed requests increment generation" do
    build = request_export
    assert_no_difference("LibraryBuild.count") do
      assert_equal build.id, request_export.id
      build.update!(status: "exporting")
      assert_equal 1, request_export.generation
      build.update!(status: "ready", published_generation: 1, published_at: Time.current)
      second = request_export
      assert_equal build.id, second.id
      assert_equal 2, second.generation
      assert_equal 1, second.published_generation
    end
  end

  test "request and rotation roll back together and no job is enqueued" do
    assert_no_enqueued_jobs only: LibraryExportJob do
      assert_no_difference([ "LibraryVersion.count", "LibraryBuild.count" ]) do
        Library.transaction(requires_new: true) do
          LibraryVersions::CreateWithBuild.call(library: @library, version_number: "3.0",
            expected_current_version_id: @library.current_version_id, user: @user)
          raise ActiveRecord::Rollback
        end
      end
    end
    assert_equal "2.0", @library.reload.current_version.version_number
  end

  test "stale sources and invalid successor numbers create nothing" do
    assert_no_difference([ "LibraryVersion.count", "LibraryBuild.count" ]) do
      assert_raises(LibraryBuilds::Error) do
        LibraryVersions::CreateWithBuild.call(library: @library, version_number: "3.0",
          expected_current_version_id: @version.id, user: @user)
      end
      assert_raises(ActiveRecord::RecordInvalid) do
        LibraryVersions::CreateWithBuild.call(library: @library, version_number: "1.0",
          expected_current_version_id: @library.current_version_id, user: @user)
      end
    end
    assert_predicate @library.reload.current_version, :editable?
  end

  test "confirmed rotation requests the previous version and does not enqueue before commit" do
    clear_enqueued_jobs
    result = nil
    assert_enqueued_jobs 1, only: LibraryExportJob do
      Library.transaction(requires_new: true) do
        assert_no_enqueued_jobs only: LibraryExportJob do
          previous = @library.current_version
          result = LibraryVersions::CreateWithBuild.call(library: @library, version_number: "3.0",
            expected_current_version_id: previous.id, user: @user)
          assert_equal previous.id, result.locked_version.id
          assert_equal previous.id, result.build.library_version_id
          assert_equal result.new_version.id, @library.reload.current_version_id
          assert_predicate result.locked_version, :locked?
        end
      end
    end
    assert_enqueued_with(job: LibraryExportJob, args: [ result.build.id, 1 ])
  end
end
