import { useCallback, useEffect, useState } from "react";
import type { User } from "@supabase/supabase-js";
import { supabase } from "@/lib/supabase";

export type Profile = {
  id: string;
  username: string;
  avatar_url: string | null;
  player_number: number | null;
  role: "citizen" | "president" | "super_admin";
  country_id: string | null;
  country_name?: string | null;
  country_flag?: string | null;
  registration_status: "active" | "pending_presidency" | "rejected";
};

export function usePlayer() {
  const [user, setUser] = useState<User | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [ready, setReady] = useState(false);

  const loadProfile = useCallback(async (u: User | null) => {
    if (!u) { setProfile(null); return; }
    const { data, error } = await supabase
      .from("profiles")
      .select("id, username, avatar_url, player_number, role, country_id, registration_status")
      .eq("id", u.id)
      .maybeSingle();
    if (error) throw error;
    const current = (data as Profile | null) ?? null;
    if (current?.country_id) {
      const { data: country } = await supabase.from("countries").select("name,flag").eq("id", current.country_id).maybeSingle();
      setProfile({ ...current, country_name: country?.name ?? null, country_flag: country?.flag ?? null });
    } else {
      setProfile(current);
    }
  }, []);

  useEffect(() => {
    let alive = true;
    supabase.auth.getUser().then(async ({ data }) => {
      if (!alive) return;
      setUser(data.user);
      try { await loadProfile(data.user); } catch (error) { console.error("Falha ao carregar perfil:", error); }
      if (alive) setReady(true);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((event, session) => {
      if (!["SIGNED_IN", "SIGNED_OUT", "USER_UPDATED", "TOKEN_REFRESHED"].includes(event)) return;
      const u = session?.user ?? null;
      setUser(u);
      if (event !== "TOKEN_REFRESHED") void loadProfile(u).catch(error => console.error("Falha ao atualizar perfil:", error));
    });
    return () => { alive = false; sub.subscription.unsubscribe(); };
  }, [loadProfile]);

  const refreshProfile = async () => { await loadProfile(user); };

  const saveProfile = async (username: string, file: File | null) => {
    if (!user) throw new Error("Entre na sua conta primeiro.");
    let avatar_url = profile?.avatar_url ?? null;
    if (file) {
      const extension = file.name.split(".").pop()?.toLowerCase() || "png";
      const path = `${user.id}/avatar-${Date.now()}.${extension}`;
      const up = await supabase.storage.from("avatars").upload(path, file, { upsert: true });
      if (up.error) throw up.error;
      avatar_url = supabase.storage.from("avatars").getPublicUrl(path).data.publicUrl;
    }
    const { error } = await supabase.from("profiles").update({
      username: username.trim(), avatar_url,
    }).eq("id", user.id);
    if (error) throw error.code === "23505" ? new Error("Esse nome de jogador já está em uso.") : error;
    await loadProfile(user);
  };

  const signOut = async () => { await supabase.auth.signOut(); };
  return { user, profile, ready, refreshProfile, saveProfile, signOut };
}
