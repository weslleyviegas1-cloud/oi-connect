import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import {
  Activity, Bell, BookOpen, Building2, Check, ClipboardList, Flag, Landmark,
  MapPin, Plus, RefreshCw, Search, ShieldCheck, Users, Wallet, X,
} from "lucide-react";
import { supabase } from "@/lib/supabase";

type GovernmentProfile = {
  id: string;
  username: string;
  role: string;
  country_id: string | null;
  player_number?: number | null;
  minecraft_username?: string | null;
};
type Row = Record<string, any>;
type Tab = "overview" | "ministries" | "departments" | "appointments" | "decisions" | "legislation" | "announcements" | "infrastructure" | "budget";

const tabs: { id: Tab; label: string; Icon: typeof Landmark }[] = [
  { id: "overview", label: "Visão geral", Icon: Activity },
  { id: "ministries", label: "Ministérios", Icon: Landmark },
  { id: "departments", label: "Departamentos", Icon: Building2 },
  { id: "appointments", label: "Nomeações", Icon: Users },
  { id: "decisions", label: "Decisões", Icon: ClipboardList },
  { id: "legislation", label: "Legislação", Icon: BookOpen },
  { id: "announcements", label: "Comunicados", Icon: Bell },
  { id: "infrastructure", label: "Infraestrutura", Icon: MapPin },
  { id: "budget", label: "Orçamento", Icon: Wallet },
];

const dateLabel = (value?: string | null) => value ? new Date(value).toLocaleString("pt-BR") : "—";
const errorMessage = (error: unknown) => error instanceof Error ? error.message : "Falha inesperada.";
const categories = ["Administrativa", "Infraestrutura", "Educação", "Saúde", "Economia", "Segurança", "Relações exteriores", "Outras"];

export function GovernmentPortal({ profile, notify }: { profile: GovernmentProfile; notify: (message: string) => void }) {
  const [tab, setTab] = useState<Tab>("overview");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [country, setCountry] = useState<Row | null>(null);
  const [president, setPresident] = useState<Row | null>(null);
  const [dashboard, setDashboard] = useState<Row | null>(null);
  const [ministries, setMinistries] = useState<Row[]>([]);
  const [departments, setDepartments] = useState<Row[]>([]);
  const [members, setMembers] = useState<Row[]>([]);
  const [memberPermissions, setMemberPermissions] = useState<Row[]>([]);
  const [appointments, setAppointments] = useState<Row[]>([]);
  const [decisions, setDecisions] = useState<Row[]>([]);
  const [legislation, setLegislation] = useState<Row[]>([]);
  const [announcements, setAnnouncements] = useState<Row[]>([]);
  const [infrastructure, setInfrastructure] = useState<Row[]>([]);
  const [budgets, setBudgets] = useState<Row[]>([]);
  const [candidateSearch, setCandidateSearch] = useState("");
  const [candidates, setCandidates] = useState<Row[]>([]);
  const [selectedCandidate, setSelectedCandidate] = useState("");
  const [ministryForm, setMinistryForm] = useState({ name: "", description: "", purpose: "", category: "Administrativa" });
  const [departmentForm, setDepartmentForm] = useState({ ministry_id: "", name: "", description: "" });
  const [appointmentForm, setAppointmentForm] = useState({ ministry_id: "", department_id: "", position: "Ministro" });
  const [announcementForm, setAnnouncementForm] = useState({ title: "", content: "", category: "Comunicado oficial", status: "draft", ministry_id: "" });
  const [decisionForm, setDecisionForm] = useState({ title: "", description: "", category: "administrative", ministry_id: "" });
  const [legislationForm, setLegislationForm] = useState({ title: "", description: "", category: "administrative", reference_number: "", ministry_id: "" });
  const [infrastructureForm, setInfrastructureForm] = useState({ name: "", category: "Cidade", description: "", location_name: "", coord_x: "", coord_y: "", coord_z: "", ministry_id: "" });
  const [budgetForm, setBudgetForm] = useState({ title: "", fiscal_period: "", budget_type: "planned", planned_amount: "0", description: "", ministry_id: "" });

  const isAdmin = profile.role === "super_admin";
  const isPresident = profile.role === "president";
  const canManage = isAdmin || isPresident;
  const hasAnyPermission = (key: string) => isAdmin || isPresident || memberPermissions.some(permission => permission.permission_key === key);
  const countryId = profile.country_id;

  const load = useCallback(async () => {
    setLoading(true);
    try {
      if (countryId) {
        const [countryRes, presidentRes, dashboardRes, ministryRes, departmentRes, memberRes, decisionRes, lawRes, announcementRes, infraRes, budgetRes] = await Promise.all([
          supabase.from("countries").select("id,name,flag,capital,continent,currency_name,currency_code").eq("id", countryId).maybeSingle(),
          supabase.from("profiles").select("id,username,player_number").eq("country_id", countryId).eq("role", "president").maybeSingle(),
          supabase.rpc("get_government_dashboard", { p_country_id: countryId }),
          supabase.from("ministries").select("*").eq("country_id", countryId).order("name"),
          supabase.from("government_departments").select("*").eq("country_id", countryId).order("name"),
          supabase.from("government_members").select("*").eq("country_id", countryId).order("appointed_at", { ascending: false }),
          supabase.from("government_decisions").select("*").eq("country_id", countryId).order("created_at", { ascending: false }).limit(50),
          supabase.from("national_legislation").select("*").eq("country_id", countryId).order("created_at", { ascending: false }).limit(50),
          supabase.from("government_announcements").select("*").eq("country_id", countryId).order("created_at", { ascending: false }).limit(50),
          supabase.from("national_infrastructure").select("*").eq("country_id", countryId).order("created_at", { ascending: false }).limit(100),
          supabase.from("government_budgets").select("*").eq("country_id", countryId).order("created_at", { ascending: false }).limit(50),
        ]);
        if (countryRes.error) throw countryRes.error;
        setCountry(countryRes.data);
        setPresident(presidentRes.data);
        if (!dashboardRes.error) setDashboard(dashboardRes.data as Row);
        setMinistries(ministryRes.data ?? []);
        setDepartments(departmentRes.data ?? []);
        setMembers(memberRes.data ?? []);
        const ownMember = (memberRes.data ?? []).find((member: Row) => member.profile_id === profile.id && member.status === "active");
        if (ownMember) {
          const permissionResult = await supabase.from("government_member_permissions").select("permission_key,scope_type,scope_id").eq("member_id", ownMember.id);
          setMemberPermissions(permissionResult.data ?? []);
        } else setMemberPermissions([]);
        setDecisions(decisionRes.data ?? []);
        setLegislation(lawRes.data ?? []);
        setAnnouncements(announcementRes.data ?? []);
        setInfrastructure(infraRes.data ?? []);
        setBudgets(budgetRes.data ?? []);
        const errors = [ministryRes, departmentRes, memberRes, decisionRes, lawRes, announcementRes, infraRes, budgetRes].filter(result => result.error);
        if (errors.length) notify("Algumas áreas não puderam ser carregadas. Confira as permissões da Etapa 4 no Supabase.");
      } else {
        setCountry(null); setPresident(null); setDashboard(null); setMemberPermissions([]);
      }

      let appointmentQuery = supabase.from("government_appointments").select("*").eq("status", "pending").order("requested_at", { ascending: false });
      if (!isAdmin && countryId) appointmentQuery = appointmentQuery.eq("country_id", countryId);
      if (isAdmin || countryId) {
        const result = await appointmentQuery.limit(100);
        if (result.error) throw result.error;
        setAppointments(result.data ?? []);
      } else setAppointments([]);
    } catch (error) {
      notify("Não foi possível carregar o governo: " + errorMessage(error));
    } finally {
      setLoading(false);
    }
  }, [countryId, isAdmin, notify]);

  useEffect(() => { void load(); }, [load]);

  useEffect(() => {
    const search = async () => {
      if (!isPresident || !countryId || candidateSearch.trim().length < 2) { setCandidates([]); return; }
      const q = candidateSearch.trim();
      const { data, error } = await supabase.from("profiles")
        .select("id,username,minecraft_username,player_number,avatar_url")
        .eq("country_id", countryId).eq("role", "citizen")
        .eq("registration_status", "active").eq("account_status", "active")
        .or(`username.ilike.%${q}%,minecraft_username.ilike.%${q}%,player_number.eq.${/^\\d+$/.test(q) ? q : "-1"}`)
        .limit(12);
      if (!error) setCandidates(data ?? []);
    };
    const timer = window.setTimeout(() => { void search(); }, 250);
    return () => window.clearTimeout(timer);
  }, [candidateSearch, countryId, isPresident]);

  const counts = useMemo(() => ({
    ministries: ministries.filter(row => row.status === "active").length,
    departments: departments.filter(row => row.status === "active").length,
    members: members.filter(row => row.status === "active").length,
  }), [ministries, departments, members]);

  const run = async (operation: () => Promise<{ error: any }>, success: string) => {
    setBusy(true);
    try {
      const result = await operation();
      if (result.error) throw result.error;
      notify(success);
      await load();
    } catch (error) {
      notify("Operação não concluída: " + errorMessage(error));
    } finally { setBusy(false); }
  };

  const saveMinistry = (event: FormEvent) => {
    event.preventDefault();
    if (!countryId) return;
    void run(() => supabase.from("ministries").insert({ ...ministryForm, country_id: countryId, created_by: profile.id }), "Ministério cadastrado.");
    setMinistryForm({ name: "", description: "", purpose: "", category: "Administrativa" });
  };

  const saveDepartment = (event: FormEvent) => {
    event.preventDefault();
    if (!countryId) return;
    void run(() => supabase.from("government_departments").insert({
      country_id: countryId, ministry_id: departmentForm.ministry_id,
      name: departmentForm.name, description: departmentForm.description, created_by: profile.id,
    }), "Departamento cadastrado.");
    setDepartmentForm({ ministry_id: "", name: "", description: "" });
  };

  const requestAppointment = (event: FormEvent) => {
    event.preventDefault();
    if (!selectedCandidate) { notify("Selecione um cidadão para indicar."); return; }
    void run(async () => {
      const result = await supabase.rpc("request_government_appointment", {
        p_candidate_profile_id: selectedCandidate,
        p_ministry_id: appointmentForm.ministry_id || null,
        p_department_id: appointmentForm.department_id || null,
        p_position: appointmentForm.position,
      });
      return { error: result.error };
    }, "Solicitação enviada ao Super Admin. O indicado ainda não recebeu permissões.");
    setSelectedCandidate("");
    setCandidateSearch("");
  };

  const requestExoneration = (member: Row) => {
    if (!window.confirm(`Solicitar exoneração de ${member.profile?.username ?? "integrante"}? A mudança só ocorrerá após aprovação do Super Admin.`)) return;
    void run(async () => {
      const result = await supabase.rpc("request_government_exoneration", { p_member_id: member.id, p_note: null });
      return { error: result.error };
    }, "Solicitação de exoneração enviada.");
  };

  const reviewAppointment = (appointment: Row, decision: "approved" | "rejected") => {
    const label = appointment.action_type === "exoneration" ? "exoneração" : "nomeação";
    if (!window.confirm(`${decision === "approved" ? "Aprovar" : "Rejeitar"} esta solicitação de ${label}?`)) return;
    void run(async () => {
      const result = await supabase.rpc("review_government_appointment", {
        p_appointment_id: appointment.id, p_decision: decision, p_note: null, p_permission_keys: null,
      });
      return { error: result.error };
    }, decision === "approved" ? "Solicitação aprovada; permissões correspondentes foram aplicadas." : "Solicitação rejeitada.");
  };

  const saveAnnouncement = (event: FormEvent) => {
    event.preventDefault();
    if (!countryId) return;
    void run(() => supabase.from("government_announcements").insert({
      ...announcementForm, ministry_id: announcementForm.ministry_id || null, country_id: countryId, author_id: profile.id,
      published_at: announcementForm.status === "published" ? new Date().toISOString() : null,
    }), "Comunicado registrado.");
    setAnnouncementForm({ title: "", content: "", category: "Comunicado oficial", status: "draft", ministry_id: "" });
  };

  const saveDecision = (event: FormEvent) => {
    event.preventDefault();
    if (!countryId) return;
    void run(() => supabase.from("government_decisions").insert({
      ...decisionForm, ministry_id: decisionForm.ministry_id || null, country_id: countryId, author_id: profile.id, status: "draft",
    }), "Decisão salva como rascunho.");
    setDecisionForm({ title: "", description: "", category: "administrative", ministry_id: "" });
  };

  const saveLegislation = (event: FormEvent) => {
    event.preventDefault();
    if (!countryId) return;
    void run(() => supabase.from("national_legislation").insert({
      ...legislationForm, ministry_id: legislationForm.ministry_id || null, country_id: countryId, author_id: profile.id, status: "draft",
    }), "Proposta legislativa salva como rascunho.");
    setLegislationForm({ title: "", description: "", category: "administrative", reference_number: "", ministry_id: "" });
  };

  const saveInfrastructure = (event: FormEvent) => {
    event.preventDefault();
    if (!countryId) return;
    const numberOrNull = (value: string) => value.trim() === "" ? null : Number(value);
    void run(() => supabase.from("national_infrastructure").insert({
      ...infrastructureForm, ministry_id: infrastructureForm.ministry_id || null, country_id: countryId, created_by: profile.id,
      coord_x: numberOrNull(infrastructureForm.coord_x), coord_y: numberOrNull(infrastructureForm.coord_y),
      coord_z: numberOrNull(infrastructureForm.coord_z),
    }), "Registro de infraestrutura cadastrado.");
    setInfrastructureForm({ name: "", category: "Cidade", description: "", location_name: "", coord_x: "", coord_y: "", coord_z: "", ministry_id: "" });
  };

  const saveBudget = (event: FormEvent) => {
    event.preventDefault();
    if (!countryId) return;
    void run(() => supabase.from("government_budgets").insert({
      ...budgetForm, ministry_id: budgetForm.ministry_id || null, country_id: countryId, created_by: profile.id,
      planned_amount: Number(budgetForm.planned_amount || 0),
    }), "Planejamento orçamentário salvo. Nenhum saldo foi movimentado.");
    setBudgetForm({ title: "", fiscal_period: "", budget_type: "planned", planned_amount: "0", description: "", ministry_id: "" });
  };

  const publishAnnouncement = async (row: Row) => {
    await run(() => supabase.from("government_announcements").update({
      status: "published", published_at: new Date().toISOString(),
    }).eq("id", row.id), "Comunicado publicado.");
  };
  const changeMinistryStatus = async (row: Row) => {
    await run(() => supabase.from("ministries").update({
      status: row.status === "active" ? "inactive" : "active", updated_at: new Date().toISOString(),
    }).eq("id", row.id), "Situação do ministério atualizada.");
  };

  const getName = (id: string | null) => ministries.find(row => row.id === id)?.name ?? "Sem ministério";
  const getDepartmentName = (id: string | null) => departments.find(row => row.id === id)?.name ?? "Sem departamento";

  return <div className="we-admin">
    <nav className="we-admin-tabs">{tabs.map(({ id, label, Icon }) => <button key={id} type="button" className={tab === id ? "active" : ""} onClick={() => setTab(id)}><Icon/><span>{label}</span></button>)}</nav>
    <div className="we-admin-toolbar"><div><small>WORLD ECONOMY / GOVERNO NACIONAL</small><h2>{tabs.find(item => item.id === tab)?.label}</h2></div><button className="we-admin-refresh" type="button" onClick={() => void load()} disabled={loading}><RefreshCw/> Atualizar</button></div>
    {loading && <div className="we-empty">Carregando dados oficiais do governo...</div>}
    {!countryId && !isAdmin && <div className="we-note">Sua conta ainda não está vinculada a um país. As informações governamentais aparecerão após a definição do vínculo nacional.</div>}
    {country && <section className="we-panel"><header><h2><Flag/> {country.flag || "🌐"} {country.name}</h2><span className="we-tag">{isPresident ? "Painel presidencial" : isAdmin ? "Super Admin" : "Meu Governo"}</span></header><div className="we-admin-notice">{country.capital || "Capital não cadastrada"} • {country.continent || "Continente não cadastrado"} • {country.currency_name ? `${country.currency_name} (${country.currency_code ?? "código não informado"})` : "Moeda não cadastrada"}<br/>Presidente: {president?.username ?? "Nenhum presidente aprovado"}</div></section>}

    {tab === "overview" && <>
      {countryId && <div className="we-admin-stat-grid">
        <Stat label="Cidadãos registrados" value={dashboard?.citizens_count ?? "—"} Icon={Users}/>
        <Stat label="Ministérios ativos" value={counts.ministries} Icon={Landmark}/>
        <Stat label="Ministros e integrantes" value={counts.members} Icon={ShieldCheck}/>
        <Stat label="Departamentos ativos" value={counts.departments} Icon={Building2}/>
      </div>}
      <div className="we-admin-columns">
        <section className="we-panel"><header><h2><Bell/> Comunicados recentes</h2></header>{announcements.filter(row => row.status === "published").slice(0,5).map(row => <article className="we-admin-row" key={row.id}><div><b>{row.title}</b><small>{row.category} • {dateLabel(row.published_at)}</small></div></article>)}{!announcements.some(row => row.status === "published") && <div className="we-empty">Nenhum comunicado publicado.</div>}</section>
        <section className="we-panel"><header><h2><ClipboardList/> Decisões publicadas</h2></header>{decisions.filter(row => row.status === "published").slice(0,5).map(row => <article className="we-admin-row" key={row.id}><div><b>{row.title}</b><small>{row.category} • {dateLabel(row.updated_at)}</small></div></article>)}{!decisions.some(row => row.status === "published") && <div className="we-empty">Nenhuma decisão publicada.</div>}</section>
      </div>
      {isAdmin && <section className="we-panel"><header><h2><ShieldCheck/> Aprovações pendentes ({appointments.length})</h2><button type="button" onClick={() => setTab("appointments")}>Analisar</button></header><div className="we-admin-notice">As solicitações de nomeação e exoneração aguardam decisão do Super Admin. Nenhuma permissão é concedida enquanto estiverem pendentes.</div></section>}
    </>}

    {tab === "ministries" && <>
      {canManage && countryId && <form className="we-form" onSubmit={saveMinistry}>
        <label>Nome do ministério<input value={ministryForm.name} onChange={e => setMinistryForm(s => ({ ...s, name: e.target.value }))} required minLength={2}/></label>
        <label>Categoria<select value={ministryForm.category} onChange={e => setMinistryForm(s => ({ ...s, category: e.target.value }))}>{categories.map(value => <option key={value}>{value}</option>)}</select></label>
        <label className="we-admin-wide">Descrição<input value={ministryForm.description} onChange={e => setMinistryForm(s => ({ ...s, description: e.target.value }))}/></label>
        <label className="we-admin-wide">Finalidade<input value={ministryForm.purpose} onChange={e => setMinistryForm(s => ({ ...s, purpose: e.target.value }))}/></label>
        <button className="we-primary we-admin-wide" disabled={busy}><Plus/> Criar ministério</button>
      </form>}
      <section className="we-panel">{ministries.map(row => <article className="we-admin-row" key={row.id}><div><b>{row.name}</b><small>{row.category ?? "Sem categoria"} • {row.description || row.purpose || "Sem descrição"} • {row.status === "active" ? "Ativo" : "Inativo"}</small><small>Departamentos: {departments.filter(d => d.ministry_id === row.id).length} • Responsáveis: {members.filter(m => m.ministry_id === row.id && m.status === "active").length}</small></div>{canManage && <button type="button" disabled={busy} onClick={() => void changeMinistryStatus(row)}>{row.status === "active" ? "Desativar" : "Reativar"}</button>}</article>)}{!ministries.length && <div className="we-empty">Nenhum ministério cadastrado.</div>}</section>
    </>}

    {tab === "departments" && <>
      {(canManage || hasAnyPermission("department.manage")) && countryId && <form className="we-form" onSubmit={saveDepartment}>
        <label>Ministério<select value={departmentForm.ministry_id} onChange={e => setDepartmentForm(s => ({ ...s, ministry_id: e.target.value }))} required><option value="">Selecione</option>{ministries.filter(row => row.status === "active").map(row => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
        <label>Nome do departamento<input value={departmentForm.name} onChange={e => setDepartmentForm(s => ({ ...s, name: e.target.value }))} required/></label>
        <label className="we-admin-wide">Descrição<input value={departmentForm.description} onChange={e => setDepartmentForm(s => ({ ...s, description: e.target.value }))}/></label>
        <button className="we-primary we-admin-wide" disabled={busy}><Plus/> Criar departamento</button>
      </form>}
      <section className="we-panel">{departments.map(row => <article className="we-admin-row" key={row.id}><div><b>{row.name}</b><small>{getName(row.ministry_id)} • {row.description || "Sem descrição"} • {row.status === "active" ? "Ativo" : "Inativo"}</small></div></article>)}{!departments.length && <div className="we-empty">Nenhum departamento cadastrado.</div>}</section>
    </>}

    {tab === "appointments" && <>
      {isPresident && countryId && <div className="we-panel" style={{ padding: 14 }}>
        <form className="we-form" onSubmit={requestAppointment}>
          <label className="we-admin-wide">Localizar cidadão do seu país<input value={candidateSearch} onChange={e => setCandidateSearch(e.target.value)} placeholder="Nickname, Minecraft ou ID do jogador" minLength={2}/></label>
          {candidates.length > 0 && <div className="we-admin-wide we-panel">{candidates.map(candidate => <button type="button" key={candidate.id} className="we-admin-row" style={{ width: "100%", textAlign: "left" }} onClick={() => { setSelectedCandidate(candidate.id); setCandidateSearch(`${candidate.username} • #${candidate.player_number}`); setCandidates([]); }}><Users/><span>{candidate.username} • #{candidate.player_number} {candidate.minecraft_username ? `• ${candidate.minecraft_username}` : ""}</span></button>)}</div>}
          {selectedCandidate && <p className="we-note we-admin-wide">Cidadão selecionado. A nomeação ainda dependerá da aprovação do Super Admin.</p>}
          <label>Ministério<select value={appointmentForm.ministry_id} onChange={e => setAppointmentForm(s => ({ ...s, ministry_id: e.target.value, department_id: "" }))}><option value="">Cargo geral do governo</option>{ministries.filter(row => row.status === "active").map(row => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
          <label>Departamento<select value={appointmentForm.department_id} onChange={e => setAppointmentForm(s => ({ ...s, department_id: e.target.value }))}><option value="">Nenhum</option>{departments.filter(row => row.ministry_id === appointmentForm.ministry_id && row.status === "active").map(row => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
          <label>Cargo<input value={appointmentForm.position} onChange={e => setAppointmentForm(s => ({ ...s, position: e.target.value }))} required/></label>
          <button className="we-primary" disabled={busy || !selectedCandidate}><Plus/> Solicitar nomeação</button>
        </form>
      </div>}
      {appointments.map(row => <article className="we-admin-row" key={row.id}><div><b>{row.action_type === "exoneration" ? "Exoneração" : row.position}</b><small>{row.action_type === "appointment" ? `Indicado: ${row.candidate_profile_id}` : `Integrante: ${row.member_id}`} • {getName(row.ministry_id)} • {dateLabel(row.requested_at)}</small></div>{isAdmin && <><button type="button" disabled={busy} onClick={() => reviewAppointment(row,"approved")}><Check/> Aprovar</button><button type="button" disabled={busy} onClick={() => reviewAppointment(row,"rejected")}><X/> Rejeitar</button></>}</article>)}
      {!appointments.length && <div className="we-empty">Nenhuma solicitação pendente.</div>}
      {members.filter(row => row.status === "active").map(row => <article className="we-admin-row" key={row.id}><div><b>{row.position}</b><small>{getName(row.ministry_id)} • {getDepartmentName(row.department_id)} • Integrante ativo</small></div>{isPresident && <button type="button" disabled={busy} onClick={() => requestExoneration(row)}>Solicitar exoneração</button>}</article>)}
    </>}

    {tab === "decisions" && <>
      {(canManage || hasAnyPermission("decision.create")) && countryId && <form className="we-form" onSubmit={saveDecision}>
        <label>Ministério<select value={decisionForm.ministry_id} onChange={e => setDecisionForm(s => ({ ...s, ministry_id: e.target.value }))}><option value="">Nacional / Presidência</option>{ministries.map(row => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
        <label>Título<input value={decisionForm.title} onChange={e => setDecisionForm(s => ({ ...s, title: e.target.value }))} required/></label>
        <label>Categoria<select value={decisionForm.category} onChange={e => setDecisionForm(s => ({ ...s, category: e.target.value }))}>{categories.map(value => <option key={value} value={value.toLowerCase().replaceAll(" ","_")}>{value}</option>)}</select></label>
        <label className="we-admin-wide">Descrição<textarea value={decisionForm.description} onChange={e => setDecisionForm(s => ({ ...s, description: e.target.value }))} required/></label>
        <button className="we-primary we-admin-wide" disabled={busy}><Plus/> Salvar rascunho</button>
      </form>}
      <Rows rows={decisions} titleKey="title" detail={row => `${row.category} • ${row.status} • ${dateLabel(row.created_at)}`} empty="Nenhuma decisão cadastrada."/>
    </>}

    {tab === "legislation" && <>
      {(canManage || hasAnyPermission("legislation.create")) && countryId && <form className="we-form" onSubmit={saveLegislation}>
        <label>Ministério<select value={legislationForm.ministry_id} onChange={e => setLegislationForm(s => ({ ...s, ministry_id: e.target.value }))}><option value="">Nacional / Presidência</option>{ministries.map(row => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
        <label>Identificação<input value={legislationForm.reference_number} onChange={e => setLegislationForm(s => ({ ...s, reference_number: e.target.value }))} placeholder="Opcional"/></label>
        <label>Título<input value={legislationForm.title} onChange={e => setLegislationForm(s => ({ ...s, title: e.target.value }))} required/></label>
        <label>Categoria<select value={legislationForm.category} onChange={e => setLegislationForm(s => ({ ...s, category: e.target.value }))}>{categories.map(value => <option key={value} value={value.toLowerCase().replaceAll(" ","_")}>{value}</option>)}</select></label>
        <label className="we-admin-wide">Texto / descrição<textarea value={legislationForm.description} onChange={e => setLegislationForm(s => ({ ...s, description: e.target.value }))} required/></label>
        <button className="we-primary we-admin-wide" disabled={busy}><Plus/> Salvar proposta</button>
      </form>}
      <Rows rows={legislation} titleKey="title" detail={row => `${row.reference_number || "Sem número"} • ${row.status} • ${dateLabel(row.created_at)}`} empty="Nenhuma proposta legislativa cadastrada."/>
    </>}

    {tab === "announcements" && <>
      {(canManage || hasAnyPermission("announcement.create")) && countryId && <form className="we-form" onSubmit={saveAnnouncement}>
        <label>Ministério<select value={announcementForm.ministry_id} onChange={e => setAnnouncementForm(s => ({ ...s, ministry_id: e.target.value }))}><option value="">Nacional / Presidência</option>{ministries.map(row => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
        <label>Título<input value={announcementForm.title} onChange={e => setAnnouncementForm(s => ({ ...s, title: e.target.value }))} required/></label>
        <label>Categoria<input value={announcementForm.category} onChange={e => setAnnouncementForm(s => ({ ...s, category: e.target.value }))}/></label>
        <label className="we-admin-wide">Conteúdo<textarea value={announcementForm.content} onChange={e => setAnnouncementForm(s => ({ ...s, content: e.target.value }))} required/></label>
        <label>Situação<select value={announcementForm.status} onChange={e => setAnnouncementForm(s => ({ ...s, status: e.target.value }))}><option value="draft">Rascunho</option><option value="published">Publicar agora</option></select></label>
        <button className="we-primary" disabled={busy}><Plus/> Salvar comunicado</button>
      </form>}
      {announcements.map(row => <article className="we-admin-row" key={row.id}><div><b>{row.title}</b><small>{row.category} • {row.status} • {dateLabel(row.published_at ?? row.created_at)}</small><small>{row.content}</small></div>{canManage && row.status === "draft" && <button type="button" disabled={busy} onClick={() => void publishAnnouncement(row)}>Publicar</button>}</article>)}
      {!announcements.length && <div className="we-empty">Nenhum comunicado cadastrado.</div>}
    </>}

    {tab === "infrastructure" && <>
      {canManage && countryId && <form className="we-form" onSubmit={saveInfrastructure}>
        <label>Ministério responsável<select value={infrastructureForm.ministry_id} onChange={e => setInfrastructureForm(s => ({ ...s, ministry_id: e.target.value }))}><option value="">Sem ministério vinculado</option>{ministries.map(row => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
        <label>Nome<input value={infrastructureForm.name} onChange={e => setInfrastructureForm(s => ({ ...s, name: e.target.value }))} required/></label>
        <label>Categoria<select value={infrastructureForm.category} onChange={e => setInfrastructureForm(s => ({ ...s, category: e.target.value }))}>{["Cidade","Região","Aeroporto","Porto","Rodovia","Ferrovia","Hospital","Escola","Instalação pública","Outra"].map(value => <option key={value}>{value}</option>)}</select></label>
        <label className="we-admin-wide">Descrição<input value={infrastructureForm.description} onChange={e => setInfrastructureForm(s => ({ ...s, description: e.target.value }))}/></label>
        <label>Localização<input value={infrastructureForm.location_name} onChange={e => setInfrastructureForm(s => ({ ...s, location_name: e.target.value }))}/></label>
        <label>Coordenada X<input type="number" value={infrastructureForm.coord_x} onChange={e => setInfrastructureForm(s => ({ ...s, coord_x: e.target.value }))}/></label>
        <label>Coordenada Y<input type="number" value={infrastructureForm.coord_y} onChange={e => setInfrastructureForm(s => ({ ...s, coord_y: e.target.value }))}/></label>
        <label>Coordenada Z<input type="number" value={infrastructureForm.coord_z} onChange={e => setInfrastructureForm(s => ({ ...s, coord_z: e.target.value }))}/></label>
        <button className="we-primary we-admin-wide" disabled={busy}><Plus/> Cadastrar infraestrutura</button>
      </form>}
      {infrastructure.map(row => <article className="we-admin-row" key={row.id}><div><b>{row.name} • {row.category}</b><small>{row.location_name || "Localização não informada"} • {row.coord_x ?? "—"}, {row.coord_y ?? "—"}, {row.coord_z ?? "—"} • {row.status}</small></div></article>)}
      {!infrastructure.length && <div className="we-empty">Nenhuma infraestrutura cadastrada.</div>}
    </>}

    {tab === "budget" && <>
      {(canManage || hasAnyPermission("budget.read")) && countryId && <form className="we-form" onSubmit={saveBudget}>
        <label>Ministério<select value={budgetForm.ministry_id} onChange={e => setBudgetForm(s => ({ ...s, ministry_id: e.target.value }))}><option value="">Orçamento nacional</option>{ministries.map(row => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
        <label>Título do planejamento<input value={budgetForm.title} onChange={e => setBudgetForm(s => ({ ...s, title: e.target.value }))} required/></label>
        <label>Período fiscal<input value={budgetForm.fiscal_period} onChange={e => setBudgetForm(s => ({ ...s, fiscal_period: e.target.value }))} placeholder="Ex.: 2027"/></label>
        <label>Tipo<select value={budgetForm.budget_type} onChange={e => setBudgetForm(s => ({ ...s, budget_type: e.target.value }))}><option value="planned">Orçamento previsto</option><option value="expense_plan">Despesas planejadas</option><option value="investment_plan">Investimentos planejados</option></select></label>
        <label>Valor previsto<input type="number" min="0" step="0.01" value={budgetForm.planned_amount} onChange={e => setBudgetForm(s => ({ ...s, planned_amount: e.target.value }))}/></label>
        <label className="we-admin-wide">Descrição<textarea value={budgetForm.description} onChange={e => setBudgetForm(s => ({ ...s, description: e.target.value }))}/></label>
        <button className="we-primary we-admin-wide" disabled={busy}><Plus/> Salvar planejamento</button>
      </form>}
      <div className="we-note">Valores exclusivamente previstos. Este módulo não cria dinheiro, não altera saldos e não executa pagamentos.</div>
      {budgets.map(row => <article className="we-admin-row" key={row.id}><div><b>{row.title}</b><small>{row.fiscal_period || "Período não informado"} • {row.budget_type} • {Number(row.planned_amount).toLocaleString("pt-BR",{minimumFractionDigits:2})} • {row.status}</small></div></article>)}
      {!budgets.length && <div className="we-empty">Nenhum planejamento orçamentário cadastrado.</div>}
    </>}
  </div>;
}

function Stat({ label, value, Icon }: { label: string; value: string | number; Icon: typeof Landmark }) {
  return <article className="we-admin-stat"><span><Icon/></span><div><small>{label}</small><strong>{Number(value).toLocaleString("pt-BR")}</strong></div></article>;
}
function Rows({ rows, titleKey, detail, empty }: { rows: Row[]; titleKey: string; detail: (row: Row) => string; empty: string }) {
  return <section className="we-panel">{rows.map(row => <article className="we-admin-row" key={row.id}><div><b>{row[titleKey]}</b><small>{detail(row)}</small><small>{row.description}</small></div></article>)}{!rows.length && <div className="we-empty">{empty}</div>}</section>;
}
