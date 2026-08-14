class LibraryFolderPathIndex
  class InvalidFolder < ArgumentError; end

  attr_reader :library

  def initialize(library:, folders: nil)
    @library = library
    configured_folders = folders || library.library_folders.order(:name, :id).to_a
    @folders_by_id = Array(configured_folders).index_by(&:id)
    @paths_by_id = {}
  end

  def path(folder)
    configured_folder = folder_for(folder)
    @paths_by_id[configured_folder.id] ||= build_path(configured_folder).freeze
  end

  def breadcrumb(folder)
    ([ library.name ] + path(folder).map(&:name)).join(" / ")
  end

  private

  attr_reader :folders_by_id, :paths_by_id

  def folder_for(folder)
    configured_folder = folders_by_id[folder&.id]
    return configured_folder if configured_folder&.library_id == library.id

    raise InvalidFolder, "Folder does not belong to this library"
  end

  def build_path(folder)
    result = []
    visited_ids = {}
    current_folder = folder

    while current_folder
      raise InvalidFolder, "Folder hierarchy contains a cycle" if visited_ids[current_folder.id]

      visited_ids[current_folder.id] = true
      result.unshift(current_folder)
      parent_id = current_folder.parent_folder_id
      current_folder = parent_id.present? ? folders_by_id[parent_id] : nil
      raise InvalidFolder, "Folder hierarchy leaves this library" if parent_id.present? && current_folder.nil?
    end

    result
  end
end
