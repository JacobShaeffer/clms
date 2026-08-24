require "test_helper"

class PurgeUnattachedBlobsJobTest < ActiveJob::TestCase
  test "queues old unattached blobs for purging" do
    old_blob = create_blob("old.png")
    new_blob = create_blob("new.png")
    old_blob.update_column(:created_at, 2.days.ago)

    assert_enqueued_with(job: ActiveStorage::PurgeJob, args: [ old_blob ]) do
      PurgeUnattachedBlobsJob.perform_now
    end

    assert ActiveStorage::Blob.exists?(new_blob.id)
  end

  test "does not purge attached blobs" do
    content = contents(:one)
    blob = create_blob("attached.png")
    ActiveStorage::Attachment.create!(name: "file", record: content, blob:)
    blob.update_column(:created_at, 2.days.ago)

    assert_no_enqueued_jobs only: ActiveStorage::PurgeJob do
      PurgeUnattachedBlobsJob.perform_now
    end
  end

  private

  def create_blob(filename)
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(filename),
      filename:,
      content_type: "image/png"
    )
  end
end
