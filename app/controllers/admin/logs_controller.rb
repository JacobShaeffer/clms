class Admin::LogsController < Admin::BaseController
  def index
    @logs_url = ENV["ADMIN_LOGS_URL"].presence
  end
end
