const PREVIEW_LABEL = /^(?:id-preview|preview)(?:-[a-z0-9]+)?--.+$/;

/** Decide whether the app-shell service worker may register in this context. */
export function canRegisterServiceWorker(opts: { prod: boolean; hostname: string; search: string; inIframe: boolean }): boolean {
  if (!opts.prod || opts.inIframe) return false;
  if (new URLSearchParams(opts.search).get("sw") === "off") return false;
  const host = opts.hostname.toLowerCase();
  const label = host.split(".")[0] ?? "";
  for (const d of ["lovable.app", "gpt-eng.com", "gptengineer.run"]) {
    if (host.endsWith(`.${d}`) && (PREVIEW_LABEL.test(label) || /^project--.+-dev$/.test(label))) return false;
  }
  for (const d of ["lovableproject.com", "lovableproject-dev.com", "beta.lovable.dev"]) {
    if (host === d || host.endsWith(`.${d}`)) return false;
  }
  if (host === "localhost" || host === "127.0.0.1") return false;
  return true;
}
