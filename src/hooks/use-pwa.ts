import { useEffect, useState } from "react";
import { pwaStatus } from "@/lib/pwa";

type PromptEvent = Event & { prompt: () => Promise<void>; userChoice: Promise<{ outcome: "accepted" | "dismissed" }> };
let deferred: PromptEvent | null = null;
const subs = new Set<() => void>();
if (typeof window !== "undefined") {
  window.addEventListener("beforeinstallprompt", e => { e.preventDefault(); deferred = e as PromptEvent; subs.forEach(f => f()); });
  window.addEventListener("appinstalled", () => { deferred = null; subs.forEach(f => f()); });
}

export type InstallPlatform = "ios" | "android" | "desktop";

function isStandalone() {
  return window.matchMedia("(display-mode: standalone)").matches
    || window.matchMedia("(display-mode: window-controls-overlay)").matches
    || (navigator as Navigator & { standalone?: boolean }).standalone === true;
}
function detectPlatform(): InstallPlatform {
  const ua = navigator.userAgent;
  const iPadOS = navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1;
  if (/iPhone|iPad|iPod/.test(ua) || iPadOS) return "ios";
  if (/Android/.test(ua)) return "android";
  return "desktop";
}

export function useInstall() {
  const [state, setState] = useState({ ready: false, installed: false, canPrompt: false, platform: "desktop" as InstallPlatform, justInstalled: false });
  useEffect(() => {
    const sync = () => setState(s => ({ ...s, ready: true, installed: isStandalone(), canPrompt: !!deferred, platform: detectPlatform() }));
    sync();
    subs.add(sync);
    const onInstalled = () => setState(s => ({ ...s, justInstalled: true }));
    window.addEventListener("appinstalled", onInstalled);
    const mq = window.matchMedia("(display-mode: standalone)");
    mq.addEventListener("change", sync);
    return () => { subs.delete(sync); window.removeEventListener("appinstalled", onInstalled); mq.removeEventListener("change", sync); };
  }, []);
  const promptInstall = async (): Promise<"accepted" | "dismissed" | "unavailable"> => {
    if (!deferred) return "unavailable";
    const ev = deferred;
    await ev.prompt();
    const { outcome } = await ev.userChoice;
    deferred = null;
    subs.forEach(f => f());
    return outcome;
  };
  return { ...state, promptInstall };
}

export function useOnline() {
  const [online, setOnline] = useState(true);
  useEffect(() => {
    const on = () => setOnline(navigator.onLine);
    on();
    window.addEventListener("online", on); window.addEventListener("offline", on);
    return () => { window.removeEventListener("online", on); window.removeEventListener("offline", on); };
  }, []);
  return online;
}

export function useAppUpdated() {
  const [u, setU] = useState(false);
  useEffect(() => { setU(pwaStatus.updated); return pwaStatus.subscribe(() => setU(pwaStatus.updated)); }, []);
  return u;
}
