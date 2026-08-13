require "test_helper"

class ActiveShelfTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.active_shelves.delete_all
    @shelf = shelves(:one)
  end

  test "activate stores the shelf in the next position and is idempotent" do
    first = ActiveShelf.activate!(user: @user, shelf: @shelf)

    assert_no_difference("ActiveShelf.count") do
      assert_equal first, ActiveShelf.activate!(user: @user, shelf: @shelf)
    end
    assert_equal 1, first.position
  end

  test "a user cannot activate more than five shelves" do
    shelves = [ @shelf ] + 5.times.map { |index| @user.shelves.create!(name: "Shelf #{index}") }
    shelves.first(5).each { |shelf| ActiveShelf.activate!(user: @user, shelf:) }

    assert_raises(ActiveShelf::LimitReached) do
      ActiveShelf.activate!(user: @user, shelf: shelves.last)
    end
  end

  test "a shelf must belong to the active shelf user" do
    active_shelf = ActiveShelf.new(user: @user, shelf: shelves(:two), position: 1)

    refute active_shelf.valid?
    assert_includes active_shelf.errors[:shelf], "must belong to the same user"
    assert_raises(ActiveRecord::RecordNotFound) do
      ActiveShelf.activate!(user: @user, shelf: shelves(:two))
    end
  end

  test "moving swaps adjacent persisted positions" do
    second_shelf = @user.shelves.create!(name: "Second")
    ActiveShelf.activate!(user: @user, shelf: @shelf)
    ActiveShelf.activate!(user: @user, shelf: second_shelf)

    ActiveShelf.move!(user: @user, shelf: second_shelf, direction: :up)

    assert_equal [ [ second_shelf.id, 1 ], [ @shelf.id, 2 ] ],
      @user.active_shelves.ordered.pluck(:shelf_id, :position)
  end

  test "archiving removes the record and compacts positions" do
    second_shelf = @user.shelves.create!(name: "Second")
    third_shelf = @user.shelves.create!(name: "Third")
    [ @shelf, second_shelf, third_shelf ].each do |shelf|
      ActiveShelf.activate!(user: @user, shelf:)
    end

    ActiveShelf.archive!(user: @user, shelf: second_shelf)

    assert_equal [ [ @shelf.id, 1 ], [ third_shelf.id, 2 ] ],
      @user.active_shelves.ordered.pluck(:shelf_id, :position)
  end

  test "database index prevents duplicate shelf records" do
    ActiveShelf.create!(user: @user, shelf: @shelf, position: 1)

    assert_raises(ActiveRecord::RecordNotUnique) do
      ActiveShelf.insert_all!([ { user_id: @user.id, shelf_id: @shelf.id, position: 2 } ])
    end
  end

  test "database index prevents duplicate position records" do
    ActiveShelf.create!(user: @user, shelf: @shelf, position: 1)
    other_shelf = @user.shelves.create!(name: "Other")

    assert_raises(ActiveRecord::RecordNotUnique) do
      ActiveShelf.insert_all!([ { user_id: @user.id, shelf_id: other_shelf.id, position: 1 } ])
    end
  end

  test "destroying a shelf removes its active record" do
    active_shelf = ActiveShelf.activate!(user: @user, shelf: @shelf)
    @shelf.destroy!
    refute ActiveShelf.exists?(active_shelf.id)
  end
end
