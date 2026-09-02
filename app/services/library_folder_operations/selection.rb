require "set"

module LibraryFolderOperations
  class Selection
    class InvalidSelection < ArgumentError; end

    TreeNode = Struct.new(:folder, :contents, :children, keyword_init: true)

    attr_reader :library, :library_version, :source_folder, :selected_folders,
      :direct_content_placements, :all_folders, :folder_ids, :content_ids

    def initialize(library:, source_folder_id:, folder_ids:, content_ids:, library_version: nil)
      @library = library
      @library_version = library_version || library.reload.current_version
      raise InvalidSelection, "The library does not have a current version." unless @library_version

      VersionGuard.ensure_current!(library:, library_version: @library_version)
      @all_folders = @library_version.library_folders.order(:name, :id).to_a
      @folders_by_id = @all_folders.index_by(&:id)
      @children_by_parent_id = @all_folders.group_by(&:parent_folder_id)
      @source_folder = resolve_optional_folder(source_folder_id, "source folder")
      @folder_ids = parse_ids(folder_ids, "folder")
      @content_ids = parse_ids(content_ids, "content")

      raise InvalidSelection, "Select at least one folder or content item." if @folder_ids.empty? && @content_ids.empty?

      @selected_folders = resolve_selected_folders
      @direct_content_placements = resolve_direct_content_placements
      @subtree_folders = build_subtree_folders
      @subtree_folder_ids = @subtree_folders.map(&:id).to_set
      @placements_by_folder_id = load_subtree_placements
    end

    def source_folder_id
      source_folder&.id
    end

    def subtree_folders
      @subtree_folders.dup
    end

    def blocked_folder_ids
      @subtree_folder_ids.dup
    end

    def subtree_content_placements
      @placements_by_folder_id.values.flatten
    end

    def children_for(folder)
      children_for_parent(folder.id)
    end

    def children_for_parent(parent_folder_id)
      Array(@children_by_parent_id[parent_folder_id]).sort_by { |folder| folder_sort_key(folder) }
    end

    def placements_for(folder)
      Array(@placements_by_folder_id[folder.id])
    end

    def removal_tree
      selected_folders.sort_by { |folder| folder_sort_key(folder) }.map { |folder| tree_node(folder) }
    end

    def folder!(value, label: "folder")
      id = parse_id(value, label)
      folder = @folders_by_id[id]
      raise_unavailable_folder!(id, label:) unless folder

      folder
    end

    def destination!(value, operation:)
      destination = folder!(value, label: "destination folder")
      if blocked_folder_ids.include?(destination.id)
        raise InvalidSelection, "A selected folder or one of its descendants cannot be the destination."
      end
      if operation.to_sym == :move && destination.id == source_folder_id
        raise InvalidSelection, "The selected items are already in that folder."
      end

      destination
    end

    private

    def resolve_optional_folder(value, label)
      return if value.nil? || value == ""

      folder!(value, label:)
    end

    def resolve_selected_folders
      folder_ids.map do |id|
        folder = @folders_by_id[id]
        raise_unavailable_folder!(id, label: "selected folder") unless folder
        unless folder.parent_folder_id == source_folder_id
          raise InvalidSelection, "Selected folders must be direct children of the open folder."
        end

        folder
      end
    end

    def resolve_direct_content_placements
      return [] if content_ids.empty?
      raise InvalidSelection, "Content cannot be selected from the library root." unless source_folder

      placements = LibraryFolderContent
        .where(
          library_version_id: library_version.id,
          library_folder_id: source_folder.id,
          content_id: content_ids
        )
        .includes(:content)
        .to_a
      if placements.length != content_ids.length
        raise InvalidSelection, "Selected content must be directly contained in the open folder."
      end

      placements.sort_by { |placement| content_sort_key(placement.content) }
    end

    def build_subtree_folders
      result = []
      visited_ids = Set.new
      selected_folders.sort_by { |folder| folder_sort_key(folder) }.each do |folder|
        collect_subtree(folder, result, visited_ids)
      end
      result
    end

    def collect_subtree(folder, result, visited_ids)
      raise InvalidSelection, "The selected folder hierarchy contains a cycle." if visited_ids.include?(folder.id)

      visited_ids << folder.id
      result << folder
      children_for(folder).each { |child| collect_subtree(child, result, visited_ids) }
    end

    def load_subtree_placements
      return {} if @subtree_folders.empty?

      LibraryFolderContent
        .where(
          library_version_id: library_version.id,
          library_folder_id: @subtree_folders.map(&:id)
        )
        .includes(:content)
        .to_a
        .group_by(&:library_folder_id)
        .transform_values do |placements|
          placements.sort_by { |placement| content_sort_key(placement.content) }
        end
    end

    def tree_node(folder)
      TreeNode.new(
        folder:,
        contents: placements_for(folder).map(&:content),
        children: children_for(folder).map { |child| tree_node(child) }
      )
    end

    def parse_ids(values, label)
      Array(values).map { |value| parse_id(value, label) }.uniq
    end

    def raise_unavailable_folder!(id, label:)
      folder_library_id = LibraryFolder.where(id:).pick(:library_id)
      if folder_library_id.present? && folder_library_id != library.id
        raise ActiveRecord::RecordNotFound, "#{label.titleize} not found"
      end

      raise InvalidSelection, "The #{label} is no longer available."
    end

    def parse_id(value, label)
      id = Integer(value, exception: false) if value.is_a?(String) || value.is_a?(Integer)
      raise InvalidSelection, "Invalid #{label} selection." unless id&.positive?

      id
    end

    def folder_sort_key(folder)
      [ folder.name.downcase, folder.id ]
    end

    def content_sort_key(content)
      [ content.title.downcase, content.id ]
    end
  end
end
