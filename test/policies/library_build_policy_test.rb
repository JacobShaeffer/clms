require "test_helper"

class LibraryBuildPolicyTest < Minitest::Test
  def test_build_permissions_require_admin
    [ nil, *User.roles.keys ].each do |role|
      user = User.new(role:) if role
      policy = LibraryBuildPolicy.new(user, LibraryBuild)
      %i[create? show? download?].each do |action|
        assert_equal role == "admin", !!policy.public_send(action), "#{role.inspect} #{action}"
      end
    end
  end

  def test_module_selection_permissions_match_library_editing
    User.roles.each_key do |role|
      expected = %w[intern_plus admin].include?(role)
      assert_equal expected, LibraryPolicy.new(User.new(role:), Library).module_selection?
    end
  end
end
