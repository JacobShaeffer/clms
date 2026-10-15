require "test_helper"

class LibraryModulePolicyTest < Minitest::Test
  FakeScope = Struct.new(:all_result, :none_result) do
    def all
      all_result
    end

    def none
      none_result
    end
  end

  def test_access
    refute LibraryModulePolicy.new(nil, LibraryModule).index?

    %i[guest organization volunteer intern].each do |role|
      refute LibraryModulePolicy.new(user(role), LibraryModule).index?
    end

    assert LibraryModulePolicy.new(user(:intern_plus), LibraryModule).index?
    assert LibraryModulePolicy.new(user(:admin), LibraryModule).index?
  end

  def test_resource_actions_for_intern_plus
    policy = LibraryModulePolicy.new(user(:intern_plus), LibraryModule)

    %i[show? create? new? update? edit?].each do |query|
      assert policy.public_send(query)
    end
    refute policy.destroy?
    refute policy.delete_confirmation?
  end

  def test_admin_can_destroy
    policy = LibraryModulePolicy.new(user(:admin), LibraryModule)

    assert policy.destroy?
    assert policy.delete_confirmation?
  end

  def test_scope
    scope = FakeScope.new(:all_records, :no_records)

    assert_equal :no_records, LibraryModulePolicy::Scope.new(user(:intern), scope).resolve
    assert_equal :all_records, LibraryModulePolicy::Scope.new(user(:intern_plus), scope).resolve
    assert_equal :all_records, LibraryModulePolicy::Scope.new(user(:admin), scope).resolve
  end

  private

  def user(role)
    User.new(name: role.to_s.titleize, email: "#{role}@example.com", password: "password", role: role)
  end
end
