require "test_helper"

# "NA" mode on a claim line = no journey: shows in both travel dropdowns, needs nothing but the date, amount stays 0
class NaTravelModeTest < ActiveSupport::TestCase
  include ClaimsHelper

  setup do
    @emp = user("1025"); @am = user("AM001")
    @tour = @emp.tours.create!(send_now: true, from_date: Date.current - 6, to_date: Date.current - 4, general_description: "Visit",
      tour_visits_attributes: [ { visit_date: Date.current - 6, place: "Jhabua", planned_activity: "SHG" } ])
    @tour.approve!(by: @am)
    @claim = with_tasks(TourClaim.build_for(@tour))
    @na = mode("NA")
  end

  test "NA is offered in A. Travel and B. Local Travel even when only active in the master" do
    assert @na.not_applicable?
    assert_includes city_travel_modes, @na
    assert_includes local_travel_modes, @na
    @na.update!(active: false)
    @city_travel_modes = @local_travel_modes = nil
    refute_includes city_travel_modes, @na
    refute_includes local_travel_modes, @na
  end

  test "NA lines need only the date and are always 0" do
    city = @claim.claim_city_travels.build(travel_date: @tour.from_date, travel_mode: @na, bill_ticket_no: "X1", amount: 500)
    local = @claim.claim_local_travels.build(travel_date: @tour.from_date, travel_mode: @na, meter_from: 1, meter_to: 9, kilometers: 8, amount: 70)
    @claim.claim_incidentals.build(expense_date: @tour.from_date, particular: "Photocopy", amount: 20)
    assert city.valid?, city.errors.full_messages.inspect
    assert local.valid?, local.errors.full_messages.inspect
    @claim.save!
    assert_equal 0, city.reload.amount
    assert_nil city.bill_ticket_no
    assert_equal 0, local.reload.amount
    assert_nil local.meter_from
    assert_equal 20, @claim.reload.grand_total
  end

  test "a normal mode still needs its fields" do
    line = @claim.claim_city_travels.build(travel_date: @tour.from_date, travel_mode: mode("Bus"))
    assert_not line.valid?
    assert line.errors[:departure_city].any?
  end
end
