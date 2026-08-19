require "application_system_test_case"

class LibrariesTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup do
    users(:one).update!(
      name: "Library System User",
      email: "library-system-user@example.com",
      password: "password",
      role: :intern_plus
    )
    sign_in users(:one)
  end

  test "clicking the version cell opens the library" do
    library = Library.create!(name: "Health Library", user: users(:one))

    visit libraries_path
    find("##{ActionView::RecordIdentifier.dom_id(library)} td", text: "1.0").click

    assert_current_path library_path(library)
    assert_selector "h1", text: library.name
  end

  test "creating a library from the modal adds it to the table" do
    visit libraries_path

    click_on "New library"

    within "turbo-frame#modal" do
      assert_selector ".modal-title", text: "New library"
      fill_in "Name", with: "Agriculture Library"
      click_on "Create Library"
    end

    assert_no_selector "turbo-frame#modal .modal"
    assert_selector "tbody#libraries tr", text: /Agriculture Library.*1\.0/
  end

  test "browses folders tabs shelves and library placement tooltips" do
    library = Library.create!(name: "Health Library", user: users(:one))
    root_folder = create_folder!(library, "Guides")
    child_folder = create_folder!(library, "First Aid", parent_folder: root_folder)
    LibraryFolderContent.create!(library_folder: child_folder, content: contents(:one))
    shelf = users(:one).shelves.create!(name: "Reading List")
    shelf.contents << contents(:one)
    ActiveShelf.activate!(user: users(:one), shelf:)

    visit library_path(library)

    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :folder_browser)}" do
      click_on root_folder.name
      assert_link child_folder.name
      click_on child_folder.name
      assert_text contents(:one).title
      assert_selector ".breadcrumb-item.active", text: child_folder.name
      assert_link root_folder.name
    end

    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :content_panel)}" do
      click_on "Library Content"
      assert_selector ".nav-link.active", text: "Library Content"
      assert_text contents(:one).title
      find("[data-controller='tooltip']", text: child_folder.name).hover
    end
    assert_selector ".tooltip .tooltip-inner", text: "Health Library / Guides / First Aid"

    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :content_panel)}" do
      click_on "Shelves"
      click_on shelf.name
      assert_text contents(:one).title
      assert_no_selector "input[name='q']"
      assert_no_button "Advanced Filters"
    end
  end

  test "creates root and child folders from the active folder" do
    library = Library.create!(name: "Health Library", user: users(:one))

    visit library_path(library)
    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :folder_browser)}" do
      click_on "Add Folder"
    end

    within "turbo-frame#modal" do
      fill_in "Name", with: "Guides"
      select library_assets(:one).name, from: "Library asset"
      click_on "Add Folder"
    end

    assert_no_selector "turbo-frame#modal .modal"
    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :folder_browser)}" do
      click_on "Guides"
      click_on "Add Folder"
    end

    within "turbo-frame#modal" do
      assert_no_select "Library asset"
      fill_in "Name", with: "First Aid"
      click_on "Add Folder"
    end

    assert_no_selector "turbo-frame#modal .modal"
    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :folder_browser)}" do
      assert_link "First Aid"
    end

    child = library.library_folders.find_by!(name: "First Aid")
    assert_nil child.logo
  end

  test "adds selected content to the folder opened in the browser" do
    library = Library.create!(name: "Health Library", user: users(:one))
    root_folder = create_folder!(library, "Guides")

    visit library_path(library)

    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :content_panel)}" do
      assert_button "Add to Active Folder", disabled: false
      find("input[aria-label='Select #{contents(:one).title}']", match: :first).check
      click_on "Add to Active Folder"
      assert_text "Open a folder before adding content."
    end

    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :folder_browser)}" do
      click_on root_folder.name
    end

    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :content_panel)}" do
      assert_button "Add to Active Folder", disabled: false
      find("input[aria-label='Select #{contents(:one).title}']", match: :first).check
      click_on "Add to Active Folder"
      assert_text "Content was added to the active folder."
    end

    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :folder_browser)}" do
      assert_text contents(:one).title
    end
    assert_includes root_folder.reload.contents, contents(:one)
  end

  private

  def create_folder!(library, name, parent_folder: nil)
    library.library_folders.create!(
      name:,
      parent_folder:,
      user: users(:one),
      logo: (parent_folder ? nil : library_assets(:one))
    )
  end
end
