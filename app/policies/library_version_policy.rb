class LibraryVersionPolicy < ApplicationPolicy
  def create?
    user&.admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user&.admin?

      scope.all
    end
  end
end
