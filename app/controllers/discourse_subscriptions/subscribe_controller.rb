# frozen_string_literal: true

module DiscourseSubscriptions
  class SubscribeController < ::ApplicationController
    include DiscourseSubscriptions::Stripe
    include DiscourseSubscriptions::Group
    before_action :set_api_key
    requires_login except: %i[index contributors show]

    def index
      begin
        product_ids = Product.all.pluck(:external_id)
        products = []

        if product_ids.present? && is_stripe_configured?
          response = ::Stripe::Product.list({ ids: product_ids, active: true })

          products = response[:data].map { |p| serialize_product(p) }
        end

        render_json_dump products
      rescue ::Stripe::InvalidRequestError => e
        render_json_error e.message
      end
    end

    def contributors
      return unless SiteSetting.discourse_subscriptions_campaign_show_contributors
      contributor_ids = Set.new

      campaign_product = SiteSetting.discourse_subscriptions_campaign_product
      if campaign_product.present?
        contributor_ids.merge(Customer.where(product_id: campaign_product).last(5).pluck(:user_id))
      else
        contributor_ids.merge(Customer.last(5).pluck(:user_id))
      end

      contributors = ::User.where(id: contributor_ids)

      render_serialized(contributors, UserSerializer)
    end

    def show
      params.require(:id)
      begin
        product = ::Stripe::Product.retrieve(params[:id])
        plans = ::Stripe::Price.list(active: true, product: params[:id])

        response = { product: serialize_product(product), plans: serialize_plans(plans) }

        render_json_dump response
      rescue ::Stripe::InvalidRequestError => e
        puts "Stripe Error: #{e.message}"
        render_json_error e.message
      end
    end

    def create_checkout
      params.require(%i[plan paymentMethod])
      begin
        payment_method = params[:paymentMethod]
        plan = ::Stripe::Price.retrieve(params[:plan])
        # group = plan_group(plan)
        recurring_plan = plan[:metadata][:is_system_recurring] == "true"
        metadata = {
          recurring_payment: false,
          group_name: plan[:metadata][:group_name],
          plan_id: plan[:id],
          system_recurring_interval: plan[:metadata][:system_recurring_interval]
        }.merge!(metadata_user)

        currency = payment_method == 'cny' ? 'cny' : SiteSetting.discourse_subscriptions_currency.downcase
        unit_amount = payment_method == 'cny' ? PlanCnyPrice.where(plan_id: plan[:id]).first[:unit_amount].to_i : (plan["unit_amount"] < 1 ? 100 : plan["unit_amount"])
        # payment_method_options = payment_method == 'cny' ? { wechat_pay: { client: 'web' } } : {}
        payment_method_options = {}
        # payment_method_types = payment_method == 'cny' ? ['wechat_pay', 'alipay'] : ['card', 'link']
        payment_method_types = payment_method == 'cny' ? ['alipay'] : ['card', 'link']
        
        payment_params = {
          success_url: "#{Discourse.base_url}/s?t=success",
          cancel_url: "#{Discourse.base_url}/s?t=cancel",
          allow_promotion_codes: true,
          line_items: [
            {
              price_data: {
                currency: currency,
                unit_amount: unit_amount,
                product_data: {
                  name: (plan["nickname"] && plan["nickname"].length > 0) ? plan["nickname"] : "Plan",
                  description: Discourse.base_url
                }
              },
              quantity: 1,
            },
          ],
          payment_method_options: payment_method_options,
          payment_method_types: payment_method_types,
          payment_intent_data: {
            metadata: metadata
          },
          mode: 'payment',
        }
        
        if recurring_plan
          metadata.merge!(
            recurring_payment: 'true'
          )
        end

        payment_intent = ::Stripe::Checkout::Session.create(payment_params)

        # Moved to Hooks Controller

        # puts "Stripe Checkout:"
        # puts payment_intent

        # if recurring_plan
          # Create internal subscription (default: active)
          # InternalSubscription.create!({
          #   product_id: plan[:id],
          #   plan_id: payment_intent[:payment_intent],
          #   user_id: current_user[:id],
          #   status: payment_intent[:status]
          # })
        # end

        render json: {
          status: true,
          data: {
            tx: payment_intent,
            is_recurring_plan: recurring_plan
          }
        }
      rescue ::Stripe::StripeError => e
        puts "Stripe Error: #{e.message}"
        render_json_error e.message
      end
    end

    def create
      params.require(%i[source plan])
      begin
        customer =
          find_or_create_customer(
            params[:source],
            params[:cardholder_name],
            params[:cardholder_address],
          )
        plan = ::Stripe::Price.retrieve(params[:plan])

        if params[:promo].present?
          promo_code = ::Stripe::PromotionCode.list({ code: params[:promo] })
          promo_code = promo_code[:data][0] # we assume promo codes have a unique name

          if promo_code.blank?
            return render_json_error I18n.t("js.discourse_subscriptions.subscribe.invalid_coupon")
          end
        end

        recurring_plan = plan[:type] == "recurring"

        if recurring_plan
          trial_days = plan[:metadata][:trial_period_days] if plan[:metadata] &&
            plan[:metadata][:trial_period_days]

          promo_code_id = promo_code[:id] if promo_code

          transaction =
            ::Stripe::Subscription.create(
              customer: customer[:id],
              items: [{ price: params[:plan] }],
              metadata: metadata_user,
              trial_period_days: trial_days,
              promotion_code: promo_code_id,
            )

          payment_intent = retrieve_payment_intent(transaction[:latest_invoice]) if transaction[
            :status
          ] == "incomplete"
        else
          coupon_id = promo_code[:coupon][:id] if promo_code && promo_code[:coupon] &&
            promo_code[:coupon][:id]
          invoice_item =
            ::Stripe::InvoiceItem.create(
              customer: customer[:id],
              price: params[:plan],
              discounts: [{ coupon: coupon_id }],
            )
          invoice = ::Stripe::Invoice.create(customer: customer[:id])
          transaction = ::Stripe::Invoice.finalize_invoice(invoice[:id])
          payment_intent = retrieve_payment_intent(transaction[:id]) if transaction[:status] ==
            "open"

          # payment_intent = confirm_intent(payment_intent)

          transaction = ::Stripe::Invoice.pay(invoice[:id]) if payment_intent[:status] ==
            "successful"
        end

        finalize_transaction(transaction, plan) if transaction_ok(transaction)

        transaction = transaction.to_h.merge(transaction, payment_intent: payment_intent)

        render_json_dump transaction
      rescue ::Stripe::InvalidRequestError => e
        render_json_error e.message
      end
    end

    def finalize
      params.require(%i[plan transaction])
      begin
        price = ::Stripe::Price.retrieve(params[:plan])
        transaction = retrieve_transaction(params[:transaction])
        finalize_transaction(transaction, price) if transaction_ok(transaction)

        render_json_dump params[:transaction]
      rescue ::Stripe::InvalidRequestError => e
        render_json_error e.message
      end
    end

    def finalize_transaction(transaction, plan)
      group = plan_group(plan)

      group.add(current_user) if group

      customer =
        Customer.create(
          user_id: current_user.id,
          customer_id: transaction[:customer],
          product_id: plan[:product],
        )

      if transaction[:object] == "subscription"
        Subscription.create(customer_id: customer.id, external_id: transaction[:id])
      end
    end

    private

    def serialize_product(product)
      internal_subscription =
            InternalSubscription.where(
              user_id: current_user[:id],
              status: 'succeeded',
              active: true
            ).first
      
      {
        id: product[:id],
        name: product[:name],
        description: PrettyText.cook(product[:metadata][:description]),
        subscribed: internal_subscription ? true : current_user_products.include?(product[:id]),
        repurchaseable: product[:metadata][:repurchaseable],
      }
    end

    def current_user_products
      return [] if current_user.nil?

      Customer.select(:product_id).where(user_id: current_user.id).map { |c| c.product_id }.compact
    end

    def serialize_plans(plans)
      plans[:data]
        .map { |plan| serialize_plan(plan) }
        .sort_by { |plan| plan[:amount] }
    end

    def serialize_plan(plan)
      plan_hash = plan.to_h.slice(:id, :unit_amount, :currency, :type, :recurring, :metadata)

      # Fetch PlanFeatures for the current plan_id
      features = PlanFeatures.where(plan_id: plan[:id]).order(feature_id: :asc)

      # CNY Price
      amount_cny = PlanCnyPrice.where(plan_id: plan[:id]).first

      # Add features to the plan hash
      plan_hash[:features] = features.map { |feature| feature.attributes }
      plan_hash[:unit_amount_cny] = amount_cny ? amount_cny[:unit_amount] : 0

      plan_hash
    end

    def find_or_create_customer(source, cardholder_name = nil, cardholder_address = nil)
      customer = Customer.find_by_user_id(current_user.id)
      cardholder_address =
        (
          if cardholder_address.present?
            {
              line1: cardholder_address[:line1],
              city: cardholder_address[:city],
              state: cardholder_address[:state],
              country: cardholder_address[:country],
              postal_code: cardholder_address[:postalCode],
            }
          else
            nil
          end
        )

      if customer.present?
        ::Stripe::Customer.retrieve(customer.customer_id)
      else
        ::Stripe::Customer.create(
          email: current_user.email,
          source: source,
          name: cardholder_name,
          address: cardholder_address,
        )
      end
    end

    def retrieve_payment_intent(invoice_id)
      invoice = ::Stripe::Invoice.retrieve(invoice_id)
      ::Stripe::PaymentIntent.retrieve(invoice[:payment_intent])
    end

    def retrieve_transaction(transaction)
      begin
        case transaction
        when /^sub_/
          ::Stripe::Subscription.retrieve(transaction)
        when /^in_/
          ::Stripe::Invoice.retrieve(transaction)
        end
      rescue ::Stripe::InvalidRequestError => e
        e.message
      end
    end

    def metadata_user
      { user_id: current_user.id, username: current_user.username_lower }
    end

    def transaction_ok(transaction)
      %w[active trialing paid].include?(transaction[:status])
    end
  
    def confirm_intent(payment_intent)
      return payment_intent unless intent_requires_confirmation?(payment_intent)

      ::Stripe::PaymentIntent.confirm(
        payment_intent[:id],
        { payment_method: payment_intent[:payment_method] }.compact
      )
    end

    def intent_requires_confirmation?(payment_intent)
      payment_intent[:status] == 'requires_confirmation'
    end
  end
end