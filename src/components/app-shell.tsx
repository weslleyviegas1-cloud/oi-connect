import type { ReactNode } from "react";
import { Link } from "@tanstack/react-router";
import { usePlayer } from "@/hooks/use-player";

export function AppShell({ children }: { children: ReactNode }) {
  const player = usePlayer();
  const isOwner = player.profile?.role === "super_admin";
  const navClass = "px-3 py-2 text-sm text-muted-foreground hover:text-foreground";
  const active = { className: "px-3 py-2 text-sm text-foreground border-b-2 border-primary" };
  return (
    <div className="flex min-h-screen flex-col">
      <header className="border-b bg-surface">
        <div className="mx-auto flex max-w-6xl flex-wrap items-center gap-x-6 gap-y-2 px-4 py-3">
          <Link to="/" className="flex items-center gap-2 font-semibold tracking-tight">
            <span className="grid size-7 place-items-center bg-primary font-mono text-xs text-primary-foreground">OI</span>
            WORLD ECONOMY
          </Link>
          <nav className="order-last flex w-full flex-wrap items-center sm:order-none sm:w-auto sm:flex-1">
            <Link to="/" className={navClass} activeProps={active} activeOptions={{ exact: true }}>Início</Link>
            <Link to="/conta" className={navClass} activeProps={active}>Minha conta</Link>
            {isOwner && <Link to="/admin" className={navClass} activeProps={active}>Administração</Link>}
          </nav>
          {player.user ? (
            <div className="flex items-center gap-3 text-sm">
              <span className="hidden text-muted-foreground sm:inline">{player.user.email}</span>
              <button type="button" onClick={() => void player.signOut()} className="border px-3 py-1.5 hover:bg-accent">Sair</button>
            </div>
          ) : (
            <Link to="/auth" className="bg-primary px-3 py-1.5 text-sm font-medium text-primary-foreground hover:opacity-90">Entrar</Link>
          )}
        </div>
      </header>
      <main className="mx-auto w-full max-w-6xl flex-1 px-4 py-8">{children}</main>
      <footer className="border-t text-xs text-muted-foreground">
        <div className="mx-auto max-w-6xl px-4 py-4">WORLD ECONOMY — plataforma de um servidor Minecraft Bedrock próprio.</div>
      </footer>
    </div>
  );
}

export function PageHeader({ eyebrow, title, description }: { eyebrow: string; title: string; description: string }) {
  return (
    <div className="mb-8 border-b pb-6">
      <p className="font-mono text-xs uppercase tracking-widest text-primary">{eyebrow}</p>
      <h1 className="mt-2 text-3xl font-semibold tracking-tight">{title}</h1>
      <p className="mt-2 max-w-2xl text-muted-foreground">{description}</p>
    </div>
  );
}

export function StatusRow({ label, value, note }: { label: string; value: string; note?: string }) {
  return (
    <div className="grid gap-1 border-b py-4 sm:grid-cols-[220px_1fr]">
      <dt className="text-sm text-muted-foreground">{label}</dt>
      <dd>
        <span className="font-medium">{value}</span>
        {note && <p className="mt-1 text-sm text-muted-foreground">{note}</p>}
      </dd>
    </div>
  );
}

export function Unavailable({ title, text }: { title: string; text: string }) {
  return (
    <section className="border border-dashed p-5">
      <div className="flex items-center gap-2">
        <span className="font-mono text-[11px] uppercase tracking-widest text-warning">Em preparação</span>
      </div>
      <h2 className="mt-2 font-semibold">{title}</h2>
      <p className="mt-1 text-sm text-muted-foreground">{text}</p>
    </section>
  );
}