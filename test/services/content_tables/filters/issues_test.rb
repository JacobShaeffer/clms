require "test_helper"
require "stringio"

class ContentTables::Filters::IssuesTest < ActiveSupport::TestCase
  setup do
    @metadata_types = MetadataType.in_display_order.to_a
    @records = []
  end

  test "normalizes only supported issue selections" do
    filter = build_filter
    %w[none warning danger any].each do |value|
      assert_equal({ "value" => value }, filter.normalize("value" => " #{value} "))
    end
    [ nil, "", "unknown", "warning OR 1=1", 1, [ "warning" ], { "nested" => "danger" } ].each do |value|
      assert_empty filter.normalize("value" => value)
    end
  end

  test "SQL selections agree with rendered flags at all missing-field boundaries" do
    complete = create_content
    one_missing = create_content
    one_missing.update_column(:description, nil)
    three_missing = create_content
    three_missing.update_columns(title: " ", display_title: "\t", description: "\n")
    four_missing = create_content
    four_missing.update_columns(title: nil, display_title: nil, description: "")
    four_missing.file.detach

    assert_equal [ complete.id ], matching("none")
    assert_equal [ one_missing.id, three_missing.id ].sort, matching("warning")
    assert_equal [ four_missing.id ], matching("danger")
    assert_equal [ one_missing.id, three_missing.id, four_missing.id ].sort, matching("any")
    assert_matches_rendered_flags
  end

  test "a missing rights type is dangerous even when it is the only missing field" do
    [ "Rights holder", " RIGHTS   STATEMENT " ].each do |name|
      type = MetadataType.create!(name:, user: users(:one))
      Metadatum.create!(name: "Provided", metadata_type: type, user: users(:one))
      @metadata_types << type
    end
    complete = create_content
    missing_holder = create_content
    missing_holder.metadata = Metadatum.where.not(metadata_type: @metadata_types[-2]).to_a
    missing_statement = create_content
    missing_statement.metadata = Metadatum.where.not(metadata_type: @metadata_types.last).to_a

    assert_equal [ complete.id ], matching("none")
    assert_empty matching("warning")
    assert_equal [ missing_holder.id, missing_statement.id ].sort, matching("danger")
    assert_matches_rendered_flags
  end

  test "counts metadata types rather than values and includes types without available values" do
    complete = create_content
    extra_value = Metadatum.create!(name: "Another value", metadata_type: @metadata_types.first, user: users(:one))
    incomplete = create_content
    incomplete.metadata = [ *@metadata_types.first.metadata, extra_value ].uniq

    assert_equal [ complete.id ], matching("none")
    assert_equal [ incomplete.id ], matching("warning")
    assert_matches_rendered_flags

    @metadata_types << MetadataType.create!(name: "Audience", user: users(:one))
    assert_empty matching("none")
    assert_equal [ complete.id, incomplete.id ].sort, matching("warning")
    assert_matches_rendered_flags
  end

  test "blank checks agree with Ruby for nulls ASCII and Unicode whitespace" do
    [ nil, "", " \t\r\n\v\f", "\u0085", "\u00a0", "\u1680", "\u2007", "\u2028", "\u202f", "\u3000", "\u200b", "present" ].each do |description|
      create_content.update_column(:description, description)
    end

    assert_matches_rendered_flags
  end

  test "publication year and additional notes are ignored and zero metadata types are supported" do
    create_content
    @metadata_types = []

    assert_equal @records.map(&:id), matching("none")
    assert_empty matching("any")
    assert_matches_rendered_flags
  end

  test "filter remains a scoped SQL relation and filters before pagination" do
    complete = create_content
    warning = create_content
    warning.update_column(:description, nil)
    danger = create_content
    danger.update_columns(title: nil, display_title: nil, description: nil)
    danger.file.detach
    filter = build_filter
    relation = filter.apply(relation: Content.where(id: @records.map(&:id)), values: { "value" => "any" }, column: nil)

    refute relation.loaded?
    assert_queries_count(1) { assert_equal 2, relation.count }
    assert_equal [ warning.id ], relation.order(:id).limit(1).ids
    assert_equal [ danger.id ], relation.order(:id).offset(1).limit(1).ids
    refute_includes relation.ids, complete.id
    assert_empty filter.apply(relation: Content.where(id: complete.id), values: { "value" => "any" }, column: nil)
  end

  private

  def create_content
    token = SecureRandom.hex(6)
    Content.new(title: "Issue filter #{token}", display_title: "Display #{token}", description: "Description", user: users(:one)).tap do |content|
      content.file.attach(io: StringIO.new(token), filename: "#{token}.pdf", content_type: "application/pdf")
      content.metadata = Metadatum.all.to_a
      content.save!
      @records << content
    end
  end

  def build_filter
    ContentTables::Filters::Issues.new(metadata_types: @metadata_types)
  end

  def matching(value)
    build_filter.apply(relation: Content.where(id: @records.map(&:id)), values: { "value" => value }, column: nil).ids.sort
  end

  def assert_matches_rendered_flags
    grouped = @records.group_by do |content|
      ContentTables::Issues.new(content: content.reload, metadata_types: @metadata_types).severity
    end
    { "none" => nil, "warning" => :warning, "danger" => :danger }.each do |value, severity|
      assert_equal Array(grouped[severity]).map(&:id).sort, matching(value), "SQL disagrees with flags for #{value}"
    end
    assert_equal @records.map(&:id).sort - Array(grouped[nil]).map(&:id).sort, matching("any")
  end
end
