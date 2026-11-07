import { createClient } from "@supabase/supabase-js";

// Publishable key: safe to ship to the browser; access is controlled by RLS policies.
const SUPABASE_URL = "https://minirkotshmgidgymndt.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_E3OujDIHY2yyqFk0H4DWVg_5yZ6ySdw";

export const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: {
    storage: typeof window !== "undefined" ? window.localStorage : undefined,
    persistSession: typeof window !== "undefined",
    autoRefreshToken: typeof window !== "undefined",
  },
});
