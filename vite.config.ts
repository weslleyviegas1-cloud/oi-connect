// @lovable.dev/vite-tanstack-config already includes the following — do NOT add them manually
// or the app will break with duplicate plugins:
//   - TanStack devtools (dev-only, first), tanstackStart, viteReact, tailwindcss, tsConfigPaths,
//     nitro (build-only using cloudflare as a default target), VITE_* env injection, @ path alias,
//     React/TanStack dedupe, error logger plugins, and sandbox detection (port/host/strictPort).
// Never set ssr.external or resolve.external. Never add compression.
import { defineConfig } from "@lovable.dev/vite-tanstack-config";
import { VitePWA } from "vite-plugin-pwa";

export default defineConfig({
  tanstackStart: {
    server: { entry: "server" },
  },
  vite: {
    plugins: [
      VitePWA({
        // Manifest is the static public/manifest.webmanifest; registration only via src/lib/pwa.ts.
        manifest: false,
        injectRegister: null,
        registerType: "autoUpdate",
        filename: "sw.js",
        devOptions: { enabled: false },
        workbox: {
          // SSR app: no index.html shell. Navigations always go to the network; offline shows a static page.
          navigateFallback: null,
          globPatterns: ["**/*.{js,css,woff2,png,svg,webmanifest}", "offline.html"],
          cleanupOutdatedCaches: true,
          clientsClaim: true,
          skipWaiting: true,
          runtimeCaching: [
            {
              urlPattern: ({ request, url }) => request.mode === "navigate" && !url.pathname.startsWith("/~oauth"),
              handler: "NetworkOnly",
              options: { precacheFallback: { fallbackURL: "/offline.html" } },
            },
            {
              // Only same-origin hashed build assets; Supabase and any other origin are never cached.
              urlPattern: ({ url, sameOrigin }) => sameOrigin && url.pathname.startsWith("/assets/"),
              handler: "CacheFirst",
              options: { cacheName: "oi-assets", expiration: { maxEntries: 120, maxAgeSeconds: 60 * 60 * 24 * 30 } },
            },
          ],
        },
      }),
    ],
  },
});
