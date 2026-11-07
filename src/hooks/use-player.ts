import { useCallback, useEffect, useState } from "react";
import type { User } from "@supabase/supabase-js";
import { supabase } from "@/lib/supabase";

export type Profile = { id: string; username: string; avatar_url: string | null };

export function usePlayer() {
  const [user, setUser] = useState<User | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [ready, setReady] = useState(false);

  const loadProfile = useCallback(async (u: User | null) => {
    if (!u) { setProfile(null); return; }
    const { data } = await supabase.from("profiles").select("id, username, avatar_url").eq("id", u.id).maybeSingle();
    setProfile((data as Profile | null) ?? { id: u.id, username: (u.user_metadata?.["username"] as string) ?? "Jogador", avatar_url: null });
  }, []);

  useEffect(() => {
    supabase.auth.getUser().then(async ({ data }) => { setUser(data.user); await loadProfile(data.user); setReady(true); });
    const { data: sub } = supabase.auth.onAuthStateChange((event, session) => {
      if (event !== "SIGNED_IN" && event !== "SIGNED_OUT" && event !== "USER_UPDATED") return;
      const u = session?.user ?? null;
      setUser(u);
      void loadProfile(u);
    });
    return () => sub.subscription.unsubscribe();
  }, [loadProfile]);

  const saveProfile = async (username: string, file: File | null) => {
    if (!user) throw new Error("Entre na sua conta primeiro.");
    let avatar_url = profile?.avatar_url ?? null;
    if (file) {
      const path = `${user.id}/avatar-${Date.now()}.${file.name.split(".").pop() ?? "png"}`;
      const up = await supabase.storage.from("avatars").upload(path, file, { upsert: true });
      if (up.error) throw up.error;
      avatar_url = supabase.storage.from("avatars").getPublicUrl(path).data.publicUrl;
    }
    const { error } = await supabase.from("profiles").upsert({ id: user.id, username: username.trim(), avatar_url });
    if (error) throw error.code === "23505" ? new Error("Esse nome de jogador já está em uso.") : error;
    await loadProfile(user);
  };

  const signOut = async () => { await supabase.auth.signOut(); };

  return { user, profile, ready, saveProfile, signOut };
}
