# frozen_string_literal: true

module DiscourseSubscriptions
  module User
    class SubscriptionsController < ::ApplicationController
      include DiscourseSubscriptions::Stripe
      include DiscourseSubscriptions::Group
      before_action :set_api_key
      requires_login

      def index
        begin
          customer = Customer.where(user_id: current_user.id)
          customer_ids = customer.map { |c| c.id } if customer
          subscription_ids =
            Subscription.where("customer_id in (?)", customer_ids).pluck(
              :external_id,
            ) if customer_ids

          subscriptions = []

          if subscription_ids
            plans = ::Stripe::Price.list(expand: ["data.product"], limit: 100)

            customers =
              ::Stripe::Customer.list(email: current_user.email, expand: ["data.subscriptions"])

            subscriptions =
              customers[:data].map { |sub_customer| sub_customer[:subscriptions][:data] }.flatten(1)

            subscriptions = subscriptions.select { |sub| subscription_ids.include?(sub[:id]) }

            subscriptions.map! do |subscription|
              plan = plans[:data].find { |p| p[:id] == subscription[:items][:data][0][:price][:id] }
              subscription.to_h.except!(:plan)
              subscription.to_h.merge(plan: plan, product: plan[:product].to_h.slice(:id, :name))
            end
          end

          # Custom here!
          internal_subscription =
            InternalSubscription.where(
              user_id: current_user[:id],
              status: ['succeeded', 'canceled'],
              active: true
            )
                    
          # Custom here!
          if internal_subscription            
            internal_subscription.each do |internal_subscription|
              plan = ::Stripe::Price.retrieve(internal_subscription[:product_id])
              product = ::Stripe::Product.retrieve(plan[:product])

              subscriptions << {
                id: "internal_#{internal_subscription[:id]}",
                plan: plan,
                product: product,
                current_period_end: internal_subscription[:next_due],
                created: internal_subscription[:created_at].to_i,
                status: internal_subscription[:active] ? internal_subscription[:status] == 'canceled' ? 'canceled' : 'active' : 'inactive'
              }
            end
          end

          render_json_dump subscriptions
        rescue ::Stripe::InvalidRequestError => e
          render_json_error e.message
        end
      end

      def destroy
        begin
          if params[:id].start_with?("internal_")
            # Internal subscription logic
            internal_id = params[:id][9..-1].to_i
            internal_subscription = InternalSubscription.find_by(id: internal_id)
            
            if internal_subscription
              # Update internal subscription status
              internal_subscription.update(status: 'canceled')
              
              plan = ::Stripe::Price.retrieve(internal_subscription[:product_id])
              product = ::Stripe::Product.retrieve(plan[:product])

              # Construct JSON data for internal subscription
              data = {
                id: "internal_#{internal_id}",
                plan: plan,
                product: product,
                current_period_end: internal_subscription[:next_due],
                created: internal_subscription[:created_at].to_i,
                status: 'canceled'
              }
              
              render_json_dump(data)
            else
              render_json_error("Internal subscription not found")
            end
          else
            # Stripe subscription logic
            subscription = ::Stripe::Subscription.update(params[:id], { cancel_at_period_end: true })
            
            if subscription
              render_json_dump(subscription)
            else
              render_json_error(I18n.t("discourse_subscriptions.customer_not_found"))
            end
          end
        rescue ::Stripe::InvalidRequestError => e
          render_json_error(e.message)
        end
      end


      def update
        params.require(:payment_method)

        subscription = Subscription.where(external_id: params[:id]).first
        begin
          attach_method_to_customer(subscription.customer_id, params[:payment_method])
          subscription =
            ::Stripe::Subscription.update(
              params[:id],
              { default_payment_method: params[:payment_method] },
            )
          render json: success_json
        rescue ::Stripe::InvalidRequestError
          render_json_error I18n.t("discourse_subscriptions.card.invalid")
        end
      end

      private

      def attach_method_to_customer(customer_id, method)
        customer = Customer.find(customer_id)
        ::Stripe::PaymentMethod.attach(method, { customer: customer.customer_id })
      end
    end
  end
end
