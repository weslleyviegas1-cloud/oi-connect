import { useState, type FormEvent } from "react";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { AppShell } from "@/components/app-shell";
import { supabase } from "@/lib/supabase";

export const Route = createFileRoute("/auth")({
  head: () => ({
    meta: [
      { title: "Entrar — OI CONNECT" },
      { name: "description", content: "Entre ou crie sua conta de jogador no OI CONNECT." },
      { property: "og:title", content: "Entrar — OI CONNECT" },
      { property: "og:description", content: "Entre ou crie sua conta de jogador no OI CONNECT." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: AuthPage,
});

const input = "mt-1 w-full border bg-background px-3 py-2 outline-none focus:border-primary";

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
    setBusy(true);
    setMsg("");
    try {
      if (mode === "signup") {
        if (username.trim().length < 3) throw new Error("O nome precisa de pelo menos 3 caracteres.");
        if (password.length < 8) throw new Error("A senha precisa de pelo menos 8 caracteres.");
        const { data, error } = await supabase.auth.signUp({
          email: email.trim(),
          password,
          options: { data: { username: username.trim() } },
        });
        if (error) throw error;
        if (!data.session) { setMsg("Conta criada. Confirme pelo link enviado ao seu e-mail e depois entre."); return; }
      } else {
        const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
        if (error) throw new Error("E-mail ou senha incorretos.");
      }
      await navigate({ to: "/conta" });
    } catch (err) {
      setMsg(err instanceof Error ? err.message : "Não foi possível concluir.");
    } finally {
      setBusy(false);
    }
  };

  return (
    <AppShell>
      <div className="mx-auto max-w-md border bg-surface p-6">
        <div className="grid grid-cols-2 border">
          {(["login", "signup"] as const).map(m => (
            <button key={m} type="button" onClick={() => { setMode(m); setMsg(""); }}
              className={`py-2 text-sm ${mode === m ? "bg-primary font-medium text-primary-foreground" : "text-muted-foreground hover:text-foreground"}`}>
              {m === "login" ? "Entrar" : "Criar conta"}
            </button>
          ))}
        </div>
        <form onSubmit={submit} className="mt-6 grid gap-4">
          {mode === "signup" && (
            <label className="text-sm">Nome na plataforma
              <input className={input} value={username} onChange={e => setUsername(e.target.value)} maxLength={24} required />
            </label>
          )}
          <label className="text-sm">E-mail
            <input className={input} type="email" value={email} onChange={e => setEmail(e.target.value)} autoComplete="email" required />
          </label>
          <label className="text-sm">Senha
            <input className={input} type="password" value={password} onChange={e => setPassword(e.target.value)} autoComplete={mode === "login" ? "current-password" : "new-password"} required />
          </label>
          {mode === "signup" && <p className="text-xs text-muted-foreground">O nickname Bedrock será informado na sua conta em uma próxima etapa.</p>}
          {msg && <p role="status" className="border-l-2 border-warning pl-3 text-sm">{msg}</p>}
          <button type="submit" disabled={busy} className="bg-primary py-2.5 font-medium text-primary-foreground disabled:opacity-60">
            {busy ? "Aguarde..." : mode === "login" ? "Entrar" : "Criar conta"}
          </button>
        </form>
      </div>
    </AppShell>
  );
}
