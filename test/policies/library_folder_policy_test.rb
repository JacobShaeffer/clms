require "test_helper"

class LibraryFolderPolicyTest < Minitest::Test
  def test_creating_folders_requires_intern_plus
    refute LibraryFolderPolicy.new(user(:intern), LibraryFolder).create?
    assert LibraryFolderPolicy.new(user(:intern_plus), LibraryFolder).create?
    assert LibraryFolderPolicy.new(user(:admin), LibraryFolder).create?
  end

  private

  def user(role)
    User.new(name: role.to_s.titleize, email: "#{role}@example.com", password: "password", role:)
  end
end
