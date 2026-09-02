require "test_helper"

class LibraryFolderPolicyTest < Minitest::Test
  def test_creating_folders_requires_intern_plus
    intern_policy = LibraryFolderPolicy.new(user(:intern), LibraryFolder)
    intern_plus_policy = LibraryFolderPolicy.new(user(:intern_plus), LibraryFolder)
    admin_policy = LibraryFolderPolicy.new(user(:admin), LibraryFolder)

    refute intern_policy.create?
    refute intern_policy.manage?
    assert intern_plus_policy.create?
    assert intern_plus_policy.manage?
    assert admin_policy.create?
    assert admin_policy.manage?
  end

  private

  def user(role)
    User.new(name: role.to_s.titleize, email: "#{role}@example.com", password: "password", role:)
  end
end
