import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import {
  Activity, Bell, BookOpen, Building2, Check, ClipboardList, Flag, Landmark,
  MapPin, Plus, RefreshCw, ShieldCheck, Users, Wallet, X,
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
type Tab = "overview" | "ministries" | "departments" | "appointments" | "decisions" | "legislation" | "announcements" | "infrastructure" | "budget" | "notifications" | "audit";

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
  { id: "notifications", label: "Notificações", Icon: Bell },
  { id: "audit", label: "Histórico", Icon: ClipboardList },
];

const dateLabel = (value?: string | null) => value ? new Date(value).toLocaleString("pt-BR") : "—";
const errorMessage = (error: unknown) => error instanceof Error ? error.message : "Falha inesperada.";
const categories = ["Administrativa", "Infraestrutura", "Educação", "Saúde", "Economia", "Segurança", "Relações exteriores", "Outras"];

export function GovernmentPortal({ profile, notify }: { profile: GovernmentProfile; notify: (message: string) => void }) {
  const [tab, setTab] = useState<Tab>("overview");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [country, setCountry] = useState<Row | null>(null);
  const [adminCountries, setAdminCountries] = useState<Row[]>([]);
  const [selectedCountryId, setSelectedCountryId] = useState("");
  const [president, setPresident] = useState<Row | null>(null);
  const [dashboard, setDashboard] = useState<Row | null>(null);
  const [ministries, setMinistries] = useState<Row[]>([]);
  const [departments, setDepartments] = useState<Row[]>([]);
  const [members, setMembers] = useState<Row[]>([]);
  const [memberPermissions, setMemberPermissions] = useState<Row[]>([]);
  const [appointments, setAppointments] = useState<Row[]>([]);
  const [pendingDecisions, setPendingDecisions] = useState<Row[]>([]);
  const [pendingLegislation, setPendingLegislation] = useState<Row[]>([]);
  const [decisions, setDecisions] = useState<Row[]>([]);
  const [legislation, setLegislation] = useState<Row[]>([]);
  const [announcements, setAnnouncements] = useState<Row[]>([]);
  const [infrastructure, setInfrastructure] = useState<Row[]>([]);
  const [budgets, setBudgets] = useState<Row[]>([]);
  const [allocations, setAllocations] = useState<Row[]>([]);
  const [notifications, setNotifications] = useState<Row[]>([]);
  const [auditLogs, setAuditLogs] = useState<Row[]>([]);
  const [candidateSearch, setCandidateSearch] = useState("");
  const [candidates, setCandidates] = useState<Row[]>([]);
  const [selectedCandidate, setSelectedCandidate] = useState("");
  const [ministryForm, setMinistryForm] = useState({ name: "", description: "", purpose: "", category: "Administrativa" });
  const [editingMinistryId, setEditingMinistryId] = useState<string | null>(null);
  const [departmentForm, setDepartmentForm] = useState({ ministry_id: "", name: "", description: "", responsible_member_id: "" });
  const [editingDepartmentId, setEditingDepartmentId] = useState<string | null>(null);
  const [appointmentForm, setAppointmentForm] = useState({ ministry_id: "", department_id: "", position: "Ministro" });
  const [announcementForm, setAnnouncementForm] = useState({ title: "", content: "", category: "Comunicado oficial", status: "draft", ministry_id: "" });
  const [editingAnnouncementId, setEditingAnnouncementId] = useState<string | null>(null);
  const [decisionForm, setDecisionForm] = useState({ title: "", description: "", category: "administrative", ministry_id: "" });
  const [legislationForm, setLegislationForm] = useState({ title: "", description: "", category: "administrative", reference_number: "", ministry_id: "" });
  const [infrastructureForm, setInfrastructureForm] = useState({ name: "", category: "Cidade", description: "", location_name: "", coord_x: "", coord_y: "", coord_z: "", ministry_id: "", responsible_member_id: "" });
  const [budgetForm, setBudgetForm] = useState({ title: "", fiscal_period: "", budget_type: "planned", planned_amount: "0", description: "", ministry_id: "" });
  const [allocationForm, setAllocationForm] = useState({ budget_id: "", ministry_id: "", planned_amount: "0", description: "" });

  const isAdmin = profile.role === "super_admin";
  const isPresident = profile.role === "president";
  const canManage = isAdmin || isPresident;
  const hasAnyPermission = (key: string) => isAdmin || isPresident || memberPermissions.some(permission => permission.permission_key === key);
  const countryId = isAdmin ? (selectedCountryId || null) : profile.country_id;

  const load = useCallback(async () => {
    setLoading(true);
    try {
      if (isAdmin) {
        const countryList = await supabase.from("countries").select("id,name,flag,is_active").order("name");
        if (countryList.error) throw countryList.error;
        setAdminCountries(countryList.data ?? []);
        if (!selectedCountryId && countryList.data?.length) {
          setSelectedCountryId(countryList.data[0].id);
          setLoading(false);
          return;
        }
      }
      if (countryId) {
        const [countryRes, presidentRes, dashboardRes, ministryRes, departmentRes, memberRes, decisionRes, lawRes, announcementRes, infraRes, budgetRes, allocationRes] = await Promise.all([
          supabase.from("countries").select("id,name,flag,capital,continent,currency_name,currency_code,is_active").eq("id", countryId).maybeSingle(),
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
          supabase.from("government_budget_allocations").select("*").eq("country_id", countryId).order("created_at", { ascending: false }).limit(100),
        ]);
        if (countryRes.error) throw countryRes.error;
        setCountry(countryRes.data);
        setPresident(presidentRes.data);
        if (!dashboardRes.error) setDashboard(dashboardRes.data as Row);
        setMinistries(ministryRes.data ?? []);
        setDepartments(departmentRes.data ?? []);
        const memberRows = memberRes.data ?? [];
        const memberProfileIds = memberRows.map((member: Row) => member.profile_id);
        const memberProfilesResult = memberProfileIds.length
          ? await supabase.from("profiles").select("id,username,player_number,minecraft_username,avatar_url").in("id", memberProfileIds)
          : { data: [], error: null };
        if (memberProfilesResult.error) throw memberProfilesResult.error;
        setMembers(memberRows.map((member: Row) => ({
          ...member,
          profile: (memberProfilesResult.data ?? []).find(person => person.id === member.profile_id),
        })));
        const ownMember = memberRows.find((member: Row) => member.profile_id === profile.id && member.status === "active");
        if (ownMember) {
          const permissionResult = await supabase.from("government_member_permissions").select("permission_key,scope_type,scope_id").eq("member_id", ownMember.id);
          setMemberPermissions(permissionResult.data ?? []);
        } else setMemberPermissions([]);
        setDecisions(decisionRes.data ?? []);
        setLegislation(lawRes.data ?? []);
        setAnnouncements(announcementRes.data ?? []);
        setInfrastructure(infraRes.data ?? []);
        setBudgets(budgetRes.data ?? []);
        setAllocations(allocationRes.data ?? []);
        if (isAdmin || isPresident) {
          const auditResult = await supabase.from("government_audit_logs").select("*").eq("country_id", countryId).order("created_at", { ascending: false }).limit(100);
          if (auditResult.error) throw auditResult.error;
          const actorIds = (auditResult.data ?? []).map(row => row.actor_id).filter(Boolean);
          const actors = actorIds.length
            ? await supabase.from("profiles").select("id,username,player_number").in("id", actorIds)
            : { data: [], error: null };
          if (actors.error) throw actors.error;
          setAuditLogs((auditResult.data ?? []).map(row => ({
            ...row,
            actor: (actors.data ?? []).find(person => person.id === row.actor_id),
          })));
        } else setAuditLogs([]);
        const errors = [ministryRes, departmentRes, memberRes, decisionRes, lawRes, announcementRes, infraRes, budgetRes, allocationRes].filter(result => result.error);
        if (errors.length) notify("Algumas áreas não puderam ser carregadas. Confira as permissões da Etapa 4 no Supabase.");
      } else {
        setCountry(null); setPresident(null); setDashboard(null); setMemberPermissions([]); setAllocations([]); setAuditLogs([]);
      }

      let appointmentQuery = supabase.from("government_appointments").select("*").eq("status", "pending").order("requested_at", { ascending: false });
      if (!isAdmin && countryId) appointmentQuery = appointmentQuery.eq("country_id", countryId);
      if (isAdmin || countryId) {
        const result = await appointmentQuery.limit(100);
        if (result.error) throw result.error;
        const appointmentRows = result.data ?? [];
        const candidateIds = appointmentRows.map(row => row.candidate_profile_id).filter(Boolean);
        const memberIds = appointmentRows.map(row => row.member_id).filter(Boolean);
        const [candidateResult, memberResult] = await Promise.all([
          candidateIds.length ? supabase.from("profiles").select("id,username,player_number,minecraft_username").in("id", candidateIds) : Promise.resolve({ data: [], error: null }),
          memberIds.length ? supabase.from("government_members").select("id,profile_id,position").in("id", memberIds) : Promise.resolve({ data: [], error: null }),
        ]);
        if (candidateResult.error) throw candidateResult.error;
        if (memberResult.error) throw memberResult.error;
        const memberProfileIds = (memberResult.data ?? []).map(row => row.profile_id);
        const memberProfiles = memberProfileIds.length
          ? await supabase.from("profiles").select("id,username,player_number").in("id", memberProfileIds)
          : { data: [], error: null };
        if (memberProfiles.error) throw memberProfiles.error;
        setAppointments(appointmentRows.map(row => ({
          ...row,
          candidate: (candidateResult.data ?? []).find(person => person.id === row.candidate_profile_id),
          member: (memberResult.data ?? []).find(member => member.id === row.member_id),
          memberProfile: (memberProfiles.data ?? []).find(person => person.id === (memberResult.data ?? []).find(member => member.id === row.member_id)?.profile_id),
        })));
      } else setAppointments([]);
      const notificationQuery = isAdmin
        ? supabase.from("admin_notifications").select("*").or("recipient_id.eq." + profile.id + ",recipient_id.is.null").order("created_at", { ascending: false }).limit(100)
        : supabase.from("admin_notifications").select("*").eq("recipient_id", profile.id).order("created_at", { ascending: false }).limit(100);
      const notificationResult = await notificationQuery;
      if (notificationResult.error) throw notificationResult.error;
      setNotifications(notificationResult.data ?? []);

      if (isAdmin) {
        const [decisionQueue, legislationQueue] = await Promise.all([
          supabase.from("government_decisions").select("*").eq("status", "pending_approval").order("created_at", { ascending: false }),
          supabase.from("national_legislation").select("*").eq("status", "under_review").order("created_at", { ascending: false }),
        ]);
        if (decisionQueue.error) throw decisionQueue.error;
        if (legislationQueue.error) throw legislationQueue.error;
        setPendingDecisions(decisionQueue.data ?? []);
        setPendingLegislation(legislationQueue.data ?? []);
      } else { setPendingDecisions([]); setPendingLegislation([]); }
    } catch (error) {
      notify("Não foi possível carregar o governo: " + errorMessage(error));
    } finally {
      setLoading(false);
    }
  }, [countryId, isAdmin, notify, profile.id, selectedCountryId]);

  useEffect(() => { void load(); }, [load]);

  useEffect(() => {
    const search = async () => {
      if (!isPresident || !countryId || candidateSearch.trim().length < 2) { setCandidates([]); return; }
      const q = candidateSearch.trim();
      const base = () => supabase.from("profiles")
        .select("id,username,minecraft_username,player_number,avatar_url")
        .eq("country_id", countryId).eq("role", "citizen")
        .eq("registration_status", "active").eq("account_status", "active");
      const searches = await Promise.all([
        base().ilike("username", `%${q}%`).limit(12),
        base().ilike("minecraft_username", `%${q}%`).limit(12),
        /^\\d+$/.test(q) ? base().eq("player_number", Number(q)).limit(12) : Promise.resolve({ data: [], error: null }),
      ]);
      const error = searches.find(result => result.error)?.error;
      if (!error) setCandidates(Array.from(new Map(searches.flatMap(result => result.data ?? []).map(person => [person.id, person] as const)).values()).slice(0, 12));
    };
    const timer = window.setTimeout(() => { void search(); }, 250);
    return () => window.clearTimeout(timer);
  }, [candidateSearch, countryId, isPresident]);

  const ownMembership = members.find(member => member.profile_id === profile.id && member.status === "active");

  const counts = useMemo(() => ({
    ministries: ministries.filter(row => row.status === "active").length,
    departments: departments.filter(row => row.status === "active").length,
    members: members.filter(row => row.status === "active").length,
  }), [ministries, departments, members]);

  const run = async (operation: () => PromiseLike<{ error: any }>, success: string) => {
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
    const operation = editingMinistryId
      ? () => supabase.from("ministries").update({ ...ministryForm, updated_at: new Date().toISOString() }).eq("id", editingMinistryId)
      : () => supabase.from("ministries").insert({ ...ministryForm, country_id: countryId, created_by: profile.id });
    void run(operation, editingMinistryId ? "Ministério atualizado." : "Ministério cadastrado.");
    setEditingMinistryId(null);
    setMinistryForm({ name: "", description: "", purpose: "", category: "Administrativa" });
  };

  const saveDepartment = (event: FormEvent) => {
    event.preventDefault();
    if (!countryId) return;
    const operation = editingDepartmentId
      ? () => supabase.from("government_departments").update({
          ministry_id: departmentForm.ministry_id, name: departmentForm.name,
          description: departmentForm.description, responsible_member_id: departmentForm.responsible_member_id || null, updated_at: new Date().toISOString(),
        }).eq("id", editingDepartmentId)
      : () => supabase.from("government_departments").insert({
          country_id: countryId, ministry_id: departmentForm.ministry_id,
          name: departmentForm.name, description: departmentForm.description, responsible_member_id: departmentForm.responsible_member_id || null, created_by: profile.id,
        });
    void run(operation, editingDepartmentId ? "Departamento atualizado." : "Departamento cadastrado.");
    setEditingDepartmentId(null);
    setDepartmentForm({ ministry_id: "", name: "", description: "", responsible_member_id: "" });
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
    const publicationDate = announcementForm.status === "published" ? new Date().toISOString() : null;
    const operation = editingAnnouncementId
      ? () => supabase.from("government_announcements").update({
          ...announcementForm, ministry_id: announcementForm.ministry_id || null,
          published_at: publicationDate, updated_at: new Date().toISOString(),
        }).eq("id", editingAnnouncementId)
      : () => supabase.from("government_announcements").insert({
          ...announcementForm, ministry_id: announcementForm.ministry_id || null, country_id: countryId, author_id: profile.id,
          published_at: publicationDate,
        });
    void run(operation, editingAnnouncementId ? "Comunicado atualizado." : "Comunicado registrado.");
    setEditingAnnouncementId(null);
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
      coord_z: numberOrNull(infrastructureForm.coord_z), responsible_member_id: infrastructureForm.responsible_member_id || null,
    }), "Registro de infraestrutura cadastrado.");
    setInfrastructureForm({ name: "", category: "Cidade", description: "", location_name: "", coord_x: "", coord_y: "", coord_z: "", ministry_id: "", responsible_member_id: "" });
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

  const saveAllocation = (event: FormEvent) => {
    event.preventDefault();
    if (!countryId) return;
    void run(() => supabase.from("government_budget_allocations").insert({
      country_id: countryId, budget_id: allocationForm.budget_id, ministry_id: allocationForm.ministry_id,
      planned_amount: Number(allocationForm.planned_amount || 0), description: allocationForm.description,
    }), "Distribuição planejada registrada. Nenhum saldo foi movimentado.");
    setAllocationForm({ budget_id: "", ministry_id: "", planned_amount: "0", description: "" });
  };

  const submitDecision = async (row: Row) => {
    await run(() => supabase.from("government_decisions").update({ status: "pending_approval", updated_at: new Date().toISOString() }).eq("id", row.id), "Decisão enviada para análise do Super Admin.");
  };
  const publishDecision = async (row: Row) => {
    await run(() => supabase.from("government_decisions").update({ status: "published", published_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", row.id), "Decisão publicada para os cidadãos do país.");
  };
  const submitLegislation = async (row: Row) => {
    await run(() => supabase.from("national_legislation").update({ status: "under_review", updated_at: new Date().toISOString() }).eq("id", row.id), "Proposta enviada para análise do Super Admin.");
  };
  const reviewContent = async (table: "government_decisions" | "national_legislation", id: string, decision: "approved" | "rejected") => {
    await run(async () => {
      const result = table === "government_decisions"
        ? await supabase.rpc("review_government_decision", { p_decision_id: id, p_decision: decision, p_note: null })
        : await supabase.rpc("review_national_legislation", { p_legislation_id: id, p_decision: decision, p_note: null });
      return { error: result.error };
    }, decision === "approved" ? "Registro aprovado." : "Registro rejeitado.");
  };
  const publishAnnouncement = async (row: Row) => {
    await run(() => supabase.from("government_announcements").update({
      status: "published", published_at: new Date().toISOString(),
    }).eq("id", row.id), "Comunicado publicado.");
  };
  const archiveAnnouncement = async (row: Row) => {
    await run(() => supabase.from("government_announcements").update({ status: "archived", updated_at: new Date().toISOString() }).eq("id", row.id), "Comunicado arquivado.");
  };
  const markNotificationRead = async (id: string) => {
    const notification = notifications.find(row => row.id === id);
    const rpcName = isAdmin && notification?.recipient_id == null
      ? "admin_mark_notification_read"
      : "mark_own_notification_read";
    await run(async () => {
      const result = await supabase.rpc(rpcName, { p_notification_id: id });
      return { error: result.error };
    }, "Notificação marcada como lida.");
  };
  const changeMinistryStatus = async (row: Row) => {
    await run(() => supabase.from("ministries").update({
      status: row.status === "active" ? "inactive" : "active", updated_at: new Date().toISOString(),
    }).eq("id", row.id), "Situação do ministério atualizada.");
  };

  const getName = (id: string | null) => ministries.find(row => row.id === id)?.name ?? "Sem ministério";
  const getDepartmentName = (id: string | null) => departments.find(row => row.id === id)?.name ?? "Sem departamento";

  return <div className="we-admin">
    {isAdmin && <div className="we-form" style={{ marginBottom: 12 }}>
      <label>País sob administração<select value={selectedCountryId} onChange={event => setSelectedCountryId(event.target.value)}><option value="">Selecione um país</option>{adminCountries.map(item => <option key={item.id} value={item.id}>{item.name}{item.is_active ? "" : " — Inativo"}</option>)}</select></label>
      <div className="we-admin-notice">O Super Admin pode selecionar qualquer país para supervisionar seu governo. As aprovações pendentes continuam globais.</div>
    </div>}
    <nav className="we-admin-tabs">{tabs.map(({ id, label, Icon }) => <button key={id} type="button" className={tab === id ? "active" : ""} onClick={() => setTab(id)}><Icon/><span>{label}</span></button>)}</nav>
    <div className="we-admin-toolbar"><div><small>WORLD ECONOMY / GOVERNO NACIONAL</small><h2>{tabs.find(item => item.id === tab)?.label}</h2></div><button className="we-admin-refresh" type="button" onClick={() => void load()} disabled={loading}><RefreshCw/> Atualizar</button></div>
    {loading && <div className="we-empty">Carregando dados oficiais do governo...</div>}
    {!countryId && !isAdmin && <div className="we-note">Sua conta ainda não está vinculada a um país. As informações governamentais aparecerão após a definição do vínculo nacional.</div>}
    {country && <section className="we-panel"><header><h2><Flag/> <CountryMark value={country.flag} label={country.name}/> {country.name}</h2><span className="we-tag">{isPresident ? "Painel presidencial" : isAdmin ? "Super Admin" : ownMembership ? "Painel ministerial" : "Meu Governo"}</span></header><div className="we-admin-notice">{country.capital || "Capital não cadastrada"} • {country.continent || "Continente não cadastrado"} • {country.currency_name ? `${country.currency_name} (${country.currency_code ?? "código não informado"})` : "Moeda não cadastrada"}<br/>Presidente: {president?.username ?? "Nenhum presidente aprovado"} {president?.player_number ? `• #${president.player_number}` : ""}<br/>Situação administrativa: {country.is_active ? "Ativo" : "Suspenso"}{ownMembership && <><br/>Seu cargo: {ownMembership.position} • {getName(ownMembership.ministry_id)}</>}</div></section>}

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
      {isAdmin && (
        <>
          <section className="we-panel"><header><h2><ShieldCheck/> Nomeações e exonerações ({appointments.length})</h2><button type="button" onClick={() => setTab("appointments")}>Analisar</button></header><div className="we-admin-notice">Solicitações pendentes. Nenhuma permissão é concedida antes da aprovação.</div></section>
          <section className="we-panel"><header><h2><ClipboardList/> Decisões aguardando aprovação ({pendingDecisions.length})</h2></header>
            {pendingDecisions.map(row => <article className="we-admin-row" key={row.id}><div><b>{row.title}</b><small>{row.category} • País ID: {row.country_id} • {dateLabel(row.created_at)}</small></div><button type="button" disabled={busy} onClick={() => void reviewContent("government_decisions",row.id,"approved")}><Check/> Aprovar</button><button type="button" disabled={busy} onClick={() => void reviewContent("government_decisions",row.id,"rejected")}><X/> Rejeitar</button></article>)}
            {!pendingDecisions.length && <div className="we-empty">Nenhuma decisão aguardando aprovação.</div>}
          </section>
          <section className="we-panel"><header><h2><BookOpen/> Legislação em análise ({pendingLegislation.length})</h2></header>
            {pendingLegislation.map(row => <article className="we-admin-row" key={row.id}><div><b>{row.title}</b><small>{row.reference_number || "Sem identificação"} • País ID: {row.country_id} • {dateLabel(row.created_at)}</small></div><button type="button" disabled={busy} onClick={() => void reviewContent("national_legislation",row.id,"approved")}><Check/> Aprovar</button><button type="button" disabled={busy} onClick={() => void reviewContent("national_legislation",row.id,"rejected")}><X/> Rejeitar</button></article>)}
            {!pendingLegislation.length && <div className="we-empty">Nenhuma proposta em análise.</div>}
          </section>
        </>
      )}
    </>}

    {tab === "ministries" && <>
      {(canManage || (editingMinistryId && hasAnyPermission("ministry.manage"))) && countryId && <form className="we-form" onSubmit={saveMinistry}>
        {editingMinistryId && <div className="we-admin-form-title"><b>Editando ministério</b><button type="button" onClick={() => { setEditingMinistryId(null); setMinistryForm({ name: "", description: "", purpose: "", category: "Administrativa" }); }}>Cancelar</button></div>}
        <label>Nome do ministério<input value={ministryForm.name} onChange={e => setMinistryForm(s => ({ ...s, name: e.target.value }))} required minLength={2}/></label>
        <label>Categoria<select value={ministryForm.category} onChange={e => setMinistryForm(s => ({ ...s, category: e.target.value }))}>{categories.map(value => <option key={value}>{value}</option>)}</select></label>
        <label className="we-admin-wide">Descrição<input value={ministryForm.description} onChange={e => setMinistryForm(s => ({ ...s, description: e.target.value }))}/></label>
        <label className="we-admin-wide">Finalidade<input value={ministryForm.purpose} onChange={e => setMinistryForm(s => ({ ...s, purpose: e.target.value }))}/></label>
        <button className="we-primary we-admin-wide" disabled={busy}><Plus/> {editingMinistryId ? "Salvar alterações" : "Criar ministério"}</button>
      </form>}
      <section className="we-panel">{ministries.map(row => <article className="we-admin-row" key={row.id}><div><b>{row.name}</b><small>{row.category ?? "Sem categoria"} • {row.description || row.purpose || "Sem descrição"} • {row.status === "active" ? "Ativo" : "Inativo"}</small><small>Departamentos: {departments.filter(d => d.ministry_id === row.id).length} • Responsáveis: {members.filter(m => m.ministry_id === row.id && m.status === "active").length}</small></div>{(canManage || hasAnyPermission("ministry.manage")) && <button type="button" disabled={busy} onClick={() => { setEditingMinistryId(row.id); setMinistryForm({ name: row.name, description: row.description ?? "", purpose: row.purpose ?? "", category: row.category ?? "Administrativa" }); window.scrollTo({ top: 0, behavior: "smooth" }); }}>Editar</button>}{canManage && <button type="button" disabled={busy} onClick={() => void changeMinistryStatus(row)}>{row.status === "active" ? "Desativar" : "Reativar"}</button>}</article>)}{!ministries.length && <div className="we-empty">Nenhum ministério cadastrado.</div>}</section>
    </>}

    {tab === "departments" && <>
      {(canManage || hasAnyPermission("department.manage")) && countryId && <form className="we-form" onSubmit={saveDepartment}>
        {editingDepartmentId && <div className="we-admin-form-title"><b>Editando departamento</b><button type="button" onClick={() => { setEditingDepartmentId(null); setDepartmentForm({ ministry_id: "", name: "", description: "", responsible_member_id: "" }); }}>Cancelar</button></div>}
        <label>Ministério<select value={departmentForm.ministry_id} onChange={e => setDepartmentForm(s => ({ ...s, ministry_id: e.target.value }))} required><option value="">Selecione</option>{ministries.filter(row => row.status === "active").map(row => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
        <label>Nome do departamento<input value={departmentForm.name} onChange={e => setDepartmentForm(s => ({ ...s, name: e.target.value }))} required/></label>
        <label className="we-admin-wide">Descrição<input value={departmentForm.description} onChange={e => setDepartmentForm(s => ({ ...s, description: e.target.value }))}/></label>
        <label>Responsável<select value={departmentForm.responsible_member_id} onChange={e => setDepartmentForm(s => ({ ...s, responsible_member_id: e.target.value }))}><option value="">Sem responsável</option>{members.filter(member => member.status === "active" && (!departmentForm.ministry_id || member.ministry_id === departmentForm.ministry_id)).map(member => <option key={member.id} value={member.id}>{member.profile?.username ?? member.position} — {member.position}</option>)}</select></label>
        <button className="we-primary we-admin-wide" disabled={busy}><Plus/> {editingDepartmentId ? "Salvar alterações" : "Criar departamento"}</button>
      </form>}
      <section className="we-panel">{departments.map(row => <article className="we-admin-row" key={row.id}><div><b>{row.name}</b><small>{getName(row.ministry_id)} • {row.description || "Sem descrição"} • Responsável: {members.find(member => member.id === row.responsible_member_id)?.profile?.username ?? "Não definido"} • {row.status === "active" ? "Ativo" : "Inativo"}</small></div>{(canManage || hasAnyPermission("department.manage")) && <><button type="button" disabled={busy} onClick={() => { setEditingDepartmentId(row.id); setDepartmentForm({ ministry_id: row.ministry_id, name: row.name, description: row.description ?? "", responsible_member_id: row.responsible_member_id ?? "" }); window.scrollTo({ top: 0, behavior: "smooth" }); }}>Editar</button><button type="button" disabled={busy} onClick={() => void run(() => supabase.from("government_departments").update({status:row.status === "active" ? "inactive" : "active",updated_at:new Date().toISOString()}).eq("id",row.id),"Situação do departamento atualizada.")}>{row.status === "active" ? "Desativar" : "Reativar"}</button></>}</article>)}{!departments.length && <div className="we-empty">Nenhum departamento cadastrado.</div>}</section>
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
      {appointments.map(row => <article className="we-admin-row" key={row.id}><div><b>{row.action_type === "exoneration" ? "Exoneração" : row.position}</b><small>{row.action_type === "appointment" ? `Indicado: ${row.candidate?.username ?? row.candidate_profile_id} • #${row.candidate?.player_number ?? "—"}` : `Integrante: ${row.memberProfile?.username ?? row.member_id} • ${row.member?.position ?? ""}`} • {getName(row.ministry_id)} • {adminCountries.find(item => item.id === row.country_id)?.name ?? country?.name ?? "País"} • {dateLabel(row.requested_at)}</small></div>{isAdmin && <><button type="button" disabled={busy} onClick={() => reviewAppointment(row,"approved")}><Check/> Aprovar</button><button type="button" disabled={busy} onClick={() => reviewAppointment(row,"rejected")}><X/> Rejeitar</button></>}</article>)}
      {!appointments.length && <div className="we-empty">Nenhuma solicitação pendente.</div>}
      {members.filter(row => row.status === "active").map(row => <article className="we-admin-row" key={row.id}><div><b>{row.profile?.username ?? "Integrante"} — {row.position}</b><small>{getName(row.ministry_id)} • {getDepartmentName(row.department_id)} • Integrante ativo</small></div>{isPresident && <button type="button" disabled={busy} onClick={() => requestExoneration(row)}>Solicitar exoneração</button>}</article>)}
    </>}

    {tab === "decisions" && <>
      {(canManage || hasAnyPermission("decision.create")) && countryId && <form className="we-form" onSubmit={saveDecision}>
        <label>Ministério<select value={decisionForm.ministry_id} onChange={e => setDecisionForm(s => ({ ...s, ministry_id: e.target.value }))}><option value="">Nacional / Presidência</option>{ministries.map(row => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
        <label>Título<input value={decisionForm.title} onChange={e => setDecisionForm(s => ({ ...s, title: e.target.value }))} required/></label>
        <label>Categoria<select value={decisionForm.category} onChange={e => setDecisionForm(s => ({ ...s, category: e.target.value }))}>{categories.map(value => <option key={value} value={value.toLowerCase().replaceAll(" ","_")}>{value}</option>)}</select></label>
        <label className="we-admin-wide">Descrição<textarea value={decisionForm.description} onChange={e => setDecisionForm(s => ({ ...s, description: e.target.value }))} required/></label>
        <button className="we-primary we-admin-wide" disabled={busy}><Plus/> Salvar rascunho</button>
      </form>}
      <section className="we-panel">{decisions.map(row => <article className="we-admin-row" key={row.id}><div><b>{row.title}</b><small>{row.category} • {row.status} • {dateLabel(row.created_at)}</small><small>{row.description}</small></div>{row.status === "draft" && (canManage || hasAnyPermission("decision.create")) && <button type="button" disabled={busy} onClick={() => void submitDecision(row)}>Enviar para aprovação</button>}{row.status === "approved" && canManage && <button type="button" disabled={busy} onClick={() => void publishDecision(row)}>Publicar</button>}</article>)}{!decisions.length && <div className="we-empty">Nenhuma decisão cadastrada.</div>}</section>
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
      <section className="we-panel">{legislation.map(row => <article className="we-admin-row" key={row.id}><div><b>{row.title}</b><small>{row.reference_number || "Sem número"} • {row.status} • {dateLabel(row.created_at)}</small><small>{row.description}</small></div>{row.status === "draft" && (canManage || hasAnyPermission("legislation.create")) && <button type="button" disabled={busy} onClick={() => void submitLegislation(row)}>Enviar para análise</button>}{row.status === "approved" && canManage && <button type="button" disabled={busy} onClick={() => void run(() => supabase.from("national_legislation").update({status:"revoked",updated_at:new Date().toISOString()}).eq("id",row.id),"Proposta revogada.")}>Revogar</button>}</article>)}{!legislation.length && <div className="we-empty">Nenhuma proposta legislativa cadastrada.</div>}</section>
    </>}

    {tab === "announcements" && <>
      {(canManage || hasAnyPermission("announcement.create")) && countryId && <form className="we-form" onSubmit={saveAnnouncement}>
        {editingAnnouncementId && <div className="we-admin-form-title"><b>Editando comunicado</b><button type="button" onClick={() => { setEditingAnnouncementId(null); setAnnouncementForm({ title: "", content: "", category: "Comunicado oficial", status: "draft", ministry_id: "" }); }}>Cancelar</button></div>}
        <label>Ministério<select value={announcementForm.ministry_id} onChange={e => setAnnouncementForm(s => ({ ...s, ministry_id: e.target.value }))}><option value="">Nacional / Presidência</option>{ministries.map(row => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
        <label>Título<input value={announcementForm.title} onChange={e => setAnnouncementForm(s => ({ ...s, title: e.target.value }))} required/></label>
        <label>Categoria<input value={announcementForm.category} onChange={e => setAnnouncementForm(s => ({ ...s, category: e.target.value }))}/></label>
        <label className="we-admin-wide">Conteúdo<textarea value={announcementForm.content} onChange={e => setAnnouncementForm(s => ({ ...s, content: e.target.value }))} required/></label>
        <label>Situação<select value={announcementForm.status} onChange={e => setAnnouncementForm(s => ({ ...s, status: e.target.value }))}><option value="draft">Rascunho</option><option value="published">Publicar agora</option></select></label>
        <button className="we-primary" disabled={busy}><Plus/> {editingAnnouncementId ? "Salvar alterações" : "Salvar comunicado"}</button>
      </form>}
      {announcements.map(row => <article className="we-admin-row" key={row.id}><div><b>{row.title}</b><small>{row.category} • {row.status} • {dateLabel(row.published_at ?? row.created_at)}</small><small>{row.content}</small></div>{(canManage || hasAnyPermission("announcement.create")) && row.status !== "archived" && <button type="button" disabled={busy} onClick={() => { setEditingAnnouncementId(row.id); setAnnouncementForm({ title: row.title, content: row.content, category: row.category ?? "Comunicado oficial", status: row.status, ministry_id: row.ministry_id ?? "" }); window.scrollTo({ top: 0, behavior: "smooth" }); }}>Editar</button>}{canManage && row.status === "draft" && <button type="button" disabled={busy} onClick={() => void publishAnnouncement(row)}>Publicar</button>}{canManage && row.status === "published" && <button type="button" disabled={busy} onClick={() => void archiveAnnouncement(row)}>Arquivar</button>}</article>)}
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
        <label>Responsável<select value={infrastructureForm.responsible_member_id} onChange={e => setInfrastructureForm(s => ({ ...s, responsible_member_id: e.target.value }))}><option value="">Sem responsável</option>{members.filter(member => member.status === "active").map(member => <option key={member.id} value={member.id}>{member.profile?.username ?? member.position} — {member.position}</option>)}</select></label>
        <button className="we-primary we-admin-wide" disabled={busy}><Plus/> Cadastrar infraestrutura</button>
      </form>}
      {infrastructure.map(row => <article className="we-admin-row" key={row.id}><div><b>{row.name} • {row.category}</b><small>{row.location_name || "Localização não informada"} • {row.coord_x ?? "—"}, {row.coord_y ?? "—"}, {row.coord_z ?? "—"} • {row.status}</small></div></article>)}
      {!infrastructure.length && <div className="we-empty">Nenhuma infraestrutura cadastrada.</div>}
    </>}

    {tab === "audit" && <>
      {(isAdmin || isPresident) ? <section className="we-panel"><header><h2><ClipboardList/> Histórico administrativo</h2></header>
        {auditLogs.map(row => <article className="we-admin-row" key={row.id}><div><b>{row.description}</b><small>{row.operation} • {row.object_type} • Registro: {row.object_id ?? "—"}</small><small>Responsável: {row.actor?.username ?? (row.actor_id ? row.actor_id : "Sistema")} {row.actor?.player_number ? `• #${row.actor.player_number}` : ""} • {dateLabel(row.created_at)}</small></div></article>)}
        {!auditLogs.length && <div className="we-empty">Nenhuma operação administrativa registrada.</div>}
      </section> : <div className="we-note">O histórico administrativo é restrito à Presidência e ao Super Admin.</div>}
    </>}

    {tab === "notifications" && <>
      <section className="we-panel"><header><h2><Bell/> Notificações do governo</h2></header>
        {notifications.map(row => <article className="we-admin-row" key={row.id}><div><b>{row.title}</b><small>{row.description} • {dateLabel(row.created_at)} • {row.is_read ? "Lida" : "Não lida"}</small></div>{!row.is_read && <button type="button" disabled={busy} onClick={() => void markNotificationRead(row.id)}>Marcar como lida</button>}</article>)}
        {!notifications.length && <div className="we-empty">Nenhuma notificação recebida.</div>}
      </section>
    </>}

    {tab === "budget" && <>
      {(canManage || hasAnyPermission("budget.manage")) && countryId && <form className="we-form" onSubmit={saveBudget}>
        <label>Ministério<select value={budgetForm.ministry_id} onChange={e => setBudgetForm(s => ({ ...s, ministry_id: e.target.value }))}><option value="">Orçamento nacional</option>{ministries.map(row => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
        <label>Título do planejamento<input value={budgetForm.title} onChange={e => setBudgetForm(s => ({ ...s, title: e.target.value }))} required/></label>
        <label>Período fiscal<input value={budgetForm.fiscal_period} onChange={e => setBudgetForm(s => ({ ...s, fiscal_period: e.target.value }))} placeholder="Ex.: 2027"/></label>
        <label>Tipo<select value={budgetForm.budget_type} onChange={e => setBudgetForm(s => ({ ...s, budget_type: e.target.value }))}><option value="planned">Orçamento previsto</option><option value="expense_plan">Despesas planejadas</option><option value="investment_plan">Investimentos planejados</option></select></label>
        <label>Valor previsto<input type="number" min="0" step="0.01" value={budgetForm.planned_amount} onChange={e => setBudgetForm(s => ({ ...s, planned_amount: e.target.value }))}/></label>
        <label className="we-admin-wide">Descrição<textarea value={budgetForm.description} onChange={e => setBudgetForm(s => ({ ...s, description: e.target.value }))}/></label>
        <button className="we-primary we-admin-wide" disabled={busy}><Plus/> Salvar planejamento</button>
      </form>}
      {(canManage || hasAnyPermission("budget.manage")) && countryId && budgets.length > 0 && ministries.length > 0 && <form className="we-form" onSubmit={saveAllocation}>
        <div className="we-admin-form-title"><div><small>DISTRIBUIÇÃO POR MINISTÉRIO</small><h3>Planejar alocação</h3></div></div>
        <label>Orçamento<select value={allocationForm.budget_id} onChange={e => setAllocationForm(s => ({ ...s, budget_id: e.target.value }))} required><option value="">Selecione</option>{budgets.map(row => <option key={row.id} value={row.id}>{row.title}</option>)}</select></label>
        <label>Ministério<select value={allocationForm.ministry_id} onChange={e => setAllocationForm(s => ({ ...s, ministry_id: e.target.value }))} required><option value="">Selecione</option>{ministries.map(row => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
        <label>Valor planejado<input type="number" min="0" step="0.01" value={allocationForm.planned_amount} onChange={e => setAllocationForm(s => ({ ...s, planned_amount: e.target.value }))}/></label>
        <label>Descrição<input value={allocationForm.description} onChange={e => setAllocationForm(s => ({ ...s, description: e.target.value }))}/></label>
        <button className="we-primary we-admin-wide" disabled={busy}><Plus/> Registrar distribuição planejada</button>
      </form>}
      <div className="we-note">Valores exclusivamente previstos. Este módulo não cria dinheiro, não altera saldos e não executa pagamentos.</div>
      {budgets.map(row => <article className="we-admin-row" key={row.id}><div><b>{row.title}</b><small>{row.fiscal_period || "Período não informado"} • {row.budget_type} • {Number(row.planned_amount).toLocaleString("pt-BR",{minimumFractionDigits:2})} • {row.status}</small></div></article>)}
      {!budgets.length && <div className="we-empty">Nenhum planejamento orçamentário cadastrado.</div>}
      <section className="we-panel"><header><h2><Wallet/> Distribuição planejada por ministério</h2></header>
        {allocations.map(row => <article className="we-admin-row" key={row.id}><div><b>{getName(row.ministry_id)}</b><small>{budgets.find(budget => budget.id === row.budget_id)?.title ?? "Orçamento"} • {Number(row.planned_amount).toLocaleString("pt-BR",{minimumFractionDigits:2})} • {row.description || "Sem descrição"}</small></div></article>)}
        {!allocations.length && <div className="we-empty">Nenhuma distribuição orçamentária cadastrada.</div>}
      </section>
    </>}
  </div>;
}

function CountryMark({ value, label }: { value?: string | null; label: string }) {
  if (!value) return <span aria-label={`Bandeira de ${label}`}>🌐</span>;
  if (/^https?:\/\//i.test(value)) return <img src={value} alt={`Bandeira de ${label}`} style={{ width: 34, height: 24, objectFit: "contain", verticalAlign: "middle" }} />;
  return <span aria-label={`Bandeira de ${label}`} style={{ fontSize: 22 }}>{value}</span>;
}

function Stat({ label, value, Icon }: { label: string; value: string | number; Icon: typeof Landmark }) {
  return <article className="we-admin-stat"><span><Icon/></span><div><small>{label}</small><strong>{typeof value === "number" ? value.toLocaleString("pt-BR") : value}</strong></div></article>;
}
