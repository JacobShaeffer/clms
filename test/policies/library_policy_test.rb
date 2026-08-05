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

  private

  def user(role)
    User.new(name: role.to_s.titleize, email: "#{role}@example.com", password: "password", role: role)
  end
end
