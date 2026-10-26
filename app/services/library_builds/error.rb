module LibraryBuilds
  class Error < StandardError
    attr_reader :code

    def initialize(message, code: "build_failed")
      @code = code
      super(message)
    end
  end
end
