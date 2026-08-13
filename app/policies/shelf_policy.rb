class ShelfPolicy < ApplicationPolicy
  def index?
    non_guest?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless non_guest?

      scope.where(user: user)
    end
  end
end
