require "test_helper"

class Contents::SorterTest < ActiveSupport::TestCase
  setup do
    @first = contents(:one)
    @second = contents(:two)
  end

  test "uses newest content first by default" do
    @first.update_column(:created_at, 2.days.ago)
    @second.update_column(:created_at, 1.day.ago)

    assert_equal [ @second.id, @first.id ], sort(column: nil, direction: nil).ids
  end

  test "sorts text without regard to case" do
    @first.update_column(:title, "zulu")
    @second.update_column(:title, "Alpha")

    assert_equal [ @second.id, @first.id ], sort(column: content_column("title"), direction: "asc").ids
    assert_equal [ @first.id, @second.id ], sort(column: content_column("title"), direction: "desc").ids
  end

  test "keeps null values last in both directions" do
    @first.update_column(:year_of_publication, nil)
    @second.update_column(:year_of_publication, 2026)

    assert_equal [ @second.id, @first.id ], sort(column: content_column("year_of_publication"), direction: "asc").ids
    assert_equal [ @second.id, @first.id ], sort(column: content_column("year_of_publication"), direction: "desc").ids
  end

  test "sorts added by using email when the name is blank" do
    users(:one).update_column(:name, "Zulu Author")
    users(:two).update_columns(name: " ", email: "alpha@example.com")

    assert_equal [ @second.id, @first.id ], sort(column: content_column("added_by"), direction: "asc").ids
  end

  test "sorts metadata by the lowest matching value and keeps untagged content last" do
    metadata_type = metadata_types(:one)
    Metadatum.find_by!(metadata_type: metadata_type).update!(name: "Zulu")
    second_value = Metadatum.create!(
      metadata_type: metadata_type,
      user: users(:one),
      name: "Alpha",
      under_review: false
    )
    @second.metadata << second_value
    untagged = Content.new(
      user: users(:one),
      title: "Untagged",
      display_title: "Untagged",
      description: "No metadata"
    )
    untagged.file.attach(
      io: StringIO.new("untagged file"),
      filename: "untagged.png",
      content_type: "image/png"
    )
    untagged.save!

    column = { type: :metadata, metadata_type_id: metadata_type.id }

    assert_equal [ @second.id, @first.id, untagged.id ], sort(column: column, direction: "asc").ids
    assert_equal [ @first.id, @second.id, untagged.id ], sort(column: column, direction: "desc").ids
  end

  test "falls back to default order for invalid input" do
    @first.update_column(:created_at, 2.days.ago)
    @second.update_column(:created_at, 1.day.ago)

    invalid_column = { type: :content, key: "password" }

    assert_equal [ @second.id, @first.id ], sort(column: invalid_column, direction: "asc").ids
    assert_equal [ @second.id, @first.id ], sort(column: content_column("title"), direction: "sideways").ids
  end

  private

  def sort(column:, direction:)
    Contents::Sorter.call(relation: Content.all, column: column, direction: direction)
  end

  def content_column(key)
    { type: :content, key: key }
  end
end
