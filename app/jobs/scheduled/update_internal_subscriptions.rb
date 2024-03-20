# frozen_string_literal: true

module ::Jobs
  class UpdateInternalSubscriptions < ::Jobs::Scheduled
    include ::DiscourseSubscriptions::Stripe
    every 1.minutes

    def execute(args)
      # Unable to access existing instant of Stripe?
      ::Stripe.api_key = SiteSetting.discourse_subscriptions_secret_key
      now = Time.now.to_i

      # Fetch all active subscriptions
      # Fetch from Stripe
      # Check if trial period is up
      # If trial period is up then ask user for payment
      # If user has not paid invoice within 12 hours then invalidate subscription
      
      puts "==========================="
      puts "-- [Discourse Subscriptions] --"
      puts "-- Internal Subscriptions --"
      puts "==========================="

      internal_subs = ::DiscourseSubscriptions::InternalSubscription.where(active: true)

      internal_subs.each do |internal_subscription|
        payment_intent = ::Stripe::PaymentIntent.retrieve(internal_subscription[:plan_id])
        payment_intent_metadata = payment_intent[:metadata]
        user = User.find_by(id: internal_subscription.user_id)

        
        plan = ::Stripe::Price.retrieve(internal_subscription[:product_id])            
        is_recurring_plan = plan[:metadata][:is_system_recurring] == "true"
        
        if internal_subscription[:status] == 'succeeded'
          next_due = internal_subscription[:next_due].to_i

          # If invoice is due
          if next_due <= now
            metadata = {
              recurring_payment: true,
              group_name: plan[:metadata][:group_name],
              system_recurring_interval: plan[:metadata][:system_recurring_interval],
              user_id: user.id,
              username: user.username
            }
            
            payment_params = {
              success_url: "#{Discourse.base_url}/s?t=success",
              cancel_url: "#{Discourse.base_url}/s?t=cancel",
              allow_promotion_codes: true,
              line_items: [
                {
                  price_data: {
                    currency: SiteSetting.discourse_subscriptions_currency.downcase,
                    unit_amount: (plan["unit_amount"] < 1 ? 100 : plan["unit_amount"]),
                    product_data: {
                      name: (plan["nickname"] && plan["nickname"].length > 0) ? plan["nickname"] : "Plan",
                      description: Discourse.base_url
                    }
                  },
                  quantity: 1,
                },
              ],
              payment_method_types: ['card', 'link'],
              payment_intent_data: {
                metadata: metadata
              },
              mode: 'payment',
            }

            payment_params_cny = payment_params.merge({
              payment_method_options: {
                wechat_pay: {
                  client: 'web'
                }
              },
              payment_method_types: ['wechat_pay', 'alipay'],
              line_items: [
                {
                  price_data: {
                    currency: currency,
                    unit_amount: unit_amount,
                  }
                }
              ]
            })

            payment_intent = ::Stripe::Checkout::Session.create(payment_params)
            payment_intent_cny = ::Stripe::Checkout::Session.create(payment_params_cny)

            if is_recurring_plan
              metadata.merge!(recurring_payment: is_recurring_plan)

              # Alert the user that the payment is due
              PostCreator.create(
                  Discourse.system_user,
                  target_usernames: user[:username],
                  archetype: Archetype.private_message,
                  subtype: TopicSubtype.system_message,
                  title: I18n.t("discourse_subscriptions.internal_subscriptions.renewal"),
                  raw: I18n.t("discourse_subscriptions.internal_subscriptions.renewal_url", {
                    package: plan[:nickname],
                    url: payment_intent[:url],
                    url_cny: payment_intent_cny[:url]
                  })
              )
              
              internal_subscription[:plan_id] = "#{payment_intent[:payment_intent]},#{payment_intent[:payment_intent_cny]}"
              internal_subscription[:status] = "created"
              internal_subscription[:last_notification] = Time.now.to_i              
                
              internal_subscription.save

              puts "#{user.username} has been alerted to make a payment"
            end
          end
        else
          # If subscription is cancelled
          if is_recurring_plan && internal_subscription[:status] == 'canceled'
            next_due = internal_subscription[:next_due].to_i
            # If time is due for next subscription
            if next_due <= now
              internal_subscription[:active] = false
              internal_subscription.save

              # Remove groups
              group = ::Group.find_by_name(plan[:metadata][:group_name])
              group&.remove(user) if group

              puts "#{user.username}'s subscription was cancelled and they have been alerted"
            
              # Alert the user that the subscription is cancelled
              PostCreator.create(
                  Discourse.system_user,
                  target_usernames: user[:username],
                  archetype: Archetype.private_message,
                  subtype: TopicSubtype.system_message,
                  title: I18n.t("discourse_subscriptions.internal_subscriptions.expired")
              )
            end
          end

          # If status of subscription is in requires_action
          if is_recurring_plan && internal_subscription[:status] == 'created' && internal_subscription[:last_notification].present?
            # Then assume that we are waiting for the user to make a payment
            last_notification = internal_subscription[:last_notification]
            difference_last_notification = now - last_notification

            # If 12 hours have passed since the last notification
            if difference_last_notification >= 43200
              # Cancel subscription
              internal_subscription[:status] = 'cancelled'
              internal_subscription[:active] = false
              internal_subscription.save

              # Remove groups
              group = ::Group.find_by_name(plan[:metadata][:group_name])
              group&.remove(user)

              puts "#{user.username}'s subscription was cancelled and they have been alerted"

              # Alert the user that the subscription is cancelled
              PostCreator.create(
                  Discourse.system_user,
                  target_usernames: user[:username],
                  archetype: Archetype.private_message,
                  subtype: TopicSubtype.system_message,
                  title: I18n.t("discourse_subscriptions.internal_subscriptions.expired")
              )
            end
          end
        end
      end
    end
  end
end