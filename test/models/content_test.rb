require "test_helper"

class ContentTest < ActiveSupport::TestCase
  test "is valid with required attributes and a supported file" do
    assert build_content.valid?
  end

  test "requires descriptive attributes and a file" do
    content = Content.new(user: users(:one))

    refute content.valid?
    %i[title display_title description file].each do |attribute|
      assert content.errors[attribute].any?, "Expected an error on #{attribute}"
    end
  end

  test "title is unique without regard to case" do
    build_content(title: "Unique title", filename: "first.png", bytes: "first").save!
    duplicate = build_content(title: "UNIQUE TITLE", filename: "second.png", bytes: "second")

    refute duplicate.valid?
    assert_includes duplicate.errors[:title], "Title must be unique"
  end

  test "file checksum is unique" do
    build_content(title: "First checksum", filename: "first.png", bytes: "same bytes").save!
    duplicate = build_content(title: "Second checksum", filename: "second.png", bytes: "same bytes")

    refute duplicate.valid?
    assert_includes duplicate.errors[:file], "File already exists with title: First checksum"
  end

  test "file name is unique without regard to case" do
    build_content(title: "First filename", filename: "shared.png", bytes: "first bytes").save!
    duplicate = build_content(title: "Second filename", filename: "SHARED.PNG", bytes: "second bytes")

    refute duplicate.valid?
    assert_includes duplicate.errors[:file], "A file with the same filename already exists with title: First filename"
  end

  private

  def build_content(title: "Valid content", filename: "content.png", bytes: SecureRandom.hex(8))
    Content.new(
      user: users(:one),
      title: title,
      display_title: "Display #{title}",
      description: "Description for #{title}"
    ).tap do |content|
      content.file.attach(
        io: StringIO.new(bytes),
        filename: filename,
        content_type: "image/png"
      )
    end
  end
end
