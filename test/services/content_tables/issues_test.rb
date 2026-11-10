require "test_helper"
require "stringio"

class ContentTables::IssuesTest < ActiveSupport::TestCase
  setup do
    @metadata_types = MetadataType.in_display_order.to_a
    @content = Content.new(
      title: "Complete content",
      display_title: "Complete display title",
      description: "Complete description",
      user: users(:one)
    )
    @content.file.attach(io: StringIO.new("content"), filename: "issues.pdf", content_type: "application/pdf")
    @content.metadata = Metadatum.all.to_a
  end

  test "complete content has no issues even without a publication year or additional notes" do
    assert_nil @content.year_of_publication
    assert_nil @content.additional_notes
    assert_empty issues.missing_fields
    assert_nil issues.severity
  end

  test "checks every intrinsic field and the attached file" do
    @content.assign_attributes(title: " ", display_title: nil, description: "")
    @content.file.detach

    assert_equal [ "Title", "Display Title", "Description", "File" ], issues.missing_fields
    assert_equal :danger, issues.severity
  end

  test "one to three missing fields warn and four or more are dangerous" do
    [ :title, :display_title, :description ].each_with_index do |attribute, index|
      @content.public_send("#{attribute}=", nil)

      assert_equal index + 1, issues.missing_fields.size
      assert_equal :warning, issues.severity
    end

    @content.file.detach

    assert_equal 4, issues.missing_fields.size
    assert_equal :danger, issues.severity
  end

  test "every metadata type counts once including types without any available values" do
    @content.metadata = []
    extra_type = MetadataType.create!(name: "Audience", user: users(:one))
    @metadata_types << extra_type

    assert_equal @metadata_types.map(&:name), issues.missing_fields
    assert_equal :warning, issues.severity

    @metadata_types << MetadataType.create!(name: "Region", user: users(:one))

    assert_equal 4, issues.missing_fields.size
    assert_equal :danger, issues.severity
  end

  test "multiple values of a type do not cover a missing different type" do
    extra_value = Metadatum.create!(name: "Another value", metadata_type: @metadata_types.first, user: users(:one))
    @content.metadata = [ *@metadata_types.first.metadata, extra_value ].uniq

    assert_equal [ @metadata_types.second.name ], issues.missing_fields
    assert_equal :warning, issues.severity
  end

  test "a missing rights holder or rights statement is immediately dangerous regardless of capitalization" do
    [ "Rights holder", " RIGHTS   STATEMENT " ].each do |name|
      type = MetadataType.create!(name:, user: users(:one))
      report = ContentTables::Issues.new(content: @content, metadata_types: @metadata_types + [ type ])

      assert_equal [ name ], report.missing_fields
      assert_equal :danger, report.severity

      @content.metadata << Metadatum.new(name: "Provided", metadata_type: type, user: users(:one))
      report = ContentTables::Issues.new(content: @content, metadata_types: @metadata_types + [ type ])

      assert_empty report.missing_fields
      assert_nil report.severity
    end
  end

  private

  def issues
    ContentTables::Issues.new(content: @content, metadata_types: @metadata_types)
  end
end
