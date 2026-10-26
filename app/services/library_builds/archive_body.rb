module LibraryBuilds
  class ArchiveBody
    def initialize(file)
      @file = file
    end

    def each
      while chunk = @file.read(64.kilobytes)
        yield chunk
      end
    ensure
      close
    end

    def close
      @file.close unless @file.closed?
    end
  end
end
