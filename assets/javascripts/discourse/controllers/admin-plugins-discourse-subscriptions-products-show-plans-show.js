import Controller from "@ember/controller";
import { alias } from "@ember/object/computed";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DiscourseURL from "discourse/lib/url";
import discourseComputed from "discourse-common/utils/decorators";

const RECURRING = "recurring";
const ONE_TIME = "one_time";
const MIN_FEATURES = 3;

export default Controller.extend({
  // Also defined in settings.
  selectedCurrency: alias("model.plan.currency"),
  selectedInterval: alias("model.plan.interval"),

  init() {
    this._super();
    
    this.set("featureList", []);

    const interval = setInterval(() => {
      if (this.model) {
        let cache = this.model.plan.features.map(item => ({ feature_id: item.feature_id, feature: item.feature }));
        cache.sort((a, b) => a.feature_id - b.feature_id);

        if (!cache.length) {
          const baseFeature = { feature: '', feature_id: 0 };
          cache = Array.from({ length: MIN_FEATURES }, (_, index) => ({
            ...baseFeature,
            feature_id: index
          }))
        }

        this.set("featureList", cache);
        clearInterval(interval);
      }
    }, 1000);
    // this.set('featureList', this.model.getFeatures());
  },

  @discourseComputed("model.plan.metadata.group_name")
  selectedGroup(groupName) {
    return groupName || "no-group";
  },

  @discourseComputed("model.groups")
  availableGroups(groups) {
    return [
      {
        id: null,
        name: "no-group",
      },
      ...groups,
    ];
  },

  @discourseComputed
  currencies() {
    return [
      { id: "AUD", name: "AUD" },
      { id: "CAD", name: "CAD" },
      { id: "EUR", name: "EUR" },
      { id: "GBP", name: "GBP" },
      { id: "USD", name: "USD" },
      { id: "INR", name: "INR" },
      { id: "BRL", name: "BRL" },
      { id: "DKK", name: "DKK" },
      { id: "SGD", name: "SGD" },
      { id: "JPY", name: "JPY" },
    ];
  },

  @discourseComputed
  availableIntervals() {
    return [
      { id: "day", name: "day" },
      { id: "week", name: "week" },
      { id: "month", name: "month" },
      { id: "year", name: "year" },
    ];
  },

  @discourseComputed("model.plan.isNew")
  planFieldDisabled(isNew) {
    return !isNew;
  },

  @discourseComputed("model.product.id")
  productId(id) {
    return id;
  },

  redirect(product_id) {
    DiscourseURL.redirectTo(
      `/admin/plugins/discourse-subscriptions/products/${product_id}`
    );
  },

  actions: {
    updateText(e) {
      const text = e.target.value;
      const id = parseInt(e.target.getAttribute('data-id'));
     
      const cacheList = [...this.get('featureList')];
      cacheList[id].feature = text;

      this.set('featureList', cacheList);
    },

    addFeature() {
      if (!this.get('featureList')) {
        this.set('featureList', []);
      }

      const cacheList = [...this.get('featureList'), { feature: '', feature_id: this.get('featureList').length+1 }];
      this.set('featureList', cacheList);
    },

    removeFeature(id) {
      if (!this.get('featureList')) {
        this.set('featureList', []);
      }

      const cacheList = [...this.get('featureList')].filter((f, i) => i !== id);
      this.set('featureList', cacheList);
    },

    changeRecurring() {
      const recurring = this.get("model.plan.isRecurring");
      
      this.set("model.plan.type", recurring ? ONE_TIME : RECURRING);
      this.set("model.plan.isRecurring", !recurring);

      // If recurring is enabled, then disable system based recurring
      if (!recurring) {
        this.set("model.plan.isSystemRecurring", false);
      }
    },

    changeSystemRecurring() {
      const recurring = this.get("model.plan.isSystemRecurring");
      this.set("model.plan.isSystemRecurring", !recurring);

      // If recurring is enabled, then disable regular recurring
      if (!recurring) {
        this.set("model.plan.isRecurring", false);
      }
    },

    createPlan() {
      if (this.model.plan.metadata.group_name === "no-group") {
        this.set("model.plan.metadata.group_name", null);
      }
      
      this.get("model.plan")
        .addFeatures(this.get('featureList') || [])
        .save()
        .then(() => this.redirect(this.productId))
        .catch(popupAjaxError);
    },

    updatePlan() {
      if (this.model.plan.metadata.group_name === "no-group") {
        this.set("model.plan.metadata.group_name", null);
      }
      this.get("model.plan")
        .addFeatures(this.get('featureList') || [])
        .update()
        .then(() => this.redirect(this.productId))
        .catch(popupAjaxError);
    },
  },
});
