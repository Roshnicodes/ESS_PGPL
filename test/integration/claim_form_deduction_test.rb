require "test_helper"

# The person filling the claim can enter Deduction Amt. / Deduction Remark on each line.
class ClaimFormDeductionTest < ActionDispatch::IntegrationTest
  test "employee enters a deduction with its remark; total is amount minus deduction" do
    emp = user("1025"); am = user("AM001")
    tour = emp.tours.create!(send_now: true, from_date: Date.current - 6, to_date: Date.current - 4,
      tour_visits_attributes: [ { visit_date: Date.current - 6, place: "Jhabua", planned_activity: "SHG" } ])
    tour.approve!(by: am)
    sign_in emp
    get new_tour_claim_path(tour)
    assert_response :success
    assert_match 'name="tour_claim[claim_city_travels_attributes][0][deduction_amount]"', response.body
    assert_match 'name="tour_claim[claim_city_travels_attributes][0][deduction_remark]"', response.body

    line = { travel_date: tour.from_date, departure_city: "Bhopal", arrival_city: "Jhabua", travel_mode_id: mode("Bus").id, amount: 500 }
    post tour_claim_path(tour), params: { commit_action: "save", tour_claim: { claim_city_travels_attributes: { "0" => line.merge(deduction_amount: 50) } } }
    assert_response :unprocessable_entity                                  # deduction without a remark
    post tour_claim_path(tour), params: { commit_action: "save", tour_claim: { claim_city_travels_attributes: { "0" => line.merge(deduction_amount: 50, deduction_remark: "Ticket partly refunded") } } }
    l = tour.reload.tour_claim.claim_city_travels.first
    assert_equal [ 500, 50, 450 ], [ l.amount.to_i, l.deduction_amount.to_i, l.total_amount.to_i ]
    assert_equal "Ticket partly refunded", l.deduction_remark
  end
end
