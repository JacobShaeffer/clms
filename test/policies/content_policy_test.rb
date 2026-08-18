require "test_helper"

class ContentPolicyTest < Minitest::Test
  FakeScope = Struct.new(:all_result, :none_result) do
    def all
      all_result
    end

    def none
      none_result
    end
  end

  def test_scope
    scope = FakeScope.new(:all_records, :no_records)

    assert_equal :no_records, ContentPolicy::Scope.new(user(:guest), scope).resolve
    assert_equal :all_records, ContentPolicy::Scope.new(user(:organization), scope).resolve
  end

  def test_index
    refute ContentPolicy.new(user(:guest), Content).index?
    assert ContentPolicy.new(user(:organization), Content).index?
  end

  def test_create
    refute ContentPolicy.new(user(:organization), Content).create?
    assert ContentPolicy.new(user(:volunteer), Content).create?
  end

  def test_metadata_input_actions
    organization_policy = ContentPolicy.new(user(:organization), Content)
    volunteer_policy = ContentPolicy.new(user(:volunteer), Content)

    assert organization_policy.table?
    assert organization_policy.reset_table?
    assert organization_policy.add_to_shelves?
    assert organization_policy.search?
    refute organization_policy.add_new_metadatum?
    refute organization_policy.add_existing_metadatum?
    assert volunteer_policy.add_new_metadatum?
    assert volunteer_policy.add_existing_metadatum?
  end

  def test_permitted_attributes
    assert_equal(
      [ :title, :display_title, :description, :year_of_publication, :additional_notes, :file, { metadatum_ids: [] } ],
      ContentPolicy.new(user(:volunteer), Content).permitted_attributes
    )
  end

  private

  def user(role)
    User.new(name: role.to_s.titleize, email: "#{role}@example.com", password: "password", role: role)
  end
end
