require "test_helper"

class MetadataTypesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  TURBO_STREAM_HEADERS = {
    "Turbo-Frame" => "modal",
    "Accept" => "text/vnd.turbo-stream.html"
  }.freeze
  TURBO_FRAME_HEADERS = { "Turbo-Frame" => "modal" }.freeze

  setup do
    @admin = users(:one)
    @admin.update!(role: :admin)
    @metadata_type = metadata_types(:one)
    sign_in @admin
  end

  test "index renders metadata types and their value counts" do
    get metadata_types_url

    assert_response :success
    assert_select "#metadata_type_#{@metadata_type.id}" do
      assert_select ".accordion-button", text: /#{Regexp.escape(@metadata_type.name)}/
      assert_select "#metadata_count_metadata_type_#{@metadata_type.id}", text: @metadata_type.metadata.count.to_s
    end
    assert_select "a[aria-label='Edit metadata types'][data-turbo-frame='modal']", text: "⋮"
  end

  test "index renders metadata types in display order" do
    first = metadata_types(:one)
    second = metadata_types(:two)
    first.update_columns(name: "Later", order: 2)
    second.update_columns(name: "Earlier", order: 1)

    get metadata_types_url

    rendered_ids = css_select("#metadata-types > div").map { |element| element["id"] }
    assert_equal [ "metadata_type_#{second.id}", "metadata_type_#{first.id}" ], rendered_ids
  end

  test "metadata values combine search and review filters" do
    create_metadatum!(name: "Matching reviewed", under_review: false)
    create_metadatum!(name: "Matching pending", under_review: true)
    create_metadatum!(name: "Different reviewed", under_review: false)

    get metadata_values_metadata_type_url(@metadata_type), params: { q: "Matching", status: "reviewed" }

    assert_response :success
    assert_select "turbo-frame#metadata_values_metadata_type_#{@metadata_type.id}"
    assert_select ".metadata-value-row", 1
    assert_includes response.body, "Matching reviewed"
    refute_includes response.body, "Matching pending"
    refute_includes response.body, "Different reviewed"
  end

  test "metadata values enforce page limits" do
    6.times { |index| create_metadatum!(name: "Limited value #{index}", under_review: false) }

    get metadata_values_metadata_type_url(@metadata_type), params: { limit: 1 }

    assert_response :success
    assert_select ".metadata-value-row", 5
    assert_select "a", text: "Show More"

    get metadata_values_metadata_type_url(@metadata_type), params: { limit: 1_000 }

    assert_response :success
    assert_select ".metadata-value-row", @metadata_type.metadata.count
    assert_select "a", text: "Show More", count: 0
  end

  test "metadata values show add without an individual edit action" do
    get metadata_values_metadata_type_url(@metadata_type)

    action_labels = css_select(".col-sm-2.d-grid > a").map { |link| link.text.strip }
    assert_equal [ "Add" ], action_labels
    assert_select "a[href='#{edit_metadata_type_path(@metadata_type)}']", count: 0
  end

  test "create appends a metadata type from the modal" do
    assert_difference("MetadataType.count") do
      post metadata_types_url,
        params: { metadata_type: { name: "New subject", order: 3, access_level: 2 } },
        headers: TURBO_STREAM_HEADERS
    end

    created = MetadataType.find_by!(name: "New subject")
    assert_equal @admin, created.user
    assert_equal 2, created.access_level
    assert_response :success
    assert_select "turbo-stream[action='update'][target='modal']"
    assert_equal MetadataType.maximum(:order), created.order
    assert_select "turbo-stream[action='append'][target='metadata-types']"
  end

  test "non-admin create uses the organization access level and ignores protected attributes" do
    sign_out @admin
    @admin.update!(role: :intern_plus)
    sign_in @admin

    post metadata_types_url, params: {
      metadata_type: { name: "Protected type", order: -10, access_level: User.roles.fetch("admin") }
    }

    created = MetadataType.find_by!(name: "Protected type")
    assert_equal User.roles.fetch("organization"), created.access_level
    assert_equal MetadataType.maximum(:order), created.order
  end

  test "invalid create rerenders the modal with errors" do
    assert_no_difference("MetadataType.count") do
      post metadata_types_url,
        params: { metadata_type: { name: "" } },
        headers: TURBO_STREAM_HEADERS
    end

    assert_response :unprocessable_content
    assert_select "turbo-stream[action='update'][target='modal'] template .alert.alert-danger"
  end

  test "admin edit uses a modal with role names" do
    get edit_metadata_type_url(@metadata_type), headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "turbo-frame#modal .modal-title", text: "Edit metadata type"
    assert_select "form[action='#{metadata_type_path(@metadata_type)}'][data-turbo-frame='modal']" do
      assert_select "input[name='metadata_type[name]']"
      assert_select "select.form-select[name='metadata_type[access_level]']" do
        assert_select "option", User.roles.length
        assert_select "option", text: "Organization"
        assert_select "option", text: "Admin"
      end
      assert_select "input[name='metadata_type[order]']", count: 0
    end
  end

  test "new defaults its role dropdown to organization" do
    get new_metadata_type_url, headers: TURBO_FRAME_HEADERS

    assert_select "select[name='metadata_type[access_level]'] option[selected][value='#{User.roles.fetch("organization")}']", text: "Organization"
  end

  test "update changes admin attributes but not order" do
    original_order = @metadata_type.order

    patch metadata_type_url(@metadata_type), params: {
      metadata_type: { name: "Updated subject", order: 7, access_level: 3 }
    }

    assert_redirected_to metadata_type_url(@metadata_type)
    assert_equal [ "Updated subject", original_order, 3 ], @metadata_type.reload.values_at(:name, :order, :access_level)
  end

  test "turbo update closes the modal and replaces the metadata type" do
    patch metadata_type_url(@metadata_type),
      params: { metadata_type: { name: "Updated subject", access_level: 3 } },
      headers: TURBO_STREAM_HEADERS

    assert_response :success
    assert_select "turbo-stream[action='update'][target='modal']"
    assert_select "turbo-stream[action='replace'][target='metadata_type_#{@metadata_type.id}']"
  end

  test "admin can edit metadata types and their order in one modal" do
    ordered_types = MetadataType.in_display_order.to_a

    get edit_all_metadata_types_url, headers: TURBO_FRAME_HEADERS

    assert_response :success
    assert_select "turbo-frame#modal .modal-title", text: "Edit metadata types"
    assert_select "form[action='#{update_all_metadata_types_path}'][data-controller='metadata-type-order']" do
      assert_select "input[name='metadata_type_ids[]']", ordered_types.length
      ordered_types.each do |metadata_type|
        assert_select "input[name='metadata_types[#{metadata_type.id}][name]'][value='#{metadata_type.name}']"
        assert_select "select[name='metadata_types[#{metadata_type.id}][access_level]']"
      end
      assert_select "button[data-action='metadata-type-order#moveUp']", ordered_types.length
      assert_select "button[data-action='metadata-type-order#moveDown']", ordered_types.length
      assert_select "button[data-bs-dismiss='modal']", text: "Cancel"
      assert_select "input[type='submit'][value='Save']"
    end

    reversed_ids = ordered_types.reverse.map(&:id)
    submitted_attributes = ordered_types.to_h do |metadata_type|
      [ metadata_type.id.to_s, {
        name: "Updated #{metadata_type.id}",
        access_level: User.roles.fetch("volunteer")
      } ]
    end
    patch update_all_metadata_types_url,
      params: { metadata_type_ids: reversed_ids, metadata_types: submitted_attributes },
      headers: TURBO_STREAM_HEADERS

    assert_response :success
    assert_equal reversed_ids, MetadataType.in_display_order.pluck(:id)
    assert_equal (1..reversed_ids.length).to_a, MetadataType.in_display_order.pluck(:order)
    assert MetadataType.all.all? { |metadata_type| metadata_type.name == "Updated #{metadata_type.id}" }
    assert MetadataType.all.all? { |metadata_type| metadata_type.access_level == User.roles.fetch("volunteer") }
    assert_select "turbo-stream[action='update'][target='modal']"
    assert_select "turbo-stream[action='update'][target='metadata-types']"
  end

  test "bulk edits are atomic when a metadata type is invalid" do
    ordered_types = MetadataType.in_display_order.to_a
    original_attributes = ordered_types.map { |metadata_type| metadata_type.attributes.slice("name", "order", "access_level") }
    duplicate_name = ordered_types.first.name
    submitted_attributes = ordered_types.to_h do |metadata_type|
      [ metadata_type.id.to_s, { name: duplicate_name, access_level: User.roles.fetch("volunteer") } ]
    end

    patch update_all_metadata_types_url,
      params: { metadata_type_ids: ordered_types.reverse.map(&:id), metadata_types: submitted_attributes },
      headers: TURBO_STREAM_HEADERS

    assert_response :unprocessable_content
    assert_equal original_attributes,
      ordered_types.map { |metadata_type| metadata_type.reload.attributes.slice("name", "order", "access_level") }
    assert_select "turbo-stream[action='update'][target='modal'] template .alert.alert-danger"
  end

  test "non-admin cannot open or submit the bulk edit modal" do
    sign_out @admin
    @admin.update!(role: :intern_plus)
    sign_in @admin
    original_order = MetadataType.in_display_order.pluck(:id)

    get metadata_types_url
    assert_select "[aria-label='Edit metadata types']", count: 0

    get metadata_values_metadata_type_url(@metadata_type)
    assert_select "a[href='#{edit_metadata_type_path(@metadata_type)}']", count: 0
    assert_select "a[href^='#{new_metadata_type_metadatum_path(@metadata_type)}']", count: 1

    get edit_all_metadata_types_url, headers: TURBO_FRAME_HEADERS
    assert_redirected_to root_url

    patch update_all_metadata_types_url, params: { metadata_type_ids: original_order.reverse, metadata_types: {} }
    assert_redirected_to root_url
    assert_equal original_order, MetadataType.in_display_order.pluck(:id)
  end

  test "only an admin can destroy a metadata type" do
    sign_out @admin
    @admin.update!(role: :intern_plus)
    sign_in @admin

    assert_no_difference("MetadataType.count") do
      delete metadata_type_url(@metadata_type)
    end
    assert_redirected_to root_url

    sign_out @admin
    @admin.update!(role: :admin)
    sign_in @admin

    assert_difference("MetadataType.count", -1) do
      delete metadata_type_url(@metadata_type)
    end
    assert_redirected_to metadata_types_url
  end

  test "unauthenticated users are redirected" do
    sign_out @admin

    get metadata_types_url

    assert_redirected_to new_user_session_url
  end

  private

  def create_metadatum!(name:, under_review:)
    Metadatum.create!(
      metadata_type: @metadata_type,
      user: @admin,
      name: name,
      under_review: under_review
    )
  end
end
