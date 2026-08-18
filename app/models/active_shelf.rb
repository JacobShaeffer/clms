class ActiveShelf < ApplicationRecord
  class LimitReached < StandardError; end

  MAXIMUM_PER_USER = 5
  DIRECTIONS = {
    "up" => -1,
    "down" => 1
  }.freeze

  belongs_to :user
  belongs_to :shelf

  scope :ordered, -> { order(:position, :id) }

  validates :shelf_id, uniqueness: { scope: :user_id }
  validates :position,
    numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAXIMUM_PER_USER },
    uniqueness: { scope: :user_id }
  validate :shelf_must_belong_to_user

  def self.activate!(user:, shelf:)
    validate_owner!(user:, shelf:)

    user.with_lock do
      normalize_positions!(user)
      existing = find_by(user:, shelf:)
      return existing if existing

      raise LimitReached, "Only five shelves can be active." if where(user:).count >= MAXIMUM_PER_USER

      create!(user:, shelf:, position: where(user:).count + 1)
    end
  end

  def self.prepend!(user:, shelf:)
    validate_owner!(user:, shelf:)

    user.with_lock do
      normalize_positions!(user)
      existing = find_by(user:, shelf:)
      return existing if existing

      records = where(user:).ordered.to_a
      records.pop&.destroy! if records.length >= MAXIMUM_PER_USER
      where(user:).update_all("position = -position")

      saved_at = Time.current
      records.each_with_index do |record, index|
        record.update_columns(position: index + 2, updated_at: saved_at)
      end

      create!(user:, shelf:, position: 1)
    end
  end

  def self.archive!(user:, shelf:)
    validate_owner!(user:, shelf:)

    user.with_lock do
      find_by(user:, shelf:)&.destroy!
      normalize_positions!(user)
    end
  end

  def self.move!(user:, shelf:, direction:)
    offset = DIRECTIONS[direction.to_s]
    raise ArgumentError, "direction must be up or down" unless offset

    validate_owner!(user:, shelf:)

    user.with_lock do
      normalize_positions!(user)
      active_shelf = find_by!(user:, shelf:)
      target = find_by(user:, position: active_shelf.position + offset)
      return active_shelf unless target

      original_position = active_shelf.position
      target_position = target.position
      saved_at = Time.current
      active_shelf.update_columns(position: 0, updated_at: saved_at)
      target.update_columns(position: original_position, updated_at: saved_at)
      active_shelf.update_columns(position: target_position, updated_at: saved_at)
      active_shelf
    end
  end

  def self.normalize_positions!(user)
    records = where(user:).ordered.to_a
    return if records.each_with_index.all? { |record, index| record.position == index + 1 }

    where(user:).update_all("position = -position")
    records.each_with_index do |record, index|
      record.update_columns(position: index + 1, updated_at: Time.current)
    end
  end
  private_class_method :normalize_positions!

  def self.validate_owner!(user:, shelf:)
    return if user&.persisted? && shelf&.persisted? && shelf.user_id == user.id

    raise ActiveRecord::RecordNotFound, "Shelf does not belong to the user"
  end
  private_class_method :validate_owner!

  private

  def shelf_must_belong_to_user
    return if shelf.blank? || user.blank? || shelf.user_id == user_id

    errors.add(:shelf, "must belong to the same user")
  end
end
