# A. Travel city to city (start and end at headquarter)
class ClaimCityTravel < ApplicationRecord
  include ClaimLine
  belongs_to :travel_mode

  validates :travel_date, presence: true
  validates :departure_city, :arrival_city, presence: true, unless: :not_applicable?
  validates :ticket_quota, inclusion: { in: TourVisit::QUOTAS.values }
  before_validation { self.ticket_quota = "normal" unless travel_mode&.is_train? }   # quota only for trains

  def tatkal? = ticket_quota == "tatkal"
  def not_applicable? = !!travel_mode&.not_applicable?

  private

  # NA = no journey on this line: no ticket, no amount
  def compute_amount
    return unless not_applicable?
    self.amount = 0
    self.bill_ticket_no = nil
    self.departure_city = "NA" if departure_city.blank?   # columns are NOT NULL; the employee need not type them
    self.arrival_city = "NA" if arrival_city.blank?
  end
end
