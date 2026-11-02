# Removes the seeded demo employees (ADMIN, HR001, FIN001, MIS001, AM001, 1025) so the real
# Employee List can be uploaded. Keeps PGPLADMIN. Run:  bin/rails runner script/remove_demo_users.rb
# Add DRY_RUN=1 to only show what would happen.
#
# Stops without changing anything if a demo user already owns tours or claims (real data).
# Everything else that points at a demo user is moved to PGPLADMIN (created_by, approver …) or,
# for their own bank accounts / notifications, deleted with them. activity_logs is append-only, so a
# demo user who already appears in it is only deactivated instead (cannot log in; listed as Inactive).
KEEP  = "PGPLADMIN"
DEMO  = %w[ADMIN HR001 FIN001 MIS001 AM001 1025].freeze
dry   = ENV["DRY_RUN"].present?

admin = User.find_by!(emp_code: KEEP)
doomed = User.where(emp_code: DEMO)
all_ids = doomed.pluck(:id)
abort "No demo users left – nothing to do." if all_ids.empty?

owned = { tours: Tour.where(user_id: all_ids).count, claims: TourClaim.where(user_id: all_ids).count }
abort "Stopped: demo users own #{owned} – these look like real records, nothing was changed." if owned.values.any?(&:positive?)

conn = ActiveRecord::Base.connection
fks = conn.select_rows(<<~SQL)
  SELECT cl.relname, att.attname, att.attnotnull
  FROM pg_constraint con
  JOIN pg_class cl ON cl.oid = con.conrelid
  JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = ANY (con.conkey)
  WHERE con.contype = 'f' AND con.confrelid = 'users'::regclass
SQL

OWN_ROWS = %w[bank_accounts notifications].freeze   # the demo user's own rows go with the user
log_cols = fks.select { |t, _, _| t == "activity_logs" }.map { |_, c, _| c }
logged = log_cols.flat_map { |c| conn.select_values("SELECT DISTINCT #{conn.quote_column_name(c)} FROM activity_logs WHERE #{conn.quote_column_name(c)} IN (#{all_ids.join(',')})") }.map(&:to_i).uniq
ids = all_ids - logged

User.transaction do
  if logged.any?
    User.where(id: logged).update_all(active: false)
    puts "Deactivated (kept for history): #{User.where(id: logged).pluck(:emp_code).join(', ')}"
  end
  id_list = ids.join(",")
  fks.each do |table, column, not_null|
    next if ids.empty? || table == "activity_logs"
    sql =
      if OWN_ROWS.include?(table) && column == "user_id"
        "DELETE FROM #{conn.quote_table_name(table)} WHERE #{conn.quote_column_name(column)} IN (#{id_list})"
      elsif table == "users" || !not_null && column !~ /created_by|updated_by|acted_by|approved_by/
        "UPDATE #{conn.quote_table_name(table)} SET #{conn.quote_column_name(column)} = NULL WHERE #{conn.quote_column_name(column)} IN (#{id_list})"
      else
        "UPDATE #{conn.quote_table_name(table)} SET #{conn.quote_column_name(column)} = #{admin.id} WHERE #{conn.quote_column_name(column)} IN (#{id_list})"
      end
    n = conn.exec_update(sql)
    puts "#{table}.#{column}: #{n} row(s)" if n.positive?
  end
  deleted = User.where(id: ids).delete_all
  puts "Removed #{deleted} demo user(s). Kept #{KEEP}. Active users left: #{User.where(active: true).pluck(:emp_code).join(', ')}"
  raise ActiveRecord::Rollback if dry
end
puts "DRY RUN – nothing was saved." if dry
