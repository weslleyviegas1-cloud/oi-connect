import { useCallback, useEffect, useState, type FormEvent } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { AppShell, PageHeader } from "@/components/app-shell";
import { usePlayer } from "@/hooks/use-player";
import { supabase } from "@/lib/supabase";

export const Route = createFileRoute("/admin")({
  head: () => ({ meta: [
    { title: "Painel administrativo — WORLD ECONOMY" },
    { name: "description", content: "Administração de contas e jogadores do WORLD ECONOMY." },
    { name: "robots", content: "noindex, nofollow" },
  ] }),
  component: Admin,
});

type AdminPlayer = {
  id: string;
  username: string;
  minecraft_username: string | null;
  player_number: number | null;
  role: string;
  registration_status: string | null;
  account_status: "active" | "suspended" | null;
  country_name: string | null;
  email: string | null;
  created_at: string;
};

function Admin() {
  const player = usePlayer();
  const isAdmin = player.profile?.role === "super_admin";
  const [players, setPlayers] = useState<AdminPlayer[]>([]);
  const [search, setSearch] = useState("");
  const [appliedSearch, setAppliedSearch] = useState("");
  const [loading, setLoading] = useState(false);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [reload, setReload] = useState(0);

  const loadPlayers = useCallback(async () => {
    if (!isAdmin) return;
    setLoading(true);
    setError("");
    const { data, error: rpcError } = await supabase.rpc("admin_list_players", {
      p_search: appliedSearch.trim() || null,
    });
    if (rpcError) {
      setError("Não foi possível carregar os jogadores. Verifique se as migrações administrativas foram aplicadas no Supabase.");
      setPlayers([]);
    } else {
      setPlayers((data ?? []) as AdminPlayer[]);
    }
    setLoading(false);
  }, [isAdmin, appliedSearch]);

  useEffect(() => {
    if (player.ready && isAdmin) void loadPlayers();
  }, [player.ready, isAdmin, loadPlayers, reload]);

  const submitSearch = (event: FormEvent) => {
    event.preventDefault();
    setAppliedSearch(search);
  };

  const setStatus = async (target: AdminPlayer, status: "active" | "suspended") => {
    if (target.id === player.user?.id || target.role === "super_admin") return;
    let note: string | null = null;
    if (status === "suspended") {
      note = window.prompt("Motivo da suspensão (obrigatório):")?.trim() ?? null;
      if (!note) return;
    }
    setBusyId(target.id);
    setError("");
    setNotice("");
    const { error: rpcError } = await supabase.rpc("admin_set_player_status", {
      p_player_id: target.id,
      p_status: status,
      p_note: note,
    });
    if (rpcError) setError(rpcError.message || "Não foi possível atualizar a conta.");
    else {
      setNotice(status === "suspended" ? "Conta suspensa e ação registrada na auditoria." : "Conta reativada e ação registrada na auditoria.");
      setReload(value => value + 1);
    }
    setBusyId(null);
  };

  const total = players.length;
  const active = players.filter(p => (p.account_status ?? "active") === "active").length;
  const suspended = players.filter(p => p.account_status === "suspended").length;
  const pending = players.filter(p => p.registration_status === "pending").length;

  if (!player.ready) return <AppShell><p className="text-sm text-muted-foreground">Carregando sessão...</p></AppShell>;
  if (!player.user) return <AppShell><PageHeader eyebrow="Área restrita" title="Painel administrativo" description="Entre com a conta proprietária para continuar." /><Link to="/auth" className="inline-flex border border-primary bg-primary px-4 py-2 text-sm font-medium text-primary-foreground">Entrar</Link></AppShell>;
  if (!isAdmin) return <AppShell><PageHeader eyebrow="Acesso restrito" title="Painel administrativo" description="Esta área é exclusiva da conta Super Admin." /><p className="border border-warning/50 p-4 text-sm text-warning">Sua conta ainda não possui a permissão Super Admin.</p></AppShell>;

  return (
    <AppShell>
      <PageHeader eyebrow="Controle da plataforma" title="Painel administrativo" description="Gerencie contas de jogadores, acompanhe os cadastros e registre ações administrativas." />
      <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {[
          ["Jogadores encontrados", total],
          ["Contas ativas", active],
          ["Contas suspensas", suspended],
          ["Cadastros pendentes", pending],
        ].map(([label, value]) => (
          <div key={label} className="border bg-surface p-4">
            <p className="text-xs uppercase tracking-wide text-muted-foreground">{label}</p>
            <p className="mt-2 font-mono text-3xl font-semibold text-primary">{value}</p>
          </div>
        ))}
      </section>

      <section className="mt-8 border bg-surface">
        <div className="flex flex-col gap-3 border-b p-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h2 className="font-semibold">Jogadores e contas</h2>
            <p className="mt-1 text-xs text-muted-foreground">Ações protegidas por autorização no banco e registradas na auditoria.</p>
          </div>
          <button type="button" onClick={() => setReload(value => value + 1)} className="border px-3 py-2 text-sm hover:bg-accent">Atualizar lista</button>
        </div>
        <form onSubmit={submitSearch} className="flex flex-col gap-2 border-b p-4 sm:flex-row">
          <input value={search} onChange={event => setSearch(event.target.value)} placeholder="Buscar por e-mail, jogador, nickname ou número" className="min-w-0 flex-1 border bg-background px-3 py-2 text-sm outline-none focus:border-primary" />
          <button type="submit" className="border border-primary bg-primary px-4 py-2 text-sm font-medium text-primary-foreground">Pesquisar</button>
        </form>

        {error && <p role="alert" className="m-4 border border-destructive/50 p-3 text-sm text-destructive">{error}</p>}
        {notice && <p role="status" className="m-4 border border-primary/40 p-3 text-sm text-primary">{notice}</p>}
        {loading ? <p className="p-6 text-sm text-muted-foreground">Carregando jogadores...</p> : players.length === 0 ? (
          <p className="p-6 text-sm text-muted-foreground">Nenhum jogador encontrado para esta busca.</p>
        ) : (
          <div className="divide-y">
            {players.map(target => {
              const isSuspended = target.account_status === "suspended";
              const protectedAccount = target.role === "super_admin" || target.id === player.user?.id;
              return (
                <article key={target.id} className="grid gap-3 p-4 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-center">
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2">
                      <h3 className="font-medium">{target.username}</h3>
                      <span className={`border px-2 py-0.5 text-[11px] uppercase tracking-wide ${isSuspended ? "border-warning/50 text-warning" : "border-primary/40 text-primary"}`}>
                        {isSuspended ? "Suspensa" : "Ativa"}
                      </span>
                      {target.role === "super_admin" && <span className="border border-primary/40 px-2 py-0.5 text-[11px] text-primary">Super Admin</span>}
                    </div>
                    <p className="mt-1 break-all text-sm text-muted-foreground">{target.email ?? "E-mail indisponível"}</p>
                    <p className="mt-1 text-xs text-muted-foreground">Minecraft: {target.minecraft_username || "Não informado"} · Cadastro: {target.registration_status || "—"} · {target.country_name || "Sem país"}</p>
                  </div>
                  <div className="flex flex-wrap gap-2">
                    {protectedAccount ? (
                      <span className="px-3 py-2 text-xs text-muted-foreground">Conta protegida</span>
                    ) : isSuspended ? (
                      <button disabled={busyId === target.id} onClick={() => void setStatus(target, "active")} className="border border-primary px-3 py-2 text-sm text-primary disabled:opacity-50">Reativar conta</button>
                    ) : (
                      <button disabled={busyId === target.id} onClick={() => void setStatus(target, "suspended")} className="border border-warning/50 px-3 py-2 text-sm text-warning disabled:opacity-50">Suspender conta</button>
                    )}
                  </div>
                </article>
              );
            })}
          </div>
        )}
      </section>

      <section className="mt-8 grid gap-3 md:grid-cols-2">
        <div className="border border-dashed p-4">
          <p className="text-xs uppercase tracking-wide text-warning">Integração pendente</p>
          <h2 className="mt-2 font-semibold">Mercado Pago</h2>
          <p className="mt-1 text-sm text-muted-foreground">Cobranças semanais, webhooks e conciliação ainda dependem das credenciais e da configuração do vendedor.</p>
        </div>
        <div className="border border-dashed p-4">
          <p className="text-xs uppercase tracking-wide text-warning">Integração pendente</p>
          <h2 className="mt-2 font-semibold">Servidor Minecraft Bedrock</h2>
          <p className="mt-1 text-sm text-muted-foreground">Liberação automática de jogadores exige uma API ou serviço seguro conectado ao servidor. Nenhum endereço ou acesso fictício será exibido.</p>
        </div>
      </section>
    </AppShell>
  );
}
