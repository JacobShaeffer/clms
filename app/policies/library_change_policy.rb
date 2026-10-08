class LibraryChangePolicy < ApplicationPolicy
  def index?
    user&.admin?
  end

  def show?
    index?
  end

  def undo?
    user&.admin? || (record.user_id == user&.id && at_least?(:intern_plus))
  end

  def redo?
    undo?
  end
end
