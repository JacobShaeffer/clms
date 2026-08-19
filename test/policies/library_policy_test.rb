require "test_helper"

class LibraryPolicyTest < Minitest::Test
  FakeScope = Struct.new(:all_result, :none_result) do
    def all
      all_result
    end

    def none
      none_result
    end
  end

  def test_read_access
    refute LibraryPolicy.new(nil, Library).index?
    refute LibraryPolicy.new(user(:guest), Library).index?

    %i[organization volunteer intern intern_plus admin].each do |role|
      policy = LibraryPolicy.new(user(role), Library)

      assert policy.index?
      assert policy.show?
    end
  end

  def test_scope
    scope = FakeScope.new(:all_records, :no_records)

    assert_equal :no_records, LibraryPolicy::Scope.new(user(:guest), scope).resolve
    assert_equal :all_records, LibraryPolicy::Scope.new(user(:organization), scope).resolve
  end

  def test_create_access
    refute LibraryPolicy.new(user(:intern), Library).create?
    assert LibraryPolicy.new(user(:intern_plus), Library).create?
    assert LibraryPolicy.new(user(:admin), Library).create?
  end

  def test_table_actions_use_library_read_access
    organization_policy = LibraryPolicy.new(user(:organization), Library)
    guest_policy = LibraryPolicy.new(user(:guest), Library)

    %i[
      all_contents_table reset_all_contents_table
      library_contents_table reset_library_contents_table
      shelf_contents_table reset_shelf_contents_table
    ].each do |action|
      assert organization_policy.public_send("#{action}?")
      refute guest_policy.public_send("#{action}?")
    end
  end

  def test_adding_content_to_a_folder_requires_intern_plus
    refute LibraryPolicy.new(user(:intern), Library).add_to_active_folder?
    assert LibraryPolicy.new(user(:intern_plus), Library).add_to_active_folder?
    assert LibraryPolicy.new(user(:admin), Library).add_to_active_folder?
  end

  private

  def user(role)
    User.new(name: role.to_s.titleize, email: "#{role}@example.com", password: "password", role: role)
  end
end
