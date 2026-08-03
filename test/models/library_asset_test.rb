require "test_helper"

class LibraryAssetTest < ActiveSupport::TestCase
  test "is valid with a PNG image and ZIP design files" do
    library_asset = build_library_asset

    assert library_asset.valid?
  end

  test "requires an image and design files" do
    library_asset = LibraryAsset.new(
      user: users(:one),
      name: "Asset without files",
      language: "English"
    )

    refute library_asset.valid?
    assert_includes library_asset.errors[:image], "can't be blank"
    assert_includes library_asset.errors[:design_files], "can't be blank"
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
