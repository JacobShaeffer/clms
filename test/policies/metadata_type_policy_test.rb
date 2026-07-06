require "test_helper"

class MetadataTypePolicyTest < Minitest::Test
  FakeScope = Struct.new(:all_result, :none_result) do
    def all
      all_result
    end

    def none
      none_result
    end
  end

  def setup
    @metadata_type = MetadataType.new(name: "Subject", access_level: User.roles.fetch("organization"))
  end

  def test_scope
    scope = FakeScope.new(:all_records, :no_records)

    assert_equal :no_records, MetadataTypePolicy::Scope.new(user(:guest), scope).resolve
    assert_equal :all_records, MetadataTypePolicy::Scope.new(user(:organization), scope).resolve
  end

  def test_show
    refute MetadataTypePolicy.new(user(:guest), @metadata_type).show?
    assert MetadataTypePolicy.new(user(:organization), @metadata_type).show?
    assert MetadataTypePolicy.new(user(:volunteer), @metadata_type).metadata_values?
  end

  def test_create
    refute MetadataTypePolicy.new(user(:intern), MetadataType).create?
    assert MetadataTypePolicy.new(user(:intern_plus), MetadataType).create?
    assert MetadataTypePolicy.new(user(:admin), MetadataType).new?
  end

  def test_update
    refute MetadataTypePolicy.new(user(:intern), @metadata_type).update?
    assert MetadataTypePolicy.new(user(:intern_plus), @metadata_type).update?
    assert MetadataTypePolicy.new(user(:admin), @metadata_type).edit?
  end

  def test_destroy
    refute MetadataTypePolicy.new(user(:intern_plus), @metadata_type).destroy?
    assert MetadataTypePolicy.new(user(:admin), @metadata_type).destroy?
  end

  def test_permitted_attributes
    assert_equal [ :name, :order ], MetadataTypePolicy.new(user(:intern_plus), @metadata_type).permitted_attributes
    assert_equal [ :name, :order, :access_level ], MetadataTypePolicy.new(user(:admin), @metadata_type).permitted_attributes
  end

  private

  def user(role)
    User.new(name: role.to_s.titleize, email: "#{role}@example.com", password: "password", role: role)
  end
end
