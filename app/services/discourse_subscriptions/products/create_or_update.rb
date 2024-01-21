# frozen_string_literal: true

module DiscourseSubscriptions
    module Products
        # TODO: to be refactored
        class CreateOrUpdate
            def initialize(object)
                @object = object
            end

            def call!
                if stripe_product_id.blank?
                raise ArgumentError, 'stripe product id cannot be blank'
                end

                # add updates for existing product
                # when new fields are added to the product model
                return true if find_product_by_stripe_id.present?

                product = ::DiscourseSubscriptions::Product.new
                product.external_id = stripe_product_id
                product.save!
            end

            private

            attr_reader :object

            def find_product_by_stripe_id
                ::DiscourseSubscriptions::Product.find_by(
                external_id: stripe_product_id
                )
            end

            def stripe_product_id
                @_stripe_product_id ||= object[:id]
            end
        end
    end
end