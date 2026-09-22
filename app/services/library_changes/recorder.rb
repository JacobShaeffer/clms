require "set"

module LibraryChanges
  class Recorder
    def self.call(...)
      new(...).call
    end

    def self.folder_key(folder_or_id)
      "folder:#{folder_or_id.respond_to?(:id) ? folder_or_id.id : folder_or_id}"
    end

    def self.content_key(folder_or_id, content_or_id)
      folder_id = folder_or_id.respond_to?(:id) ? folder_or_id.id : folder_or_id
      content_id = content_or_id.respond_to?(:id) ? content_or_id.id : content_or_id
      "content:#{folder_id}:#{content_id}"
    end

    def initialize(
      library_version:,
      user:,
      action_type:,
      details:,
      targets:,
      batch_key: SecureRandom.uuid,
      dependency_resource_keys: [],
      required_folder_ids: [],
      dependency_change_ids: []
    )
      @library_version = library_version
      @user = user
      @action_type = action_type
      @details = details
      @targets = targets
      @batch_key = batch_key
      @dependency_resource_keys = dependency_resource_keys
      @required_folder_ids = required_folder_ids
      @dependency_change_ids = dependency_change_ids
    end

    def call
      library_version.transaction do
        prerequisite_ids = resolved_prerequisite_ids
        change = library_version.library_changes.create!(
          user:,
          action_type:,
          details:,
          batch_key:
        )
        targets.each do |attributes|
          change.library_change_targets.create!(target_attributes(attributes))
        end
        prerequisite_ids.each do |prerequisite_id|
          change.dependency_links.create!(prerequisite_change_id: prerequisite_id)
        end
        change
      end
    end

    private

    attr_reader :library_version, :user, :action_type, :details, :targets,
      :batch_key, :dependency_resource_keys, :required_folder_ids,
      :dependency_change_ids

    def resolved_prerequisite_ids
      ids = dependency_change_ids.map(&:to_i)
      ids.concat(latest_pending_change_ids_for_resources(dependency_resource_keys))
      ids.concat(pending_folder_creations.pluck(:id))
      ids.select(&:positive?).uniq
    end

    def latest_pending_change_ids_for_resources(keys)
      return [] if keys.blank?

      rows = library_version.library_changes.pending
        .joins(:library_change_targets)
        .where(library_change_targets: { resource_key: keys })
        .pluck("library_change_targets.resource_key", "library_changes.id")
      rows.group_by(&:first).values.map do |resource_rows|
        resource_rows.max_by(&:last).last
      end
    end

    def pending_folder_creations
      return library_version.library_changes.none if required_folder_ids.blank?

      library_version.library_changes.pending
        .joins(:library_change_targets)
        .where(
          library_change_targets: {
            target_kind: "folder",
            target_id: required_folder_ids,
            effect: "new"
          }
        )
        .distinct
    end

    def target_attributes(attributes)
      normalized = attributes.deep_symbolize_keys
      target_details = normalized.fetch(:details, {}).stringify_keys
      target_details["path"] ||= target_path(normalized)
      normalized.merge(details: target_details)
    end

    def target_path(attributes)
      folder = folders_by_id[attributes[:folder_id].to_i]
      names = []
      visited_ids = Set.new
      while folder && visited_ids.add?(folder.id)
        names.unshift(folder.name)
        folder = folders_by_id[folder.parent_folder_id]
      end
      names << attributes[:label] if attributes[:target_kind].to_s == "content"
      "/#{names.join('/')}"
    end

    def folders_by_id
      @folders_by_id ||= library_version.library_folders.to_a.index_by(&:id)
    end
  end
end
