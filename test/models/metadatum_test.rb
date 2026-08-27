require "test_helper"

class MetadatumTest < ActiveSupport::TestCase
  test "requires a name" do
    metadatum = Metadatum.new(
      user: users(:one),
      metadata_type: metadata_types(:one),
      name: ""
    )

    refute metadatum.valid?
    assert_includes metadatum.errors[:name], "can't be blank"
  end

  test "name is unique within a metadata type without regard to case" do
    existing = Metadatum.find_by!(metadata_type: metadata_types(:one))
    duplicate = Metadatum.new(
      user: users(:one),
      metadata_type: existing.metadata_type,
      name: existing.name.swapcase
    )

    refute duplicate.valid?
    assert_includes duplicate.errors[:name], "Name must be unique within the same metadata type"
  end

  test "the same name is valid in another metadata type" do
    existing = Metadatum.find_by!(metadata_type: metadata_types(:one))
    metadatum = Metadatum.new(
      user: users(:one),
      metadata_type: metadata_types(:two),
      name: "Scoped value"
    )

    existing.update!(name: "Scoped value")

    assert metadatum.valid?
  end

  test "review scopes select the requested state" do
    assert_equal Metadatum.where(under_review: true).ids.sort, Metadatum.by_under_review(true).ids.sort
    assert_equal Metadatum.where(under_review: false).ids.sort, Metadatum.by_under_review(false).ids.sort
  end

  test "replace_with moves content references, removes overlaps, and destroys the original" do
    original = Metadatum.find_by!(metadata_type: metadata_types(:one))
    replacement = original.metadata_type.metadata.create!(
      user: users(:two),
      name: "Replacement",
      under_review: true
    )
    overlapping_content = contents(:two)
    ContentMetadatum.create!(content: overlapping_content, metadata: original)
    ContentMetadatum.create!(content: overlapping_content, metadata: replacement)
    replacement_attributes = replacement.attributes.slice("name", "user_id", "under_review")

    original.replace_with!(replacement)

    refute Metadatum.exists?(original.id)
    assert_equal [ contents(:one).id, overlapping_content.id ].sort,
      ContentMetadatum.where(metadata: replacement).pluck(:content_id).sort
    assert_equal 1, ContentMetadatum.where(metadata: replacement, content: overlapping_content).count
    assert_equal replacement_attributes, replacement.reload.attributes.slice("name", "user_id", "under_review")
  end

  test "replace_with requires a different persisted value from the same type" do
    original = Metadatum.find_by!(metadata_type: metadata_types(:one))

    assert_raises(ArgumentError) { original.replace_with!(original) }
    assert_raises(ArgumentError) do
      original.replace_with!(Metadatum.find_by!(metadata_type: metadata_types(:two)))
    end
    assert_raises(ArgumentError) { original.replace_with!(Metadatum.new) }

    assert Metadatum.exists?(original.id)
  end

  test "replace_with rolls back moved references when deletion fails" do
    original = Metadatum.find_by!(metadata_type: metadata_types(:one))
    replacement = original.metadata_type.metadata.create!(user: users(:one), name: "Replacement")
    original_content_id = original.contents_metadata.pick(:content_id)
    original.define_singleton_method(:destroy!) { raise "deletion failed" }

    assert_raises(RuntimeError) { original.replace_with!(replacement) }

    assert ContentMetadatum.exists?(metadata: original, content_id: original_content_id)
    refute ContentMetadatum.exists?(metadata: replacement, content_id: original_content_id)
    assert Metadatum.exists?(original.id)
  end
end
