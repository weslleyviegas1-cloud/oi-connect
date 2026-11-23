import { describe, expect, it } from "vitest";
import { canRegisterServiceWorker } from "@/lib/pwa-guard";
import { avatarObjectPath, validateAvatarDimensions, validateAvatarFile } from "@/lib/avatar";

const base = { prod: true, search: "", inIframe: false };
describe("service worker guard", () => {
  it("registers on the published domain", () => expect(canRegisterServiceWorker({ ...base, hostname: "globalwolrd1.lovable.app" })).toBe(true));
  it("never registers in the Lovable preview", () => expect(canRegisterServiceWorker({ ...base, hostname: "id-preview--2c14901c.lovable.app" })).toBe(false));
  it("never registers in dev", () => expect(canRegisterServiceWorker({ ...base, prod: false, hostname: "globalwolrd1.lovable.app" })).toBe(false));
  it("never registers inside an iframe", () => expect(canRegisterServiceWorker({ ...base, inIframe: true, hostname: "globalwolrd1.lovable.app" })).toBe(false));
  it("honours ?sw=off", () => expect(canRegisterServiceWorker({ ...base, search: "?sw=off", hostname: "globalwolrd1.lovable.app" })).toBe(false));
});
describe("avatar rules", () => {
  it("rejects GIF", () => expect(validateAvatarFile({ type: "image/gif", size: 1000 })).not.toBeNull());
  it("rejects files over 8 MB", () => expect(validateAvatarFile({ type: "image/png", size: 8 * 1024 * 1024 + 1 })).not.toBeNull());
  it("accepts an 8 MB JPG", () => expect(validateAvatarFile({ type: "image/jpeg", size: 8 * 1024 * 1024 })).toBeNull());
  it("rejects images under 96px", () => expect(validateAvatarDimensions(95, 400)).not.toBeNull());
  it("accepts 96px images", () => expect(validateAvatarDimensions(96, 96)).toBeNull());
  it("reads the path from an old public URL", () =>
    expect(avatarObjectPath("https://x.supabase.co/storage/v1/object/public/avatars/u1/a.png")).toBe("u1/a.png"));
});
