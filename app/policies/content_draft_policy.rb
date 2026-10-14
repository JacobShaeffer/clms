class ContentDraftPolicy < ApplicationPolicy
  def index?
    at_least?(:volunteer)
  end

  def create?
    at_least?(:volunteer) && owner?
  end

  def show?
    user.present? && (user.admin? || owner?)
  end

  def update?
    create?
  end

  def destroy?
    owner?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user
      return scope.all if user.admin?

      scope.where(user: user)
    end
  end

  private

  def owner?
    user.present? && record.user_id == user.id
  end
end
