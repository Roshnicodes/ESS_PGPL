require "test_helper"

# An employee who is still someone's L-1 / L-2 / Finance approver cannot be deactivated
# until HR sets a new approver for those employees.
class UserDeactivationTest < ActiveSupport::TestCase
  setup do
    @boss = User.create!(emp_code: "BOSSD1", name: "Boss D", password: "123456")
    @emp  = User.create!(emp_code: "EMPD1", name: "Emp D", password: "123456", l2_manager: @boss)
  end

  test "approver cannot be deactivated while assigned" do
    refute @boss.update(active: false)
    assert_match(/approval authority for 1 active employee: Emp D \(EMPD1\) – L-2/, @boss.errors.full_messages.join)
    assert @boss.reload.active?
  end

  test "approver can be deactivated once a new approver is set" do
    @emp.update!(l2_manager: nil)
    assert @boss.update(active: false)
  end

  test "inactive dependents do not block, and other edits still save" do
    assert @boss.update(mobile: "9999999999")
    @emp.update!(active: false)
    assert @boss.update(active: false)
  end

  test "approver with a pending tour plan cannot be deactivated until it is decided" do
    emp = user("1025"); l1 = User.create!(emp_code: "L1D1", name: "Old L1", password: "123456")
    l2 = User.create!(emp_code: "L2D1", name: "Old L2", password: "123456")
    emp.update!(reporting_manager: l1, l2_manager: l2)
    tour = emp.tours.create!(send_now: true, from_date: Date.current + 5, to_date: Date.current + 6,
      tour_visits_attributes: [ { visit_date: Date.current + 5, place: "Indore", planned_activity: "Review" } ])
    tour.approve!(by: l1, remark: "ok")                     # now waiting with L2
    emp.update!(reporting_manager: @boss, l2_manager: nil)  # new managers; a plan already past L1 stays with Old L2

    refute l2.update(active: false)
    assert_match(/1 tour plan still pending with them for approval: Tour plan of #{emp.name}/, l2.errors.full_messages.join)

    tour.approve!(by: l2, remark: "ok")
    assert l2.reload.update(active: false)
  end

  test "PGPL: a plan still waiting at L1 follows the new L-1, so the old L-1 can be deactivated" do
    emp = user("1025"); l1 = User.create!(emp_code: "L1D2", name: "Old L1", password: "123456")
    emp.update!(reporting_manager: l1, l2_manager: nil)
    tour = emp.tours.create!(send_now: true, from_date: Date.current + 5, to_date: Date.current + 6,
      tour_visits_attributes: [ { visit_date: Date.current + 5, place: "Indore", planned_activity: "Review" } ])
    emp.update!(reporting_manager: @boss)
    assert_equal @boss, tour.reload.approver
    assert l1.update(active: false)
  end
end
