# frozen_string_literal: true

class CreatePlanCnyPrice < ActiveRecord::Migration[6.0]
    def change
      create_table :discourse_subscriptions_plan_cny_price do |t|
        t.string :plan_id
        t.float :unit_amount

        t.timestamps
      end
    end
end