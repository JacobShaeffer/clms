module LibrariesHelper
  def library_change_badge_class(label)
    case label
    when "Removed" then "text-bg-danger"
    when "Parent Folder Removed" then "text-bg-warning"
    when "Moved" then "text-bg-info"
    else "text-bg-success"
    end
  end
end
