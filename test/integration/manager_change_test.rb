require "test_helper"

# HR sets L-2 to "None" (or changes L-1 / L-2) in Employee List → what is still waiting at L1 follows it;
# new sends use it; anything already past L1 or approved is left as it was.
class ManagerChangeTest < ActionDispatch::IntegrationTest
  setup do
    @emp = user("1025"); @l1 = user("AM001"); @l2 = user("HR001")
    @emp.update!(l2_manager: @l2)
    @attrs = { send_now: true, tour_visits_attributes: [ { visit_date: Date.current - 5, place: "Indore", planned_activity: "Review" } ] }
  end

  def new_tour(from)
    @emp.tours.create!(@attrs.merge(from_date: from, to_date: from, tour_visits_attributes: [ { visit_date: from, place: "Indore", planned_activity: "Review" } ]))
  end

  test "L-2 set to None in the employee form: pending-at-L1 tour loses L2, L1 approval is then final" do
    waiting = new_tour(Date.current - 5)
    past_l1 = new_tour(Date.current - 10)
    past_l1.approve!(by: @l1)
    assert_equal @l2, waiting.l2_approver
    assert past_l1.l1_approved?

    sign_in user("ADMIN")
    patch masters_user_path(@emp), params: { user: { l2_manager_id: "" } }
    assert_redirected_to masters_users_path
    assert_nil @emp.reload.l2_manager_id

    assert_nil waiting.reload.l2_approver_id
    waiting.approve!(by: @l1)
    assert waiting.reload.approved?, "no L2 → L1 approval is final"
    assert_equal @l2, past_l1.reload.l2_approver            # already with L2 – not changed

    fresh = new_tour(Date.current - 15)
    assert_nil fresh.l2_approver_id
  end

  test "claim waiting at L1 follows a new L1 / L2" do
    tour = new_tour(Date.current - 6)
    tour.approve!(by: @l1); tour.approve!(by: @l2)
    claim = with_tasks(TourClaim.build_for(tour))
    claim.claim_city_travels.build(travel_date: tour.from_date, departure_city: "Bhopal", arrival_city: "Indore", travel_mode: mode("Bus"), amount: 300)
    claim.save!
    claim.submit!(by: @emp)
    assert_equal [ @l1, @l2 ], [ claim.l1_approver, claim.l2_approver ]

    new_l1 = user("MIS001")
    @emp.update!(reporting_manager: new_l1, l2_manager: nil)
    claim.reload
    assert_equal new_l1, claim.l1_approver
    assert_nil claim.l2_approver
  end

  test "draft made while L-2 was set, sent after L-2 set to None: goes to L1 only" do
    draft = @emp.tours.create!(@attrs.merge(send_now: false, from_date: Date.current - 7, to_date: Date.current - 7,
                                            tour_visits_attributes: [ { visit_date: Date.current - 7, place: "Indore", planned_activity: "Review" } ]))
    assert draft.draft?
    @emp.update!(l2_manager: nil)
    draft.reload.submit!(by: @emp)
    assert_nil draft.reload.l2_approver_id
    draft.approve!(by: @l1)
    assert draft.reload.approved?
  end
end
