class MetadatumPolicy < ApplicationPolicy
  def index?
    non_guest?
  end

  def show?
    non_guest?
  end

  def tagged_items?
    show?
  end

  def create?
    can_manage_value?
  end

  def update?
    can_manage_value?
  end

  def toggle_review?
    at_least?(:intern_plus)
  end

  def destroy?
    at_least?(:intern_plus)
  end

  def delete_confirmation?
    destroy?
  end

  def permitted_attributes
    return [ :name, :under_review ] if toggle_review?

    [ :name ]
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless non_guest?

      scope.all
    end
  end

  private

  def can_manage_value?
    non_guest? && record.metadata_type.present? && role_level >= record.metadata_type.access_level.to_i
  end
end
