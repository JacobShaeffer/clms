require "test_helper"

class ContentDraftPolicyTest < ActiveSupport::TestCase
  setup do
    @owner = users(:one)
    @owner.update!(role: :volunteer)
    @other = users(:two)
    @other.update!(role: :volunteer)
    @draft = @owner.content_drafts.create!
  end

  test "only users who can create content can create or update their own drafts" do
    policy = ContentDraftPolicy.new(@owner, @draft)
    assert policy.index?
    assert policy.create?
    assert policy.update?

    @owner.update!(role: :organization)
    refute policy.index?
    refute policy.create?
    refute policy.update?

    other_policy = ContentDraftPolicy.new(@other, @draft)
    refute other_policy.create?
    refute other_policy.update?
  end

  test "viewing permits the owner and an admin while deletion requires ownership" do
    assert ContentDraftPolicy.new(@owner, @draft).show?
    assert ContentDraftPolicy.new(@owner, @draft).destroy?
    refute ContentDraftPolicy.new(@other, @draft).show?
    refute ContentDraftPolicy.new(@other, @draft).destroy?

    @other.update!(role: :admin)
    admin_policy = ContentDraftPolicy.new(@other, @draft)
    assert admin_policy.show?
    refute admin_policy.update?
    refute admin_policy.destroy?

    anonymous_policy = ContentDraftPolicy.new(nil, @draft)
    refute anonymous_policy.show?
    refute anonymous_policy.create?
    refute anonymous_policy.destroy?
  end

  test "scope exposes owned drafts and supports future admin viewing" do
    other_draft = @other.content_drafts.create!
    assert_equal [ @draft.id ], ContentDraftPolicy::Scope.new(@owner, ContentDraft).resolve.ids
    assert_empty ContentDraftPolicy::Scope.new(nil, ContentDraft).resolve

    @other.update!(role: :admin)
    assert_equal [ @draft.id, other_draft.id ].sort,
      ContentDraftPolicy::Scope.new(@other, ContentDraft).resolve.ids.sort
  end
end
