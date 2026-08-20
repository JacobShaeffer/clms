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
    user&.admin?
  end

  def manage?
    user&.admin?
  end

  def destroy?
    user&.admin?
  end

  def permitted_attributes
    return [ :name, :access_level ] if user&.admin?

    [ :name ]
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless non_guest?

      scope.in_display_order
    end
  end
end
