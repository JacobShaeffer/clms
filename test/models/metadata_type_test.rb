require "test_helper"

class MetadataTypeTest < ActiveSupport::TestCase
  test "defaults access level to organization" do
    metadata_type = MetadataType.new

    assert_equal User.roles.fetch("organization"), metadata_type.access_level
  end

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

  test "requires access level to be a role value" do
    metadata_type = MetadataType.new(user: users(:one), name: "Invalid access", access_level: 42)

    refute metadata_type.valid?
    assert_includes metadata_type.errors[:access_level], "is not included in the list"
  end

  test "requires a numerical order" do
    metadata_type = MetadataType.new(user: users(:one), name: "Invalid order", order: "first")

    refute metadata_type.valid?
    assert_includes metadata_type.errors[:order], "is not a number"
  end

  test "display order uses order then name and id" do
    first = metadata_types(:one)
    second = metadata_types(:two)
    first.update_columns(name: "Zulu", order: 2)
    second.update_columns(name: "Alpha", order: 1)

    assert_equal [ second, first ], MetadataType.in_display_order.to_a
  end
end
