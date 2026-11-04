# Admin: every tour of every employee – view, edit, delete.
class Masters::AllToursController < ApplicationController
  before_action { raise CanCan::AccessDenied, "Only admin" unless current_user.admin? }

  ACTION_ORDER = <<~SQL.squish.freeze
    CASE
      WHEN tours.status IN ('submitted', 'l1_approved', 'l2_approved') THEN 0
      WHEN tour_claims.status IN ('submitted', 'l1_approved', 'extra_pending', 'finance_pending', 'finance_query') THEN 1
      WHEN tours.status = 'returned' OR tour_claims.status = 'returned' THEN 2
      WHEN tours.status = 'draft' OR tour_claims.status = 'draft'
        OR (tours.tour_type = 'local' AND tours.status = 'approved' AND tour_claims.id IS NULL) THEN 4
      ELSE 3
    END
  SQL

  def index
    # what needs action first: tours waiting for approval, then claims waiting for approval, then returned ones,
    # then finished / cancelled; tours and claims that are only saved (not sent) come last. Newest first inside each group.
    @tours = Tour.includes(:user, :approver, :l2_approver, :tour_claim).left_joins(:tour_claim)
                 .order(Arel.sql(ACTION_ORDER), created_at: :desc)
    if params[:q].present?
      q = "%#{Tour.sanitize_sql_like(params[:q].strip)}%"
      @tours = @tours.joins(:user).where("users.name ILIKE :q OR users.emp_code ILIKE :q", q: q)
    end
    @tours = @tours.where(status: params[:status]) if params[:status].present?
    @tours = @tours.where(tour_type: params[:type]) if params[:type].present?
    @tours = @tours.page(params[:page]).per(30)
  end
end
