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
end
