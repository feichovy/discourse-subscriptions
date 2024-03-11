import EmberObject, { computed } from "@ember/object";
import discourseComputed from "discourse-common/utils/decorators";

const Plan = EmberObject.extend({
  amountDollars: computed("unit_amount", {
    get() {
      return parseFloat(this.get("unit_amount") / 100).toFixed(2);
    },
    set(key, value) {
      const decimal = parseFloat(value) * 100;
      this.set("unit_amount", decimal);
      return value;
    },
  }),

  @discourseComputed("recurring.interval", "metadata.is_system_recurring", "metadata.system_recurring_interval")
  billingInterval(interval, isSystemRecurring, systemInterval) {
    return (interval ? interval : (isSystemRecurring ? systemInterval : interval)) || "one-time";
  },

  @discourseComputed("amountDollars", "currency", "billingInterval")
  subscriptionRate(amountDollars, currency, interval) {
    return `${amountDollars} ${currency.toUpperCase()} / ${interval}`;
  },

  @discourseComputed("features")
  getFeatures(features) {
    return features;
  }
});

export default Plan;
