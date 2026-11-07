import { useState, type FormEvent } from "react";
import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { Globe2, LogIn, UserPlus } from "lucide-react";
import { supabase } from "@/lib/supabase";

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
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setBusy(true); setMsg("");
    try {
      if (mode === "signup") {
        if (username.trim().length < 3) throw new Error("O nome de jogador precisa de pelo menos 3 letras.");
        const { data, error } = await supabase.auth.signUp({
          email, password,
          options: { data: { username: username.trim() }, emailRedirectTo: window.location.origin },
        });
        if (error) throw error;
        if (!data.session) { setMsg("Conta criada! Confira seu e-mail para confirmar e depois entre."); return; }
      } else {
        const { error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw new Error("E-mail ou senha incorretos.");
      }
      navigate({ to: "/" });
    } catch (err) {
      setMsg(err instanceof Error ? err.message : "Algo deu errado.");
    } finally { setBusy(false); }
  };

  return (
    <main className="we-app" style={{ display: "grid", placeItems: "center", minHeight: "100vh", padding: 16 }}>
      <section className="we-module" style={{ width: "100%", maxWidth: 420 }}>
        <div className="we-module-heading">
          <span><Globe2 /></span>
          <div><small>WORLD ECONOMY</small><h1>{mode === "login" ? "Entrar" : "Criar conta"}</h1><p>Seu país. Sua economia. Seu futuro.</p></div>
        </div>
        <form className="we-form" onSubmit={submit}>
          {mode === "signup" && <label>Nome de jogador<input value={username} onChange={e => setUsername(e.target.value)} maxLength={24} required /></label>}
          <label>E-mail<input type="email" value={email} onChange={e => setEmail(e.target.value)} required /></label>
          <label>Senha<input type="password" value={password} onChange={e => setPassword(e.target.value)} minLength={6} required /></label>
          <button className="we-primary" type="submit" disabled={busy}>{mode === "login" ? <><LogIn /> Entrar</> : <><UserPlus /> Criar conta</>}</button>
        </form>
        {msg && <p className="we-note">{msg}</p>}
        <p className="we-note">
          {mode === "login" ? "Ainda não tem conta? " : "Já tem conta? "}
          <button type="button" onClick={() => { setMode(mode === "login" ? "signup" : "login"); setMsg(""); }}>{mode === "login" ? "Criar conta" : "Entrar"}</button>
          {" "}<Link to="/">Voltar ao jogo</Link>
        </p>
      </section>
    </main>
  );
}
