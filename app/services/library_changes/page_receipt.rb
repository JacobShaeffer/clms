module LibraryChanges
  class PageReceipt
    HEADER = "X-Library-Edit-Receipt".freeze
    SESSION_HEADER = "X-Library-Page-Session".freeze

    def self.issue(changes:, user:, page_session:)
      return if changes.empty? || !page_session.is_a?(String) || !page_session.match?(/\A[\w-]{36}\z/)

      version = changes.first.library_version
      verifier.generate({
        ids: changes.map(&:id).sort, batch_key: changes.first.batch_key,
        generations: changes.sort_by(&:id).map(&:replay_generation),
        user_id: user.id, library_id: version.library_id, version_id: version.id, page_session:
      }, purpose: :library_page)
    end

    def self.resolve(receipt:, user:, library:, page_session:)
      data = verifier.verified(receipt, purpose: :library_page)&.symbolize_keys if receipt.is_a?(String)
      unless data && data[:user_id] == user.id && data[:library_id] == library.id &&
          data[:version_id] == library.current_version_id && data[:page_session] == page_session
        raise InvalidUndo, "This page edit is no longer available."
      end
      changes = library.current_version.library_changes.where(id: data[:ids], user_id: user.id, batch_key: data[:batch_key]).order(:id).to_a
      unless changes.map(&:id) == data[:ids] && changes.map(&:replay_generation) == data[:generations]
        raise InvalidUndo, "This edit has changed or is no longer available."
      end
      changes
    end

    def self.verifier
      Rails.application.message_verifier(:library_edit_receipt)
    end
  end
end
