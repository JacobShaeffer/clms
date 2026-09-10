module ContentTables
  class PageNavigation
    PURPOSE = "content-table-page-navigation"
    EXPIRATION = 1.hour

    def self.token_for(user:, records:)
      verifier.generate(
        {
          "user_id" => user.id,
          "content_ids" => Array(records).map(&:id)
        },
        purpose: PURPOSE,
        expires_in: EXPIRATION
      )
    end

    def self.content_ids_for(user:, token:)
      return [] unless token.is_a?(String) && token.present?

      payload = verifier.verified(token, purpose: PURPOSE)
      return [] unless payload.is_a?(Hash) && payload["user_id"] == user.id

      Array(payload["content_ids"])
        .filter_map { |id| Integer(id, exception: false) }
        .select(&:positive?)
        .uniq
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, TypeError
      []
    end

    def self.verifier
      Rails.application.message_verifier(PURPOSE)
    end
    private_class_method :verifier
  end
end
