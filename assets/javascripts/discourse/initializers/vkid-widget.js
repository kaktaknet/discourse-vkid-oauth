import { withPluginApi } from "discourse/lib/plugin-api";

// VK ID SDK Widget Integration
// Adds OneTap widget to login modal with support for VK ID, OK.ru, and Mail.ru
export default {
  name: "vkid-widget",

  initialize() {
    withPluginApi("0.8.31", (api) => {
      // Only initialize if VK ID is enabled
      if (!api.container.lookup("site-settings:main").vkid_enabled) {
        return;
      }

      // Load VK ID SDK
      this.loadVKIDSDK();

      // Add widget to login modal
      api.modifyClass("component:login-modal", {
        pluginId: "vkid-widget",

        didInsertElement() {
          this._super(...arguments);
          this.initVKIDWidget();
        },

        willDestroyElement() {
          this._super(...arguments);
          this.destroyVKIDWidget();
        },

        initVKIDWidget() {
          // Wait for SDK to load
          const checkSDK = setInterval(() => {
            if (window.VKIDSDK) {
              clearInterval(checkSDK);
              this.renderVKIDWidget();
            }
          }, 100);

          // Timeout after 5 seconds
          setTimeout(() => clearInterval(checkSDK), 5000);
        },

        renderVKIDWidget() {
          const VKID = window.VKIDSDK;
          const settings = this.siteSettings;

          // Initialize VK ID Config
          VKID.Config.init({
            app: parseInt(settings.vkid_client_id),
            redirectUrl: `${window.location.origin}/auth/vkid/callback`,
            responseMode: VKID.ConfigResponseMode.Callback,
            source: VKID.ConfigSource.LOWCODE,
            scope: settings.vkid_scope || "vkid.personal_info email phone",
          });

          // Create container for widget
          const container = document.createElement("div");
          container.id = "vkid-onetap-container";
          container.className = "vkid-widget-container";

          // Find login buttons area and insert widget
          const loginButtons = document.querySelector(".login-buttons");
          if (loginButtons) {
            loginButtons.insertBefore(container, loginButtons.firstChild);
          }

          // Render OneTap widget
          const oneTap = new VKID.OneTap();

          oneTap
            .render({
              container: container,
              showAlternativeLogin: true,
              oauthList: ["vkid", "ok_ru", "mail_ru"],
            })
            .on(VKID.WidgetEvents.ERROR, this.vkidOnError.bind(this))
            .on(
              VKID.OneTapInternalEvents.LOGIN_SUCCESS,
              this.vkidOnSuccess.bind(this)
            );

          this._vkidWidget = oneTap;
        },

        vkidOnSuccess(payload) {
          const VKID = window.VKIDSDK;
          const code = payload.code;
          const deviceId = payload.device_id;

          console.log("[VK ID] Login success, exchanging code...");

          VKID.Auth.exchangeCode(code, deviceId)
            .then((data) => {
              console.log("[VK ID] Token exchange successful");

              // Redirect to Discourse OAuth callback with code and device_id
              const callbackUrl = new URL("/auth/vkid/callback", window.location.origin);
              callbackUrl.searchParams.set("code", code);
              callbackUrl.searchParams.set("device_id", deviceId);

              window.location.href = callbackUrl.toString();
            })
            .catch(this.vkidOnError.bind(this));
        },

        vkidOnError(error) {
          console.error("[VK ID] Error:", error);

          // Show error message to user
          const errorMessage =
            error?.error_description ||
            error?.message ||
            "VK ID authentication failed. Please try again.";

          this.flash(errorMessage, "error");
        },

        destroyVKIDWidget() {
          const container = document.getElementById("vkid-onetap-container");
          if (container) {
            container.remove();
          }
        },
      });
    });
  },

  loadVKIDSDK() {
    // Check if SDK already loaded
    if (window.VKIDSDK || document.getElementById("vkid-sdk-script")) {
      return;
    }

    // Load VK ID SDK script
    const script = document.createElement("script");
    script.id = "vkid-sdk-script";
    script.src = "https://unpkg.com/@vkid/sdk@<3.0.0/dist-sdk/umd/index.js";
    script.async = true;

    script.onload = () => {
      console.log("[VK ID] SDK loaded successfully");
    };

    script.onerror = () => {
      console.error("[VK ID] Failed to load SDK");
    };

    document.head.appendChild(script);
  },
};
