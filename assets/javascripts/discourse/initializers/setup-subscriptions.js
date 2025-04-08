import { withPluginApi } from "discourse/lib/plugin-api";
import I18n from "I18n";

export default {
  name: "setup-subscriptions",
  initialize(container) {
    withPluginApi("0.8.11", (api) => {
      const siteSettings = container.lookup("service:site-settings");
      const isNavLinkEnabled =
        siteSettings.discourse_subscriptions_extra_nav_subscribe;
      if (isNavLinkEnabled) {
        api.addNavigationBarItem({
          name: "subscribe",
          displayName: I18n.t("discourse_subscriptions.navigation.subscribe"),
          href: "/s",
        });
      }

      const user = api.getCurrentUser();
      if (user) {
        api.addQuickAccessProfileItem({
          icon: "far-credit-card",
          href: `/u/${user.username}/billing/subscriptions`,
          content: "Billing",
        });
       // ✅ 订阅卡片排序逻辑：每月优先，每类按价格升序
      api.onPageChange((url) => {
        if (!url.startsWith("/s")) return;

        setTimeout(() => {
          const container = document.querySelector(".subscribe-buttons");
          if (!container) return;

          const cards = Array.from(container.querySelectorAll(".card"));

          const extractPrice = (card) => {
            const priceText = card.querySelector("h3")?.innerText || "";
            return parseFloat(priceText.replace(/[^0-9.]/g, "")) || 0;
          };

          const extractPeriod = (card) => {
            const periodText = card.querySelector(".price-period")?.innerText || "";
            if (periodText.includes("每月")) return "monthly";
            if (periodText.includes("每年")) return "yearly";
            return "other";
          };

          const monthly = cards.filter(c => extractPeriod(c) === "monthly")
                               .sort((a, b) => extractPrice(a) - extractPrice(b));
          const yearly = cards.filter(c => extractPeriod(c) === "yearly")
                              .sort((a, b) => extractPrice(a) - extractPrice(b));
          const others = cards.filter(c => !["monthly", "yearly"].includes(extractPeriod(c)));

          const sorted = [...monthly, ...yearly, ...others];
          sorted.forEach(card => container.appendChild(card));

        }, 50); // 延迟确保渲染完成
      });
    });
  },
};