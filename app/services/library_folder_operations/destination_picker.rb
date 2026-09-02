module LibraryFolderOperations
  class DestinationPicker
    OPERATIONS = %i[move duplicate].freeze

    attr_reader :library, :library_version, :selection, :operation, :current_folder,
      :breadcrumbs, :folders

    def initialize(library:, selection:, operation:, current_folder_id: nil)
      @library = library
      @selection = selection
      @library_version = VersionGuard.ensure_current!(
        library:,
        library_version: selection.library_version
      )
      @operation = operation.to_sym
      raise Selection::InvalidSelection, "Invalid folder operation." unless OPERATIONS.include?(@operation)

      @current_folder = current_folder_id.present? ? selection.folder!(current_folder_id, label: "picker folder") : nil
      if @current_folder && selection.blocked_folder_ids.include?(@current_folder.id)
        raise Selection::InvalidSelection, "A selected folder cannot be opened as a destination."
      end

      path_index = LibraryFolderPathIndex.new(
        library:,
        library_version:,
        folders: selection.all_folders
      )
      @breadcrumbs = @current_folder ? path_index.path(@current_folder) : []
      @folders = selection.children_for_parent(@current_folder&.id)
    end

    def blocked?(folder)
      selection.blocked_folder_ids.include?(folder.id)
    end

    def selectable?(folder)
      return false if blocked?(folder)
      return false if operation == :move && folder.id == selection.source_folder_id

      true
    end

    def openable?(folder)
      !blocked?(folder)
    end

    def current_folder_selectable?
      current_folder.present? && selectable?(current_folder)
    end
  end
end
