module ContentTables
  class Coordinator
    attr_reader :definition, :state, :pagy, :records

    def self.call(user:, definition:, params:, paginator:)
      new(user:, definition:, params:, paginator:).call
    end

    def initialize(user:, definition:, params:, paginator:)
      @user = user
      @definition = definition
      @params = params
      @paginator = paginator

      raise ArgumentError, "paginator must be callable" unless paginator.respond_to?(:call)
    end

    def call
      @state = State.new(user:, definition:, params:).apply_request!
      relation = definition.relation_for(state)
      @pagy, @records = paginate(relation)

      if pagy.page > pagy.last
        state.clamp_page!(pagy.last)
        @pagy, @records = paginate(relation)
      end

      state.persist!
      self
    end

    private

    attr_reader :user, :params, :paginator

    def paginate(relation)
      paginator.call(relation:, page: state.page, per_page: state.per_page)
    end
  end
end
