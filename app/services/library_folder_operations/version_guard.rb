module LibraryFolderOperations
  module VersionGuard
    module_function

    def editable_current_version!(library)
      library_version = library.current_version
      unless library_version
        raise Selection::InvalidSelection, "The library does not have a current version."
      end
      unless library_version.editable?
        raise Selection::InvalidSelection, "The current library version is locked."
      end

      library_version
    end

    def ensure_current!(library:, library_version:)
      current_version_id = library.class.where(id: library.id).pick(:current_version_id)
      return library_version if current_version_id == library_version.id

      raise Selection::InvalidSelection, "The library version changed. Refresh and try again."
    end
  end
end
