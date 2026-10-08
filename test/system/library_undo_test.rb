require "application_system_test_case"

class LibraryUndoTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @user.update!(role: :intern_plus)
    sign_in @user
    @library = Library.create!(name: "Page Undo Library", user: @user)
    @root = @library.current_version.library_folders.create!(name: "Root", user: @user, logo: library_assets(:one))
  end

  test "tracks only the last three actions and clears redo after a new edit" do
    visit library_path(@library, folder_id: @root.id)
    assert_button "Undo", disabled: true
    assert_button "Redo", disabled: true
    %w[First Second Third Fourth].each { |name| create_child(name) }

    %w[Fourth Third Second].each do |name|
      click_control("Undo")
      assert_no_link name
    end
    assert_link "First"
    assert_button "Undo", disabled: true
    click_control("Redo")
    assert_link "Second"
    click_control("Redo")
    assert_link "Third"
    create_child("New branch")
    assert_button "Redo", disabled: true
    assert_no_link "Fourth"
  end

  test "keeps state through folders tabs modals and refreshes but clears on leaving and reloading" do
    visit library_path(@library, folder_id: @root.id)
    create_child("Child")
    within browser do
      click_link "Child"
      assert_selector ".breadcrumb-item.active", text: "Child"
    end
    page.go_back
    assert_selector ".breadcrumb-item.active", text: "Root"
    assert_button "Undo", disabled: false
    within browser do
      click_link "Child"
    end
    click_link "Current Library"
    assert_selector ".nav-link.active", text: "Current Library"
    click_link "New Folder"
    within "#modal" do
      click_button "Cancel"
    end
    assert_no_selector "#modal .modal"
    assert_button "Undo", disabled: false
    click_control("Undo")
    assert_no_link "Child"
    assert_selector ".breadcrumb-item.active", text: "Root"
    assert_selector ".nav-link.active", text: "Current Library"
    click_control("Redo")
    assert_link "Child"

    within browser do
      find("input[aria-label='Select folder Child']").check
      click_button "Remove"
    end
    within "#modal" do
      click_button "Remove"
    end
    assert_no_link "Child"
    assert_button "Undo", disabled: false
    click_control("Undo")
    assert_link "Child"
    page.refresh
    assert_button "Undo", disabled: true
    assert_button "Redo", disabled: true

    create_child("Another")
    click_link "Back to libraries"
    assert_current_path libraries_path
    page.go_back
    assert_link "Another"
    assert_button "Undo", disabled: true
    assert_button "Redo", disabled: true
  end

  test "stops at another user's dependent edit without skipping older edits" do
    visit library_path(@library, folder_id: @root.id)
    create_child("Earlier")
    create_child("Blocked")
    folder = @library.current_version.library_folders.find_by!(name: "Blocked")
    other = users(:two)
    other.update!(role: :admin)
    LibraryFolderOperations::PlaceContents.call(library: @library, folder_id: folder.id,
      content_ids: [ contents(:one).id ], user: other)

    click_control("Undo")
    assert_text "blocked by later dependent edits"
    assert_button "Undo", disabled: true
    assert_link "Earlier"
    assert_link "Blocked"
    create_child("Fresh")
    click_control("Undo")
    assert_no_link "Fresh"
    assert_button "Undo", disabled: true
    assert_link "Earlier"
  end

  test "a multi-item removal counts as one action through the Turbo refresh" do
    %w[First Second].each do |name|
      @root.child_folders.create!(library: @library, library_version: @library.current_version, user: @user, name:)
    end
    visit library_path(@library, folder_id: @root.id)
    within browser do
      %w[First Second].each { |name| find("input[aria-label='Select folder #{name}']").check }
      click_button "Remove"
    end
    within "#modal" do
      click_button "Remove"
    end
    assert_no_link "First"
    assert_no_link "Second"
    click_control("Undo")
    assert_link "First"
    assert_link "Second"
    assert_button "Undo", disabled: true
    click_control("Redo")
    assert_no_link "First"
    assert_no_link "Second"
    assert_button "Redo", disabled: true
  end

  test "browser tabs have separate histories and switching versions clears them" do
    @user.update!(role: :admin)
    previous = @library.current_version
    LibraryVersions::Create.call(library: @library, version_number: "2.0", user: @user)
    @root = @library.reload.current_version.library_folders.find_by!(name: "Root")
    visit library_path(@library, folder_id: @root.id)
    create_child("This tab")
    other_window = open_new_window
    within_window(other_window) do
      visit library_path(@library, folder_id: @root.id)
      assert_button "Undo", disabled: true
      create_child("Other tab")
    end
    other_window.close
    click_control("Undo")
    assert_no_link "This tab"
    assert_link "Other tab"
    click_control("Redo")
    assert_link "This tab"
    click_button "2.0"
    within "ul[aria-labelledby='library-version-dropdown']" do
      click_link previous.version_number
    end
    assert_no_selector '[data-controller="library-undo"]'
    click_button "1.0"
    within "ul[aria-labelledby='library-version-dropdown']" do
      click_link "2.0"
    end
    assert_button "Undo", disabled: true
    assert_button "Redo", disabled: true
  end

  test "admin history lists and redoes a complete dependent chain" do
    @user.update!(role: :admin)
    child = @root.child_folders.create!(library: @library, library_version: @library.current_version, user: @user, name: "Child")
    creation = LibraryChanges::Recorder.call(library_version: @library.current_version, user: @user,
      action_type: :add_folder, details: { folder_id: child.id, parent_folder_id: @root.id, logo_id: nil },
      targets: [ { target_kind: :folder, target_id: child.id, folder_id: child.id,
        resource_key: LibraryChanges::Recorder.folder_key(child), effect: :new, direct: true, label: child.name } ],
      required_folder_ids: [ @root.id ])
    placement = LibraryFolderOperations::PlaceContents.call(library: @library, folder_id: child.id,
      content_ids: [ contents(:one).id ], user: @user).added_placements.first
    visit library_changes_path(@library)
    find("[data-change-id='#{creation.id}'] a").click
    within "#modal" do
      click_button "Undo"
    end
    assert_text "Library change was undone."
    refute LibraryFolder.exists?(child.id)
    find("[data-change-id='#{creation.id}'] a").click
    within "#modal" do
      assert_selector "ul[aria-label='Edits to redo'] li", count: 2
      assert_text "Redo will restore all 2 edits undone together."
      click_button "Redo"
    end
    assert_text "Library changes were redone."
    assert LibraryFolder.exists?(child.id)
    assert LibraryFolderContent.exists?(placement.id)
    assert_selector ".library-change-row", count: 2
    assert_no_selector ".library-change-undone"
    assert_no_text "Redone by"
    find("[data-change-id='#{creation.id}'] a").click
    within "#modal" do
      assert_no_text "Undone by"
      assert_no_button "Redo"
      click_button "Undo"
    end
    assert_text "Library change was undone."
    assert_selector ".library-change-undone", count: 2
    find("[data-change-id='#{creation.id}'] a").click
    within "#modal" do
      click_button "Redo"
    end
    assert_text "Library changes were redone."
    assert_selector ".library-change-row", count: 2
    assert_no_selector ".library-change-undone"
  end

  test "adding multiple contents uses one slot and repeating the addition uses none" do
    visit library_path(@library, folder_id: @root.id)
    panel = "turbo-frame##{ActionView::RecordIdentifier.dom_id(@library, :content_panel)}"
    2.times do
      within panel do
        [ contents(:one), contents(:two) ].each do |content|
          find("input[data-content-table-selection-target='row'][value='#{content.id}']").check
        end
        click_on "Add to Active Folder"
      end
      within browser do
        assert_text contents(:one).title
        assert_text contents(:two).title
      end
      assert_button "Undo", disabled: false
    end
    click_control("Undo")
    within browser do
      assert_no_text contents(:one).title
      assert_no_text contents(:two).title
    end
    assert_button "Undo", disabled: true
    click_control("Redo")
    within browser do
      assert_text contents(:one).title
      assert_text contents(:two).title
    end
  end

  private

  def browser
    "turbo-frame##{ActionView::RecordIdentifier.dom_id(@library, :folder_browser)}"
  end

  def create_child(name)
    click_link "New Folder"
    within "#modal" do
      fill_in "Name", with: name
      click_button "New Folder"
    end
    assert_no_selector "#modal .modal"
    assert_link name
    assert_button "Undo", disabled: false
  end

  def click_control(name)
    within '[data-controller="library-undo"]' do
      assert_button name, disabled: false
      click_button name
    end
  end
end
