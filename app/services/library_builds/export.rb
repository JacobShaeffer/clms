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
        [ "export", "export/content", "export/assets" ].each { |directory| zip.mkdir(directory) }
        folder.glob("**/*").select(&:file?).sort.each do |path|
          zip.add("export/#{path.relative_path_from(folder)}", path)
        end
      end
    end
  end
end
