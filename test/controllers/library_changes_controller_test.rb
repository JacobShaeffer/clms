require "test_helper"

class LibraryChangesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @author = users(:one)
    @author.update!(role: :intern_plus)
    @admin = users(:two)
    @admin.update!(role: :admin)
    @library = Library.create!(name: "Change Controller Library", user: @author)
    @folder = @library.current_version.library_folders.create!(
      library: @library,
      name: "Folder",
      user: @author,
      logo: library_assets(:one)
    )
  end

  test "the author undoes a change" do
    change = add_content_change
    sign_in @author

    patch undo_library_change_url(@library, change), params: { folder_id: @folder.id }

    assert_redirected_to library_url(@library, folder_id: @folder.id)
    assert_predicate change.reload, :undone?
    assert_equal @author, change.undone_by
    refute @folder.library_folder_contents.exists?(content: contents(:one))
  end

  test "approval route is absent" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path(
        "/libraries/#{@library.id}/changes/1/approve",
        method: :patch
      )
    end
  end

  test "a blocked undo redirects with an explanation" do
    first = add_content_change
    LibraryFolderOperations::Remove.call(
      library: @library,
      source_folder_id: @folder.id,
      folder_ids: [],
      content_ids: [ contents(:one).id ],
      user: @author
    )
    second = @library.current_version.library_changes.remove_content.last
    sign_in @author

    patch undo_library_change_url(@library, first)

    assert_redirected_to library_url(@library)
    assert_match(/Undo #{Regexp.escape(second.display_label)} before/, flash[:alert])
    refute_predicate first.reload, :undone?
  end

  test "undoing a new folder while viewing it returns to its parent" do
    child = @library.current_version.library_folders.create!(
      library: @library,
      name: "New Child",
      parent_folder: @folder,
      user: @author
    )
    change = LibraryChanges::Recorder.call(
      library_version: @library.current_version,
      user: @author,
      action_type: :add_folder,
      details: {
        folder_id: child.id,
        parent_folder_id: @folder.id,
        logo_id: nil
      },
      targets: [ {
        target_kind: :folder,
        target_id: child.id,
        folder_id: child.id,
        resource_key: LibraryChanges::Recorder.folder_key(child),
        effect: :new,
        direct: true,
        label: child.name
      } ]
    )
    sign_in @author

    patch undo_library_change_url(@library, change), params: { folder_id: child.id }

    assert_redirected_to library_url(@library, folder_id: @folder.id)
    refute LibraryFolder.exists?(child.id)
  end

  private

  def add_content_change
    LibraryFolderOperations::PlaceContents.call(
      library: @library,
      folder_id: @folder.id,
      content_ids: [ contents(:one).id ],
      user: @author
    )
    @library.current_version.library_changes.add_content.last
  end
end
