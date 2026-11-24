class Admin::ReportPeriod
  attr_reader :zone, :start_date, :end_date, :error

  def initialize(params)
    @zone = ActiveSupport::TimeZone[params[:timezone].to_s] || ActiveSupport::TimeZone["UTC"]

    today = Time.current.in_time_zone(zone).to_date
    if params[:start_date].present? || params[:end_date].present?
      @start_date = Date.iso8601(params[:start_date].to_s)
      @end_date = Date.iso8601(params[:end_date].to_s)
    else
      week = if params[:week].to_s.match?(/\A\d{4}-W\d{2}\z/)
        year, number = params[:week].split("-W").map(&:to_i)
        Date.commercial(year, number, 1)
      elsif params[:week].present?
        Date.iso8601(params[:week].to_s)
      else
        today
      end
      @start_date = week.beginning_of_week(:monday)
      @end_date = @start_date + 6
    end
    @error = "The end date must be on or after the start date." if end_date < start_date
  rescue Date::Error
    @error = "Enter valid dates."
  end

  def ready?
    zone.present? && error.blank? && start_date.present? && end_date.present?
  end

  def range
    zone.local(start_date.year, start_date.month, start_date.day).utc...zone.local(
      (end_date + 1).year, (end_date + 1).month, (end_date + 1).day
    ).utc
  end

  def params
    { timezone: zone.tzinfo.identifier, start_date: start_date.iso8601, end_date: end_date.iso8601 }
  end
end
