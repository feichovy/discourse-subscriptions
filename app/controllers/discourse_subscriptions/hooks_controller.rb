# frozen_string_literal: true

# Intervals in Seconds
INTERVALS = {
  "day" => 86400,
  "week" => 604800,
  "month" => 2629800,
  "year" => 31557600,
}

module DiscourseSubscriptions
  class HooksController < ::ApplicationController
      include DiscourseSubscriptions::Group
      include DiscourseSubscriptions::Stripe

      layout false

      skip_before_action :check_xhr
      skip_before_action :redirect_to_login_if_required
      skip_before_action :verify_authenticity_token, only: [:create]
      before_action :set_api_key

      def create
          begin
              payload = request.body.read
              sig_header = request.env["HTTP_STRIPE_SIGNATURE"]
              webhook_secret = SiteSetting.discourse_subscriptions_webhook_secret

              event = ::Stripe::Webhook.construct_event(payload, sig_header, webhook_secret)
          rescue JSON::ParserError => e
              return render_json_error e.message
          rescue ::Stripe::SignatureVerificationError => e
              return render_json_error e.message
          end
          
          case event[:type]
              when "payment_intent.requires_action"
                    #   internal_subscription = InternalSubscription.where(
                    #     plan_id: event[:data][:object][:id]
                    #   )
                      internal_subscription = InternalSubscription.where("plan_id LIKE ?", "%#{event[:data][:object][:id]}%")

                      if internal_subscription && event[:data][:object][:metadata][:recurring_payment] == 'true'
                        internal_subscription.update_all status: "cancelled", active: false
                      end
              when "payment_intent.succeeded"
                    puts "Payment Succeeded:"
                    puts event
                
                    payment_intent = event[:data][:object]
                    recurring_payment = event[:data][:object][:metadata][:recurring_payment] == 'true'
                    system_recurring_interval = event[:data][:object][:metadata][:system_recurring_interval]
                
                    interval = INTERVALS[system_recurring_interval]
                    puts "Interval:"
                    puts interval
                    puts system_recurring_interval
                
                    next_due = Time.now.to_i + interval
                
                    internal_subscription = InternalSubscription.find_by(plan_id: "%#{payment_intent[:id]}%")
                
                    if internal_subscription.present?
                        if recurring_payment
                            internal_subscription.update(status: "succeeded", active: true, next_due: next_due, last_notification: nil)
                        end
                    else
                        if recurring_payment
                            InternalSubscription.create!(
                                product_id: payment_intent[:metadata][:plan_id],
                                plan_id: payment_intent[:id],
                                user_id: payment_intent[:metadata][:user_id].to_i,
                                status: payment_intent[:status],
                                last_notification: nil,
                                active: true,
                                next_due: next_due
                            )
                        else
                            # Single payment
                        end
                    end

                    if group = ::Group.find_by_name(event[:data][:object][:metadata][:group_name])
                        group&.add(::User.find(event[:data][:object][:metadata][:user_id].to_i))
                    end
              when "payment_intent.cancelled"
                    # If user cancels from Stripe, detect it here too
                    # internal_subscription = InternalSubscription.where(
                    #     plan_id: event[:data][:object][:id]
                    # )

                    internal_subscription = InternalSubscription.where("plan_id LIKE ?", "%#{event[:data][:object][:id]}%")

                    if internal_subscription.present? && event[:data][:object][:metadata][:recurring_payment] == 'true'
                        internal_subscription.update_all status: "cancelled", active: false
                    end
                    
                    if group = ::Group.find_by_name(event[:data][:object][:metadata][:group_name])
                        group&.remove(::User.find(event[:data][:object][:metadata][:user_id].to_i))
                    end
              when "customer.subscription.created"
                  ActiveRecord::Base.transaction do
                      customer = find_or_create_customer(event)

                      subscription_attrs = subscription_attrs(event, customer)
                      subscription = ::DiscourseSubscriptions::Subscription.find_by(
                          external_id: subscription_attrs[:external_id]
                      )
                      subscription ||= ::DiscourseSubscriptions::Subscription.create!(
                          subscription_attrs(event, customer)
                      )

                      group = ::Group.find_by_name(event[:data][:object][:items][:data][0][:plan][:nickname])
                      group&.add(::User.find(customer.user_id))
                      end
              when "customer.subscription.updated"
                  customer =
                  Customer.find_by(
                      customer_id: event[:data][:object][:customer],
                      product_id: event[:data][:object][:plan][:product],
                  )

                  return render_json_error "customer not found" if !customer
                  return head 200 if event[:data][:object][:status] != "complete"

                  user = ::User.find_by(id: customer.user_id)
                  return render_json_error "user not found" if !user

                  if group = plan_group(event[:data][:object][:plan])
                  group.add(user)
                  end
              when "customer.subscription.deleted"
                  customer =
                  Customer.find_by(
                      customer_id: event[:data][:object][:customer],
                      product_id: event[:data][:object][:plan][:product],
                  )

                  return render_json_error "customer not found" if !customer

                  Subscription.find_by(
                    customer_id: customer.id,
                    external_id: event[:data][:object][:id],
                  )&.destroy!

                  user = ::User.find(customer.user_id)
                  return render_json_error "user not found" if !user

                  if group = plan_group(event[:data][:object][:plan])
                  group.remove(user)
                  end

                  customer.destroy!
              when 'product.updated'
                  create_or_update_product(event['data'])
                  when 'product.created'
                  create_or_update_product(event['data'])
              end

              head 200
      end

      private

      def find_or_create_customer(event)
          attrs = customer_attrs(event)
          customer = ::DiscourseSubscriptions::Customer.find_by(attrs)
          customer ||= ::DiscourseSubscriptions::Customer.create!(attrs)
      end

      def create_or_update_product(product_data)
          fresh_data = product_data['object']
          ::DiscourseSubscriptions::Products::CreateOrUpdate.new(fresh_data).call!
      end

      def subscription_attrs(event, customer)
          {
              customer_id: customer.id,
              external_id: event[:data][:object][:id]
          }
      end

      def customer_attrs(event)
          customer_id = event[:data][:object][:customer]

          {
              customer_id: customer_id,
              product_id: event[:data][:object][:items][:data][0][:plan][:product],
              user_id: user(customer_id)&.id
          }
      end

      def user(stripe_customer_id)
          user_email = ::Stripe::Customer.retrieve(stripe_customer_id).email

          ::UserEmail.find_by(email: user_email).user
      end
  end
end