require "test_helper"

class ContentDraftTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "captures incomplete content without publishing it" do
    attributes = { "title" => "Unfinished", "display_title" => "", "metadatum_ids" => [] }
    content = users(:one).contents.build(attributes)
    draft = users(:one).content_drafts.build

    assert_no_difference("Content.count") do
      draft.capture!(content:, attributes:, submission_errors: [ "Description can't be blank" ])
    end

    assert_equal attributes, draft.reload.form_data
    assert_equal [ "Description can't be blank" ], draft.submission_errors
    refute draft.build_content.persisted?
  end

  test "restores fields and surviving metadata" do
    surviving_metadatum = Metadatum.find(ActiveRecord::FixtureSet.identify(:one))
    removed_metadatum = Metadatum.find(ActiveRecord::FixtureSet.identify(:two))
    removed_id = removed_metadatum.id
    draft = users(:one).content_drafts.create!(form_data: {
      title: "Restored", description: "Partial description", year_of_publication: "2026",
      metadatum_ids: [ surviving_metadatum.id.to_s, removed_id.to_s ]
    })
    removed_metadatum.destroy!

    content = draft.build_content

    assert_equal "Restored", content.title
    assert_equal "Partial description", content.description
    assert_equal 2026, content.year_of_publication
    assert_equal [ surviving_metadatum.id ], content.metadatum_ids
    assert_equal users(:one), content.user
  end

  test "retains an unvalidated file and clears errors on a manual snapshot" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("unfinished file"), filename: "unfinished.txt", content_type: "text/plain"
    )
    content = users(:one).contents.build
    content.file = blob
    draft = users(:one).content_drafts.create!(submission_errors: [ "File must be a supported file type" ])

    draft.capture!(content:, attributes: { "title" => "", "file" => blob, "metadatum_ids" => [] })

    assert_empty draft.reload.submission_errors
    refute draft.form_data.key?("file")
    assert_equal "unfinished file", draft.file.download
    assert_equal blob, draft.build_content.file.blob
  end

  test "display name prefers title then filename then saved date" do
    draft = users(:one).content_drafts.create!(form_data: { title: "Named draft" })
    draft.file.attach(io: StringIO.new("draft bytes"), filename: "draft.pdf", content_type: "application/pdf")
    assert_equal "Named draft", draft.display_name

    draft.update!(form_data: { title: " " })
    assert_equal "draft.pdf", draft.display_name

    empty_draft = users(:one).content_drafts.create!
    assert_equal I18n.l(empty_draft.updated_at, format: :long), empty_draft.display_name
  end

  test "saving unchanged data updates the saved time and list order" do
    draft = users(:one).content_drafts.create!(form_data: { title: "Saved again" })
    newer_draft = users(:one).content_drafts.create!(form_data: { title: "Newer draft" })
    saved_at = draft.updated_at

    travel 1.minute do
      draft.capture!(content: draft.build_content, attributes: draft.form_data)
    end

    assert_operator draft.reload.updated_at, :>, saved_at
    assert_equal [ draft.id, newer_draft.id ], users(:one).content_drafts.recent_first.ids
  end

  test "deletion purges unreferenced files but preserves shared files" do
    draft = users(:one).content_drafts.create!
    draft.file.attach(io: StringIO.new("discarded bytes"), filename: "discarded.pdf", content_type: "application/pdf")
    discarded_blob = draft.file.blob
    perform_enqueued_jobs { draft.destroy! }
    refute ActiveStorage::Blob.exists?(discarded_blob.id)

    shared_draft = users(:one).content_drafts.create!
    shared_draft.file.attach(io: StringIO.new("shared bytes"), filename: "shared.pdf", content_type: "application/pdf")
    shared_blob = shared_draft.file.blob
    content = users(:one).contents.create!(
      title: "Shared published document", display_title: "Shared display", description: "Shared description", file: shared_blob
    )
    perform_enqueued_jobs { shared_draft.destroy! }
    assert ActiveStorage::Blob.exists?(shared_blob.id)
    assert_equal "shared bytes", content.file.download
  end
end
