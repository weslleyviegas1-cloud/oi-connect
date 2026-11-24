// @lovable.dev/vite-tanstack-config already includes the application plugins.
// Keep this configuration minimal to avoid duplicating TanStack Start or React plugins.
import { defineConfig } from "@lovable.dev/vite-tanstack-config";

export default defineConfig({
  tanstackStart: {
    server: { entry: "server" },
  },
});
