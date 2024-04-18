import Component from "@ember/component";
import discourseComputed from "discourse-common/utils/decorators";

const RECURRING = "recurring";

export default Component.extend({
  tagName: "",

  @discourseComputed("selectedPlan")
  selectedClass(planId) {
    return planId === this.plan.id ? "btn-primary" : "";
  },

  @discourseComputed("plan.type")
  recurringPlan(type) {
    return type === RECURRING;
  },

  @discourseComputed("plan.metadata.is_system_recurring")
  systemRecurring(type) {
    return type === 'true';
  },

  actions: {
    planClick() {
      setTimeout(() => {
        document.querySelector(".payment-list").scrollIntoView();
      }, 100)

      this.clickPlan(this.plan);
      return false;
    },
  },
});
