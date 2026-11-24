import { canRegisterServiceWorker } from "./pwa-guard";

type Listener = () => void;
let updated = false;
const listeners = new Set<Listener>();
export const pwaStatus = {
  get updated() { return updated; },
  subscribe(listener: Listener) { listeners.add(listener); return () => { listeners.delete(listener); }; },
};

async function unregisterAppSw() {
  if (!("serviceWorker" in navigator)) return;
  const registrations = await navigator.serviceWorker.getRegistrations();
  await Promise.all(registrations.filter(reg => reg.active?.scriptURL.endsWith("/sw.js")).map(reg => reg.unregister()));
}

/** Register the public static worker only on the published, top-level production app. */
export async function setupServiceWorker() {
  if (typeof window === "undefined" || !("serviceWorker" in navigator)) return;
  let inIframe = true;
  try { inIframe = window.self !== window.top; } catch { inIframe = true; }
  const allowed = canRegisterServiceWorker({
    prod: import.meta.env.PROD,
    hostname: window.location.hostname,
    search: window.location.search,
    inIframe,
  });
  if (!allowed) { await unregisterAppSw(); return; }

  navigator.serviceWorker.addEventListener("controllerchange", () => {
    updated = true;
    listeners.forEach(listener => listener());
  }, { once: true });

  const registration = await navigator.serviceWorker.register("/sw.js", { scope: "/", updateViaCache: "none" });
  if (navigator.onLine) await registration.update().catch(error => console.warn("PWA update check failed:", error));
  window.setInterval(() => {
    if (navigator.onLine) void registration.update().catch(error => console.warn("PWA update check failed:", error));
  }, 60 * 60 * 1000);
}
