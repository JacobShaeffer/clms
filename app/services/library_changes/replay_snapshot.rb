module LibraryChanges
  # Save only the records touched by an edit, plus membership guards for its tree.
  # This lets redo restore identities without replacing unrelated library data.
  class ReplaySnapshot
    FOLDER_ATTRIBUTES = LibraryFolderOperations::Remove::FOLDER_SNAPSHOT_ATTRIBUTES
    PLACEMENT_ATTRIBUTES = LibraryFolderOperations::Remove::PLACEMENT_SNAPSHOT_ATTRIBUTES

    def self.rows(records, attributes)
      records.to_h do |record|
        values = record.attributes.slice(*attributes)
        %w[created_at updated_at].each { |key| values[key] = record.public_send(key).iso8601(6) }
        [ record.id.to_s, values ]
      end
    end

    def self.world(version)
      {
        "folders" => rows(version.library_folders.order(:id), FOLDER_ATTRIBUTES),
        "placements" => rows(version.library_folder_contents.order(:id), PLACEMENT_ATTRIBUTES)
      }
    end

    def initialize(change)
      @change = change
      details = change.details
      @folder_ids = [ details["folder_id"] ].compact if %w[add_folder move_folder].include?(change.action_type)
      @folder_ids ||= Array(details["folder_ids"])
      @placement_ids = [ details["placement_id"], details["source_placement_id"], details["destination_placement_id"] ].compact
      @placement_ids.concat(Array(details["placement_ids"]))
      current = self.class.world(change.library_version)
      if %w[add_folder move_folder duplicate_folder].include?(change.action_type)
        loop do
          descendants = current["folders"].values.select { |row| @folder_ids.include?(row["parent_folder_id"]) }.map { |row| row["id"] }
          expanded = (@folder_ids + descendants).uniq
          break if expanded == @folder_ids
          @folder_ids = expanded
        end
      end
      @placement_ids.concat(current["placements"].values.select { |row| @folder_ids.include?(row["library_folder_id"]) }.map { |row| row["id"] })
      @folder_ids = @folder_ids.uniq
      @placement_ids = @placement_ids.uniq
      known = Array(details["placement_snapshots"]) + [ details["placement_snapshot"] ].compact
      known.concat(current["placements"].values.select { |row| @placement_ids.include?(row["id"]) })
      @placement_keys = known.map { |row| [ row["library_folder_id"], row["content_id"] ] }
      if details["content_id"]
        %w[folder_id source_folder_id destination_folder_id].each do |key|
          @placement_keys << [ details[key], details["content_id"] ] if details[key]
        end
      end
      @placement_keys.uniq!
      context_ids = current["folders"].values.select { |row| @folder_ids.include?(row["id"]) }.filter_map { |row| row["parent_folder_id"] }
      context_keys = case change.action_type
      when "add_folder" then %w[parent_folder_id]
      when "move_folder" then %w[source_parent_folder_id destination_folder_id]
      when "remove_folder" then %w[source_parent_folder_id]
      when "duplicate_folder" then %w[destination_folder_id]
      when "move_content" then %w[source_folder_id destination_folder_id]
      else %w[folder_id]
      end
      context_ids.concat(context_keys.filter_map { |key| details[key] })
      @context_folder_ids = []
      context_ids.each do |id|
        visited = Set.new
        while id && visited.add?(id)
          @context_folder_ids << id unless @folder_ids.include?(id)
          id = current["folders"][id.to_s]&.fetch("parent_folder_id")
        end
      end
      @context_folder_ids.uniq!
    end

    def capture
      current = self.class.world(@change.library_version)
      {
        "folders" => @folder_ids.to_h { |id| [ id.to_s, current["folders"][id.to_s] ] },
        "placements" => @placement_ids.to_h { |id| [ id.to_s, current["placements"][id.to_s] ] },
        "context_folders" => @context_folder_ids.to_h { |id| [ id.to_s, current["folders"][id.to_s] ] },
        "placement_keys" => @placement_keys.map do |folder_id, content_id|
          ids = current["placements"].values.select { |row| row["library_folder_id"] == folder_id && row["content_id"] == content_id }.map { |row| row["id"] }.sort
          { "folder_id" => folder_id, "content_id" => content_id, "ids" => ids }
        end,
        "children" => @folder_ids.to_h { |id| [ id.to_s, current["folders"].values.select { |row| row["parent_folder_id"] == id }.map { |row| row["id"] }.sort ] },
        "contents" => @folder_ids.to_h { |id| [ id.to_s, current["placements"].values.select { |row| row["library_folder_id"] == id }.map { |row| row["id"] }.sort ] }
      }
    end

    def self.verify!(expected, current)
      expected.fetch("context_folders", {}).each do |id, row|
        unless comparable(current["folders"][id]) == comparable(row)
          raise InvalidUndo, "This edit is blocked because a required folder has changed."
        end
      end
      %w[folders placements].each do |kind|
        expected.fetch(kind).each do |id, row|
          actual = current.fetch(kind)[id]
          unless comparable(actual) == comparable(row)
            raise InvalidUndo, "This edit is blocked because its folders or content have changed."
          end
        end
      end
      expected.fetch("placement_keys").each do |key|
        ids = current["placements"].values.select { |row| row["library_folder_id"] == key["folder_id"] && row["content_id"] == key["content_id"] }.map { |row| row["id"] }.sort
        raise InvalidUndo, "This edit is blocked because its content placements have changed." unless ids == key["ids"]
      end
      { "children" => [ "folders", "parent_folder_id" ], "contents" => [ "placements", "library_folder_id" ] }.each do |guard, (kind, parent_key)|
        expected.fetch(guard).each do |id, ids|
          actual_ids = current[kind].values.select { |row| row[parent_key] == id.to_i }.map { |row| row["id"] }.sort
          raise InvalidUndo, "This edit is blocked because its folder tree has changed." unless actual_ids == ids
        end
      end
    end

    def self.comparable(row)
      row&.except("created_at", "updated_at")
    end

    def self.simulate!(snapshot, current)
      verify!(snapshot.fetch("undone"), current)
      %w[folders placements].each do |kind|
        snapshot.fetch("applied").fetch(kind).each do |id, row|
          row ? current[kind][id] = row : current[kind].delete(id)
        end
      end
      snapshot.fetch("applied")["folders"].each_value do |row|
        next unless row
        if row["parent_folder_id"] && !current["folders"].key?(row["parent_folder_id"].to_s)
          raise InvalidUndo, "A required parent folder is no longer available."
        end
      end
      snapshot.fetch("applied")["placements"].each_value do |row|
        if row && !current["folders"].key?(row["library_folder_id"].to_s)
          raise InvalidUndo, "A required content folder is no longer available."
        end
      end
    end

    def self.apply!(snapshot)
      undone = snapshot.fetch("undone")
      applied = snapshot.fetch("applied")
      applied["placements"].each do |id, row|
        LibraryFolderContent.find(id).destroy! if row.nil? && undone["placements"][id]
      end
      removed_folders = undone["folders"].values.compact.select { |row| applied["folders"][row["id"].to_s].nil? }
      until removed_folders.empty?
        leaves, removed_folders = removed_folders.partition { |row| removed_folders.none? { |child| child["parent_folder_id"] == row["id"] } }
        raise InvalidUndo, "The folder tree cannot be restored." if leaves.empty?
        leaves.each { |row| LibraryFolder.find(row["id"]).destroy! }
      end
      pending = applied["folders"].values.compact
      until pending.empty?
        ready, pending = pending.partition { |row| row["parent_folder_id"].nil? || LibraryFolder.exists?(row["parent_folder_id"]) }
        raise InvalidUndo, "A required parent folder is no longer available." if ready.empty?
        ready.each do |row|
          previous = undone["folders"][row["id"].to_s]
          if previous
            changes = comparable(row).reject { |key, value| previous[key] == value }
            LibraryFolder.find(row["id"]).update!(changes) if changes.any?
          else
            LibraryFolder.create!(row)
          end
        end
      end
      applied["placements"].each do |id, row|
        LibraryFolderContent.create!(row) if row && undone["placements"][id].nil?
      end
    end
  end
end
