class EnforceLibraryChangeDependencyChronology < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :library_change_dependencies,
      name: "library_change_dependencies_not_self"
    add_check_constraint :library_change_dependencies,
      "prerequisite_change_id < library_change_id",
      name: "library_change_dependencies_chronological"
  end

  def down
    remove_check_constraint :library_change_dependencies,
      name: "library_change_dependencies_chronological"
    add_check_constraint :library_change_dependencies,
      "library_change_id <> prerequisite_change_id",
      name: "library_change_dependencies_not_self"
  end
end
