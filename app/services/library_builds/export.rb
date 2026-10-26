require "tmpdir"
require "digest"
require "zip"

module LibraryBuilds
  class Export
    def self.call(build:, generation:)
      new(build:, generation:).call
    end

    def initialize(build:, generation:)
      @build, @generation = build, generation
      @storage = Storage.new(build)
    end

    def call
      storage.with_lock do
        storage.cleanup
        build.reload
        next false unless build.generation == generation && (build.queued? || build.exporting?)

        begin
          build.update!(status: "exporting", started_at: Time.current, last_error: nil)
          build.working_files.detach
          stage = Pathname.new(Dir.mktmpdir("stage-", storage.root))
          folder = stage.join("export")
          FileUtils.mkdir_p([ folder.join("content"), folder.join("assets") ])
          source = Source.call(build:)
          create_module_folders(source, folder)
          copy_files(source, folder)
          SqliteWriter.call(source:, path: folder.join("library.db"))
          package(folder, stage.join("export.zip"))

          destination = storage.generation_path(generation)
          File.rename(stage, destination)
          build.with_lock do
            raise Error, "The build generation changed" unless build.generation == generation

            build.update!(status: "ready", published_generation: generation,
              published_at: Time.current, completed_at: Time.current, last_error: nil)
          end
          true
        rescue StandardError => error
          build.update!(status: "failed", completed_at: Time.current,
            last_error: "#{error.class}: #{error.message}".truncate(2000))
          raise
        ensure
          build.working_files.detach
          storage.cleanup
        end
      end
    end

    private

    attr_reader :build, :generation, :storage

    def create_module_folders(source, folder)
      names = source.modules.map { |mod| mod.fetch(:module_name) }
      return if names.empty?

      names.each do |name|
        if name.blank? || %w[. ..].include?(name) || name.include?("/") || name.include?("\\") || name.include?("\0")
          raise Error, "Module folder name #{name.inspect} must be a single folder name"
        end
      end
      raise Error, "Selected modules must have distinct folder names" unless names.uniq.length == names.length

      FileUtils.mkdir_p(names.map { |name| folder.join("modules", name) })
    end

    def copy_files(source, folder)
      source.files.each do |file|
        destination = folder.join(file[:path])
        blob = file[:blob]
        blob.open(tmpdir: folder.parent) do |input|
          File.open(destination, "wb", 0o600) { |output| IO.copy_stream(input, output) }
        end
        unless destination.size == blob.byte_size && Digest::MD5.file(destination).base64digest == blob.checksum
          raise ActiveStorage::IntegrityError, "Copied file failed integrity validation"
        end
      end
    end

    def package(folder, archive)
      Zip::File.open(archive, create: true) do |zip|
        zip.mkdir("export")
        folder.glob("**/*", File::FNM_DOTMATCH).sort.each do |path|
          next if path.basename.to_s == "."

          entry = "export/#{path.relative_path_from(folder)}"
          if path.directory?
            zip.mkdir(entry)
          else
            zip.add(entry, path)
          end
        end
      end
    end
  end
end
