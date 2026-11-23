import { canRegisterServiceWorker } from "./pwa-guard";

type Listener = () => void;
let updated = false;
const listeners = new Set<Listener>();
export const pwaStatus = {
  get updated() { return updated; },
  subscribe(l: Listener) { listeners.add(l); return () => { listeners.delete(l); }; },
};

async function unregisterAppSw() {
  if (!("serviceWorker" in navigator)) return;
  const regs = await navigator.serviceWorker.getRegistrations();
  await Promise.all(regs.filter(r => r.active?.scriptURL.endsWith("/sw.js")).map(r => r.unregister()));
}

/** Only registrar of the app service worker. Call from useEffect. */
export async function setupServiceWorker() {
  if (typeof window === "undefined" || !("serviceWorker" in navigator)) return;
  let inIframe = true;
  try { inIframe = window.self !== window.top; } catch { inIframe = true; }
  const ok = canRegisterServiceWorker({ prod: import.meta.env.PROD, hostname: window.location.hostname, search: window.location.search, inIframe });
  if (!ok) { await unregisterAppSw(); return; }
  if (navigator.serviceWorker.controller) {
    navigator.serviceWorker.addEventListener("controllerchange", () => { updated = true; listeners.forEach(l => l()); }, { once: true });
  }
  const { registerSW } = await import("virtual:pwa-register");
  registerSW({
    immediate: true,
    onRegisteredSW(_url, reg) {
      if (reg) setInterval(() => { if (navigator.onLine) void reg.update(); }, 60 * 60 * 1000);
    },
  });
}
