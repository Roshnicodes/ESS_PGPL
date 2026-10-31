class MakeDeepNarayanMishraAdmin < ActiveRecord::Migration[8.1]
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  def up
    user = MigrationUser.find_or_initialize_by(emp_code: "1686")
    user.assign_attributes(
      name: "Deep Narayan Mishra",
      email: "pd.hr@asabhopal.org",
      designation: "Programme Director-HR",
      short_designation: "PD HR",
      role: "admin",
      active: true
    )
    user.encrypted_password = BCrypt::Password.create("123456") if user.new_record? || user.encrypted_password.blank?
    user.save!
  end

  def down
    # This is a requested account change. Keep the account on rollback so
    # existing audit records and ownership relationships are never orphaned.
  end
end
