require "pagy"

class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include Pagy::Method

  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :sign_out_deactivated_user

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  def sign_out_deactivated_user
    return unless user_signed_in? && !current_user.active?

    sign_out(current_user)
    redirect_to new_user_session_path, alert: "Your account has been deactivated."
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :name ])
  end

  def user_not_authorized
    redirect_to root_path, alert: "You are not authorized to perform that action."
  end
end
