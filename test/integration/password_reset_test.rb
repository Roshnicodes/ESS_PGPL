require "test_helper"

class PasswordResetTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @emp = user("1025")
    @emp.update_columns(email: "roshni@example.org")
    @relay_was = ENV["ESS_MAIL_RELAY_URL"]
    ENV["ESS_MAIL_RELAY_URL"] = "https://krai.asaindia.org/pgpless_notification.aspx"
  end
  teardown { ENV["ESS_MAIL_RELAY_URL"] = @relay_was }

  def reset_link
    params = enqueued_jobs.select { _1["job_class"] == "EssMailJob" }.last["arguments"].first
    assert_equal "password_reset", params["mail_type"]
    assert_equal "roshni@example.org", params["to_email"]
    assert_match %r{\Ahttps://hr\.asaindia\.org/pgpl/password/reset/[\w-]+\z}, params["link"]
    params["link"].delete_prefix("https://hr.asaindia.org/pgpl")
  end

  test "login page links to forgot password; reset link sets a new password once" do
    get new_user_session_path
    assert_match forgot_password_path, response.body

    post forgot_password_path, params: { emp_code: " 1025 " }
    assert_redirected_to forgot_password_path(sent: 1)
    path = reset_link

    get path
    assert_response :success
    patch path, params: { password: "newpass1", password_confirmation: "other" }
    assert_response :unprocessable_entity
    patch path, params: { password: "newpass1", password_confirmation: "newpass1" }
    assert_redirected_to new_user_session_path
    assert @emp.reload.valid_password?("newpass1")

    get path                                         # used once – gone
    assert_redirected_to forgot_password_path
  end

  test "unknown code looks the same and sends nothing; expired link is refused" do
    assert_no_enqueued_jobs(only: EssMailJob) { post forgot_password_path, params: { emp_code: "NOPE" } }
    assert_redirected_to forgot_password_path(sent: 1)

    post forgot_password_path, params: { emp_code: "1025" }
    path = reset_link
    travel 3.hours do
      get path
      assert_redirected_to forgot_password_path
    end
  end

  test "asking again within 2 minutes does not send a second mail" do
    post forgot_password_path, params: { emp_code: "1025" }
    assert_no_enqueued_jobs(only: EssMailJob) { post forgot_password_path, params: { emp_code: "1025" } }
  end
end

class TourClaimClarityTest < ActionDispatch::IntegrationTest
  test "approved tour with a saved claim: tour says Tour Approved, claim says not sent – two stamps" do
    emp = user("1025"); am = user("AM001")
    tour = emp.tours.create!(send_now: true, from_date: Date.current - 6, to_date: Date.current - 4,
      tour_visits_attributes: [ { visit_date: Date.current - 6, place: "Jhabua", planned_activity: "SHG" } ])
    tour.approve!(by: am)
    claim = with_tasks(TourClaim.build_for(tour))
    claim.claim_city_travels.build(travel_date: tour.from_date, departure_city: "Bhopal", arrival_city: "Jhabua", travel_mode: mode("Bus"), amount: 400)
    claim.save!
    sign_in emp
    get tour_path(tour)
    assert_match "Tour Approved", response.body
    assert_match "Claim: Prepared (not sent)", response.body
    assert_match ">Tour Plan<", response.body          # stamp top line
    assert_match ">TA/DA Claim<", response.body
    assert_match ">Not sent<", response.body
  end

  test "All Tours lists pending first and only-saved last" do
    emp = user("1025"); am = user("AM001")
    saved = emp.tours.create!(from_date: Date.current - 30, to_date: Date.current - 29,
      tour_visits_attributes: [ { visit_date: Date.current - 30, place: "Saved", planned_activity: "x" } ])
    pending = emp.tours.create!(send_now: true, from_date: Date.current - 60, to_date: Date.current - 59,
      tour_visits_attributes: [ { visit_date: Date.current - 60, place: "Pending", planned_activity: "x" } ])
    assert saved.draft? && pending.submitted?
    sign_in user("ADMIN")
    get masters_all_tours_path
    assert_response :success
    assert response.body.index(tour_path(pending)) < response.body.index(tour_path(saved)), "pending tour must come before the saved one"
  end
end
