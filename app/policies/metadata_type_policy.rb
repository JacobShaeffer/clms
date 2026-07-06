class MetadataTypePolicy < ApplicationPolicy
  def index?
    non_guest?
  end

  def show?
    non_guest?
  end

  def metadata_values?
    show?
  end

  def create?
    at_least?(:intern_plus)
  end

  def update?
    at_least?(:intern_plus)
  end

  def destroy?
    user&.admin?
  end

  def permitted_attributes
    return [ :name, :order, :access_level ] if user&.admin?

    [ :name, :order ]
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless non_guest?

      scope.all
    end
  end
end
