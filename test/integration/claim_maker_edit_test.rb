require "test_helper"

# The employee may correct their own claim until the money is out. A claim that was
# already sent (or already approved) goes back to L1 after the edit, so nobody's
# approval stays on figures they never saw. A paid claim (UTR recorded) is closed.
class ClaimMakerEditTest < ActionDispatch::IntegrationTest
  setup do
    @emp = user("1025")
    @l1  = @emp.reporting_manager
    @fin = user("FIN001")
    @emp.update!(l2_manager: nil, finance_approver: @fin)
  end

  test "a claim pending with L1 can still be edited and goes to L1 again" do
    claim = sent_claim
    assert claim.submitted?
    assert claim.maker_editable?
    assert claim.reapproval_on_edit?

    sign_in @emp
    get tours_path(type: "local")
    assert_match edit_tour_claim_path(claim.tour), response.body

    get edit_tour_claim_path(claim.tour)
    assert_response :success
    assert_match "already sent for approval", response.body
    assert_match "Save &amp; Send Again", response.body

    patch tour_claim_path(claim.tour), params: { tour_claim: { general_description: "corrected bill" } }
    assert_redirected_to tours_path(type: "local")
    assert_match "sent again to L1", flash[:notice]
    claim.reload
    assert_equal "submitted", claim.status
    assert_equal "corrected bill", claim.general_description
    assert claim.activity_logs.exists?(action: "claim_edited_resubmitted")
  end

  test "an approved claim edited by the employee loses its approval and starts again at L1" do
    claim = approved_claim
    assert claim.approved?
    assert claim.reapproval_on_edit?

    sign_in @emp
    get edit_tour_claim_path(claim.tour)
    assert_response :success
    assert_match "already approved", response.body

    assert_difference -> { Notification.where(user: @l1, kind: "claim_pending").count }, 1 do
      patch tour_claim_path(claim.tour), params: { tour_claim: { general_description: "one bill was wrong" } }
    end
    assert_redirected_to tours_path(type: "local")
    claim.reload
    assert_equal "submitted", claim.status
    assert_nil claim.approved_at
    assert_nil claim.approved_by_id
    assert_nil claim.l1_approved_at
    assert_equal @l1, claim.l1_approver
    assert claim.activity_logs.exists?(action: "claim_edited_resubmitted")
  end

  test "an edited approved claim leaves the payment advice list until it is approved again" do
    claim = approved_claim
    assert_includes TourClaim.awaiting_payment, claim
    claim.resend_after_edit!(by: @emp)
    assert_not_includes TourClaim.awaiting_payment.reload, claim.reload
  end

  test "a claim whose payment UTR is recorded can no longer be edited" do
    claim = approved_claim
    assert claim.record_payment!(utr: "SBIN0099", by: @fin), claim.errors.full_messages.to_sentence
    claim.reload
    assert claim.paid?
    refute claim.reapproval_on_edit?
    refute claim.maker_editable?

    sign_in @emp
    get tours_path(type: "local")
    assert_no_match(/#{Regexp.escape(edit_tour_claim_path(claim.tour))}/, response.body)
    patch tour_claim_path(claim.tour), params: { tour_claim: { general_description: "too late" } }
    assert_response :redirect   # CanCan: not allowed
    assert_equal "approved", claim.reload.status
    assert_equal "SBIN0099", claim.utr_no
  end

  test "a rejected claim stays closed" do
    claim = sent_claim
    claim.reject!(by: @l1, remark: "not payable")
    claim.reload
    refute claim.maker_editable?
    refute claim.reapproval_on_edit?
  end

  test "a returned claim is edited the old way – no re-approval notice, Save stays" do
    claim = sent_claim
    claim.return!(by: @l1, remark: "attach the bill")
    claim.reload
    assert claim.employee_editable?
    refute claim.reapproval_on_edit?

    sign_in @emp
    get edit_tour_claim_path(claim.tour)
    assert_response :success
    assert_no_match(/already sent for approval/, response.body)
    patch tour_claim_path(claim.tour), params: { commit_action: "save", tour_claim: { general_description: "bill attached" } }
    assert_equal "returned", claim.reload.status   # plain save, not sent
    assert_equal "bill attached", claim.general_description
  end

  private

  # A Local Mileage claim of the open month, sent to L1.
  def sent_claim
    month = LocalMileagePeriod.new(@emp).month
    tour = Tour.create!(user: @emp, tour_type: "local", general_description: "local travel milage claim")
    claim = TourClaim.build_for(tour.reload)
    claim.claim_local_travels.build(travel_date: month, place_from: "Office", place_to: "Field",
                                    travel_mode: mode("Public Transport"), kilometers: 10, amount: 250, purpose: "SHG meeting")
    claim.bank_account = @emp.bank_accounts.first
    claim.save!
    claim.submit!(by: @emp)
    claim.reload
  end

  def approved_claim
    claim = sent_claim
    claim.forward!(by: @l1, remark: "ok")
    claim.reload.approve!(by: @fin, remark: "paid next week")
    claim.reload
  end
end
