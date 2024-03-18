import { ajax } from "discourse/lib/ajax";
import discourseComputed from "discourse-common/utils/decorators";
import Plan from "discourse/plugins/discourse-subscriptions/discourse/models/plan";

const AdminPlan = Plan.extend({
  isNew: false,
  name: "",
  interval: "month",
  unit_amount: 0,
  unit_amount_cny: 0,
  intervals: ["day", "week", "month", "year"],
  metadata: {},
  features: [],

  @discourseComputed("trial_period_days")
  parseTrialPeriodDays(trialDays) {
    if (trialDays) {
      return parseInt(0 + trialDays, 10);
    } else {
      return 0;
    }
  },

  addFeatures(features) {
    let count = 0; // Initialize the count

    features.map((item, index) => {
        // If the feature is not empty, update its feature_id and decrement count
        if (item.feature.length) {
            item.feature_id = count;
            count++;
        }
    });

    this.features = features.filter(item => item.feature.length);
  
    return this
  },

  save() {
    const data = {
      nickname: this.nickname,
      interval: this.interval,
      amount: this.unit_amount,
      currency: this.currency,
      trial_period_days: this.parseTrialPeriodDays,
      type: this.type,
      is_system_recurring: this.isSystemRecurring,
      features: this.features,
      unit_amount_cny: this.unit_amount_cny,
      product: this.product,
      metadata: this.metadata,
      active: this.active,
    };

    return ajax("/s/admin/plans", { method: "post", data });
  },

  update() {
    const data = {
      nickname: this.nickname,
      trial_period_days: this.parseTrialPeriodDays,
      features: this.features,
      metadata: this.metadata,
      active: this.active,
    };

    return ajax(`/s/admin/plans/${this.id}`, { method: "patch", data });
  },
});

AdminPlan.reopenClass({
  findAll(data) {
    return ajax("/s/admin/plans", { method: "get", data }).then((result) =>
      result.map((plan) => AdminPlan.create(plan))
    );
  },

  find(id) {
    return ajax(`/s/admin/plans/${id}`, { method: "get" }).then((plan) =>
      AdminPlan.create(plan)
    );
  },
});

export default AdminPlan;
