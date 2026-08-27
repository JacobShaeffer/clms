require "test_helper"

class BootstrapStylingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  self.fixture_table_names = []

  setup do
    @admin = User.create!(
      name: "Bootstrap Admin",
      email: "bootstrap-admin@example.com",
      password: "password",
      role: :admin
    )
    @metadata_type = MetadataType.create!(
      name: "Bootstrap Subject",
      order: 1,
      access_level: 0,
      user: @admin
    )
    6.times do |index|
      Metadatum.create!(
        name: "Bootstrap Value #{index}",
        metadata_type: @metadata_type,
        user: @admin,
        under_review: index.odd?
      )
    end

    sign_in @admin
  end

  test "layout loads Bootstrap before application CSS without Tailwind" do
    get root_url

    assert_response :success
    assert_select "link[rel='stylesheet'][href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.8/dist/css/bootstrap.min.css'][integrity][crossorigin='anonymous']", count: 1
    assert_select "link[rel='stylesheet'][href*='/assets/application']", count: 1
    assert_select "link[rel='stylesheet'][href*='tailwind']", count: 0
    assert_select "script[src='https://cdn.jsdelivr.net/npm/bootstrap@5.3.8/dist/js/bootstrap.bundle.min.js'][integrity][crossorigin='anonymous']", count: 1
    assert_operator @response.body.index("bootstrap@5.3.8/dist/css/bootstrap.min.css"), :<,
      @response.body.index("/assets/application")
    assert_operator @response.body.index("bootstrap@5.3.8/dist/js/bootstrap.bundle.min.js"), :<,
      @response.body.index('<script type="importmap"')
    assert_select "nav.navbar button.navbar-toggler[data-bs-toggle='collapse'][data-bs-target='#navbarSupportedContent']"
    assert_select "#navbarSupportedContent.navbar-collapse.collapse"
    assert_select "#content-navigation.nav-item.dropdown" do
      assert_select "a.nav-link[href='#{contents_path}']", text: "Content", count: 1
      assert_select "button.nav-link.dropdown-toggle.dropdown-toggle-split[data-bs-toggle='dropdown'][aria-expanded='false']", count: 1
      assert_select "ul.dropdown-menu a.dropdown-item[href='#{shelves_path}']", text: "Shelves", count: 1
    end
    assert_select "#library-navigation.nav-item.dropdown" do
      assert_select "a.nav-link[href='#{libraries_path}']", text: "Library", count: 1
      assert_select "button.nav-link.dropdown-toggle.dropdown-toggle-split[data-bs-toggle='dropdown'][aria-expanded='false']", count: 1
      assert_select "ul.dropdown-menu a.dropdown-item[href='#{library_assets_path}']", text: "Library Assets", count: 1
    end
    assert_select "h1.mb-3", text: "Home Page"
  end

  test "layout renders success and danger flashes as Bootstrap alerts" do
    post metadata_types_url, params: {
      metadata_type: {
        name: "Created Subject",
        order: 2,
        access_level: 0
      }
    }

    assert_redirected_to metadata_type_url(MetadataType.find_by!(name: "Created Subject"))
    follow_redirect!
    assert_select ".alert.alert-success[role='alert']", text: "Metadata type was successfully created."

    sign_out @admin
    guest = User.create!(
      name: "Bootstrap Guest",
      email: "bootstrap-guest@example.com",
      password: "password",
      role: :guest
    )
    sign_in guest

    get metadata_types_url

    assert_redirected_to root_url
    follow_redirect!
    assert_select ".alert.alert-danger[role='alert']", text: "You are not authorized to perform that action."
  end

  test "metadata screens use Bootstrap grids forms actions and components" do
    get metadata_types_url

    assert_response :success
    assert_select "h1.mb-0", text: "Metadata types"
    assert_select "h1.title", count: 0
    assert_select "a.btn.btn-primary[data-turbo-frame='modal']", text: "New metadata type"
    assert_select ".accordion .accordion-button[data-bs-toggle='collapse']"

    get metadata_values_metadata_type_url(@metadata_type)

    assert_response :success
    assert_select "turbo-frame#metadata_values_metadata_type_#{@metadata_type.id}" do
      assert_select "label.form-label", text: "Metadata Search"
      assert_select "input.form-control[type='search']"
      assert_select "label.form-label", text: "Status"
      assert_select "select.form-select"
      assert_select "a.btn.btn-primary[data-turbo-frame='modal']", text: "Add"
      assert_select ".border.rounded .metadata-value-row", 5
      assert_select ".dropdown button[data-bs-toggle='dropdown']", 10
      assert_select "a.btn.btn-outline-secondary", text: "Show More"
    end

    get new_metadata_type_url

    assert_response :success
    assert_select ".row.justify-content-center > .col-12.col-md-8" do
      assert_select "h1.mb-4", text: "New metadata type"
      assert_select "form input.form-control[name='metadata_type[name]']"
      assert_select "a.btn.btn-secondary", text: "Back to metadata types"
    end

    get new_metadata_type_url, headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_select "turbo-frame#modal .modal.fade[data-controller='modal']" do
      assert_select ".modal-dialog .modal-content"
      assert_select "button.btn-close[data-bs-dismiss='modal']"
      assert_select ".modal-body form[data-turbo-frame='modal']"
    end
  end
end
