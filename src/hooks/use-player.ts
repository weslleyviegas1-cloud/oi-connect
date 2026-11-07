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
  minecraft_username?: string | null;
  account_status?: "active" | "suspended";
  country_spawn_x?: number | null;
  country_spawn_y?: number | null;
  country_spawn_z?: number | null;
  country_spawn_name?: string | null;
  global_spawn_x?: number | null;
  global_spawn_y?: number | null;
  global_spawn_z?: number | null;
  global_spawn_name?: string | null;
};

export function usePlayer() {
  const [user, setUser] = useState<User | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [ready, setReady] = useState(false);

  const loadProfile = useCallback(async (u: User | null) => {
    if (!u) { setProfile(null); return; }
    const { data, error } = await supabase
      .from("profiles")
      .select("id, username, avatar_url, player_number, role, country_id, registration_status, minecraft_username, account_status")
      .eq("id", u.id)
      .maybeSingle();
    if (error) throw error;
    const current = (data as Profile | null) ?? null;
    if (current?.account_status === "suspended") {
      setProfile(current);
      await supabase.auth.signOut();
      setUser(null);
      setProfile(null);
      return;
    }
    const [countryResult, spawnResult] = await Promise.all([
      current?.country_id
        ? supabase.from("countries").select("name,flag,spawn_x,spawn_y,spawn_z,spawn_name").eq("id", current.country_id).maybeSingle()
        : Promise.resolve({ data: null, error: null }),
      supabase.from("world_spawn").select("name,coord_x,coord_y,coord_z").eq("id", true).maybeSingle(),
    ]);
    const country = countryResult.data;
    const globalSpawn = spawnResult.data;
    setProfile(current ? {
      ...current,
      country_name: country?.name ?? null,
      country_flag: country?.flag ?? null,
      country_spawn_x: country?.spawn_x ?? null,
      country_spawn_y: country?.spawn_y ?? null,
      country_spawn_z: country?.spawn_z ?? null,
      country_spawn_name: country?.spawn_name ?? null,
      global_spawn_x: globalSpawn?.coord_x ?? null,
      global_spawn_y: globalSpawn?.coord_y ?? null,
      global_spawn_z: globalSpawn?.coord_z ?? null,
      global_spawn_name: globalSpawn?.name ?? null,
    } : null);
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
