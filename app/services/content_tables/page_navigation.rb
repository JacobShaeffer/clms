module ContentTables
  class PageNavigation
    PURPOSE = "content-table-page-navigation"
    EXPIRATION = 1.hour
    Context = Data.define(:content_ids, :table_id)

    def self.token_for(user:, records:, table_id:)
      verifier.generate(
        {
          "user_id" => user.id,
          "content_ids" => Array(records).map(&:id),
          "table_id" => table_id.to_s
        },
        purpose: PURPOSE,
        expires_in: EXPIRATION
      )
    end

    def self.context_for(user:, token:)
      return empty_context unless token.is_a?(String) && token.present?

      payload = verifier.verified(token, purpose: PURPOSE)
      return empty_context unless payload.is_a?(Hash) && payload["user_id"] == user.id

      table_id = payload["table_id"]
      return empty_context unless table_id.is_a?(String) && table_id.present?

      content_ids = Array(payload["content_ids"])
        .filter_map { |id| Integer(id, exception: false) }
        .select(&:positive?)
        .uniq

      Context.new(content_ids:, table_id:)
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, TypeError
      empty_context
    end

    def self.content_ids_for(user:, token:)
      context_for(user:, token:).content_ids
    end

    def self.empty_context
      Context.new(content_ids: [], table_id: nil)
    end
    private_class_method :empty_context

    def self.verifier
      Rails.application.message_verifier(PURPOSE)
    end
    private_class_method :verifier
  end
end
