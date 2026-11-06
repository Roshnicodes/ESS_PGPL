require "test_helper"

class PasswordResetTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  # The reset mail goes straight to krai (not queued) – capture it instead of calling krai.
  setup do
    @emp = user("1025")
    @emp.update_columns(email: "roshni@example.org")
    @sent = []
    @fail_mail = false
    sent, test = @sent, self
    @deliver_was = EssMailRelay.method(:deliver!)
    EssMailRelay.define_singleton_method(:deliver!) do |params, relay_url: url|
      raise EssMailRelay::DeliveryError, "service unavailable" if test.instance_variable_get(:@fail_mail)
      sent << [ params, relay_url ]
      true
    end
  end
  teardown do
    was = @deliver_was
    EssMailRelay.define_singleton_method(:deliver!) { |*args, **kw| was.call(*args, **kw) }
  end

  def reset_link
    params, relay_url = @sent.last
    assert_equal EssMailRelay.password_reset_url, relay_url
    assert_equal "pending", params["action"]
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
    post forgot_password_path, params: { emp_code: "NOPE" }
    assert_empty @sent
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
    post forgot_password_path, params: { emp_code: "1025" }
    assert_equal 1, @sent.size
  end

  test "a failed mail keeps the earlier reset link working" do
    post forgot_password_path, params: { emp_code: "1025" }
    path = reset_link
    @emp.update_columns(reset_password_sent_at: 10.minutes.ago)   # past the 2-minute wait
    @fail_mail = true
    post forgot_password_path, params: { emp_code: "1025" }
    assert_redirected_to forgot_password_path(sent: 1)
    get path
    assert_response :success                                     # old link still valid
  end

  test "password reset has a relay even where notification mail is off" do
    old_url = ENV.delete("ESS_MAIL_RELAY_URL")
    old_reset = ENV.delete("ESS_PASSWORD_RESET_MAIL_RELAY_URL")
    assert_not EssMailRelay.enabled?
    assert_equal EssMailRelay::DEFAULT_RELAY_URL, EssMailRelay.password_reset_url
  ensure
    ENV["ESS_MAIL_RELAY_URL"] = old_url if old_url
    ENV["ESS_PASSWORD_RESET_MAIL_RELAY_URL"] = old_reset if old_reset
  end
end

class TourClaimClarityTest < ActionDispatch::IntegrationTest
  test "approved tour with a saved claim: plan and claim have their own card, badge and stamp" do
    emp = user("1025"); am = user("AM001")
    tour = emp.tours.create!(send_now: true, from_date: Date.current - 6, to_date: Date.current - 4,
      tour_visits_attributes: [ { visit_date: Date.current - 6, place: "Jhabua", planned_activity: "SHG" } ])
    tour.approve!(by: am)
    claim = with_tasks(TourClaim.build_for(tour))
    claim.claim_city_travels.build(travel_date: tour.from_date, departure_city: "Bhopal", arrival_city: "Jhabua", travel_mode: mode("Bus"), amount: 400)
    claim.save!
    sign_in emp
    get tour_path(tour)
    body = response.body
    assert_match ">Plan approved<", body                               # the plan, not its claim
    assert_match "TA/DA Claim", body                                   # the claim's own card
    assert_match ">Prepared<", body                                    # claim badge on that card
    assert_match %r{seal-top">Tour Plan<.*?seal-word">Approved<}m, body
    assert_match %r{seal-top">TA/DA Claim<.*?seal-word">Not sent<}m, body
    assert_match "Tour plan history", body                             # plan and claim history kept apart
    assert_match "Claim history", body
    assert_equal 3, body.scan('class="seal ').size   # plan + claim stamps on screen, plan stamp beside the printed signatures
  end

  test "All Tours sorted 'Pending first' lists pending before only-saved" do
    emp = user("1025")
    pending = emp.tours.create!(send_now: true, from_date: Date.current - 60, to_date: Date.current - 59,
      tour_visits_attributes: [ { visit_date: Date.current - 60, place: "Pending", planned_activity: "x" } ])
    saved = emp.tours.create!(from_date: Date.current - 30, to_date: Date.current - 29,   # newer, but only saved
      tour_visits_attributes: [ { visit_date: Date.current - 30, place: "Saved", planned_activity: "x" } ])
    assert saved.draft? && pending.submitted?
    sign_in user("ADMIN")
    get masters_all_tours_path(sort: "pending_first")
    assert_response :success
    assert response.body.index(tour_path(pending)) < response.body.index(tour_path(saved)), "pending tour must come before the saved one"
  end
end
