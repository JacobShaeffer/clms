module LibraryBuilds
  class Source
    # VERSIONING MAINTENANCE: whenever versioning starts saving another field or
    # file reference, update this adapter and its tests to prefer that saved value.
    # Do not infer historical file bytes from file_checksum or snapshot metadata.
    Result = Data.define(:contents, :folders, :placements, :modules, :metadata_types,
      :metadata, :content_metadata, :files)

    def self.call(build:)
      new(build:).call
    end

    def initialize(build:)
      @build = build
    end

    def call
      options = ApplicationRecord.connection.transaction_open? ? {} : { isolation: :repeatable_read }
      ApplicationRecord.transaction(**options) do
        version = LibraryVersion.find(build.library_version_id)
        raise Error, "The source version must be locked" unless version.locked?

        folders = version.library_folders.order(:id).map do |folder|
          { id: folder.id, folder_name: folder.name, parent_id: folder.parent_folder_id, logo_id: folder.logo_id }
        end
        placements = version.library_folder_contents.order(:library_folder_id, :content_id)
          .pluck(:content_id, :library_folder_id).map { |id, folder_id| { id:, folder_id: } }
        records = Content.where(id: placements.map { |row| row[:id] }.uniq).with_attached_file.order(:id).to_a
        files = []
        contents = records.map do |content|
          blob = required_blob(content.file, "Content #{content.id}")
          extension = File.extname(blob.filename.to_s).downcase
          unless Content::ALLOWED_FILE_EXTENSIONS.include?(extension) && Content::ALLOWED_FILE_CONTENT_TYPES.include?(blob.content_type)
            raise Error, "Content #{content.id} has an unsupported file type"
          end
          name = filename(content.id, blob, extension)
          files << { blob:, path: "content/#{name}" }
          { id: content.id, title: content.display_title.presence || content.title,
            description: content.description, file_name: name, file_size: blob.byte_size,
            year_of_publication: content.year_of_publication, additional_notes: content.additional_notes }
        end
        unless contents.map { |row| row[:id] }.sort == placements.map { |row| row[:id] }.uniq.sort
          raise Error, "One or more placed content items are unavailable"
        end

        modules = version.library.selected_modules.order(:id).map do |mod|
          { id: mod.id, module_name: mod.folder_name, icon_id: mod.icon_id }
        end
        asset_ids = (folders.pluck(:logo_id) + modules.pluck(:icon_id) + [ version.library.banner_id ]).compact.uniq
        assets = LibraryAsset.where(id: asset_ids).with_attached_image.index_by(&:id)
        asset_paths = asset_ids.to_h do |id|
          asset = assets.fetch(id) { raise Error, "Asset #{id} is unavailable" }
          blob = required_blob(asset.image, "Asset #{id}")
          raise Error, "Asset #{id} is not a PNG image" unless blob.content_type == "image/png"

          path = "assets/#{filename(id, blob, '.png')}"
          files << { blob:, path: }
          [ id, path ]
        end
        folders.each { |row| row[:logo] = asset_paths[row.delete(:logo_id)] }
        modules.each { |row| row[:logo] = asset_paths.fetch(row.delete(:icon_id)) }

        types, metadata, links = current_metadata(records.map(&:id))
        blobs = ActiveStorage::Blob.where(id: files.map { |file| file[:blob].id }.uniq).order(:id).lock.to_a
        raise Error, "One or more source files are unavailable" unless blobs.length == files.map { |file| file[:blob].id }.uniq.length

        build.working_files.attach(blobs) if blobs.any?
        Result.new(contents:, folders:, placements:, modules:, metadata_types: types,
          metadata:, content_metadata: links, files:)
      end
    end

    private

    attr_reader :build

    def required_blob(attachment, label)
      raise Error, "#{label} has no attached file" unless attachment.attached?

      attachment.blob
    end

    def filename(id, blob, extension)
      stem = File.basename(blob.filename.to_s, File.extname(blob.filename.to_s))
        .unicode_normalize(:nfc).gsub(/[^[:alnum:]_-]+/, "_").byteslice(0, 120).scrub("")
      "#{id}-#{stem.presence || 'file'}#{extension}"
    end

    def current_metadata(content_ids)
      types, values, links = {}, {}, []
      ContentMetadatum.where(content_id: content_ids).joins(metadata: :metadata_type)
        .distinct.order(:content_id, :metadata_id)
        .pluck(:content_id, :metadata_id, "metadata.name", "metadata.metadata_type_id", "metadata_types.name")
        .each do |content_id, metadata_id, name, type_id, type_name|
          types[type_id] = { id: type_id, type_name: }
          values[metadata_id] = { id: metadata_id, meta_name: name, type_id:, type_name: }
          links << { content_id:, metadata_id: }
        end
      [ types.values.sort_by { |row| row[:id] }, values.values.sort_by { |row| row[:id] }, links ]
    end
  end
end
