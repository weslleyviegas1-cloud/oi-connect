import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import {
  Bell, BookOpen, Clipboard, FileBadge, FileText, Flag, Globe2, History,
  IdCard, LockKeyhole, RefreshCw, Save, ShieldCheck, UserRound, Wallet,
} from "lucide-react";
import { supabase } from "@/lib/supabase";

type Row = Record<string, any>;
type CitizenTab = "overview" | "profile" | "identity" | "documents" | "country" | "history" | "notifications" | "privacy";

const tabs: { id: CitizenTab; label: string; Icon: typeof UserRound }[] = [
  { id: "overview", label: "Visão geral", Icon: Globe2 },
  { id: "profile", label: "Meu perfil", Icon: UserRound },
  { id: "identity", label: "Minha identidade", Icon: IdCard },
  { id: "documents", label: "Meus documentos", Icon: FileText },
  { id: "country", label: "Meu país", Icon: Flag },
  { id: "history", label: "Meu histórico", Icon: History },
  { id: "notifications", label: "Notificações", Icon: Bell },
  { id: "privacy", label: "Privacidade", Icon: LockKeyhole },
];

const dateLabel = (value?: string | null) => value ? new Date(value).toLocaleDateString("pt-BR") : "—";
const dateTime = (value?: string | null) => value ? new Date(value).toLocaleString("pt-BR") : "—";
const statusLabel: Record<string, string> = {
  active: "Ativo", pending: "Pendente de aprovação", inactive: "Inativo",
  suspended: "Suspenso", under_review: "Em análise", not_issued: "Não emitido",
  expired: "Expirado", cancelled: "Cancelado", issued: "Emitido",
};

export function CitizenPortal({ profileId, notify, initialTab = "overview" }: { profileId: string; notify: (message: string) => void; initialTab?: CitizenTab }) {
  const [tab, setTab] = useState<CitizenTab>(initialTab);
  const [profile, setProfile] = useState<Row | null>(null);
  const [documents, setDocuments] = useState<Row[]>([]);
  const [passport, setPassport] = useState<Row | null>(null);
  const [passportRequest, setPassportRequest] = useState<Row | null>(null);
  const [requests, setRequests] = useState<Row[]>([]);
  const [history, setHistory] = useState<Row[]>([]);
  const [nicknameHistory, setNicknameHistory] = useState<Row[]>([]);
  const [nationalityHistory, setNationalityHistory] = useState<Row[]>([]);
  const [notifications, setNotifications] = useState<Row[]>([]);
  const [countries, setCountries] = useState<Row[]>([]);
  const [memberships, setMemberships] = useState<Row[]>([]);
  const [targetCountry, setTargetCountry] = useState("");
  const [minecraftNickname, setMinecraftNickname] = useState("");
  const [birthDate, setBirthDate] = useState("");
  const [city, setCity] = useState("");
  const [bio, setBio] = useState("");
  const [publicEnabled, setPublicEnabled] = useState(true);
  const [showId, setShowId] = useState(false);
  const [showCity, setShowCity] = useState(false);
  const [showBio, setShowBio] = useState(false);
  const [publicPreview, setPublicPreview] = useState<Row | null>(null);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [
        profileRes, documentsRes, passportRes, passportRequestRes, requestsRes, historyRes, nicknameRes,
        nationalityRes, notificationsRes, countriesRes, membershipsRes,
      ] = await Promise.all([
        supabase.rpc("get_my_citizen_profile"),
        supabase.from("citizen_documents").select("*").eq("profile_id", profileId).order("created_at", { ascending: false }),
        supabase.from("citizen_passports").select("*").eq("profile_id", profileId).maybeSingle(),
        supabase.from("passport_requests").select("id,request_type,status,requested_at,review_note,reason").eq("profile_id", profileId).order("requested_at", { ascending: false }).limit(1).maybeSingle(),
        supabase.from("nationality_change_requests").select("id,from_country_id,to_country_id,status,requested_at,reviewed_at,review_note").eq("profile_id", profileId).order("requested_at", { ascending: false }).limit(20),
        supabase.from("citizen_history").select("id,event_type,title,description,country_id,actor_id,created_at").eq("profile_id", profileId).order("created_at", { ascending: false }).limit(100),
        supabase.from("citizen_nickname_history").select("id,field_name,old_value,new_value,changed_at").eq("profile_id", profileId).order("changed_at", { ascending: false }).limit(50),
        supabase.from("citizen_nationality_history").select("id,from_country_id,to_country_id,reason,created_at").eq("profile_id", profileId).order("created_at", { ascending: false }).limit(50),
        supabase.from("citizen_notifications").select("*").eq("recipient_id", profileId).order("created_at", { ascending: false }).limit(100),
        supabase.from("countries").select("id,name,flag,capital,continent,is_active,citizens_available").eq("is_active", true).eq("citizens_available", true).order("name"),
        supabase.from("government_members").select("id,position,status,appointed_at,ministry_id,department_id").eq("profile_id", profileId).eq("status", "active").order("appointed_at", { ascending: false }),
      ]);
      if (profileRes.error) throw profileRes.error;
      setProfile(profileRes.data as Row);
      setMinecraftNickname(profileRes.data?.minecraft_username ?? "");
      setBirthDate(profileRes.data?.birth_date_sim ?? "");
      setCity(profileRes.data?.residence_city ?? "");
      setBio(profileRes.data?.bio ?? "");
      setPublicEnabled(profileRes.data?.public_profile_enabled ?? true);
      setShowId(profileRes.data?.show_player_number ?? false);
      setShowCity(profileRes.data?.show_residence_city ?? false);
      setShowBio(profileRes.data?.show_bio ?? false);
      if (documentsRes.error) throw documentsRes.error;
      if (passportRes.error) throw passportRes.error;
      if (passportRequestRes.error) throw passportRequestRes.error;
      if (requestsRes.error) throw requestsRes.error;
      if (historyRes.error) throw historyRes.error;
      if (nicknameRes.error) throw nicknameRes.error;
      if (nationalityRes.error) throw nationalityRes.error;
      if (notificationsRes.error) throw notificationsRes.error;
      if (countriesRes.error) throw countriesRes.error;
      setDocuments(documentsRes.data ?? []);
      setPassport(passportRes.data);
      setPassportRequest(passportRequestRes.data);
      setRequests(requestsRes.data ?? []);
      setHistory(historyRes.data ?? []);
      setNicknameHistory(nicknameRes.data ?? []);
      setNationalityHistory(nationalityRes.data ?? []);
      setNotifications(notificationsRes.data ?? []);
      setCountries(countriesRes.data ?? []);
      setMemberships(membershipsRes.data ?? []);
    } catch (error) {
      notify("Não foi possível carregar sua área de cidadão: " + (error instanceof Error ? error.message : "erro desconhecido"));
    } finally {
      setLoading(false);
    }
  }, [notify, profileId]);

  useEffect(() => { setTab(initialTab); }, [initialTab]);
  useEffect(() => { void load(); }, [load]);

  const identity = useMemo(
    () => documents.find(item => item.document_type === "national_identity") ?? null,
    [documents],
  );
  const pendingRequest = requests.find(item => item.status === "pending") ?? null;
  const unreadCount = notifications.filter(item => !item.is_read).length;

  const requestPassport = async () => {
    if (profile?.role !== "citizen") return;
    setBusy(true);
    try {
      const { error } = await supabase.rpc("request_passport", { p_reason: "Solicitação realizada pela área do cidadão." });
      if (error) throw error;
      notify("Solicitação de passaporte enviada para análise do governo nacional.");
      await load();
    } catch (error) {
      notify("Não foi possível solicitar o passaporte: " + (error instanceof Error ? error.message : "erro desconhecido"));
    } finally { setBusy(false); }
  };

  const savePersonalData = async (event: FormEvent) => {
    event.preventDefault();
    setBusy(true);
    try {
      const { error } = await supabase.rpc("update_my_citizen_profile", {
        p_birth_date_sim: birthDate || null,
        p_residence_city: city.trim() || null,
        p_bio: bio.trim() || null,
        p_public_profile_enabled: publicEnabled,
        p_show_player_number: showId,
        p_show_residence_city: showCity,
        p_show_bio: showBio,
      });
      if (error) throw error;
      notify("Informações do perfil atualizadas.");
      await load();
    } catch (error) {
      notify("Não foi possível salvar o perfil: " + (error instanceof Error ? error.message : "erro desconhecido"));
    } finally { setBusy(false); }
  };

  const saveMinecraftNickname = async (event: FormEvent) => {
    event.preventDefault();
    setBusy(true);
    try {
      const { error } = await supabase.rpc("update_my_minecraft_nickname", { p_nickname: minecraftNickname.trim() });
      if (error) throw error;
      notify("Nickname atualizado. O histórico foi preservado.");
      await load();
    } catch (error) {
      notify("Não foi possível atualizar o nickname: " + (error instanceof Error ? error.message : "erro desconhecido"));
    } finally { setBusy(false); }
  };

  const requestChange = async (event: FormEvent) => {
    event.preventDefault();
    if (!targetCountry) return;
    const target = countries.find(country => country.id === targetCountry);
    if (!window.confirm("Enviar solicitação de mudança de nacionalidade para " + (target?.name ?? "o país selecionado") + "? O vínculo atual só muda após aprovação do Super Admin.")) return;
    setBusy(true);
    try {
      const { error } = await supabase.rpc("request_nationality_change", { p_country_id: targetCountry });
      if (error) throw error;
      setTargetCountry("");
      notify("Solicitação enviada e aguardando análise do Super Admin.");
      await load();
    } catch (error) {
      notify("Não foi possível enviar a solicitação: " + (error instanceof Error ? error.message : "erro desconhecido"));
    } finally { setBusy(false); }
  };

  const loadPublicPreview = async () => {
    const { data, error } = await supabase.rpc("get_public_citizen_profile", { p_profile_id: profileId });
    if (error) notify("Não foi possível gerar a prévia pública: " + error.message);
    else setPublicPreview(data as Row | null);
  };

  const markRead = async (id: string) => {
    const { error } = await supabase.from("citizen_notifications").update({ is_read: true }).eq("id", id).eq("recipient_id", profileId);
    if (error) notify("Não foi possível atualizar a notificação: " + error.message);
    else await load();
  };

  const markAllRead = async () => {
    setBusy(true);
    const { error } = await supabase.from("citizen_notifications").update({ is_read: true }).eq("recipient_id", profileId).eq("is_read", false);
    setBusy(false);
    if (error) notify("Não foi possível atualizar as notificações: " + error.message);
    else { notify("Todas as notificações foram marcadas como lidas."); await load(); }
  };

  if (loading && !profile) return <div className="we-coming"><RefreshCw/><b>Carregando sua identidade...</b></div>;
  if (!profile) return <div className="we-empty">Não foi possível localizar seu perfil de cidadão.</div>;

  return (
    <div className="we-citizen">
      <nav className="we-citizen-nav" aria-label="Área do cidadão">
        {tabs.map(({ id, label, Icon }) => <button key={id} type="button" className={tab === id ? "active" : ""} onClick={() => setTab(id)}><Icon/><span>{label}</span>{id === "notifications" && unreadCount > 0 && <em>{unreadCount}</em>}</button>)}
      </nav>
      <div className="we-citizen-content">
        {tab === "overview" && <>
          <section className="we-citizen-hero">
            <div><small>WORLD ECONOMY / ÁREA DO CIDADÃO</small><h2>Olá, {profile.username}</h2><p>Identidade, nacionalidade e registros da sua trajetória na simulação.</p></div>
            <div className="we-citizen-id"><IdCard/><span>ID PERMANENTE</span><strong>#{profile.player_number ?? "—"}</strong></div>
          </section>
          <div className="we-citizen-grid">
            <article className="we-panel"><header><h2><Flag/> Nacionalidade</h2></header><div className="we-citizen-country"><b>{profile.country_flag ?? "🌐"}</b><span><strong>{profile.country_name ?? "Sem país"}</strong><small>{profile.country_capital ?? "Capital não cadastrada"} • {profile.country_continent ?? "Continente não cadastrado"}</small></span></div><small className="we-citizen-muted">Desde {dateLabel(profile.country_joined_at)}</small></article>
            <article className="we-panel"><header><h2><FileBadge/> Identidade digital</h2></header><strong>{identity?.document_number ?? "Aguardando emissão"}</strong><small className="we-citizen-muted">{identity ? statusLabel[identity.status] ?? identity.status : "Documento não disponível"}</small><button type="button" className="we-secondary" onClick={() => setTab("identity")}>Visualizar identidade</button></article>
            <article className="we-panel"><header><h2><BookOpen/> Passaporte</h2></header><strong>{passport?.passport_number ?? statusLabel[passport?.status ?? "not_issued"]}</strong><small className="we-citizen-muted">{passport ? `Emitido em ${dateLabel(passport.issued_at)} • válido até ${dateLabel(passport.expires_at)} • ${statusLabel[passport.status] ?? passport.status}` : passportRequest ? `Solicitação ${passportRequest.status === "issued" ? "emitida" : passportRequest.status === "rejected" ? "rejeitada" : "em análise"} • ${dateLabel(passportRequest.requested_at)}` : "Você ainda não possui passaporte emitido."}</small>{profile.role === "citizen" && <button type="button" className="we-secondary" onClick={() => void requestPassport()} disabled={busy || !!passportRequest && ["pending","in_review"].includes(passportRequest.status)}>{passport ? "Solicitar renovação" : "Solicitar emissão"}</button>}</article>
            <article className="we-panel"><header><h2><Bell/> Notificações</h2></header><strong>{unreadCount} não lida(s)</strong><small className="we-citizen-muted">Atualizações administrativas pessoais.</small><button type="button" className="we-secondary" onClick={() => setTab("notifications")}>Abrir notificações</button></article>
          </div>
          {memberships.length > 0 && <section className="we-panel"><header><h2><ShieldCheck/> Vínculos governamentais</h2></header>{memberships.map(item => <article className="we-citizen-event" key={item.id}><div><b>{item.position}</b><small>Nomeação em {dateLabel(item.appointed_at)}</small></div><span className="we-tag">Ativo</span></article>)}</section>}
          <div className="we-citizen-grid">
            <article className="we-panel"><header><h2><ShieldCheck/> Situação</h2></header><strong>{statusLabel[profile.citizen_status] ?? profile.citizen_status ?? "Ativo"}</strong><small className="we-citizen-muted">Situação da conta: {statusLabel[profile.account_status] ?? profile.account_status}</small></article>
            <article className="we-panel"><header><h2><Wallet/> Serviços disponíveis</h2></header><strong>Empresas e bancos</strong><small className="we-citizen-muted">Consulte seus vínculos profissionais no módulo Empresas e suas contas e extratos no módulo Bancos.</small></article>
          </div>
        </>}

        {tab === "profile" && <>
          <section className="we-panel">
            <header><h2><UserRound/> Informações do cidadão</h2></header>
            <div className="we-citizen-profile-head">{profile.avatar_url ? <img src={profile.avatar_url} alt="Avatar do cidadão"/> : <span><UserRound/></span>}<div><strong>{profile.username}</strong><small>Cadastro em {dateTime(profile.created_at)} • ID #{profile.player_number}</small><small>Conta: {statusLabel[profile.account_status] ?? profile.account_status}</small></div></div>
            <form className="we-form" onSubmit={saveMinecraftNickname}>
              <label>Nickname do Minecraft<input value={minecraftNickname} onChange={e => setMinecraftNickname(e.target.value)} minLength={3} maxLength={32} required/></label>
              <button className="we-primary" type="submit" disabled={busy}><Save/> Atualizar nickname</button>
              <small className="we-citizen-muted">A alteração é manual. O ID permanente não muda e o histórico de nicknames é preservado.</small>
            </form>
          </section>
          <form className="we-form we-panel" onSubmit={savePersonalData}>
            <header><h2><UserRound/> Dados opcionais da simulação</h2></header>
            <label>Data de nascimento fictícia<input type="date" value={birthDate} onChange={e => setBirthDate(e.target.value)}/></label>
            <label>Cidade de residência fictícia<input value={city} onChange={e => setCity(e.target.value)} maxLength={100} placeholder="Opcional"/></label>
            <label>Descrição pessoal<textarea value={bio} onChange={e => setBio(e.target.value)} maxLength={500} rows={4} placeholder="Conte um pouco sobre seu personagem..."/></label>
            <button className="we-primary" type="submit" disabled={busy}><Save/> Salvar informações</button>
          </form>
          {nicknameHistory.length > 0 && <section className="we-panel"><header><h2><History/> Histórico de nicknames</h2></header>{nicknameHistory.map(item => <article className="we-citizen-event" key={item.id}><div><b>{item.field_name === "username" ? "Nome de exibição" : "Nickname Minecraft"}</b><small>{item.old_value ?? "—"} → {item.new_value ?? "—"}</small></div><time>{dateTime(item.changed_at)}</time></article>)}</section>}
        </>}

        {tab === "identity" && <section className="we-panel">
          <header><h2><IdCard/> Identidade Nacional Digital</h2></header>
          <div className="we-identity-card">
            <div className="we-identity-top"><span>WORLD ECONOMY</span><small>DOCUMENTO NACIONAL • WORLD ECONOMY</small></div>
            <div className="we-identity-body">
              {profile.avatar_url ? <img src={profile.avatar_url} alt="Foto do cidadão"/> : <span className="we-identity-avatar"><UserRound/></span>}
              <div className="we-identity-data"><small>NOME DO CIDADÃO</small><strong>{profile.username}</strong><small>NICKNAME DO MINECRAFT</small><b>{profile.minecraft_username ?? "Não informado"}</b><small>CPF</small><strong>{profile.cpf_number ? String(profile.cpf_number).replace(/(\\d{3})(\\d{3})(\\d{3})(\\d{2})/, "$1.$2.$3-$4") : "Em geração"}</strong><small>ID PERMANENTE</small><strong>#{profile.player_number}</strong><small>NACIONALIDADE</small><b>{profile.country_flag ?? ""} {profile.country_name ?? "Não definida"}</b><small>DATA DE EMISSÃO</small><b>{dateLabel(identity?.issued_at ?? profile.created_at)}</b></div>
            </div>
            <div className="we-identity-footer"><span>Documento fictício válido somente dentro do WORLD ECONOMY.</span><b>{identity?.document_number ?? "IDENTIDADE NÃO EMITIDA"}</b></div>
          </div>
          <button type="button" className="we-secondary" onClick={() => { void navigator.clipboard?.writeText(String(profile.player_number ?? "")); notify("ID permanente copiado."); }}><Clipboard/> Copiar ID permanente</button>
        </section>}

        {tab === "documents" && <>
          <section className="we-panel"><header><h2><FileText/> Documentos disponíveis</h2></header>
            {documents.map(document => <article className="we-citizen-event" key={document.id}><FileBadge/><div><b>{document.document_type === "national_identity" ? "Identidade Nacional" : "Documento"}</b><small>{document.document_number} • Emissor: {profile.country_name ?? "WORLD ECONOMY"}</small><small>Emissão: {dateLabel(document.issued_at)} • Validade: {document.expires_at ? dateLabel(document.expires_at) : "Sem prazo configurado"}</small></div><span className="we-tag">{statusLabel[document.status] ?? document.status}</span></article>)}
            {passport && <article className="we-citizen-event"><BookOpen/><div><b>Passaporte Digital</b><small>{passport.passport_number} • Emissor: {profile.country_name ?? "A definir"}</small><small>Emissão: {dateLabel(passport.issued_at)} • Validade: {dateLabel(passport.expires_at)}</small></div><span className="we-tag">{statusLabel[passport.status] ?? passport.status}</span></article>}
            {!documents.length && <div className="we-empty">Nenhum documento emitido.</div>}
          </section>
          <section className="we-panel"><header><h2><LockKeyhole/> Documentos futuros</h2></header><div className="we-citizen-future"><span>Carteira de motorista</span><span>Documentos profissionais</span><span>Licenças</span></div><small className="we-citizen-muted">Estas opções ainda não executam ações e serão ativadas nas etapas correspondentes.</small></section>
        </>}

        {tab === "country" && <>
          <section className="we-panel"><header><h2><Flag/> Nacionalidade atual</h2></header><div className="we-citizen-country"><b>{profile.country_flag ?? "🌐"}</b><span><strong>{profile.country_name ?? "Sem país"}</strong><small>{profile.country_capital ?? "Capital não cadastrada"} • {profile.country_continent ?? "Continente não cadastrado"}</small></span></div><p className="we-citizen-muted">Vínculo desde {dateTime(profile.country_joined_at)}. A mudança só ocorre após autorização do Super Admin.</p></section>
          <section className="we-panel"><header><h2><RefreshCw/> Solicitar mudança de nacionalidade</h2></header>
            {pendingRequest ? <p className="we-note">Você já possui uma solicitação pendente para análise administrativa.</p> : <form className="we-form" onSubmit={requestChange}><label>País de destino<select value={targetCountry} onChange={e => setTargetCountry(e.target.value)} required><option value="">Selecione um país disponível</option>{countries.filter(country => country.id !== profile.country_id).map(country => <option key={country.id} value={country.id}>{country.flag ?? ""} {country.name}</option>)}</select></label><button className="we-primary" disabled={busy || !targetCountry}><RefreshCw/> Enviar solicitação</button></form>}
            {countries.filter(country => country.id !== profile.country_id).length === 0 && !pendingRequest && <div className="we-empty">Nenhum país está aceitando novos cidadãos no momento.</div>}
          </section>
          {requests.length > 0 && <section className="we-panel"><header><h2><History/> Solicitações anteriores</h2></header>{requests.map(item => <article className="we-citizen-event" key={item.id}><div><b>{item.status === "approved" ? "Aprovada" : item.status === "rejected" ? "Rejeitada" : item.status === "cancelled" ? "Cancelada" : "Pendente"}</b><small>Solicitada em {dateTime(item.requested_at)}</small><small>{item.review_note ?? "Sem observação administrativa."}</small></div></article>)}</section>}
          {nationalityHistory.length > 0 && <section className="we-panel"><header><h2><History/> Histórico de nacionalidade</h2></header>{nationalityHistory.map(item => <article className="we-citizen-event" key={item.id}><div><b>{item.reason ?? "Alteração de vínculo"}</b><small>{dateTime(item.created_at)}</small></div></article>)}</section>}
        </>}

        {tab === "history" && <section className="we-panel"><header><h2><History/> Linha do tempo do cidadão</h2></header>
          {history.map(item => <article className="we-citizen-event" key={item.id}><div><b>{item.title}</b><small>{item.description}</small><small>{item.event_type} {item.country_id ? "• Registro nacional" : ""}</small></div><time>{dateTime(item.created_at)}</time></article>)}
          {!history.length && <div className="we-empty">Nenhum evento registrado.</div>}
        </section>}

        {tab === "notifications" && <section className="we-panel"><header><h2><Bell/> Notificações pessoais</h2>{unreadCount > 0 && <button type="button" className="we-secondary" onClick={() => void markAllRead()} disabled={busy}>Marcar todas como lidas</button>}</header>
          {notifications.map(item => <article className="we-citizen-event" key={item.id}><div><b>{item.title}</b><small>{item.description}</small><small>{dateTime(item.created_at)} • {item.is_read ? "Lida" : "Não lida"}</small></div>{!item.is_read && <button type="button" className="we-secondary" onClick={() => void markRead(item.id)}>Marcar como lida</button>}</article>)}
          {!notifications.length && <div className="we-empty">Você não possui notificações.</div>}
        </section>}

        {tab === "privacy" && <form className="we-panel we-form" onSubmit={savePersonalData}>
          <header><h2><LockKeyhole/> Privacidade do perfil público</h2></header>
          <label className="we-citizen-check"><input type="checkbox" checked={publicEnabled} onChange={e => setPublicEnabled(e.target.checked)}/> Permitir consulta do meu perfil público</label>
          <label className="we-citizen-check"><input type="checkbox" checked={showId} onChange={e => setShowId(e.target.checked)}/> Exibir meu ID permanente no perfil público</label>
          <label className="we-citizen-check"><input type="checkbox" checked={showCity} onChange={e => setShowCity(e.target.checked)}/> Exibir minha cidade fictícia</label>
          <label className="we-citizen-check"><input type="checkbox" checked={showBio} onChange={e => setShowBio(e.target.checked)}/> Exibir minha descrição pessoal</label>
          <small className="we-citizen-muted">Documentos, notificações, histórico privado e informações bancárias nunca são exibidos no perfil público.</small>
          <button className="we-primary" type="submit" disabled={busy}><Save/> Salvar privacidade</button>
          <button className="we-secondary" type="button" onClick={() => void loadPublicPreview()}>Visualizar meu perfil público</button>
          {publicPreview && <article className="we-citizen-event"><div><b>{publicPreview.username}</b><small>{publicPreview.minecraft_username ?? "Nickname não informado"} • {publicPreview.country_flag ?? ""} {publicPreview.country_name ?? "Sem país"}</small>{publicPreview.player_number && <small>ID #{publicPreview.player_number}</small>}{publicPreview.residence_city && <small>Cidade: {publicPreview.residence_city}</small>}{publicPreview.bio && <small>{publicPreview.bio}</small>}</div></article>}
        </form>}
      </div>
    </div>
  );
}
