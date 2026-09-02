require "test_helper"

class LibraryVersionPolicyTest < Minitest::Test
  FakeScope = Struct.new(:all_result, :none_result) do
    def all
      all_result
    end

    def none
      none_result
    end
  end

  def test_only_admins_can_create_versions
    %i[guest organization volunteer intern intern_plus].each do |role|
      refute LibraryVersionPolicy.new(user(role), LibraryVersion).create?
    end

    assert LibraryVersionPolicy.new(user(:admin), LibraryVersion).create?
    refute LibraryVersionPolicy.new(nil, LibraryVersion).create?
  end

  def test_new_access_matches_create_access
    refute LibraryVersionPolicy.new(user(:intern_plus), LibraryVersion).new?
    assert LibraryVersionPolicy.new(user(:admin), LibraryVersion).new?
  end

  def test_scope_is_admin_only
    scope = FakeScope.new(:all_records, :no_records)

    assert_equal :no_records, LibraryVersionPolicy::Scope.new(user(:intern_plus), scope).resolve
    assert_equal :all_records, LibraryVersionPolicy::Scope.new(user(:admin), scope).resolve
  end

  private

  def user(role)
    User.new(name: role.to_s.titleize, email: "#{role}@example.com", password: "password", role:)
  end
end
