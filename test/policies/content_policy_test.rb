require "test_helper"

class ContentPolicyTest < Minitest::Test
  FakeScope = Struct.new(:active_result, :none_result) do
    def active
      active_result
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

  def test_show_and_update
    refute ContentPolicy.new(user(:guest), Content).show?
    assert ContentPolicy.new(user(:organization), Content).show?
    refute ContentPolicy.new(user(:organization), Content).update?
    assert ContentPolicy.new(user(:volunteer), Content).update?
  end

  def test_file_replacement_and_permanent_deletion_have_separate_permissions
    %i[guest organization volunteer intern].each do |role|
      policy = ContentPolicy.new(user(role), Content)
      refute policy.destroy?
      refute policy.replace_file?
    end

    intern_plus_policy = ContentPolicy.new(user(:intern_plus), Content)
    refute intern_plus_policy.destroy?
    assert intern_plus_policy.replace_file?

    admin_policy = ContentPolicy.new(user(:admin), Content)
    assert admin_policy.destroy?
    assert admin_policy.replace_file?
  end

  def test_trash_permissions
    %i[guest organization volunteer intern].each do |role|
      policy = ContentPolicy.new(user(role), Content)
      refute policy.trash?
      refute policy.trash_confirmation?
      refute policy.trash_index?
      refute policy.restore?
    end

    intern_plus_policy = ContentPolicy.new(user(:intern_plus), Content)
    assert intern_plus_policy.trash?
    assert intern_plus_policy.trash_confirmation?
    refute intern_plus_policy.trash_index?
    refute intern_plus_policy.restore?

    admin_policy = ContentPolicy.new(user(:admin), Content)
    assert admin_policy.trash?
    assert admin_policy.trash_confirmation?
    assert admin_policy.trash_index?
    assert admin_policy.restore?
  end

  def test_metadata_input_actions
    organization_policy = ContentPolicy.new(user(:organization), Content)
    volunteer_policy = ContentPolicy.new(user(:volunteer), Content)

    assert organization_policy.table?
    assert organization_policy.reset_table?
    assert organization_policy.add_to_shelves?
    assert organization_policy.search?
    refute organization_policy.add_new_metadatum?
    assert organization_policy.add_existing_metadatum?
    assert volunteer_policy.add_new_metadatum?
    assert volunteer_policy.add_existing_metadatum?
  end

  def test_permitted_attributes
    assert_equal(
      [ :title, :display_title, :description, :year_of_publication, :additional_notes, :file, { metadatum_ids: [] } ],
      ContentPolicy.new(user(:volunteer), Content).permitted_attributes
    )

    persisted_content = Struct.new(:new_record?).new(false)
    refute_includes ContentPolicy.new(user(:volunteer), persisted_content).permitted_attributes, :file
    assert_includes ContentPolicy.new(user(:intern_plus), persisted_content).permitted_attributes, :file
  end

  private

  def user(role)
    User.new(name: role.to_s.titleize, email: "#{role}@example.com", password: "password", role: role)
  end
end
