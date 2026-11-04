# Colleagues on tour on a day (default today): every Tour Plan that is approved or still waiting for approval
# and covers that day. Each row shows the tour's status; clicking an employee opens the tour's details.
class OnTourController < ApplicationController
  def index
    @date = (Date.parse(params[:date].to_s) rescue nil) || Date.current
    tours = Tour.type_tour.where(status: Tour::LIVE).where("tours.from_date <= :d AND tours.to_date >= :d", d: @date)
                .includes(:approver, :l2_approver, :approval_steps, :tour_visits, user: :location)
    if params[:q].present?
      q = "%#{Tour.sanitize_sql_like(params[:q].strip)}%"
      tours = tours.joins(:user).where("users.name ILIKE :q OR users.emp_code ILIKE :q OR users.designation ILIKE :q", q: q)
    end
    all = tours.to_a.sort_by { |t| [ t.user.name.to_s.downcase, t.from_date ] }
    @counts = { all: all.size, approved: all.count(&:approved?), pending: all.count { !_1.approved? } }
    @tours = case params[:status]
             when "approved" then all.select(&:approved?)
             when "pending"  then all.reject(&:approved?)
             else all
             end
  end
end
