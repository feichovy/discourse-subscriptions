# frozen_string_literal: true

class CreatePlanFeatures < ActiveRecord::Migration[6.0]
    def change
      create_table :discourse_subscriptions_plan_features do |t|
        t.string :plan_id
        t.string :feature
        t.integer :feature_id

        t.timestamps
      end
    end
end