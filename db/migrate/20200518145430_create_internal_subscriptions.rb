# frozen_string_literal: true

class CreateInternalSubscriptions < ActiveRecord::Migration[6.0]
    def change
      create_table :discourse_subscriptions_internal_subscriptions do |t|
        t.string :product_id
        t.string :plan_id
        
        t.integer :last_notification
        t.integer :next_due, null: true
        
        t.string :status
        t.boolean :active, default: true
        t.references :user

        t.timestamps
      end
    end
end