require "test_helper"

class LibraryAssetPolicyTest < Minitest::Test
  FakeScope = Struct.new(:all_result, :none_result) do
    def all
      all_result
    end

    def none
      none_result
    end
  end

  def test_access
    refute LibraryAssetPolicy.new(nil, LibraryAsset).index?

    %i[guest organization volunteer intern].each do |role|
      refute LibraryAssetPolicy.new(user(role), LibraryAsset).index?
    end

    assert LibraryAssetPolicy.new(user(:intern_plus), LibraryAsset).index?
    assert LibraryAssetPolicy.new(user(:admin), LibraryAsset).index?
  end

  def test_resource_actions_use_the_same_access_rule
    intern_policy = LibraryAssetPolicy.new(user(:intern), LibraryAsset)
    admin_policy = LibraryAssetPolicy.new(user(:admin), LibraryAsset)

    %i[show? create? new? update? edit? destroy? delete_confirmation?].each do |query|
      refute intern_policy.public_send(query)
      assert admin_policy.public_send(query)
    end
  end

  def test_scope
    scope = FakeScope.new(:all_records, :no_records)

    assert_equal :no_records, LibraryAssetPolicy::Scope.new(user(:intern), scope).resolve
    assert_equal :all_records, LibraryAssetPolicy::Scope.new(user(:intern_plus), scope).resolve
    assert_equal :all_records, LibraryAssetPolicy::Scope.new(user(:admin), scope).resolve
  end

  private

  def user(role)
    User.new(name: role.to_s.titleize, email: "#{role}@example.com", password: "password", role: role)
  end
end
