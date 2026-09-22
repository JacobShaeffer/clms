require "test_helper"

class LibraryChangePolicyTest < ActiveSupport::TestCase
  setup do
    @author = users(:one)
    @author.update!(role: :intern_plus)
    @admin = users(:two)
    @admin.update!(role: :admin)
    library = Library.create!(name: "Policy Library", user: @author)
    @change = library.current_version.library_changes.create!(
      user: @author,
      action_type: :add_folder,
      batch_key: SecureRandom.uuid,
      details: { "folder_id" => 1 }
    )
  end

  test "admins can approve including their own changes" do
    assert LibraryChangePolicy.new(@admin, @change).approve?
    @change.update_column(:user_id, @admin.id)
    assert LibraryChangePolicy.new(@admin, @change.reload).approve?
    refute LibraryChangePolicy.new(@author, @change).approve?
  end

  test "authors and admins can undo" do
    assert LibraryChangePolicy.new(@author, @change).undo?
    assert LibraryChangePolicy.new(@admin, @change).undo?

    other = User.create!(
      name: "Other",
      email: "other-policy@example.com",
      password: "password",
      role: :intern_plus
    )
    refute LibraryChangePolicy.new(other, @change).undo?

    @author.update!(role: :intern)
    refute LibraryChangePolicy.new(@author, @change).undo?
  end
end
