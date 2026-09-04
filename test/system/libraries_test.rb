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

  test "selecting a previous version shows its folder snapshot as read only" do
    library = Library.create!(name: "Versioned Library", user: users(:one))
    root_folder = create_folder!(library, "Guides")
    child_folder = create_folder!(library, "First Aid", parent_folder: root_folder)
    LibraryFolderContent.create!(library_folder: child_folder, content: contents(:one))
    historical_version = library.current_version

    LibraryVersions::Create.call(library:, version_number: "2.0", user: users(:one))
    current_root = library.reload.current_version.library_folders.find_by!(name: root_folder.name)
    current_child = current_root.child_folders.find_by!(name: child_folder.name)
    current_child.library_folder_contents.find_by!(content: contents(:one)).destroy!
    current_child.destroy!

    visit library_path(library, folder_id: current_root.id)
    click_button "2.0"
    within "ul[aria-labelledby='library-version-dropdown']" do
      click_link historical_version.version_number
    end

    assert_current_path library_path(library, library_version_id: historical_version.id)
    assert_no_selector "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :content_panel)}"
    assert_no_selector ".nav-tabs"

    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :folder_browser)}" do
      assert_no_selector "input[data-library-folder-selection-target='item']"
      assert_no_link "New Folder"
      click_link root_folder.name
      click_link child_folder.name
      assert_text contents(:one).title
      assert_no_selector "input[data-library-folder-selection-target='item']"
    end
  end

  test "an admin creates an editable snapshot from the library page" do
    users(:one).update!(role: :admin)
    library = Library.create!(name: "Versioned Library", user: users(:one))
    folder = create_folder!(library, "Guides")
    LibraryFolderContent.create!(library_folder: folder, content: contents(:one))
    previous_version = library.current_version

    visit library_path(library, folder_id: folder.id)
    click_on "New version"

    within "turbo-frame#modal" do
      fill_in "Version number", with: "2.0"
      click_on "Create version"
    end

    assert_no_selector "turbo-frame#modal .modal"
    assert_current_path library_path(library)
    assert_button "2.0"
    assert_link "Guides"

    current_version = library.reload.current_version
    assert_equal "2.0", current_version.version_number
    assert_predicate current_version, :editable?
    assert_predicate previous_version.reload, :locked?
    assert current_version.library_version_contents.exists?(content: contents(:one))
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
      click_on "Current Library"
      assert_selector ".nav-link.active", text: "Current Library"
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

      click_on "All Content"
      assert_selector ".nav-link.active", text: "All Content"
      click_on "Shelves"
      assert_selector "##{ActionView::RecordIdentifier.dom_id(shelf, :library)}.active"
      assert_text contents(:one).title
    end
  end

  test "selects visible browser items and clears selection during folder navigation" do
    library = Library.create!(name: "Health Library", user: users(:one))
    root_folder = create_folder!(library, "Guides")
    child_folder = create_folder!(library, "First Aid", parent_folder: root_folder)
    LibraryFolderContent.create!(library_folder: root_folder, content: contents(:one))

    visit library_path(library)

    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :folder_browser)}" do
      assert_no_button "Move"
      assert_no_button "Remove"
      assert_no_button "Duplicate"

      root_checkbox = find("input[aria-label='Select folder #{root_folder.name}']")
      root_checkbox.check

      assert root_checkbox.checked?
      assert_button "Move"
      assert_button "Remove"
      assert_button "Duplicate"
      assert_selector ".breadcrumb-item.active", text: library.name

      click_on root_folder.name
      assert_no_selector "input[data-library-folder-selection-target='item']:checked"
      assert_no_button "Move"
      assert_no_button "Remove"
      assert_no_button "Duplicate"

      child_checkbox = find("input[aria-label='Select folder #{child_folder.name}']")
      content_checkbox = find("input[aria-label='Select content #{contents(:one).title}']")
      child_checkbox.check
      content_checkbox.check
      assert_selector "input[data-library-folder-selection-target='item']:checked", count: 2
      assert_button "Move"
      assert_button "Remove"
      assert_button "Duplicate"

      child_checkbox.uncheck
      content_checkbox.uncheck
      assert_no_button "Move"
      assert_no_button "Remove"
      assert_no_button "Duplicate"

      child_checkbox.check

      click_on child_folder.name
      assert_no_selector "input[data-library-folder-selection-target='item']:checked"
      assert_current_path library_path(library, folder_id: child_folder.id, tab: "all")
    end

    page.go_back
    assert_current_path library_path(library, folder_id: root_folder.id, tab: "all")

    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :folder_browser)}" do
      assert_selector ".breadcrumb-item.active", text: root_folder.name
      assert_no_selector "input[data-library-folder-selection-target='item']:checked"

      click_on library.name
      assert_selector ".breadcrumb-item.active", text: library.name
      assert_no_selector "input[data-library-folder-selection-target='item']:checked"
    end
  end

  test "confirms and removes selected content and recursive folders" do
    library = Library.create!(name: "Removal Library", user: users(:one))
    source = create_folder!(library, "Source")
    selected_folder = create_folder!(library, "Selected", parent_folder: source)
    nested_folder = create_folder!(library, "Nested", parent_folder: selected_folder)
    LibraryFolderContent.create!(library_folder: source, content: contents(:one))
    LibraryFolderContent.create!(library_folder: nested_folder, content: contents(:two))

    visit library_path(library, folder_id: source.id)

    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :folder_browser)}" do
      find("input[aria-label='Select folder #{selected_folder.name}']").check
      find("input[aria-label='Select content #{contents(:one).title}']").check
      click_button "Remove"
    end

    within "turbo-frame#modal" do
      assert_text "Remove selected items"
      assert_text selected_folder.name
      assert_text nested_folder.name
      assert_text contents(:one).title
      assert_text contents(:two).title
      click_button "Cancel"
    end
    assert_no_selector "turbo-frame#modal .modal"
    assert LibraryFolder.exists?(selected_folder.id)

    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :folder_browser)}" do
      click_button "Remove"
    end
    within "turbo-frame#modal" do
      click_button "Remove"
    end

    assert_no_selector "turbo-frame#modal .modal"
    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :folder_browser)}" do
      assert_no_text selected_folder.name
      assert_no_text contents(:one).title
    end
    assert Content.exists?(contents(:one).id)
    refute LibraryFolder.exists?(selected_folder.id)
    refute LibraryFolder.exists?(nested_folder.id)
  end

  test "moves selected content and folder trees to one destination" do
    library = Library.create!(name: "Move Library", user: users(:one))
    source = create_folder!(library, "Source")
    destination = create_folder!(library, "Destination")
    selected_folder = create_folder!(library, "Selected", parent_folder: source)
    nested_folder = create_folder!(library, "Nested", parent_folder: selected_folder)
    LibraryFolderContent.create!(library_folder: source, content: contents(:one))

    visit library_path(library, folder_id: source.id)

    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :folder_browser)}" do
      find("input[aria-label='Select folder #{selected_folder.name}']").check
      find("input[aria-label='Select content #{contents(:one).title}']").check
      click_button "Move"
    end

    within "turbo-frame#modal" do
      assert_button "Move Here", disabled: true
      click_on destination.name
      assert_button "Move Here", disabled: false
      click_on library.name
      assert_button "Move Here", disabled: true
      click_on destination.name
      assert_button "Move Here", disabled: false
      click_button "Move Here"
    end

    assert_no_selector "turbo-frame#modal .modal"
    assert_equal destination, selected_folder.reload.parent_folder
    assert_equal selected_folder, nested_folder.reload.parent_folder
    refute source.contents.exists?(contents(:one).id)
    assert destination.contents.exists?(contents(:one).id)
  end

  test "duplicates selected items into a newly created destination folder" do
    library = Library.create!(name: "Duplicate Library", user: users(:one))
    source = create_folder!(library, "Source")
    destination = create_folder!(library, "Destination")
    selected_folder = create_folder!(library, "Selected", parent_folder: source)
    nested_folder = create_folder!(library, "Nested", parent_folder: selected_folder)
    LibraryFolderContent.create!(library_folder: source, content: contents(:one))
    LibraryFolderContent.create!(library_folder: nested_folder, content: contents(:two))

    visit library_path(library, folder_id: source.id)

    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :folder_browser)}" do
      find("input[aria-label='Select folder #{selected_folder.name}']").check
      find("input[aria-label='Select content #{contents(:one).title}']").check
      click_button "Duplicate"
    end

    within "turbo-frame#modal" do
      page.execute_script(
        "document.querySelector('turbo-frame#modal .modal').dataset.navigationMarker = 'preserved'"
      )
      click_on destination.name
      assert_selector ".modal[data-navigation-marker='preserved']"
      assert_selector "turbo-frame#library-folder-destination-browser .breadcrumb-item.active",
        text: destination.name
      click_on "New Folder"
    end
    within "turbo-frame#modal" do
      fill_in "Name", with: "Copies"
      click_button "New Folder"
    end
    within "turbo-frame#modal" do
      assert_selector "turbo-frame#library-folder-destination-browser .breadcrumb-item.active", text: "Copies"
      assert_button "Duplicate Here", disabled: false
      click_button "Duplicate Here"
    end

    assert_no_selector "turbo-frame#modal .modal"
    copies = destination.child_folders.find_by!(name: "Copies")
    copied_selected = copies.child_folders.find_by!(name: selected_folder.name)
    assert copied_selected.child_folders.exists?(name: nested_folder.name)
    assert copies.contents.exists?(contents(:one).id)
    assert_equal source, selected_folder.reload.parent_folder
  end

  test "creates root and child folders from the active folder" do
    library = Library.create!(name: "Health Library", user: users(:one))

    visit library_path(library)
    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :folder_browser)}" do
      click_on "New Folder"
    end

    within "turbo-frame#modal" do
      fill_in "Name", with: "Guides"
      select library_assets(:one).name, from: "Library asset"
      click_on "New Folder"
    end

    assert_no_selector "turbo-frame#modal .modal"
    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :folder_browser)}" do
      click_on "Guides"
      click_on "New Folder"
    end

    within "turbo-frame#modal" do
      assert_no_select "Library asset"
      fill_in "Name", with: "First Aid"
      click_on "New Folder"
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
      find("input[data-content-table-selection-target='row'][value='#{contents(:one).id}']").check
      click_on "Add to Active Folder"
      assert_text "Open a folder before adding content."
    end

    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :folder_browser)}" do
      click_on root_folder.name
    end

    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :content_panel)}" do
      assert_button "Add to Active Folder", disabled: false
      assert_selector "input[data-content-table-selection-target='row'][value='#{contents(:one).id}']:checked"
      click_on "Add to Active Folder"
      assert_text "Content was added to the active folder."
    end

    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :folder_browser)}" do
      assert_text contents(:one).title
    end
    assert_includes root_folder.reload.contents, contents(:one)
  end

  test "keeps separate content selections for each library tab" do
    library = Library.create!(name: "Health Library", user: users(:one))
    root_folder = create_folder!(library, "Guides")
    LibraryFolderContent.create!(library_folder: root_folder, content: contents(:one))
    LibraryFolderContent.create!(library_folder: root_folder, content: contents(:two))
    shelf = users(:one).shelves.create!(name: "Reading List")
    shelf.contents << [ contents(:one), contents(:two) ]
    ActiveShelf.activate!(user: users(:one), shelf:)

    visit library_path(library)

    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :content_panel)}" do
      find("input[data-content-table-selection-target='row'][value='#{contents(:one).id}']").check

      click_on "Current Library"
      assert_no_selector "input[data-content-table-selection-target='row']:checked"
      find("input[data-content-table-selection-target='row'][value='#{contents(:two).id}']").check

      click_on "Shelves"
      click_on shelf.name
      assert_no_selector "input[data-content-table-selection-target='row']:checked"
      find("input[data-content-table-selection-target='row'][value='#{contents(:one).id}']").check

      click_on "All Content"
      assert_selector "input[data-content-table-selection-target='row'][value='#{contents(:one).id}']:checked"
      assert_selector "input[data-content-table-selection-target='row'][value='#{contents(:two).id}']:not(:checked)"

      click_on "Current Library"
      assert_selector "input[data-content-table-selection-target='row'][value='#{contents(:one).id}']:not(:checked)"
      assert_selector "input[data-content-table-selection-target='row'][value='#{contents(:two).id}']:checked"

      click_on "Shelves"
      assert_selector "input[data-content-table-selection-target='row'][value='#{contents(:one).id}']:checked"
      assert_selector "input[data-content-table-selection-target='row'][value='#{contents(:two).id}']:not(:checked)"
    end

    assert_not_includes current_url, "selected_content_ids"
  end

  test "sorting a library table clears its saved tab selection" do
    library = Library.create!(name: "Health Library", user: users(:one))

    visit library_path(library)

    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :content_panel)}" do
      find("input[data-content-table-selection-target='row'][value='#{contents(:one).id}']").check
      find("thead a[aria-label='Sort Title ascending']").click

      assert_no_selector "input[data-content-table-selection-target='row']:checked"

      click_on "Current Library"
      click_on "All Content"
      assert_no_selector "input[data-content-table-selection-target='row']:checked"
    end
  end

  test "column changes can retain a library tab selection" do
    library = Library.create!(name: "Health Library", user: users(:one))

    visit library_path(library)

    within "turbo-frame##{ActionView::RecordIdentifier.dom_id(library, :content_panel)}" do
      find("input[data-content-table-selection-target='row'][value='#{contents(:one).id}']").check
      click_button "Column select"
      check "Display title"

      assert_selector "thead th", text: "Display title"
      assert_selector "input[data-content-table-selection-target='row'][value='#{contents(:one).id}']:checked"

      click_on "Current Library"
      click_on "All Content"
      assert_selector "input[data-content-table-selection-target='row'][value='#{contents(:one).id}']:checked"
    end
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
