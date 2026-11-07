import { useEffect, useState, type FormEvent } from "react";
import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { Globe2, LogIn, UserPlus } from "lucide-react";
import { supabase } from "@/lib/supabase";

type CountryOption = { id: string; name: string; flag: string | null; president_available: boolean; citizens_available: boolean };

export const Route = createFileRoute("/auth")({
  head: () => ({
    meta: [
      { title: "Entrar — WORLD ECONOMY" },
      { name: "description", content: "Entre ou crie sua conta de jogador no WORLD ECONOMY." },
      { property: "og:title", content: "Entrar — WORLD ECONOMY" },
      { property: "og:description", content: "Crie sua conta e comece a construir seu país." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: AuthPage,
});

function AuthPage() {
  const navigate = useNavigate();
  const [mode, setMode] = useState<"login" | "signup">("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [username, setUsername] = useState("");
  const [minecraftUsername, setMinecraftUsername] = useState("");
  const [signupOpen, setSignupOpen] = useState(true);
  const [loginEnabled, setLoginEnabled] = useState(true);
  const [playerType, setPlayerType] = useState<"citizen" | "president">("citizen");
  const [countryId, setCountryId] = useState("");
  const [countries, setCountries] = useState<CountryOption[]>([]);
  const [loadingCountries, setLoadingCountries] = useState(false);
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const loadRegistrationOptions = async () => {
      setLoadingCountries(true);
      const [countryResult, settingsResult] = await Promise.all([
        supabase.from("countries").select("id,name,flag,president_available,citizens_available").eq("is_active", true).order("name"),
        supabase.from("platform_settings").select("signup_open,login_enabled").eq("id", true).maybeSingle(),
      ]);
      if (countryResult.error) setMsg("Não foi possível carregar os países. Verifique se a migração da Etapa 3 foi executada no Supabase.");
      else setCountries((countryResult.data ?? []) as CountryOption[]);
      if (!settingsResult.error && settingsResult.data) {
        setSignupOpen(settingsResult.data.signup_open);
        setLoginEnabled(settingsResult.data.login_enabled);
      }
      setLoadingCountries(false);
    };
    void loadRegistrationOptions();
    const refresh = () => { void loadRegistrationOptions(); };
    window.addEventListener("focus", refresh);
    return () => window.removeEventListener("focus", refresh);
  }, []);

  const availableCountries = playerType === "president"
    ? countries.filter(country => country.president_available)
    : countries.filter(country => country.citizens_available);

  useEffect(() => {
    if (!availableCountries.some(country => country.id === countryId)) {
      setCountryId(availableCountries[0]?.id ?? "");
    }
  }, [playerType, countries, countryId, availableCountries]);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setMsg("");
    try {
      if (mode === "signup") {
        if (!signupOpen) throw new Error("O cadastro está temporariamente fechado pelo Super Admin.");
        if (username.trim().length < 3) throw new Error("O nome de jogador precisa de pelo menos 3 letras.");
        if (minecraftUsername.trim().length < 3 || minecraftUsername.trim().length > 32) throw new Error("Informe seu nickname Minecraft entre 3 e 32 caracteres.");
        if (!countryId) throw new Error(playerType === "president"
          ? "Nenhum país está aceitando solicitações de presidência no momento."
          : "Nenhum país está cadastrado. Aguarde a configuração pelo Super Admin.");
        const { data, error } = await supabase.auth.signUp({
          email: email.trim(),
          password,
          options: { data: { username: username.trim() } },
        });
        if (error) throw error;
        if (!data.session) {
          setMsg("A conta foi criada, mas não foi iniciada uma sessão. Confira a configuração de confirmação de e-mail no Supabase.");
          return;
        }
        const { data: registration, error: registrationError } = await supabase.rpc("register_player_v3", {
          p_type: playerType,
          p_country_id: countryId,
          p_minecraft_username: minecraftUsername.trim(),
        });
        if (registrationError) throw registrationError;
        if (registration?.status === "pending") {
          setMsg("Solicitação enviada. Sua conta ficará aguardando a aprovação do Super Admin.");
        }
      } else {
        if (!loginEnabled) throw new Error("O login está temporariamente indisponível pelo Super Admin.");
        const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
        if (error) throw new Error("E-mail ou senha incorretos.");
      }
      navigate({ to: "/" });
    } catch (err) {
      setMsg(err instanceof Error ? err.message : "Algo deu errado.");
    } finally {
      setBusy(false);
    }
  };

  return (
    <main className="we-app" style={{ display: "grid", placeItems: "center", minHeight: "100vh", padding: 16 }}>
      <section className="we-module" style={{ width: "100%", maxWidth: 440 }}>
        <div className="we-module-heading">
          <span><Globe2 /></span>
          <div><small>WORLD ECONOMY</small><h1>{mode === "login" ? "Entrar" : "Criar conta"}</h1><p>Seu país. Sua economia. Seu futuro.</p></div>
        </div>
        <form className="we-form" onSubmit={submit}>
          {mode === "signup" && <>
            <label>Nome de jogador<input value={username} onChange={e => setUsername(e.target.value)} maxLength={24} minLength={3} required /></label>
            <label>Nickname do Minecraft<input value={minecraftUsername} onChange={e => setMinecraftUsername(e.target.value)} maxLength={32} minLength={3} required placeholder="Seu nickname no Minecraft" /></label>
            <label>Tipo de jogador
              <select value={playerType} onChange={e => setPlayerType(e.target.value as "citizen" | "president")}>
                <option value="citizen">Cidadão</option>
                <option value="president">Quero solicitar a presidência</option>
              </select>
            </label>
            <label>País
              <select value={countryId} onChange={e => setCountryId(e.target.value)} required disabled={loadingCountries || availableCountries.length === 0}>
                {availableCountries.length === 0
                  ? <option value="">{loadingCountries ? "Carregando países..." : "Nenhum país disponível"}</option>
                  : availableCountries.map(country => <option key={country.id} value={country.id}>{country.flag && !/^(https?:|data:image\\/)/i.test(country.flag) ? country.flag + " " : "🏳️ "}{country.name}</option>)}
              </select>
            </label>
            {playerType === "president" && <p className="we-note">Sua solicitação será analisada pelo Super Admin. Você só será presidente depois da aprovação.</p>}
          </>}
          <label>E-mail<input type="email" value={email} onChange={e => setEmail(e.target.value)} required /></label>
          <label>Senha<input type="password" value={password} onChange={e => setPassword(e.target.value)} minLength={6} required /></label>
          <button className="we-primary" type="submit" disabled={busy || (mode === "signup" && (!countryId || loadingCountries || !signupOpen))}>
            {busy ? "Aguarde..." : mode === "login" ? <><LogIn /> Entrar</> : <><UserPlus /> Criar conta</>}
          </button>
        </form>
        {mode === "signup" && !signupOpen && <p className="we-note" role="status">O cadastro está fechado temporariamente pelo Super Admin.</p>}
        {msg && <p className="we-note" role="status">{msg}</p>}
        <p className="we-note">
          {mode === "login" ? "Ainda não tem conta? " : "Já tem conta? "}
          <button type="button" onClick={() => { setMode(mode === "login" ? "signup" : "login"); setMsg(""); }}>{mode === "login" ? "Criar conta" : "Entrar"}</button>
          {" "}<Link to="/">Voltar ao jogo</Link>
        </p>
      </section>
    </main>
  );
}
