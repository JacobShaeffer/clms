class LibraryChangePolicy < ApplicationPolicy
  def approve?
    user&.admin?
  end

  def undo?
    user&.admin? || (record.user_id == user&.id && at_least?(:intern_plus))
  end
end
