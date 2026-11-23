import { useEffect, useState, type FormEvent } from "react";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { Eye, EyeOff, LoaderCircle } from "lucide-react";
import { AppShell } from "@/components/app-shell";
import { supabase } from "@/lib/supabase";

export const Route = createFileRoute("/auth")({
  head: () => ({
    meta: [
      { title: "Entrar — WORLD ECONOMY" },
      { name: "description", content: "Entre ou crie sua conta de jogador no WORLD ECONOMY." },
      { property: "og:title", content: "Entrar — WORLD ECONOMY" },
      { property: "og:description", content: "Entre ou crie sua conta de jogador no WORLD ECONOMY." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: AuthPage,
});

type Mode = "login" | "signup" | "forgot" | "recover";
const input = "mt-1 w-full border bg-background px-3 py-2.5 pr-11 outline-none transition-colors focus:border-primary disabled:opacity-60";

function friendlyError(error: unknown) {
  const authError = error as { message?: string; code?: string; status?: number };
  const code = authError?.code ?? "";
  const message = authError?.message ?? "";

  if (code === "invalid_credentials" || /invalid login credentials/i.test(message))
    return "E-mail ou senha incorretos. Confira os dados e tente novamente.";
  if (code === "email_not_confirmed" || /email not confirmed/i.test(message))
    return "Seu e-mail ainda não foi confirmado. Use o botão para reenviar o link de confirmação.";
  if (code === "user_already_exists" || /user already registered/i.test(message))
    return "Já existe uma conta com esse e-mail. Vá para Entrar ou use Esqueci minha senha.";
  if (code === "weak_password" || /password should be at least/i.test(message))
    return "A senha é fraca. Crie uma senha com pelo menos 8 caracteres.";
  if (code === "over_email_send_rate_limit" || code === "over_request_rate_limit")
    return "Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente novamente.";
  if (code === "signup_disabled")
    return "O cadastro está temporariamente desativado no servidor.";
  if (/failed to fetch|network request failed|fetch failed/i.test(message))
    return "Não foi possível alcançar o servidor de autenticação. Verifique a conexão e tente novamente.";
  return message || "Não foi possível concluir a operação. Tente novamente.";
}

function AuthPage() {
  const navigate = useNavigate();
  const [mode, setMode] = useState<Mode>("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [username, setUsername] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [msg, setMsg] = useState("");
  const [notice, setNotice] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const { data } = supabase.auth.onAuthStateChange((event) => {
      if (event === "PASSWORD_RECOVERY") {
        setMode("recover");
        setPassword("");
        setMsg("");
        setNotice("Defina uma nova senha para sua conta.");
      }
    });
    return () => data.subscription.unsubscribe();
  }, []);

  const normalizedEmail = email.trim().toLowerCase();

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setMsg("");
    setNotice("");
    try {
      if (!normalizedEmail) throw new Error("Informe seu e-mail.");

      if (mode === "forgot") {
        const { error } = await supabase.auth.resetPasswordForEmail(normalizedEmail, {
          redirectTo: window.location.origin + "/auth",
        });
        if (error) throw error;
        setNotice("Se houver uma conta cadastrada com esse e-mail, enviaremos um link para redefinir a senha. Verifique também o spam.");
        return;
      }

      if (mode === "recover") {
        if (password.length < 8) throw new Error("A nova senha precisa ter pelo menos 8 caracteres.");
        const { error } = await supabase.auth.updateUser({ password });
        if (error) throw error;
        setNotice("Senha atualizada. Sua conta está pronta para uso.");
        await navigate({ to: "/conta" });
        return;
      }

      if (mode === "signup") {
        const cleanName = username.trim();
        if (cleanName.length < 3 || cleanName.length > 24)
          throw new Error("O nome na plataforma precisa ter entre 3 e 24 caracteres.");
        if (password.length < 8)
          throw new Error("A senha precisa ter pelo menos 8 caracteres.");
        const { data: existingName, error: nameCheckError } = await supabase\n          .from("profiles").select("id").ilike("username", cleanName).maybeSingle();\n        if (nameCheckError) throw nameCheckError;\n        if (existingName) throw new Error("Esse nome já está em uso. Escolha outro nome na plataforma.");\n\n        const { data, error } = await supabase.auth.signUp({
          email: normalizedEmail,
          password,
          options: { data: { username: cleanName }, emailRedirectTo: window.location.origin + "/auth" },
        });
        if (error) throw error;
        if (!data.session) {
          setNotice("Cadastro recebido. Confirme o endereço pelo link enviado ao seu e-mail. Depois, volte aqui para entrar. Se não chegar, confira o spam e use Reenviar confirmação.");
          return;
        }
      } else {
        const { error } = await supabase.auth.signInWithPassword({
          email: normalizedEmail,
          password,
        });
        if (error) throw error;
      }

      await navigate({ to: "/conta" });
    } catch (error) {
      setMsg(friendlyError(error));
    } finally {
      setBusy(false);
    }
  };

  const resendConfirmation = async () => {
    if (!normalizedEmail) {
      setMsg("Informe o e-mail usado no cadastro.");
      return;
    }
    setBusy(true);
    setMsg("");
    setNotice("");
    try {
      const { error } = await supabase.auth.resend({ type: "signup", email: normalizedEmail });
      if (error) throw error;
      setNotice("Se a conta estiver aguardando confirmação, um novo link foi enviado. Confira a caixa de entrada e o spam.");
    } catch (error) {
      setMsg(friendlyError(error));
    } finally {
      setBusy(false);
    }
  };

  const title = mode === "signup" ? "Criar conta" : mode === "forgot" ? "Recuperar senha" : mode === "recover" ? "Nova senha" : "Entrar";
  const passwordLabel = mode === "recover" ? "Nova senha" : "Senha";

  return (
    <AppShell>
      <div className="mx-auto max-w-md border bg-surface p-6">
        <div className="mb-6 flex flex-col items-center border-b pb-5 text-center">
          <img src="/brand/world-economy-brand.webp" alt="WORLD ECONOMY" className="mb-3 size-36 border object-cover" />
          <h1 className="text-xl font-semibold tracking-tight">WORLD ECONOMY</h1>
          <p className="mt-1 text-sm text-muted-foreground">Acesso ao servidor Minecraft Bedrock</p>
        </div>

        {mode !== "forgot" && mode !== "recover" && (
          <div className="grid grid-cols-2 border">
            <button type="button" onClick={() => { setMode("login"); setMsg(""); setNotice(""); }}
              className={`py-2.5 text-sm transition-colors ${mode === "login" ? "bg-primary font-medium text-primary-foreground" : "text-muted-foreground hover:text-foreground"}`}>
              Entrar
            </button>
            <button type="button" onClick={() => { setMode("signup"); setMsg(""); setNotice(""); }}
              className={`py-2.5 text-sm transition-colors ${mode === "signup" ? "bg-primary font-medium text-primary-foreground" : "text-muted-foreground hover:text-foreground"}`}>
              Criar conta
            </button>
          </div>
        )}

        <form onSubmit={submit} className="mt-6 grid gap-4">
          {mode === "signup" && (
            <label className="text-sm">Nome na plataforma
              <input className={input} value={username} onChange={e => setUsername(e.target.value)} maxLength={24} minLength={3} autoComplete="nickname" required />
            </label>
          )}

          <label className="text-sm">E-mail
            <input className={input} type="email" value={email} onChange={e => setEmail(e.target.value)} autoComplete="email" autoCapitalize="none" spellCheck={false} required disabled={mode === "recover"} />
          </label>

          {mode !== "forgot" && (
            <label className="text-sm">{passwordLabel}
              <span className="relative block">
                <input className={input} type={showPassword ? "text" : "password"} value={password}
                  onChange={e => setPassword(e.target.value)}
                  autoComplete={mode === "login" ? "current-password" : "new-password"}
                  minLength={mode === "login" ? undefined : 8} required />
                <button type="button" onClick={() => setShowPassword(value => !value)}
                  className="absolute inset-y-0 right-0 flex w-11 items-center justify-center text-muted-foreground hover:text-foreground"
                  aria-label={showPassword ? "Ocultar senha" : "Mostrar senha"} aria-pressed={showPassword}>
                  {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                </button>
              </span>
            </label>
          )}

          {mode === "signup" && <p className="text-xs text-muted-foreground">Use seu nome de jogador. O nickname Bedrock será vinculado à conta na etapa de cadastro do jogador.</p>}
          {mode === "login" && (
            <button type="button" onClick={() => { setMode("forgot"); setMsg(""); setNotice(""); }}
              className="justify-self-end text-sm text-primary underline-offset-4 hover:underline">
              Esqueci minha senha
            </button>
          )}

          {notice && <p role="status" className="border-l-2 border-primary pl-3 text-sm leading-relaxed">{notice}</p>}
          {msg && <p role="alert" className="border-l-2 border-destructive pl-3 text-sm leading-relaxed">{msg}</p>}

          <button type="submit" disabled={busy} className="flex items-center justify-center gap-2 bg-primary py-3 font-medium text-primary-foreground disabled:cursor-not-allowed disabled:opacity-60">
            {busy && <LoaderCircle size={17} className="animate-spin" />}
            {busy ? "Aguarde..." : title}
          </button>

          {mode === "signup" && notice && (
            <button type="button" disabled={busy} onClick={resendConfirmation}
              className="border px-3 py-2 text-sm hover:bg-muted disabled:opacity-60">
              Reenviar confirmação
            </button>
          )}
          {mode === "login" && (
            <button type="button" disabled={busy} onClick={resendConfirmation}
              className="text-sm text-muted-foreground underline-offset-4 hover:text-foreground hover:underline">
              Reenviar confirmação de e-mail
            </button>
          )}
          {(mode === "forgot" || mode === "recover") && (
            <button type="button" onClick={() => { setMode("login"); setPassword(""); setMsg(""); setNotice(""); }}
              className="text-sm text-muted-foreground hover:text-foreground">
              Voltar para entrar
            </button>
          )}
        </form>
      </div>
    </AppShell>
  );
}
