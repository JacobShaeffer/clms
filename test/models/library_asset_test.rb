require "test_helper"

class LibraryAssetTest < ActiveSupport::TestCase
  test "is valid with a PNG image and ZIP design files" do
    library_asset = build_library_asset

    assert library_asset.valid?
  end

  test "only requires an image" do
    library_asset = LibraryAsset.new(user: users(:one))

    refute library_asset.valid?
    assert_includes library_asset.errors[:image], "can't be blank"
    assert_empty library_asset.errors[:name]
    assert_empty library_asset.errors[:design_files]
    assert_empty library_asset.errors[:language]
    assert_empty library_asset.errors[:asset_type]
  end

  test "saves multiple unnamed assets with only an image" do
    2.times do
      library_asset = build_image_only_asset
      assert library_asset.save, library_asset.errors.full_messages.to_sentence
      assert_equal "preview.png", library_asset.display_name
      refute library_asset.design_files.attached?
    end
  end

  test "validates optional asset types" do
    library_asset = build_image_only_asset
    [ nil, "", "Banner", "Subject", "Module" ].each do |asset_type|
      library_asset.asset_type = asset_type
      assert library_asset.valid?, library_asset.errors.full_messages.to_sentence
    end

    library_asset.asset_type = "Unsupported"
    refute library_asset.valid?
    assert_includes library_asset.errors[:asset_type], "is not included in the list"
  end

  test "requires the image to be a PNG" do
    library_asset = build_library_asset
    library_asset.image.attach(
      io: StringIO.new("JPEG contents"),
      filename: "preview.jpg",
      content_type: "image/jpeg"
    )

    refute library_asset.valid?
    assert_includes library_asset.errors[:image], "must be a supported file type"
  end

  test "requires design files to be a ZIP" do
    library_asset = build_library_asset
    library_asset.design_files.attach(
      io: StringIO.new("PDF contents"),
      filename: "design.pdf",
      content_type: "application/pdf"
    )

    refute library_asset.valid?
    assert_includes library_asset.errors[:design_files], "must be a supported file type"
  end

  private

  def build_image_only_asset
    LibraryAsset.new(user: users(:one)).tap do |library_asset|
      library_asset.image.attach(
        io: StringIO.new("PNG contents"), filename: "preview.png", content_type: "image/png"
      )
    end
  end

  def build_library_asset
    LibraryAsset.new(
      user: users(:one),
      name: "Library asset #{SecureRandom.hex(4)}",
      language: "English"
    ).tap do |library_asset|
      library_asset.image.attach(
        io: StringIO.new("PNG contents"),
        filename: "preview.png",
        content_type: "image/png"
      )
      library_asset.design_files.attach(
        io: StringIO.new("ZIP contents"),
        filename: "design_files.zip",
        content_type: "application/zip"
      )
    end
  end
end
