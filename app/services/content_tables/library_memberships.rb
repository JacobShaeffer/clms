module ContentTables
  class LibraryMemberships
    LibraryBadge = Data.define(:id, :name)

    def self.placements(library_scope:)
      LibraryFolderContent.joins(library_version: :library)
        .where(libraries: { id: library_scope.reselect(:id).reorder(nil) })
        .where(LibraryFolderContent.arel_table[:library_version_id].eq(Library.arel_table[:current_version_id]))
    end

    def initialize(content_ids:, library_scope:)
      @libraries_by_content_id = {}
      return if content_ids.empty?

      placements = LibraryFolderContent.arel_table
      libraries = Library.arel_table
      rows = self.class.placements(library_scope:).where(content_id: content_ids)
        .distinct.pluck(placements[:content_id], libraries[:id], libraries[:name])

      rows.each do |content_id, library_id, name|
        (@libraries_by_content_id[content_id] ||= []) << LibraryBadge.new(id: library_id, name:)
      end
      @libraries_by_content_id.each_value do |badges|
        badges.sort_by! { |badge| [ badge.name.downcase, badge.name, badge.id ] }
      end
    end

    def libraries_for(content)
      @libraries_by_content_id.fetch(content.id, [])
    end
  end
end
