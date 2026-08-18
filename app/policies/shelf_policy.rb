class ShelfPolicy < ApplicationPolicy
  def index?
    non_guest?
  end

  def new?
    non_guest?
  end

  def create?
    owned_by_user?
  end

  def table?
    owned_by_user?
  end

  def activate?
    owned_by_user?
  end

  def archive?
    owned_by_user?
  end

  def move?
    owned_by_user?
  end

  def reset_table?
    owned_by_user?
  end

  def permitted_attributes
    [ :name ]
  end

  private

  def owned_by_user?
    non_guest? && record.is_a?(Shelf) && record.user_id == user.id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless non_guest?

      scope.where(user: user)
    end
  end
end
