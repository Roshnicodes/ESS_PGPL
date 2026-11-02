# PGPL: Finance approves claims without Project / BLI / BLI Code, so an approved claim only needs approved_at.
class DropFinanceCodingRequirement < ActiveRecord::Migration[8.1]
  def up
    execute "ALTER TABLE tour_claims DROP CONSTRAINT IF EXISTS chk_claims_finance_coding_on_approval"
    execute <<~SQL
      ALTER TABLE tour_claims ADD CONSTRAINT chk_claims_approved_at_on_approval
        CHECK (status::text <> 'approved'::text OR approved_at IS NOT NULL)
    SQL
  end

  def down
    execute "ALTER TABLE tour_claims DROP CONSTRAINT IF EXISTS chk_claims_approved_at_on_approval"
    execute <<~SQL
      ALTER TABLE tour_claims ADD CONSTRAINT chk_claims_finance_coding_on_approval
        CHECK (status::text <> 'approved'::text OR (project_id IS NOT NULL AND budget_line_item_id IS NOT NULL
               AND budget_line_item_code_id IS NOT NULL AND approved_at IS NOT NULL))
    SQL
  end
end
