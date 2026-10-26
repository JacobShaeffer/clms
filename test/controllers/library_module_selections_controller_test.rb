require "test_helper"
require_relative "../support/library_build_helpers"

class LibraryModuleSelectionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include LibraryBuildHelpers

  setup do
    setup_build_library
    @user.update!(role: :intern_plus)
    sign_in @user
    @module = LibraryModule.create!(name: "Learning", folder_name: "learning", icon: @asset, user: @user)
  end
  teardown { teardown_build_library }

  test "replaces deduplicates reads and clears library module selections" do
    put library_module_selection_url(@library), params: { module_selection: { module_ids: [ @module.id, @module.id ] } }, as: :json
    assert_response :success
    assert_equal [ @module.id ], response.parsed_body["module_ids"]
    assert_equal 1, @library.library_module_selections.count
    get library_module_selection_url(@library), as: :json
    assert_response :success
    assert_equal [ @module.id ], response.parsed_body["module_ids"]
    put library_module_selection_url(@library), params: { module_selection: { module_ids: [] } }, as: :json
    assert_response :success
    assert_empty @library.reload.selected_modules
  end

  test "invalid selections do not partially replace existing modules" do
    @library.selected_modules << @module
    [ [ "invalid" ], [ @module.id, LibraryModule.maximum(:id) + 1 ], [ -1 ] ].each do |ids|
      put library_module_selection_url(@library), params: { module_selection: { module_ids: ids } }, as: :json
      assert_response :unprocessable_content
      assert_equal [ @module.id ], @library.reload.selected_modules.ids
    end
    put library_module_selection_url(@library), params: { module_selection: { module_ids: [ { id: @module.id } ] } }, as: :json
    assert_response :bad_request
    assert_equal [ @module.id ], @library.reload.selected_modules.ids
  end

  test "lower roles cannot read or update module selections" do
    @user.update!(role: :intern)
    get library_module_selection_url(@library), as: :json
    assert_response :forbidden
    put library_module_selection_url(@library), params: { module_selection: { module_ids: [ @module.id ] } }, as: :json
    assert_response :forbidden
    assert_empty @library.selected_modules
  end
end
