require "test_helper"

class MetadataTypeTest < ActiveSupport::TestCase
  test "requires a name" do
    metadata_type = MetadataType.new(user: users(:one), name: "")

    refute metadata_type.valid?
    assert_includes metadata_type.errors[:name], "can't be blank"
  end

  test "name is unique without regard to case" do
    metadata_type = MetadataType.new(user: users(:one), name: metadata_types(:one).name.swapcase)

    refute metadata_type.valid?
    assert_includes metadata_type.errors[:name], "Name must be unique"
  end

  test "destroying a metadata type destroys its values" do
    metadata_type = metadata_types(:one)
    value_ids = metadata_type.metadata.ids

    metadata_type.destroy!

    assert_empty Metadatum.where(id: value_ids)
  end
end
