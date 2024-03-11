# frozen_string_literal: true

module DiscourseSubscriptions
    class InternalSubscription < ActiveRecord::Base
        self.table_name = "discourse_subscriptions_internal_subscriptions"

        scope :find_user, ->(user) { find_by_user_id(user.id) }
    end
end