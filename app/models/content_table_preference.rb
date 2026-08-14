class ContentTablePreference < ApplicationRecord
  belongs_to :user

  validates :table_key, presence: true, uniqueness: { scope: :user_id }
  validate :state_must_be_an_object

  def self.save_state!(user:, table_key:, state:)
    raise ArgumentError, "user must be persisted" unless user&.persisted?
    raise ArgumentError, "table_key is required" if table_key.blank?
    raise ArgumentError, "state must be an object" unless state.is_a?(Hash)

    saved_at = Time.current
    upsert_all(
      [ {
        user_id: user.id,
        table_key:,
        state:,
        created_at: saved_at,
        updated_at: saved_at
      } ],
      unique_by: [ :user_id, :table_key ],
      update_only: %i[state updated_at],
      record_timestamps: false
    )

    find_by!(user:, table_key:)
  end

  private

  def state_must_be_an_object
    errors.add(:state, "must be an object") unless state.is_a?(Hash)
  end
end
