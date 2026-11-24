class Admin::UsersController < Admin::BaseController
  SORT_COLUMNS = %w[name email role status].freeze
  before_action :set_user, only: %i[edit update toggle_active]

  def index
    @query = params[:q].is_a?(String) ? params[:q].strip : ""
    @sort = SORT_COLUMNS.include?(params[:sort]) ? params[:sort] : "name"
    @direction = %w[asc desc].include?(params[:direction]) ? params[:direction] : "asc"

    @users = User.all
    if @query.present?
      search = "%#{User.sanitize_sql_like(@query)}%"
      @users = @users.where("users.name ILIKE :search OR users.email ILIKE :search", search:)
    end
    @users = @users.order(user_sort_expression.public_send(@direction), User.arel_table[:id].asc)
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new
    if valid_role? && password_confirmation_present? && @user.update(user_params)
      redirect_to admin_users_path, notice: "User created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    attributes = user_params.to_h
    if attributes["password"].blank? && attributes["password_confirmation"].blank?
      attributes.delete("password")
      attributes.delete("password_confirmation")
    end
    success = valid_role? && password_confirmation_present? && change_with_admin_guard { @user.update(attributes) }
    if success
      redirect_to admin_users_path, notice: "User updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def toggle_active
    success = change_with_admin_guard { @user.update(active: !@user.active?) }
    redirect_to admin_users_path, notice: success ? "User status updated." : nil,
      alert: success ? nil : @user.errors.full_messages.to_sentence
  end

  private

  def user_sort_expression
    users = User.arel_table
    case @sort
    when "email" then users[:email].lower
    when "role"
      User.roles.reduce(Arel::Nodes::Case.new(users[:role])) do |expression, (name, value)|
        expression.when(value).then(name.humanize.downcase)
      end
    when "status"
      Arel::Nodes::Case.new.when(users[:active].eq(true)).then("active").else("inactive")
    else users[:name].lower
    end
  end

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:name, :email, :role, :password, :password_confirmation)
  end

  def password_confirmation_present?
    password = user_params[:password]
    confirmation = user_params[:password_confirmation]
    return true if @user.persisted? && password.blank? && confirmation.blank?
    return true if password.present? && confirmation.present?

    @user.errors.add(:password_confirmation, "must be provided with the password")
    false
  end

  def valid_role?
    return true if User.roles.key?(user_params[:role].to_s)

    @user.errors.add(:role, "is invalid")
    false
  end

  def change_with_admin_guard
    User.transaction do
      # Serialize changes to the set of administrators, including concurrent demotions.
      User.lock.order(:id).load
      @user.reload
      was_last_admin = @user.active? && @user.admin? && User.where(active: true, role: :admin).count == 1
      result = yield
      if result && was_last_admin && (!@user.active? || !@user.admin?)
        @user.errors.add(:base, "The last active administrator cannot be deactivated or demoted.")
        raise ActiveRecord::Rollback
      end
      result
    end || false
  end
end
