import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import {
  Activity, Bell, Check, ChevronRight, Clipboard, Flag, Globe2, History, ImagePlus,
  MapPin, Plus, RefreshCw, Search, Settings, ShieldCheck, Users, X, UserRound,
} from "lucide-react";
import { supabase } from "@/lib/supabase";

type Country = {
  id: string; name: string; short_name: string | null; identifier: string | null; flag: string | null;
  description: string | null; capital: string | null; continent: string | null;
  currency_name: string | null; currency_code: string | null; is_active: boolean;
  citizens_available: boolean; president_available: boolean;
  coord_x: number | null; coord_y: number | null; coord_z: number | null;
  spawn_x: number | null; spawn_y: number | null; spawn_z: number | null;
  spawn_name: string | null; spawn_description: string | null;
};
type Player = {
  id: string; username: string; minecraft_username: string | null; player_number: number | null;
  role: string; registration_status: string; account_status: string; country_id: string | null;
  country_name: string | null; country_flag: string | null; avatar_url: string | null;
  email: string; created_at: string;
};
type Application = { id: string; player_id: string; country_id: string; status: string; requested_at: string; player?: Player; country?: Country };
type Stats = { countries_total: number; countries_active: number; countries_suspended: number; presidencies_available: number; citizens_total: number; presidents_total: number; applications_pending: number; users_total: number };
type Tab = "overview" | "countries" | "applications" | "players" | "nationality" | "coordinates" | "notifications" | "audit" | "settings";
const blankCountry = {
  id: "", name: "", short_name: "", identifier: "", flag: "", description: "", capital: "", continent: "",
  currency_name: "", currency_code: "", coord_x: "", coord_y: "", coord_z: "",
  spawn_x: "", spawn_y: "", spawn_z: "", spawn_name: "", spawn_description: "",
  is_active: true, citizens_available: true, president_available: false,
};
const tabItems: { id: Tab; label: string; Icon: typeof Globe2 }[] = [
  { id: "overview", label: "Visão geral", Icon: Activity },
  { id: "countries", label: "Países", Icon: Flag },
  { id: "applications", label: "Solicitações presidenciais", Icon: ShieldCheck },
  { id: "players", label: "Cidadãos e jogadores", Icon: Users },
  { id: "nationality", label: "Mudanças de nacionalidade", Icon: Flag },
  { id: "coordinates", label: "Coordenadas", Icon: MapPin },
  { id: "notifications", label: "Notificações", Icon: Bell },
  { id: "audit", label: "Auditoria", Icon: History },
  { id: "settings", label: "Configurações gerais", Icon: Settings },
];
const asNumber = (value: string) => value.trim() === "" ? null : Number(value);
const dateTime = (value: string) => new Date(value).toLocaleString("pt-BR");
const isFlagImage = (value: string | null | undefined) => !!value && /^(https?:|data:image\/)/i.test(value);

export function AdminGovernance({ notify }: { notify: (message: string) => void }) {
  const [tab, setTab] = useState<Tab>("overview");
  const [stats, setStats] = useState<Stats | null>(null);
  const [countries, setCountries] = useState<Country[]>([]);
  const [applications, setApplications] = useState<Application[]>([]);
  const [players, setPlayers] = useState<Player[]>([]);
  const [nationalityRequests, setNationalityRequests] = useState<any[]>([]);
  const [notifications, setNotifications] = useState<any[]>([]);
  const [audit, setAudit] = useState<any[]>([]);
  const [spawn, setSpawn] = useState<any>({ name: "Nascimento global", description: "", coord_x: 0, coord_y: 70, coord_z: 0, is_active: true });
  const [settings, setSettings] = useState<any>({ platform_name: "WORLD ECONOMY", logo_url: "", app_status: "online", signup_open: true, login_enabled: true, global_notice: "", maintenance_at: "", notifications_enabled: true });
  const [countryForm, setCountryForm] = useState<any>(blankCountry);
  const [flagFile, setFlagFile] = useState<File | null>(null);
  const [flagPreview, setFlagPreview] = useState("");
  const [countrySearch, setCountrySearch] = useState("");
  const [countryFilter, setCountryFilter] = useState("all");
  const [playerSearch, setPlayerSearch] = useState("");
  const [playerFilter, setPlayerFilter] = useState("all");
  const [playerCountryFilter, setPlayerCountryFilter] = useState("all");
  const [playerDateFilter, setPlayerDateFilter] = useState("all");
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    const [statsRes, countryRes, appRes, playerRes, noteRes, auditRes, spawnRes, settingsRes] = await Promise.all([
      supabase.rpc("admin_dashboard_stats"),
      supabase.from("countries").select("*").order("name"),
      supabase.from("president_applications").select("id,player_id,country_id,status,requested_at").eq("status", "pending").order("requested_at"),
      supabase.rpc("admin_list_players", { p_search: "" }),
      supabase.from("admin_notifications").select("*").is("recipient_id", null).order("created_at", { ascending: false }).limit(50),
      supabase.from("admin_audit_logs").select("*").order("created_at", { ascending: false }).limit(100),
      supabase.from("world_spawn").select("*").eq("id", true).maybeSingle(),
      supabase.from("platform_settings").select("*").eq("id", true).maybeSingle(),
    ]);
    const nationalityRes = await supabase.rpc("admin_list_nationality_change_requests");
    if (nationalityRes.error) notify("Falha ao carregar solicitações de nacionalidade: " + nationalityRes.error.message);
    else setNationalityRequests(nationalityRes.data ?? []);
    if (statsRes.error) notify("Falha ao carregar indicadores: " + statsRes.error.message); else setStats(statsRes.data as Stats);
    if (countryRes.error) notify("Falha ao carregar países: " + countryRes.error.message); else setCountries((countryRes.data ?? []) as Country[]);
    if (playerRes.error) notify("Falha ao carregar jogadores: " + playerRes.error.message); else setPlayers((playerRes.data ?? []) as Player[]);
    if (appRes.error) notify("Falha ao carregar solicitações: " + appRes.error.message);
    else {
      const rows = (appRes.data ?? []) as Application[];
      const allPlayers = (playerRes.data ?? []) as Player[];
      const allCountries = (countryRes.data ?? []) as Country[];
      setApplications(rows.map(row => ({ ...row, player: allPlayers.find(p => p.id === row.player_id), country: allCountries.find(c => c.id === row.country_id) })));
    }
    if (noteRes.error) notify("Falha ao carregar notificações: " + noteRes.error.message); else setNotifications(noteRes.data ?? []);
    if (auditRes.error) notify("Falha ao carregar auditoria: " + auditRes.error.message); else setAudit(auditRes.data ?? []);
    if (spawnRes.error) notify("Falha ao carregar nascimento global: " + spawnRes.error.message); else if (spawnRes.data) setSpawn(spawnRes.data);
    if (settingsRes.error) notify("Falha ao carregar configurações: " + settingsRes.error.message); else if (settingsRes.data) setSettings({ ...settingsRes.data, maintenance_at: settingsRes.data.maintenance_at ?? "" });
    setLoading(false);
  }, [notify]);

  useEffect(() => { void load(); }, [load]);

  const filteredCountries = useMemo(() => countries.filter(country => {
    const matchesName = country.name.toLowerCase().includes(countrySearch.toLowerCase());
    const hasPresident = players.some(player => player.country_id === country.id && player.role === "president" && player.account_status !== "suspended");
    const matchesFilter = countryFilter === "all"
      || (countryFilter === "active" && country.is_active)
      || (countryFilter === "suspended" && !country.is_active)
      || (countryFilter === "with-president" && hasPresident)
      || (countryFilter === "without-president" && !hasPresident)
      || (countryFilter === "available" && country.president_available && !hasPresident)
      || (countryFilter === "unavailable" && !country.president_available);
    return matchesName && matchesFilter;
  }), [countries, countrySearch, countryFilter, players]);

  const filteredPlayers = useMemo(() => players.filter(player => {
    const q = playerSearch.toLowerCase();
    const matches = player.username.toLowerCase().includes(q)
      || (player.minecraft_username ?? "").toLowerCase().includes(q)
      || String(player.player_number ?? "").includes(q);
    const roleMatches = playerFilter === "all"
      || (playerFilter === "citizen" && player.role === "citizen")
      || (playerFilter === "president" && player.role === "president")
      || (playerFilter === "suspended" && player.account_status === "suspended")
      || (playerFilter === "pending" && player.registration_status === "pending_presidency");
    const countryMatches = playerCountryFilter === "all" || player.country_id === playerCountryFilter;
    const ageDays = (Date.now() - new Date(player.created_at).getTime()) / 86400000;
    const dateMatches = playerDateFilter === "all"
      || (playerDateFilter === "7" && ageDays <= 7)
      || (playerDateFilter === "30" && ageDays <= 30)
      || (playerDateFilter === "90" && ageDays <= 90)
      || (playerDateFilter === "older" && ageDays > 90);
    return matches && roleMatches && countryMatches && dateMatches;
  }), [players, playerSearch, playerFilter, playerCountryFilter, playerDateFilter]);

  const editCountry = (country: Country) => {
    setCountryForm({
      ...country,
      coord_x: country.coord_x ?? "", coord_y: country.coord_y ?? "", coord_z: country.coord_z ?? "",
      spawn_x: country.spawn_x ?? "", spawn_y: country.spawn_y ?? "", spawn_z: country.spawn_z ?? "",
    });
    setFlagFile(null); setFlagPreview(country.flag ?? ""); setTab("countries");
  };

  const saveCountry = async (event: FormEvent) => {
    event.preventDefault();
    setBusy(true);
    try {
      let flagUrl = countryForm.flag || "";
      if (flagFile) {
        const extension = flagFile.name.split(".").pop()?.toLowerCase() || "png";
        const path = `${countryForm.identifier.trim().toLowerCase()}/${crypto.randomUUID()}.${extension}`;
        const upload = await supabase.storage.from("country-flags").upload(path, flagFile, { upsert: true, contentType: flagFile.type });
        if (upload.error) throw upload.error;
        flagUrl = supabase.storage.from("country-flags").getPublicUrl(path).data.publicUrl;
      }
      const { error } = await supabase.rpc("admin_upsert_country", {
        p_id: countryForm.id || null, p_name: countryForm.name, p_short_name: countryForm.short_name || null,
        p_identifier: countryForm.identifier, p_flag: flagUrl || null, p_description: countryForm.description || null,
        p_capital: countryForm.capital || null, p_continent: countryForm.continent || null,
        p_currency_name: countryForm.currency_name || null, p_currency_code: countryForm.currency_code || null,
        p_coord_x: asNumber(String(countryForm.coord_x)), p_coord_y: asNumber(String(countryForm.coord_y)), p_coord_z: asNumber(String(countryForm.coord_z)),
        p_spawn_x: asNumber(String(countryForm.spawn_x)), p_spawn_y: asNumber(String(countryForm.spawn_y)), p_spawn_z: asNumber(String(countryForm.spawn_z)),
        p_spawn_name: countryForm.spawn_name || null, p_spawn_description: countryForm.spawn_description || null,
        p_is_active: countryForm.is_active, p_citizens_available: countryForm.citizens_available,
        p_president_available: countryForm.president_available,
      });
      if (error) throw error;
      setCountryForm(blankCountry); setFlagFile(null); setFlagPreview("");
      notify("País salvo no banco de dados.");
      await load();
    } catch (error) {
      notify("Não foi possível salvar o país: " + (error instanceof Error ? error.message : "erro desconhecido"));
    } finally { setBusy(false); }
  };

  const review = async (application: Application, decision: "approved" | "rejected") => {
    if (!window.confirm(decision === "approved" ? `Aprovar ${application.player?.username ?? "este jogador"} como presidente de ${application.country?.name ?? "este país"}?` : `Recusar a solicitação de ${application.player?.username ?? "este jogador"}?`)) return;
    setBusy(true);
    const { error } = await supabase.rpc("review_president_application", { p_application_id: application.id, p_decision: decision, p_note: null });
    setBusy(false);
    if (error) notify("Não foi possível revisar a solicitação: " + error.message);
    else { notify(decision === "approved" ? "Presidência aprovada." : "Solicitação recusada."); await load(); }
  };

  const reviewNationality = async (request: any, decision: "approved" | "rejected") => {
    const note = window.prompt(decision === "approved"
      ? "Observação administrativa (opcional):"
      : "Motivo da rejeição:");
    if (note === null) return;
    if (!window.confirm(decision === "approved"
      ? "Aprovar a mudança de nacionalidade deste cidadão? O sistema verificará vínculos presidenciais e ministeriais ativos."
      : "Rejeitar esta solicitação de nacionalidade?")) return;
    setBusy(true);
    const { error } = await supabase.rpc("admin_review_nationality_change", {
      p_request_id: request.id, p_decision: decision, p_note: note,
    });
    setBusy(false);
    if (error) notify("Não foi possível revisar a solicitação: " + error.message);
    else { notify(decision === "approved" ? "Mudança de nacionalidade aprovada." : "Solicitação rejeitada."); await load(); }
  };

  const setPlayerStatus = async (player: Player) => {
    const next = player.account_status === "suspended" ? "active" : "suspended";
    const note = next === "suspended" ? window.prompt("Motivo da suspensão (opcional):") : null;
    if (next === "suspended" && note === null) return;
    if (!window.confirm(next === "suspended" ? `Suspender a conta de ${player.username}?` : `Reativar a conta de ${player.username}?`)) return;
    setBusy(true);
    const { error } = await supabase.rpc("admin_set_player_status", { p_player_id: player.id, p_status: next, p_note: note });
    setBusy(false);
    if (error) notify("Não foi possível alterar a conta: " + error.message);
    else { notify(next === "suspended" ? "Conta marcada como suspensa." : "Conta reativada."); await load(); }
  };

  const removePresident = async (player: Player) => {
    const note = window.prompt(`Motivo para encerrar a presidência de ${player.username} (opcional):`);
    if (note === null) return;
    if (!window.confirm(`Remover ${player.username} da presidência? A vaga do país será reaberta.`)) return;
    setBusy(true);
    const { error } = await supabase.rpc("admin_remove_president", { p_player_id: player.id, p_note: note });
    setBusy(false);
    if (error) notify("Não foi possível remover o presidente: " + error.message);
    else { notify("Presidência encerrada e vaga reaberta."); await load(); }
  };

  const saveSpawn = async (event: FormEvent) => {
    event.preventDefault(); setBusy(true);
    const { error } = await supabase.rpc("admin_save_world_spawn", {
      p_name: spawn.name, p_description: spawn.description || null,
      p_x: Number(spawn.coord_x), p_y: Number(spawn.coord_y), p_z: Number(spawn.coord_z), p_is_active: spawn.is_active,
    });
    setBusy(false);
    if (error) notify("Falha ao salvar coordenadas: " + error.message); else { notify("Nascimento global atualizado."); await load(); }
  };

  const copyCommand = async (x: number | string, y: number | string, z: number | string) => {
    const command = `/tp ${x} ${y} ${z}`;
    try { await navigator.clipboard.writeText(command); notify("Comando copiado com sucesso!"); }
    catch { notify("Não foi possível copiar automaticamente neste navegador."); }
  };

  const saveSettings = async (event: FormEvent) => {
    event.preventDefault(); setBusy(true);
    const { error } = await supabase.rpc("admin_save_platform_settings", {
      p_platform_name: settings.platform_name, p_logo_url: settings.logo_url || null,
      p_app_status: settings.app_status, p_signup_open: settings.signup_open,
      p_login_enabled: settings.login_enabled, p_global_notice: settings.global_notice || null,
      p_maintenance_at: settings.maintenance_at || null, p_notifications_enabled: settings.notifications_enabled,
    });
    setBusy(false);
    if (error) notify("Falha ao salvar configurações: " + error.message); else { notify("Configurações globais salvas."); await load(); }
  };

  const markRead = async (id: string) => {
    const { error } = await supabase.rpc("admin_mark_notification_read", { p_notification_id: id });
    if (error) notify("Falha ao marcar notificação: " + error.message); else await load();
  };

  const statCards = stats ? [
    ["Países cadastrados", stats.countries_total, Globe2], ["Países ativos", stats.countries_active, Flag],
    ["Países suspensos", stats.countries_suspended, X], ["Vagas presidenciais disponíveis", stats.presidencies_available, ShieldCheck],
    ["Cidadãos", stats.citizens_total, Users], ["Presidentes", stats.presidents_total, ShieldCheck],
    ["Solicitações pendentes", stats.applications_pending, Bell], ["Usuários cadastrados", stats.users_total, UserRound],
  ] as const : [];

  const input = (label: string, key: string, type = "text", required = false) => (
    <label>{label}<input type={type} value={countryForm[key] ?? ""} required={required}
      onChange={event => setCountryForm((old: any) => ({ ...old, [key]: event.target.value }))} /></label>
  );
  const check = (label: string, key: string) => (
    <label className="we-admin-check"><input type="checkbox" checked={!!countryForm[key]}
      onChange={event => setCountryForm((old: any) => ({ ...old, [key]: event.target.checked }))} />{label}</label>
  );

  return <div className="we-admin">
    <nav className="we-admin-tabs">{tabItems.map(({ id, label, Icon }) => <button key={id} type="button" className={tab === id ? "active" : ""} onClick={() => setTab(id)}><Icon/><span>{label}</span></button>)}</nav>
    <div className="we-admin-toolbar"><div><small>WORLD ECONOMY / CONTROLE CENTRAL</small><h2>{tabItems.find(item => item.id === tab)?.label}</h2></div><button className="we-admin-refresh" type="button" onClick={() => void load()} disabled={loading}><RefreshCw/> Atualizar</button></div>
    {loading && <div className="we-empty">Atualizando dados administrativos do banco...</div>}

    {tab === "overview" && <>
      <div className="we-admin-stat-grid">{statCards.map(([label, value, Icon]) => <article className="we-admin-stat" key={label}><span><Icon/></span><div><small>{label}</small><strong>{value.toLocaleString("pt-BR")}</strong></div></article>)}</div>
      <div className="we-admin-columns">
        <section className="we-panel"><header><h2><ShieldCheck/> Solicitações pendentes</h2><button type="button" onClick={() => setTab("applications")}>Ver todas <ChevronRight/></button></header>
          {applications.length ? applications.slice(0,5).map(app => <article className="we-admin-row" key={app.id}><div><b>{app.player?.username ?? "Jogador"} • #{app.player?.player_number ?? "—"}</b><small>{app.country?.flag && !isFlagImage(app.country.flag) ? app.country.flag : "🌐"} {app.country?.name ?? "País"} • {dateTime(app.requested_at)}</small></div><button type="button" onClick={() => setTab("applications")}>Analisar</button></article>) : <div className="we-empty">Nenhuma solicitação pendente.</div>}
        </section>
        <section className="we-panel"><header><h2><Activity/> Atividades recentes</h2><button type="button" onClick={() => setTab("audit")}>Auditoria <ChevronRight/></button></header>
          {audit.slice(0,6).map(item => <article className="we-admin-row" key={item.id}><div><b>{item.description}</b><small>{item.operation} • {dateTime(item.created_at)}</small></div></article>)}
          {!audit.length && <div className="we-empty">Ainda não há registros administrativos.</div>}
        </section>
      </div>
      <section className="we-panel"><header><h2><Bell/> Aviso global atual</h2></header><div className="we-admin-notice">{settings.global_notice || "Nenhum aviso global publicado."}</div></section>
    </>}

    {tab === "countries" && <>
      <form className="we-form we-admin-country-form" onSubmit={saveCountry}>
        <div className="we-admin-form-title"><div><small>CADASTRO E EDIÇÃO</small><h3>{countryForm.id ? "Editar país" : "Adicionar novo país"}</h3></div>{countryForm.id && <button type="button" className="we-danger" onClick={() => { setCountryForm(blankCountry); setFlagFile(null); setFlagPreview(""); }}>Cancelar edição</button>}</div>
        <label>Nome oficial do país<input value={countryForm.name} onChange={e => setCountryForm((s: any) => ({ ...s, name: e.target.value }))} required minLength={2}/></label>
        {input("Nome abreviado","short_name")}
        <label>Identificador exclusivo<input value={countryForm.identifier} onChange={e => setCountryForm((s: any) => ({ ...s, identifier: e.target.value.toLowerCase().replace(/[^a-z0-9-]/g,"-") }))} required placeholder="ex: united-states"/></label>
        {input("Capital","capital")}{input("Continente","continent")}
        {input("Nome da moeda","currency_name")}{input("Código da moeda","currency_code")}
        <label className="we-admin-wide">Descrição<textarea value={countryForm.description} onChange={e => setCountryForm((s: any) => ({ ...s, description: e.target.value }))}/></label>
        <div className="we-admin-flag-upload"><label>Bandeira nacional — upload de imagem<input type="file" accept="image/png,image/jpeg,image/webp,image/svg+xml" onChange={e => { const file = e.target.files?.[0] ?? null; setFlagFile(file); setFlagPreview(file ? URL.createObjectURL(file) : countryForm.flag); }}/></label>{flagPreview ? (isFlagImage(flagPreview) ? <img src={flagPreview} alt="Pré-visualização da bandeira"/> : <strong className="we-admin-flag-emoji">{flagPreview}</strong>) : <span><ImagePlus/> Pré-visualização da bandeira</span>}</div>
        <div className="we-admin-subheading">Coordenadas oficiais do país</div>
        {input("Coordenada X","coord_x","number")}{input("Coordenada Y","coord_y","number")}{input("Coordenada Z","coord_z","number")}
        <div className="we-admin-subheading">Ponto de nascimento do país</div>
        {input("Nome do ponto","spawn_name")}{input("Descrição do ponto","spawn_description")}
        {input("Nascimento X","spawn_x","number")}{input("Nascimento Y","spawn_y","number")}{input("Nascimento Z","spawn_z","number")}
        <div className="we-admin-checks">{check("País ativo","is_active")}{check("Aceitar novos cidadãos","citizens_available")}{check("Aceitar solicitações presidenciais","president_available")}</div>
        <button className="we-primary we-admin-wide" type="submit" disabled={busy}>{busy ? "Salvando..." : <><Plus/> Salvar país</>}</button>
      </form>
      <div className="we-admin-filters"><label className="we-search"><Search/><input placeholder="Pesquisar país..." value={countrySearch} onChange={e => setCountrySearch(e.target.value)}/></label>
        <select value={countryFilter} onChange={e => setCountryFilter(e.target.value)}><option value="all">Todos os países</option><option value="active">Ativos</option><option value="suspended">Suspensos</option><option value="with-president">Com presidente</option><option value="without-president">Sem presidente</option><option value="available">Disponíveis para presidência</option><option value="unavailable">Indisponíveis para presidência</option></select>
      </div>
      <div className="we-admin-country-grid">{filteredCountries.map(country => {
        const president = players.find(p => p.country_id === country.id && p.role === "president");
        const citizenCount = players.filter(p => p.country_id === country.id && p.role === "citizen" && p.account_status !== "suspended").length;
        return <article className="we-admin-country-card" key={country.id}>{country.flag ? (isFlagImage(country.flag) ? <img src={country.flag} alt={`Bandeira de ${country.name}`}/> : <span className="we-admin-no-flag">{country.flag}</span>) : <span className="we-admin-no-flag">🌐</span>}<div className="we-admin-country-copy"><b>{country.name}</b><small>{country.capital || "Capital não informada"} • {country.continent || "Continente não informado"}</small><small>Presidente: {president?.username ?? "Nenhum"} • Cidadãos: {citizenCount}</small><small>{country.is_active ? "Ativo" : "Suspenso"} • {country.president_available ? "Vaga liberada" : "Vaga fechada"}</small></div><button type="button" onClick={() => editCountry(country)}>Editar <ChevronRight/></button>{president && <button type="button" className="we-danger" disabled={busy} onClick={() => void removePresident(president)}>Remover presidente</button>}</article>;
      })}{!filteredCountries.length && <div className="we-empty">Nenhum país corresponde aos filtros.</div>}</div>
    </>}

    {tab === "applications" && <section className="we-panel"><header><h2><ShieldCheck/> Pedidos aguardando decisão</h2></header>
      {applications.map(app => <article className="we-admin-row" key={app.id}><div><b>{app.player?.username ?? "Jogador"} • #{app.player?.player_number ?? "—"}</b><small>{app.player?.minecraft_username ? "Minecraft: "+app.player.minecraft_username+" • " : ""}{app.player?.email ?? "E-mail restrito"} • {app.country?.name ?? "País"} • {dateTime(app.requested_at)}</small></div><button type="button" disabled={busy} onClick={() => app.player && window.alert(`Perfil: ${app.player.username}\nID: ${app.player.player_number}\nE-mail: ${app.player.email}\nPaís solicitado: ${app.country?.name ?? "—"}`)}>Ver perfil</button><button type="button" disabled={busy} onClick={() => void review(app,"approved")}><Check/> Aprovar</button><button type="button" className="we-danger" disabled={busy} onClick={() => void review(app,"rejected")}><X/> Recusar</button></article>)}
      {!applications.length && <div className="we-empty">Não há solicitações pendentes.</div>}
    </section>}

    {tab === "players" && <>
      <div className="we-admin-filters"><label className="we-search"><Search/><input placeholder="Pesquisar nickname ou ID..." value={playerSearch} onChange={e => setPlayerSearch(e.target.value)}/></label><select value={playerFilter} onChange={e => setPlayerFilter(e.target.value)}><option value="all">Todos os jogadores</option><option value="citizen">Cidadãos</option><option value="president">Presidentes</option><option value="suspended">Contas suspensas</option><option value="pending">Contas pendentes</option></select><select value={playerCountryFilter} onChange={e => setPlayerCountryFilter(e.target.value)}><option value="all">Todos os países</option>{countries.map(country => <option key={country.id} value={country.id}>{country.name}</option>)}</select><select value={playerDateFilter} onChange={e => setPlayerDateFilter(e.target.value)}><option value="all">Todas as datas</option><option value="7">Últimos 7 dias</option><option value="30">Últimos 30 dias</option><option value="90">Últimos 90 dias</option><option value="older">Mais de 90 dias</option></select></div>
      <section className="we-panel"><header><h2><Users/> Jogadores cadastrados ({filteredPlayers.length})</h2></header>
        {filteredPlayers.map(player => <article className="we-admin-row" key={player.id}>{player.avatar_url ? <img className="we-admin-avatar" src={player.avatar_url} alt=""/> : <span className="we-admin-avatar-fallback"><UserRound/></span>}<div><b>{player.username} • #{player.player_number ?? "—"}</b><small>{player.minecraft_username ? "Minecraft: "+player.minecraft_username+" • " : ""}{player.email} • {player.country_flag ?? ""} {player.country_name ?? "Sem país"}</small><small>{player.role} • {player.registration_status} • {player.account_status} • Cadastro: {dateTime(player.created_at)}</small></div><button type="button" disabled={busy || player.role === "super_admin"} onClick={() => void setPlayerStatus(player)}>{player.account_status === "suspended" ? "Reativar" : "Suspender"}</button></article>)}
        {!filteredPlayers.length && <div className="we-empty">Nenhum jogador encontrado.</div>}
      </section>
    </>}

    {tab === "nationality" && <section className="we-panel"><header><h2><Flag/> Solicitações de mudança de nacionalidade</h2></header>
      {nationalityRequests.map(request => <article className="we-admin-row" key={request.id}><div><b>{request.username} • #{request.player_number ?? "—"}</b><small>{request.minecraft_username ? "Minecraft: " + request.minecraft_username + " • " : ""}{request.from_country_name ?? "Sem país"} → {request.to_country_name} • {dateTime(request.requested_at)}</small></div><button type="button" disabled={busy} onClick={() => void reviewNationality(request,"approved")}><Check/> Aprovar</button><button type="button" className="we-danger" disabled={busy} onClick={() => void reviewNationality(request,"rejected")}><X/> Rejeitar</button></article>)}
      {!nationalityRequests.length && <div className="we-empty">Não há solicitações pendentes de nacionalidade.</div>}
    </section>}

    {tab === "coordinates" && <>
      <form className="we-form" onSubmit={saveSpawn}><div className="we-admin-form-title we-admin-wide"><div><small>CONFIGURAÇÃO GLOBAL</small><h3>Ponto global de nascimento</h3></div></div>
        <label>Nome do ponto<input value={spawn.name ?? ""} onChange={e => setSpawn((s: any) => ({...s,name:e.target.value}))} required/></label>
        <label>Descrição<input value={spawn.description ?? ""} onChange={e => setSpawn((s: any) => ({...s,description:e.target.value}))}/></label>
        {(["coord_x","coord_y","coord_z"] as const).map((key,i)=><label key={key}>Coordenada {"XYZ"[i]}<input type="number" value={spawn[key] ?? 0} onChange={e=>setSpawn((s:any)=>({...s,[key]:e.target.value}))} required/></label>)}
        <label className="we-admin-check"><input type="checkbox" checked={!!spawn.is_active} onChange={e=>setSpawn((s:any)=>({...s,is_active:e.target.checked}))}/> Ponto ativo</label>
        <button className="we-primary" type="submit" disabled={busy}>Salvar coordenadas globais</button>
        <div className="we-coordinates we-admin-wide"><MapPin/><code>/tp {spawn.coord_x} {spawn.coord_y} {spawn.coord_z}</code><button type="button" onClick={()=>void copyCommand(spawn.coord_x,spawn.coord_y,spawn.coord_z)}><Clipboard/> Copiar comando</button></div>
      </form>
      <section className="we-panel"><header><h2><MapPin/> Pontos de nascimento por país</h2></header>
        {countries.map(country=><article className="we-admin-row" key={country.id}><div><b>{country.flag && !isFlagImage(country.flag) ? country.flag : "🌐"} {country.name} — {country.spawn_name || "Ponto não nomeado"}</b><small>{country.spawn_x ?? "—"}, {country.spawn_y ?? "—"}, {country.spawn_z ?? "—"} • {country.spawn_description || "Sem descrição"}</small></div><button type="button" onClick={()=>{editCountry(country);setTab("countries");}}>Editar ponto</button>{country.spawn_x != null && country.spawn_y != null && country.spawn_z != null && <button type="button" onClick={()=>void copyCommand(country.spawn_x!,country.spawn_y!,country.spawn_z!)}>Copiar /tp</button>}</article>)}
      </section>
    </>}

    {tab === "notifications" && <section className="we-panel"><header><h2><Bell/> Central de notificações administrativas</h2></header>
      {notifications.map(note=><article className="we-admin-row" key={note.id}><div><b>{note.title}</b><small>{note.description} • {dateTime(note.created_at)} • {note.is_read ? "Lida" : "Não lida"}</small></div>{!note.is_read && <button type="button" onClick={()=>void markRead(note.id)}>Marcar como lida</button>}</article>)}
      {!notifications.length && <div className="we-empty">Nenhuma notificação administrativa registrada.</div>}
    </section>}

    {tab === "audit" && <section className="we-panel"><header><h2><History/> Registros administrativos</h2></header>
      {audit.map(item=><article className="we-admin-row" key={item.id}><div><b>{item.description}</b><small>{item.operation} • {item.object_type} • {item.object_id} • {dateTime(item.created_at)}</small></div></article>)}
      {!audit.length && <div className="we-empty">Nenhum registro de auditoria disponível.</div>}
    </section>}

    {tab === "settings" && <form className="we-form" onSubmit={saveSettings}>
      <div className="we-admin-form-title we-admin-wide"><div><small>CONTROLE EXCLUSIVO DO SUPER ADMIN</small><h3>Configurações da plataforma</h3></div></div>
      <label>Nome da plataforma<input value={settings.platform_name} onChange={e=>setSettings((s:any)=>({...s,platform_name:e.target.value}))}/></label>
      <label>URL da logo oficial<input value={settings.logo_url ?? ""} onChange={e=>setSettings((s:any)=>({...s,logo_url:e.target.value}))} placeholder="URL da logo existente"/></label>
      <label>Status geral<select value={settings.app_status} onChange={e=>setSettings((s:any)=>({...s,app_status:e.target.value}))}><option value="online">Online</option><option value="maintenance">Manutenção</option><option value="paused">Pausado</option></select></label>
      <label>Manutenção programada<input type="datetime-local" value={settings.maintenance_at ? String(settings.maintenance_at).slice(0,16) : ""} onChange={e=>setSettings((s:any)=>({...s,maintenance_at:e.target.value ? new Date(e.target.value).toISOString() : ""}))}/></label>
      <label className="we-admin-wide">Aviso global<textarea value={settings.global_notice ?? ""} onChange={e=>setSettings((s:any)=>({...s,global_notice:e.target.value}))}/></label>
      <div className="we-admin-checks we-admin-wide">
        <label className="we-admin-check"><input type="checkbox" checked={!!settings.signup_open} onChange={e=>setSettings((s:any)=>({...s,signup_open:e.target.checked}))}/> Cadastro aberto</label>
        <label className="we-admin-check"><input type="checkbox" checked={!!settings.login_enabled} onChange={e=>setSettings((s:any)=>({...s,login_enabled:e.target.checked}))}/> Login disponível</label>
        <label className="we-admin-check"><input type="checkbox" checked={!!settings.notifications_enabled} onChange={e=>setSettings((s:any)=>({...s,notifications_enabled:e.target.checked}))}/> Notificações habilitadas</label>
      </div>
      <button className="we-primary we-admin-wide" type="submit" disabled={busy}>Salvar configurações globais</button>
      <p className="we-note we-admin-wide">A logo é armazenada como URL de referência; a alteração visual global e o bloqueio efetivo do login/cadastro ainda exigem integração nas telas públicas.</p>
    </form>}
  </div>;
}
