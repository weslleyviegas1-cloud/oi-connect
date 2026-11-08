import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import { ArrowDownUp, BadgeCheck, CircleAlert, Coins, Globe2, History, Plus, RefreshCw, Search, Settings2, TrendingUp } from "lucide-react";
import { supabase } from "@/lib/supabase";
import { CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import "./currency-portal.css";

type Row = Record<string, any>;
type Snapshot = { currencies: Row[]; assignments: Row[]; rates: Row[]; reference_currency_id: string | null };
type Props = { profile: Row; notify: (message: string) => void };
type Tab = "market" | "converter" | "currencies" | "rates" | "history";
const errorText = (e: unknown) => e instanceof Error ? e.message : "Não foi possível concluir a operação.";
const dateTime = (s?: string) => s ? new Date(s).toLocaleString("pt-BR") : "—";
const fmt = (v: unknown, decimals = 2) => v == null ? "—" : Number(v).toLocaleString("pt-BR", { minimumFractionDigits: decimals, maximumFractionDigits: decimals });
const nowLocal = () => new Date().toISOString().slice(0, 16);

export function CurrencyPortal({ profile, notify }: Props) {
  const isAdmin = profile?.role === "super_admin";
  const [tab, setTab] = useState<Tab>("market");
  const [snapshot, setSnapshot] = useState<Snapshot>({ currencies: [], assignments: [], rates: [], reference_currency_id: null });
  const [countries, setCountries] = useState<Row[]>([]);
  const [history, setHistory] = useState<Row[]>([]);
  const [currencyRequests, setCurrencyRequests] = useState<Row[]>([]);
  const [requestReason, setRequestReason] = useState("");
  const [rateHistory, setRateHistory] = useState<Row[]>([]);
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [amount, setAmount] = useState("100");
  const [fromId, setFromId] = useState("");
  const [toId, setToId] = useState("");
  const [conversion, setConversion] = useState<Row | null>(null);
  const [currencyForm, setCurrencyForm] = useState({ name: "", short_name: "", internal_code: "", symbol: "", decimal_places: "2", description: "" });
  const [assignmentForm, setAssignmentForm] = useState({ country_id: "", currency_id: "", justification: "Definição da moeda nacional." });
  const [rateForm, setRateForm] = useState({ from_currency_id: "", to_currency_id: "", rate: "", effective_from: nowLocal(), effective_until: "", justification: "" });
  const [referenceId, setReferenceId] = useState("");
  const [statusNote, setStatusNote] = useState("Atualização administrativa da cotação.");

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [snap, ratesResult] = await Promise.all([
        supabase.rpc("get_currency_market_snapshot", { p_at: new Date().toISOString() }),
        supabase.from("exchange_rates").select("id,from_currency_id,to_currency_id,rate,effective_from,effective_until,version,status").eq("status","active").order("effective_from", { ascending: false }).limit(200),
      ]);
      if (snap.error) throw snap.error;
      if (ratesResult.error) throw ratesResult.error;
      setRateHistory(ratesResult.data ?? []);
      const data = (snap.data ?? {}) as Snapshot;
      setSnapshot({ currencies: data.currencies ?? [], assignments: data.assignments ?? [], rates: data.rates ?? [], reference_currency_id: data.reference_currency_id ?? null });
      setReferenceId(data.reference_currency_id ?? "");
      const requestResult = await supabase.from("currency_change_requests").select("*,currencies(name,internal_code)").order("created_at", { ascending: false }).limit(100);
      if (requestResult.error) throw requestResult.error;
      setCurrencyRequests(requestResult.data ?? []);
      if (isAdmin) {
        const [countryResult, eventResult, auditResult] = await Promise.all([
          supabase.from("countries").select("id,name,flag,currency_code").order("name"),
          supabase.from("exchange_rate_events").select("*,exchange_rates(from_currency_id,to_currency_id,rate,version)").order("created_at", { ascending: false }).limit(100),
          supabase.from("currency_audit_logs").select("*").order("created_at", { ascending: false }).limit(100),
        ]);
        if (countryResult.error) throw countryResult.error;
        if (eventResult.error) throw eventResult.error;
        if (auditResult.error) throw auditResult.error;
        setCountries(countryResult.data ?? []);
        setHistory([...(eventResult.data ?? []).map((x: Row) => ({ ...x, kind: "Cotação" })), ...(auditResult.data ?? []).map((x: Row) => ({ ...x, kind: x.entity_type }))].sort((a: Row, b: Row) => +new Date(b.created_at) - +new Date(a.created_at)));
      }
      setFromId(old => old || data.currencies?.[0]?.id || "");
      setToId(old => old || data.currencies?.[1]?.id || data.currencies?.[0]?.id || "");
      setAssignmentForm(old => ({ ...old, currency_id: old.currency_id || data.currencies?.[0]?.id || "", country_id: old.country_id || (isAdmin ? "" : profile?.country_id || "") }));
      setRateForm(old => ({ ...old, from_currency_id: old.from_currency_id || data.currencies?.[0]?.id || "", to_currency_id: old.to_currency_id || data.currencies?.[1]?.id || "" }));
    } catch (e) {
      notify("Falha ao carregar o mercado monetário: " + errorText(e));
    } finally { setLoading(false); }
  }, [isAdmin, notify, profile?.country_id]);

  useEffect(() => { void load(); }, [load]);

  const currencies = snapshot.currencies;
  const byId = useMemo(() => new Map(currencies.map(c => [c.id, c])), [currencies]);
  const refCurrency = byId.get(snapshot.reference_currency_id ?? "");
  const filtered = currencies.filter(c => [c.name, c.short_name, c.internal_code, c.symbol].join(" ").toLowerCase().includes(search.toLowerCase())
    || snapshot.assignments.some(a => a.currency_id === c.id && String(a.country_name).toLowerCase().includes(search.toLowerCase())));
  const assignmentFor = (id: string) => snapshot.assignments.filter(a => a.currency_id === id);
  const currentRate = (a: string, b: string) => snapshot.rates.find(r => r.from_currency_id === a && r.to_currency_id === b)
    ?? snapshot.rates.find(r => r.from_currency_id === b && r.to_currency_id === a);
  const chartPair = rateHistory.find(r => r.from_currency_id === fromId && r.to_currency_id === toId)
    ? [fromId, toId] : rateHistory.find(r => r.from_currency_id === toId && r.to_currency_id === fromId) ? [toId, fromId] : null;
  const chartRows = chartPair ? rateHistory.filter(r => r.from_currency_id === chartPair[0] && r.to_currency_id === chartPair[1])
    .slice().sort((a,b) => +new Date(a.effective_from) - +new Date(b.effective_from)) : [];

  const run = async (fn: () => PromiseLike<{ data?: any; error: any }>, success: string) => {
    setBusy(true);
    try { const result = await fn(); if (result.error) throw result.error; notify(success); await load(); return result.data; }
    catch (e) { notify("Operação não concluída: " + errorText(e)); return null; }
    finally { setBusy(false); }
  };

  const createCurrency = (e: FormEvent) => {
    e.preventDefault();
    if (!isAdmin) return;
    void run(() => supabase.rpc("admin_create_currency", {
      p_name: currencyForm.name, p_short_name: currencyForm.short_name, p_internal_code: currencyForm.internal_code.toUpperCase(),
      p_symbol: currencyForm.symbol, p_decimal_places: Number(currencyForm.decimal_places), p_description: currencyForm.description || null,
    }), "Moeda cadastrada.").then(result => { if (result) setCurrencyForm({ name: "", short_name: "", internal_code: "", symbol: "", decimal_places: "2", description: "" }); });
  };

  const assignCurrency = (e: FormEvent) => {
    e.preventDefault();
    if (!isAdmin || !assignmentForm.country_id || !assignmentForm.currency_id) return;
    if (!window.confirm("Confirmar a alteração da moeda nacional? Os registros financeiros antigos não serão convertidos.")) return;
    void run(() => supabase.rpc("admin_assign_country_currency", {
      p_country_id: assignmentForm.country_id, p_currency_id: assignmentForm.currency_id,
      p_effective_from: new Date().toISOString(), p_justification: assignmentForm.justification,
    }), "Moeda nacional atualizada. Os snapshots históricos foram preservados.");
  };

  const requestNationalCurrency = (e: FormEvent) => {
    e.preventDefault();
    if (!profile?.country_id || !assignmentForm.currency_id) return;
    void run(() => supabase.rpc("request_country_currency_change", {
      p_country_id: profile.country_id, p_currency_id: assignmentForm.currency_id, p_reason: requestReason,
    }), "Solicitação enviada ao Super Admin.").then(result => { if (result) setRequestReason(""); });
  };

  const reviewCurrencyRequest = (id: string, decision: "approved" | "rejected") => {
    const note = window.prompt("Observação da análise (obrigatória):");
    if (!note || note.trim().length < 5) return;
    void run(() => supabase.rpc("admin_review_currency_change_request", {
      p_request_id: id, p_decision: decision, p_note: note.trim(),
    }), decision === "approved" ? "Mudança de moeda aprovada." : "Solicitação rejeitada.");
  };

  const setReference = () => {
    if (!isAdmin || !referenceId) return;
    const justification = window.prompt("Justificativa para alterar a moeda de referência:");
    if (!justification || justification.trim().length < 5) return;
    void run(() => supabase.rpc("admin_set_reference_currency", { p_currency_id: referenceId, p_justification: justification.trim() }), "Moeda de referência atualizada.");
  };

  const createRate = (e: FormEvent) => {
    e.preventDefault();
    if (!isAdmin) return;
    void run(() => supabase.rpc("admin_create_exchange_rate", {
      p_from_currency_id: rateForm.from_currency_id, p_to_currency_id: rateForm.to_currency_id,
      p_rate: rateForm.rate, p_effective_from: new Date(rateForm.effective_from).toISOString(),
      p_effective_until: rateForm.effective_until ? new Date(rateForm.effective_until).toISOString() : null,
      p_justification: rateForm.justification,
    }), "Nova versão de cotação registrada.");
  };

  const changeRateStatus = (id: string, status: string) => {
    const justification = window.prompt("Justificativa obrigatória para esta alteração:");
    if (!justification || justification.trim().length < 5) return;
    void run(() => supabase.rpc("admin_set_exchange_rate_status", { p_rate_id: id, p_status: status, p_justification: justification.trim() }), "Situação da cotação atualizada.");
  };

  const convert = async (e?: FormEvent) => {
    e?.preventDefault();
    if (!fromId || !toId || !amount.trim() || !/^\d+(?:[.,]\d+)?$/.test(amount.trim())) { notify("Informe um valor válido e selecione as moedas."); return; }
    setBusy(true); setConversion(null);
    try {
      const result = await supabase.rpc("convert_currency_amount", {
        p_amount: amount.replace(",", "."), p_from_currency_id: fromId, p_to_currency_id: toId, p_at: new Date().toISOString(),
      });
      if (result.error) throw result.error;
      setConversion(result.data as Row);
    } catch (e) { notify(errorText(e)); }
    finally { setBusy(false); }
  };

  const invert = () => { setFromId(toId); setToId(fromId); setConversion(null); };
  const from = byId.get(fromId), to = byId.get(toId);

  if (loading) return <div className="currency-empty">Carregando sistema monetário…</div>;

  return <div className="currency-shell">
    <div className="currency-heading"><div><span>WORLD ECONOMY / SISTEMA MONETÁRIO</span><h2>Mercado Internacional de Câmbio</h2><p>Moedas nacionais, cotações oficiais e conversão informativa da simulação.</p></div><button className="currency-button secondary" onClick={() => void load()}><RefreshCw size={16}/> Atualizar</button></div>
    <div className="currency-tabs">{([{id:"market",label:"Mercado",icon:Globe2},{id:"converter",label:"Conversor",icon:ArrowDownUp},{id:"currencies",label:"Moedas",icon:Coins},{id:"rates",label:"Cotações",icon:TrendingUp},{id:"history",label:"Histórico",icon:History}] as const).filter(t => isAdmin || t.id === "market" || t.id === "converter").map(({id,label,icon:Icon}) => <button key={id} className={tab===id?"active":""} onClick={() => setTab(id)}><Icon size={15}/>{label}</button>)}</div>

    {tab === "market" && <>
      <div className="currency-summary">
        <article><small>Moedas ativas</small><strong>{currencies.length}</strong><span>Cadastro central</span></article>
        <article><small>Países com moeda</small><strong>{snapshot.assignments.length}</strong><span>Vínculos nacionais atuais</span></article>
        <article><small>Moeda de referência</small><strong>{refCurrency ? refCurrency.internal_code : "Não configurada"}</strong><span>{refCurrency?.name ?? "Definição do Super Admin"}</span></article>
        <article><small>Cotações vigentes</small><strong>{snapshot.rates.length}</strong><span>Sem dados inventados</span></article>
      </div>
      <div className="currency-toolbar"><label><Search size={16}/><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Pesquisar moeda, código ou país"/></label><span>Atualizado em {new Date().toLocaleString("pt-BR")}</span></div>
      <div className="currency-grid">{filtered.length ? filtered.map(c => {
        const countriesForCurrency = assignmentFor(c.id);
        return <article className="currency-card" key={c.id}><div className="currency-symbol">{c.symbol}</div><div className="currency-card-main"><strong>{c.name}</strong><span>{c.short_name} · {c.internal_code}</span><small>{countriesForCurrency.length ? countriesForCurrency.map(x=>x.country_name).join(", ") : "Nenhum país associado"}</small></div><span className="currency-status">{c.status === "active" ? "Ativa" : c.status}</span>{isAdmin && <button className="currency-text-button" onClick={() => { const note = window.prompt("Justificativa para alterar a situação da moeda:"); if (note && note.trim().length >= 5) void run(() => supabase.rpc("admin_set_currency_status", { p_currency_id: c.id, p_status: c.status === "active" ? "suspended" : "active", p_justification: note.trim() }), "Situação da moeda atualizada."); }}>{c.status === "active" ? "Suspender" : "Reativar"}</button>}</article>;
      }) : <div className="currency-empty">Nenhuma moeda encontrada.</div>}</div>
      {!currencies.length && <div className="currency-empty"><CircleAlert/> Ainda não existem moedas cadastradas. O Super Admin deverá criar as primeiras moedas antes de habilitar cotações.</div>}
      <div className="currency-panel"><h3><TrendingUp size={18}/> Evolução cambial registrada</h3>{chartRows.length > 1 ? <><p className="currency-hint">Histórico real de {byId.get(chartPair![0])?.internal_code} para {byId.get(chartPair![1])?.internal_code}. Não há preenchimento artificial de períodos sem cotação.</p><div className="currency-chart"><ResponsiveContainer width="100%" height="100%"><LineChart data={chartRows}><CartesianGrid stroke="#263b55" strokeDasharray="3 3"/><XAxis dataKey="effective_from" tickFormatter={(v)=>new Date(v).toLocaleDateString("pt-BR")} stroke="#91a7c2"/><YAxis stroke="#91a7c2" domain={["auto","auto"]}/><Tooltip labelFormatter={(v)=>dateTime(String(v))} formatter={(v)=>[fmt(v,8),"Taxa"]}/><Line type="monotone" dataKey="rate" stroke="#53b5ff" strokeWidth={2} dot={false}/></LineChart></ResponsiveContainer></div><p className="currency-hint">Variação entre o primeiro e o último registro do gráfico: {fmt(((Number(chartRows[chartRows.length-1]?.rate ?? 0)/Number(chartRows[0]?.rate ?? 1))-1)*100,2)}%.</p></> : <div className="currency-empty">Ainda não há histórico suficiente para desenhar um gráfico. Cadastre mais de uma versão de cotação para o par selecionado.</div>}</div>

      {profile?.role === "president" && profile?.country_id && <div className="currency-panel"><h3>Solicitar alteração da moeda nacional</h3><form className="currency-form" onSubmit={requestNationalCurrency}><label>Moeda pretendida<select required value={assignmentForm.currency_id} onChange={e=>setAssignmentForm({...assignmentForm,currency_id:e.target.value})}><option value="">Selecione</option>{currencies.filter(c=>c.status==="active").map(c=><option key={c.id} value={c.id}>{c.name} ({c.internal_code})</option>)}</select></label><label>Justificativa<input required minLength={5} value={requestReason} onChange={e=>setRequestReason(e.target.value)} placeholder="Explique o motivo da solicitação"/></label><button className="currency-button" disabled={busy || !assignmentForm.currency_id}>Enviar solicitação</button></form><p className="currency-hint">A moeda do país só muda após análise e aprovação do Super Admin.</p></div>}
      {isAdmin && <div className="currency-panel"><h3>Solicitações de mudança de moeda nacional</h3>{currencyRequests.filter(r=>r.status==="pending").length ? currencyRequests.filter(r=>r.status==="pending").map(r=><article className="currency-request" key={r.id}><div><strong>{r.currencies?.name ?? "Moeda solicitada"} ({r.currencies?.internal_code ?? "—"})</strong><p>País ID: {r.country_id}</p><small>{r.reason} · {dateTime(r.created_at)}</small></div><div className="currency-request-actions"><button className="currency-button" disabled={busy} onClick={()=>reviewCurrencyRequest(r.id,"approved")}>Aprovar</button><button className="currency-text-button" disabled={busy} onClick={()=>reviewCurrencyRequest(r.id,"rejected")}>Rejeitar</button></div></article>) : <div className="currency-empty">Não há solicitações pendentes.</div>}</div>}
      {isAdmin && <div className="currency-panel"><h3><Settings2 size={17}/> Moeda de referência internacional</h3><div className="currency-inline"><select value={referenceId} onChange={e=>setReferenceId(e.target.value)}><option value="">Selecione a moeda</option>{currencies.map(c=><option key={c.id} value={c.id}>{c.name} ({c.internal_code})</option>)}</select><button className="currency-button" disabled={busy || !referenceId} onClick={setReference}>Definir referência</button></div><p className="currency-hint">A moeda de referência é usada somente para comparações dentro da simulação. Não representa moeda real.</p></div>}
    </>}

    {tab === "converter" && <div className="currency-panel"><h3><ArrowDownUp size={18}/> Calculadora de conversão</h3><form onSubmit={convert} className="currency-converter"><label>Valor<input value={amount} onChange={e=>{setAmount(e.target.value);setConversion(null);}} inputMode="decimal" placeholder="100,00"/></label><label>De<select value={fromId} onChange={e=>{setFromId(e.target.value);setConversion(null);}}>{currencies.map(c=><option key={c.id} value={c.id}>{c.name} ({c.internal_code})</option>)}</select></label><button type="button" className="currency-invert" onClick={invert} aria-label="Inverter moedas"><ArrowDownUp/></button><label>Para<select value={toId} onChange={e=>{setToId(e.target.value);setConversion(null);}}>{currencies.map(c=><option key={c.id} value={c.id}>{c.name} ({c.internal_code})</option>)}</select></label><button className="currency-button" type="submit" disabled={busy || !currencies.length}>Converter</button></form>
      {conversion && from && to && <div className="currency-result"><small>RESULTADO INFORMATIVO · SEM MOVIMENTAÇÃO FINANCEIRA</small><strong>{fmt(conversion.amount, to.decimal_places)} {to.symbol}</strong><p>{fmt(amount.replace(",", "."), from.decimal_places)} {from.symbol} × {fmt(conversion.rate, 8)} = {fmt(conversion.amount, to.decimal_places)} {to.symbol}</p><span>Taxa aplicada · {conversion.direction === "inverse" ? "inversa" : conversion.direction === "same" ? "mesma moeda" : "direta"} · {dateTime(conversion.as_of)}</span></div>}
      {!conversion && <p className="currency-hint">A calculadora utiliza somente uma cotação ativa e vigente. Se não existir taxa, nenhum resultado será exibido.</p>}
    </div>}

    {tab === "currencies" && isAdmin && <>
      <div className="currency-panel"><h3><Plus size={18}/> Cadastrar moeda</h3><form className="currency-form" onSubmit={createCurrency}>
        <label>Nome oficial<input required minLength={2} value={currencyForm.name} onChange={e=>setCurrencyForm({...currencyForm,name:e.target.value})}/></label>
        <label>Nome abreviado<input required minLength={2} value={currencyForm.short_name} onChange={e=>setCurrencyForm({...currencyForm,short_name:e.target.value})}/></label>
        <label>Código interno<input required minLength={3} maxLength={8} value={currencyForm.internal_code} onChange={e=>setCurrencyForm({...currencyForm,internal_code:e.target.value.toUpperCase().replace(/[^A-Z0-9]/g,"")})} placeholder="Ex.: WEC"/></label>
        <label>Símbolo<input required maxLength={8} value={currencyForm.symbol} onChange={e=>setCurrencyForm({...currencyForm,symbol:e.target.value})}/></label>
        <label>Casas decimais<select value={currencyForm.decimal_places} onChange={e=>setCurrencyForm({...currencyForm,decimal_places:e.target.value})}>{[0,1,2,3,4,5,6].map(n=><option key={n}>{n}</option>)}</select></label>
        <label className="wide">Descrição<textarea value={currencyForm.description} onChange={e=>setCurrencyForm({...currencyForm,description:e.target.value})}/></label>
        <button className="currency-button" disabled={busy}>Salvar moeda</button>
      </form></div>
      <div className="currency-panel"><h3>Associar moeda a um país</h3><form className="currency-form" onSubmit={assignCurrency}>
        <label>País<select required value={assignmentForm.country_id} onChange={e=>setAssignmentForm({...assignmentForm,country_id:e.target.value})}><option value="">Selecione</option>{countries.map(c=><option key={c.id} value={c.id}>{c.flag} {c.name}</option>)}</select></label>
        <label>Moeda<select required value={assignmentForm.currency_id} onChange={e=>setAssignmentForm({...assignmentForm,currency_id:e.target.value})}><option value="">Selecione</option>{currencies.map(c=><option key={c.id} value={c.id}>{c.name} ({c.internal_code})</option>)}</select></label>
        <label className="wide">Justificativa<input required minLength={5} value={assignmentForm.justification} onChange={e=>setAssignmentForm({...assignmentForm,justification:e.target.value})}/></label>
        <button className="currency-button" disabled={busy || !countries.length || !currencies.length}>Definir moeda nacional</button>
      </form><p className="currency-hint">A alteração não converte saldos nem reescreve snapshots históricos. A Etapa 6 mantém sua validação de consistência monetária.</p></div>
    </>}

    {tab === "rates" && isAdmin && <>
      <div className="currency-panel"><h3><Plus size={18}/> Nova cotação oficial</h3><form className="currency-form" onSubmit={createRate}>
        <label>Moeda de origem<select value={rateForm.from_currency_id} onChange={e=>setRateForm({...rateForm,from_currency_id:e.target.value})}>{currencies.map(c=><option key={c.id} value={c.id}>{c.name} ({c.internal_code})</option>)}</select></label>
        <label>Moeda de destino<select value={rateForm.to_currency_id} onChange={e=>setRateForm({...rateForm,to_currency_id:e.target.value})}>{currencies.map(c=><option key={c.id} value={c.id}>{c.name} ({c.internal_code})</option>)}</select></label>
        <label>Taxa · 1 origem = destino<input required type="number" min="0.000000000001" step="any" value={rateForm.rate} onChange={e=>setRateForm({...rateForm,rate:e.target.value})}/></label>
        <label>Início da vigência<input required type="datetime-local" value={rateForm.effective_from} onChange={e=>setRateForm({...rateForm,effective_from:e.target.value})}/></label>
        <label>Fim da vigência (opcional)<input type="datetime-local" value={rateForm.effective_until} onChange={e=>setRateForm({...rateForm,effective_until:e.target.value})}/></label>
        <label className="wide">Justificativa<input required minLength={5} value={rateForm.justification} onChange={e=>setRateForm({...rateForm,justification:e.target.value})}/></label>
        <button className="currency-button" disabled={busy || !currencies.length || rateForm.from_currency_id===rateForm.to_currency_id}>Registrar nova versão</button>
      </form></div>
      <div className="currency-panel"><h3>Cotações vigentes no mercado</h3>{snapshot.rates.length ? <div className="currency-table-wrap"><table className="currency-table"><thead><tr><th>Par</th><th>Taxa</th><th>Versão</th><th>Vigência</th><th>Situação</th><th/></tr></thead><tbody>{snapshot.rates.map(r=>{const a=byId.get(r.from_currency_id),b=byId.get(r.to_currency_id);return <tr key={r.id}><td>{a?.internal_code} → {b?.internal_code}</td><td>{fmt(r.rate,8)}</td><td>v{r.version}</td><td>{dateTime(r.effective_from)}</td><td>{r.status}</td><td><button className="currency-text-button" onClick={()=>changeRateStatus(r.id,"suspended")}>Suspender</button></td></tr>;})}</tbody></table></div>:<div className="currency-empty">Nenhuma cotação vigente cadastrada.</div>}</div>
    </>}

    {tab === "history" && isAdmin && <div className="currency-panel"><h3><History size={18}/> Histórico administrativo</h3>{history.length ? <div className="currency-history">{history.map((h,i)=><article key={h.id ?? i}><span className="currency-history-dot"/><div><strong>{h.action ?? h.event_type ?? h.kind}</strong><p>{h.justification ?? h.entity_type ?? "Registro administrativo"}</p><small>{dateTime(h.created_at)} · {h.actor_id ?? h.actor ?? "Sistema"}</small></div></article>)}</div>:<div className="currency-empty">Ainda não há alterações registradas.</div>}</div>}

    <div className="currency-footer"><BadgeCheck size={15}/> Valores fictícios exclusivos da simulação. A calculadora não movimenta dinheiro.</div>
  </div>;
}
