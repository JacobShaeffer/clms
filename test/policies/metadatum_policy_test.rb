require "test_helper"

class MetadatumPolicyTest < Minitest::Test
  FakeScope = Struct.new(:all_result, :none_result) do
    def all
      all_result
    end

    def none
      none_result
    end
  end

  def setup
    @metadata_type = MetadataType.new(name: "Subject", access_level: User.roles.fetch("volunteer"))
    @metadatum = Metadatum.new(name: "Value", metadata_type: @metadata_type)
  end

  def test_scope
    scope = FakeScope.new(:all_records, :no_records)

    assert_equal :no_records, MetadatumPolicy::Scope.new(user(:guest), scope).resolve
    assert_equal :all_records, MetadatumPolicy::Scope.new(user(:organization), scope).resolve
  end

  def test_show
    refute MetadatumPolicy.new(user(:guest), @metadatum).show?
    assert MetadatumPolicy.new(user(:organization), @metadatum).show?
    assert MetadatumPolicy.new(user(:volunteer), @metadatum).tagged_items?
  end

  def test_create
    refute MetadatumPolicy.new(user(:organization), @metadatum).create?
    assert MetadatumPolicy.new(user(:volunteer), @metadatum).create?
    assert MetadatumPolicy.new(user(:intern), @metadatum).new?
  end

  def test_update
    refute MetadatumPolicy.new(user(:organization), @metadatum).update?
    assert MetadatumPolicy.new(user(:volunteer), @metadatum).update?
    assert MetadatumPolicy.new(user(:intern), @metadatum).edit?
  end

  def test_destroy
    refute MetadatumPolicy.new(user(:intern), @metadatum).destroy?
    assert MetadatumPolicy.new(user(:intern_plus), @metadatum).destroy?
    assert MetadatumPolicy.new(user(:admin), @metadatum).delete_confirmation?
  end

  def test_toggle_review
    refute MetadatumPolicy.new(user(:intern), @metadatum).toggle_review?
    assert MetadatumPolicy.new(user(:intern_plus), @metadatum).toggle_review?
    assert MetadatumPolicy.new(user(:admin), @metadatum).toggle_review?
  end

  def test_permitted_attributes
    assert_equal [ :name ], MetadatumPolicy.new(user(:volunteer), @metadatum).permitted_attributes
    assert_equal [ :name, :under_review ], MetadatumPolicy.new(user(:intern_plus), @metadatum).permitted_attributes
  end

  private

  def user(role)
    User.new(name: role.to_s.titleize, email: "#{role}@example.com", password: "password", role: role)
  end
end
