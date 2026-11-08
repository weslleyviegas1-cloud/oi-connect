import { useCallback, useEffect, useState, type FormEvent, type InputHTMLAttributes, type ReactNode } from "react";
import { Activity, BarChart3, Coins, FileSpreadsheet, Landmark, RefreshCw, ShieldCheck, TrendingDown, TrendingUp, Wallet, XCircle } from "lucide-react";
import { CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { supabase } from "@/lib/supabase";
import "./economy-portal.css";

type Row = any;
type Props = { profile: Row; notify: (message: string) => void };
type Tab = "overview" | "gdp" | "prices" | "tax" | "treasury" | "budget" | "investments" | "reports";
const tabs: { id: Tab; label: string }[] = [
  { id: "overview", label: "Visão geral" }, { id: "gdp", label: "PIB" }, { id: "prices", label: "Inflação" },
  { id: "tax", label: "Tributação" }, { id: "treasury", label: "Tesouro" }, { id: "budget", label: "Orçamento" },
  { id: "investments", label: "Investimentos" }, { id: "reports", label: "Relatórios" },
];
const today = () => new Date().toISOString().slice(0, 10);
const money = (value: unknown) => value == null ? "Dados insuficientes" : Number(value).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const date = (value: string) => value ? new Date(value + (value.length === 10 ? "T12:00:00" : "")).toLocaleDateString("pt-BR") : "—";

export function EconomyPortal({ profile, notify }: Props) {
  const isAdmin = profile?.role === "super_admin";
  const isPresident = profile?.role === "president";
  const [tab, setTab] = useState<Tab>("overview");
  const [countries, setCountries] = useState<Row[]>([]);
  const [countryId, setCountryId] = useState<string>(profile?.country_id ?? "");
  const [dashboard, setDashboard] = useState<Row | null>(null);
  const [gdp, setGdp] = useState<Row[]>([]);
  const [prices, setPrices] = useState<Row[]>([]);
  const [taxRules, setTaxRules] = useState<Row[]>([]);
  const [obligations, setObligations] = useState<Row[]>([]);
  const [ledger, setLedger] = useState<Row[]>([]);
  const [budgets, setBudgets] = useState<Row[]>([]);
  const [allocations, setAllocations] = useState<Row[]>([]);
  const [projects, setProjects] = useState<Row[]>([]);
  const [ministries, setMinistries] = useState<Row[]>([]);
  const [treasury, setTreasury] = useState<Row | null>(null);
  const [permissions, setPermissions] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const canManage = isAdmin || isPresident;

  const load = useCallback(async () => {
    setLoading(true);
    try {
      if (isAdmin) {
        const c = await supabase.from("countries").select("id,name,flag,currency_code,is_active").order("name");
        if (c.error) throw c.error;
        setCountries(c.data ?? []);
      }
      const selected = isAdmin ? countryId || null : profile?.country_id ?? null;
      let granted: string[] = [];
      if (selected && profile?.id && !isAdmin && !isPresident) {
        const member = await supabase.from("government_members").select("id").eq("profile_id", profile.id).eq("country_id", selected).eq("status", "active").maybeSingle();
        if (member.data) {
          const perms = await supabase.from("government_member_permissions").select("permission_key").eq("member_id", member.data.id);
          granted = (perms.data ?? []).map(row => row.permission_key);
        }
      }
      setPermissions(granted);
      let gQuery = supabase.from("economic_gdp_records").select("*").order("period_end", { ascending: false }).limit(selected ? 36 : 1000);
      let pQuery = supabase.from("economic_price_observations").select("*,economic_price_items(name,category,base_weight)").order("reference_date", { ascending: false }).limit(100);
      let trQuery = supabase.from("tax_rules").select("*").order("created_at", { ascending: false }).limit(100);
      let obQuery = supabase.from("tax_obligations").select("*").order("created_at", { ascending: false }).limit(100);
      let leQuery = supabase.from("treasury_ledger_entries").select("*").order("created_at", { ascending: false }).limit(100);
      let buQuery = supabase.from("budget_plans").select("*").order("created_at", { ascending: false }).limit(50);
      let alQuery = supabase.from("budget_allocations").select("*").limit(200);
      let prQuery = supabase.from("public_investment_projects").select("*").order("created_at", { ascending: false }).limit(100);
      if (selected) {
        gQuery = gQuery.eq("country_id", selected); pQuery = pQuery.eq("country_id", selected);
        trQuery = trQuery.eq("country_id", selected); obQuery = obQuery.eq("country_id", selected);
        leQuery = leQuery.eq("country_id", selected); buQuery = buQuery.eq("country_id", selected);
        alQuery = alQuery.eq("country_id", selected); prQuery = prQuery.eq("country_id", selected);
      }
      const [dash, g, p, tr, ob, le, bu, al, pr, ts, mi] = await Promise.all([
        supabase.rpc("get_economy_dashboard", { p_country_id: selected }),
        gQuery, pQuery, trQuery, obQuery, leQuery, buQuery, alQuery, prQuery,
        selected ? supabase.from("national_treasuries").select("*").eq("country_id", selected).maybeSingle() : Promise.resolve({ data: null, error: null }),
        selected ? supabase.from("ministries").select("id,name").eq("country_id", selected).eq("status","active").order("name") : Promise.resolve({ data: [], error: null }),
      ]);
      if (dash.error) throw dash.error;
      setDashboard(dash.data);
      setGdp(g.data ?? []); setPrices(p.data ?? []); setTaxRules(tr.data ?? []);
      setObligations(ob.data ?? []); setLedger(le.data ?? []); setBudgets(bu.data ?? []);
      setAllocations(al.data ?? []); setProjects(pr.data ?? []); setTreasury(ts.data); setMinistries(mi.data ?? []);
    } catch (error) {
      notify(error instanceof Error ? error.message : "Não foi possível carregar a economia.");
    } finally { setLoading(false); }
  }, [countryId, isAdmin, isPresident, profile?.country_id, profile?.id, notify]);

  useEffect(() => { void load(); }, [load]);

  const invoke = async (name: string, args: Row, success: string) => {
    setBusy(true);
    try {
      const result = await supabase.rpc(name as never, args as never);
      if (result.error) throw result.error;
      notify(success);
      await load();
    } catch (error) {
      notify(error instanceof Error ? error.message : "A operação não foi concluída.");
    } finally { setBusy(false); }
  };

  const exportCsv = (rows: Row[], filename: string) => {
    if (!rows.length) { notify("Não há registros para exportar."); return; }
    const first = rows[0];
    if (!first) return;
    const keys = Object.keys(first);
    const csv = [keys.join(";"), ...rows.map(row => keys.map(key => '"' + String(row[key] ?? "").replaceAll('"', '""') + '"').join(";"))].join("\n");
    const url = URL.createObjectURL(new Blob(["\ufeff" + csv], { type: "text/csv;charset=utf-8" }));
    const anchor = document.createElement("a"); anchor.href = url; anchor.download = filename; anchor.click(); URL.revokeObjectURL(url);
  };
  const selectedCountryId = isAdmin ? countryId : profile?.country_id ?? "";
  const hasPermission = (...keys: string[]) => canManage || keys.some(key => permissions.includes(key));
  const canGDP = !!selectedCountryId && hasPermission("economy.manage");
  const canTax = !!selectedCountryId && hasPermission("tax.manage");
  const canCollect = !!selectedCountryId && hasPermission("tax.collect", "economy.manage");
  const canTreasury = !!selectedCountryId && hasPermission("treasury.revenue", "treasury.expense", "economy.manage");
  const canBudget = !!selectedCountryId && hasPermission("budget.manage");
  const canInvestment = !!selectedCountryId && hasPermission("investment.manage");

  return <div className="eco-root">
    <div className="eco-toolbar"><div><span className="eco-eyebrow">WORLD ECONOMY / ECONOMIA</span><h2>{isAdmin && !countryId ? "Economia Global" : "Economia Nacional"}</h2><p>{isAdmin ? "Supervisão consolidada dos países e dos Tesouros Nacionais." : isPresident ? "Administração econômica do seu país." : "Indicadores públicos da economia do seu país."}</p></div>
      <div className="eco-toolbar-actions">{isAdmin && <select value={countryId} onChange={e => setCountryId(e.target.value)}><option value="">Visão global</option>{countries.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}</select>}<button type="button" onClick={() => void load()} disabled={loading}><RefreshCw size={16}/> Atualizar</button></div>
    </div>
    <div className="eco-tabs">{tabs.map(item => <button key={item.id} className={tab === item.id ? "active" : ""} onClick={() => setTab(item.id)}>{item.label}</button>)}</div>
    {loading ? <div className="eco-empty">Carregando dados econômicos...</div> : !dashboard ? <div className="eco-empty">Não há país vinculado ou dados econômicos disponíveis para esta conta.</div> :
      <>
        {tab === "overview" && <Overview dashboard={dashboard} countries={dashboard.countries ?? []} gdp={gdp}/>}
        {tab === "gdp" && <section className="eco-panel"><SectionTitle title="Produto Interno Bruto" subtitle="O PIB soma somente componentes de produção registrados. Tesouro e transferências não entram no cálculo." onExport={() => exportCsv(gdp,"world-economy-pib.csv")}/>
          {canGDP && <form className="eco-form" onSubmit={e => { e.preventDefault(); const f = new FormData(e.currentTarget); const sectors: [string,string][] = [["industrial","Produção industrial"],["mining","Produção mineral"],["agriculture","Produção agrícola"],["services","Serviços"],["commerce","Comércio"],["construction","Construção e infraestrutura"],["other","Outras atividades"]]; const components = sectors.map(([key,label]) => ({ sector: label, amount: Number(f.get(key) || 0) })).filter(x => x.amount > 0); void invoke("save_gdp_record",{p_country_id:selectedCountryId,p_period_start:f.get("start"),p_period_end:f.get("end"),p_components:components,p_source_description:f.get("source") || "Registro manual autorizado"},"Registro do PIB salvo."); e.currentTarget.reset(); }}>
            <h3>Novo registro manual</h3><div className="eco-grid-2"><Field label="Início do período" name="start" type="date" required/><Field label="Fim do período" name="end" type="date" required/></div>
            <div className="eco-grid-2">{[["industrial","Produção industrial"],["mining","Produção mineral"],["agriculture","Produção agrícola"],["services","Serviços"],["commerce","Comércio"],["construction","Construção e infraestrutura"],["other","Outras atividades"]].map(([name,label])=><Field key={name} label={label+" (unidades monetárias)"} name={name} type="number" min="0" step="0.01" defaultValue="0"/>)}</div><Field label="Fonte / observação" name="source" placeholder="Registro manual do governo"/><button disabled={busy}>Salvar PIB calculado</button>
          </form>}
          <div className="eco-chart"><ResponsiveContainer width="100%" height={260}><LineChart data={[...gdp].reverse()}><CartesianGrid strokeDasharray="3 3" opacity={.15}/><XAxis dataKey="period_end"/><YAxis/><Tooltip formatter={(v: any) => money(v)}/><Line type="monotone" dataKey="total_value" stroke="#39a9ff" strokeWidth={2} dot={false}/></LineChart></ResponsiveContainer></div>
          <DataTable rows={gdp} columns={[["period_start","Início"],["period_end","Fim"],["total_value","PIB"],["source","Fonte"],["status","Situação"]]}/>
        </section>}
        {tab === "prices" && <section className="eco-panel"><SectionTitle title="Preços e inflação simulada" subtitle="IPC calculado a partir das observações de preços e pesos cadastrados; sem base suficiente, a inflação não é exibida."/>
          {canGDP && <form className="eco-form" onSubmit={e=>{e.preventDefault();const f=new FormData(e.currentTarget);void invoke("save_price_item",{p_country_id:selectedCountryId,p_name:f.get("name"),p_category:f.get("category"),p_weight:Number(f.get("weight")),p_price:Number(f.get("price")),p_reference_date:f.get("date")},"Preço de referência atualizado.");e.currentTarget.reset();}}>
            <h3>Registrar preço de item</h3><div className="eco-grid-2"><Field label="Produto ou serviço" name="name" required/><Field label="Categoria" name="category" required/><Field label="Peso no índice" name="weight" type="number" min="0.0001" step="0.0001" defaultValue="1" required/><Field label="Preço observado" name="price" type="number" min="0.01" step="0.01" required/><Field label="Data de referência" name="date" type="date" defaultValue={today()} required/></div><button disabled={busy}>Salvar observação</button>
          </form>}<DataTable rows={prices} columns={[["reference_date","Data"],["name","Item"],["category","Categoria"],["price","Preço"]]}/>
        </section>}
        {tab === "tax" && <section className="eco-panel"><SectionTitle title="Sistema tributário" subtitle="Regras tributárias versionadas e obrigações registradas no país." onExport={() => exportCsv(obligations,"world-economy-tributos.csv")}/>
          {canTax && <><form className="eco-form" onSubmit={e=>{e.preventDefault();const f=new FormData(e.currentTarget);void invoke("create_tax_rule",{p_country_id:selectedCountryId,p_name:f.get("name"),p_identifier:f.get("identifier"),p_category:f.get("category"),p_description:f.get("description"),p_rate:Number(f.get("rate")),p_calculation_base:f.get("base"),p_effective_from:f.get("effective")},"Proposta tributária enviada para aprovação.");e.currentTarget.reset();}}>
            <h3>Propor tributo</h3><div className="eco-grid-2"><Field label="Nome" name="name" required/><Field label="Identificador" name="identifier" required/><Field label="Categoria" name="category" required/><Field label="Alíquota (%)" name="rate" type="number" min="0" max="100" step="0.01" required/><Field label="Base de cálculo" name="base" defaultValue="declared_value"/><Field label="Início da vigência" name="effective" type="date" defaultValue={today()} required/></div><Field label="Descrição" name="description"/><button disabled={busy}>Enviar proposta</button>
          </form><form className="eco-form" onSubmit={e=>{e.preventDefault();const f=new FormData(e.currentTarget);void invoke("create_tax_obligation",{p_country_id:selectedCountryId,p_rule_id:f.get("rule"),p_taxpayer_profile_id:null,p_taxpayer_label:f.get("taxpayer"),p_reference_period:f.get("period"),p_calculation_base:Number(f.get("base")),p_due_date:f.get("due") || null},"Obrigação tributária lançada.");e.currentTarget.reset();}}>
            <h3>Lançar obrigação</h3><label>Regra ativa<select name="rule" required><option value="">Selecione</option>{taxRules.filter(x=>x.status==="active").map(x=><option key={x.id} value={x.id}>{x.name} — {x.rate}%</option>)}</select></label><div className="eco-grid-2"><Field label="Contribuinte (referência)" name="taxpayer" required/><Field label="Período" name="period" placeholder="2026-11" required/><Field label="Base de cálculo" name="base" type="number" min="0" step="0.01" required/><Field label="Vencimento" name="due" type="date"/></div><button disabled={busy}>Calcular e lançar</button>
          </form></>}
          <h3>Regras tributárias</h3><DataTable rows={taxRules} columns={[["name","Tributo"],["category","Categoria"],["rate","Alíquota %"],["status","Situação"],["effective_from","Vigência"]]}/>
          {isAdmin && <ReviewList rows={taxRules.filter(x=>x.status==="awaiting_approval")} onReview={(id,decision)=>void invoke("review_tax_rule",{p_rule_id:id,p_decision:decision,p_note:"Revisão do Super Admin"},"Regra tributária revisada.")}/>}
          <h3>Obrigações tributárias</h3><DataTable rows={obligations} columns={[["taxpayer_label","Contribuinte"],["reference_period","Período"],["amount_due","Valor devido"],["status","Situação"],["due_date","Vencimento"]]}/>
          {canCollect && <form className="eco-form" onSubmit={e=>{e.preventDefault();const f=new FormData(e.currentTarget);void invoke("confirm_tax_collection",{p_obligation_id:f.get("obligation"),p_amount:Number(f.get("amount")),p_confirmation_reference:f.get("reference")},"Arrecadação confirmada e lançada no Tesouro.");e.currentTarget.reset();}}>
            <h3>Confirmar arrecadação manual</h3><label>Obrigação<select name="obligation" required><option value="">Selecione</option>{obligations.filter(x=>["open","partially_paid","overdue"].includes(x.status)).map(x=><option key={x.id} value={x.id}>{x.taxpayer_label || "Contribuinte"} — {money(x.amount_due)} ({x.status})</option>)}</select></label><div className="eco-grid-2"><Field label="Valor recebido" name="amount" type="number" min="0.01" step="0.01" required/><Field label="Referência única" name="reference" required/></div><button disabled={busy}>Confirmar recebimento</button>
          </form>}
        </section>}
        {tab === "treasury" && <section className="eco-panel"><SectionTitle title="Tesouro Nacional" subtitle="Saldo derivado do saldo inicial e do livro-razão; não existe campo para editar o saldo diretamente." onExport={() => exportCsv(ledger,"world-economy-tesouro.csv")}/>
          <div className="eco-metrics"><Metric title="Saldo atual" value={money(dashboard.treasury_balance)} icon={<Wallet/>}/><Metric title="Receitas realizadas" value={money(dashboard.revenue)} icon={<TrendingUp/>}/><Metric title="Despesas realizadas" value={money(dashboard.expenses)} icon={<TrendingDown/>}/><Metric title="Arrecadação tributária" value={money(dashboard.tax_collected)} icon={<Coins/>}/></div>
          {isAdmin && treasury && treasury.opening_balance_set_at == null && ledger.length === 0 && <form className="eco-form" onSubmit={e=>{e.preventDefault();const f=new FormData(e.currentTarget);void invoke("set_treasury_opening_balance",{p_country_id:selectedCountryId,p_amount:Number(f.get("opening"))},"Saldo inicial definido. Este procedimento não poderá ser repetido após o primeiro lançamento.");e.currentTarget.reset();}}>
            <h3>Definir saldo inicial do Tesouro</h3><p className="eco-muted">Disponível uma única vez, antes do primeiro lançamento. O valor ficará registrado como saldo de abertura.</p><Field label="Saldo inicial" name="opening" type="number" min="0" step="0.01" defaultValue="0" required/><button disabled={busy}>Definir saldo inicial</button>
          </form>}
          {canTreasury && <form className="eco-form" onSubmit={e=>{e.preventDefault();const f=new FormData(e.currentTarget);void invoke("post_treasury_entry",{p_country_id:selectedCountryId,p_entry_type:f.get("type"),p_category:f.get("category"),p_description:f.get("description"),p_amount:Number(f.get("amount")),p_idempotency_key:crypto.randomUUID(),p_budget_allocation_id:f.get("allocation") || null,p_investment_project_id:f.get("investment") || null},"Lançamento registrado no livro-razão.");e.currentTarget.reset();}}>
            <h3>Registrar receita ou despesa</h3><div className="eco-grid-2"><label>Tipo<select name="type"><option value="revenue">Receita não tributária</option><option value="expense">Despesa</option></select></label><Field label="Categoria" name="category" required/><Field label="Descrição e origem" name="description" required/><Field label="Valor" name="amount" type="number" min="0.01" step="0.01" required/><label>Alocação orçamentária (obrigatória para despesa)<select name="allocation"><option value="">Selecione se despesa</option>{allocations.map(a=><option key={a.id} value={a.id}>{a.category} — limite {money(a.planned_amount)}</option>)}</select></label><label>Projeto de investimento (opcional)<select name="investment"><option value="">Não vincular</option>{projects.filter(p=>["approved","in_progress"].includes(p.status)).map(p=><option key={p.id} value={p.id}>{p.name}</option>)}</select></label></div><button disabled={busy}>Registrar no Tesouro</button>
          </form>}
          <DataTable rows={ledger} columns={[["created_at","Data"],["entry_type","Tipo"],["category","Categoria"],["description","Descrição"],["amount","Valor"],["idempotency_key","Referência"]]}/>
          {isAdmin && <ReviewList rows={ledger} onReview={(id)=>{if(confirm("Estornar este lançamento? O registro original será preservado."))void invoke("reverse_treasury_entry",{p_entry_id:id,p_reason:"Correção administrativa",p_idempotency_key:"reversal-"+crypto.randomUUID()},"Estorno registrado.");}} reversal/>}
          {canManage && countryId && <button className="eco-secondary" onClick={()=>void invoke("set_treasury_public_visibility",{p_country_id:selectedCountryId,p_visible:!treasury?.public_balance_visible},"Visibilidade pública atualizada.")}>{treasury?.public_balance_visible ? "Ocultar saldo público" : "Tornar saldo do Tesouro público"}</button>}
        </section>}
        {tab === "budget" && <section className="eco-panel"><SectionTitle title="Orçamento Nacional" subtitle="Previsão e aprovação não movimentam dinheiro; a execução exige lançamento no Tesouro." onExport={() => exportCsv(budgets,"world-economy-orcamento.csv")}/>
          {canBudget && <form className="eco-form" onSubmit={e=>{e.preventDefault();const f=new FormData(e.currentTarget);void invoke("create_budget_plan",{p_country_id:selectedCountryId,p_name:f.get("name"),p_period_start:f.get("start"),p_period_end:f.get("end"),p_allocations:[{category:f.get("category"),planned_amount:Number(f.get("amount")),ministry_id:f.get("ministry") || null}]},"Orçamento criado e enviado conforme a regra de aprovação.");e.currentTarget.reset();}}>
            <h3>Elaborar orçamento</h3><div className="eco-grid-2"><Field label="Nome" name="name" required/><Field label="Categoria orçamentária" name="category" required/><label>Ministério responsável<select name="ministry"><option value="">Sem ministério específico</option>{ministries.map(m=><option key={m.id} value={m.id}>{m.name}</option>)}</select></label><Field label="Início" name="start" type="date" required/><Field label="Fim" name="end" type="date" required/><Field label="Valor previsto" name="amount" type="number" min="0" step="0.01" required/></div><button disabled={busy}>Criar orçamento</button>
          </form>}
          <DataTable rows={budgets} columns={[["name","Orçamento"],["period_start","Início"],["period_end","Fim"],["total_planned","Previsto"],["status","Situação"]]}/>
          {isAdmin && <ReviewList rows={budgets.filter(x=>x.status==="awaiting_approval")} onReview={(id,decision)=>void invoke("review_budget_plan",{p_plan_id:id,p_decision:decision,p_note:"Revisão do Super Admin"},"Orçamento revisado.")}/>}
          <DataTable rows={allocations} columns={[["category","Categoria"],["planned_amount","Limite aprovado"]]}/>
        </section>}
        {tab === "investments" && <section className="eco-panel"><SectionTitle title="Investimentos públicos" subtitle="Projetos aprovados só entram como execução após lançamento financeiro correspondente." onExport={() => exportCsv(projects,"world-economy-investimentos.csv")}/>
          {canInvestment && <form className="eco-form" onSubmit={e=>{e.preventDefault();const f=new FormData(e.currentTarget);void invoke("create_investment_project",{p_country_id:selectedCountryId,p_name:f.get("name"),p_description:f.get("description"),p_category:f.get("category"),p_budget_allocation_id:f.get("allocation") || null,p_planned_amount:Number(f.get("amount")),p_starts_on:f.get("start") || null,p_expected_end:f.get("end") || null},"Projeto de investimento criado.");e.currentTarget.reset();}}>
            <h3>Propor projeto</h3><div className="eco-grid-2"><Field label="Nome" name="name" required/><Field label="Categoria" name="category" required/><Field label="Valor previsto" name="amount" type="number" min="0" step="0.01" required/><Field label="Início" name="start" type="date"/><Field label="Prazo" name="end" type="date"/><label>Alocação aprovada<select name="allocation" required><option value="">Selecione</option>{allocations.map(a=><option key={a.id} value={a.id}>{a.category}</option>)}</select></label></div><Field label="Descrição" name="description"/><button disabled={busy}>Criar projeto</button>
          </form>}
          <DataTable rows={projects} columns={[["name","Projeto"],["category","Categoria"],["planned_amount","Previsto"],["approved_amount","Aprovado"],["executed_amount","Executado"],["status","Situação"]]}/>
          {isAdmin && <ReviewList rows={projects.filter(x=>["proposed","under_review"].includes(x.status))} onReview={(id,decision)=>{const item=projects.find(x=>x.id===id);const approved=decision==="approved"?prompt("Valor aprovado (até "+item?.planned_amount+")",String(item?.planned_amount ?? 0)):null;if(decision==="approved" && approved===null)return;void invoke("review_investment_project",{p_project_id:id,p_decision:decision,p_approved_amount:approved===null?null:Number(approved)},"Projeto revisado.");}}/>}
        </section>}
        {tab === "reports" && <section className="eco-panel"><SectionTitle title="Relatórios econômicos" subtitle="Exportação CSV dos registros visíveis nesta conta; os dados incompletos permanecem identificados."/><div className="eco-report-list"><button onClick={()=>exportCsv(gdp,"world-economy-pib.csv")}><BarChart3/> Exportar PIB</button><button onClick={()=>exportCsv(obligations,"world-economy-tributos.csv")}><FileSpreadsheet/> Exportar tributos</button><button onClick={()=>exportCsv(ledger,"world-economy-tesouro.csv")}><Landmark/> Exportar Tesouro</button><button onClick={()=>exportCsv(budgets,"world-economy-orcamento.csv")}>Exportar orçamento</button><button onClick={()=>exportCsv(projects,"world-economy-investimentos.csv")}>Exportar investimentos</button></div></section>}
      </>}
  </div>;
}

function Overview({ dashboard, countries, gdp }: { dashboard: Row; countries: Row[]; gdp: Row[] }) {
  const [search, setSearch] = useState("");
  const [continent, setContinent] = useState("all");
  const [period, setPeriod] = useState("all");
  const [customStart, setCustomStart] = useState("");
  const [customEnd, setCustomEnd] = useState("");
  const [status, setStatus] = useState("all");
  const [indicator, setIndicator] = useState("both");
  if (dashboard.scope === "global") {
    const days = Number(period);
    const cutoff = Number.isFinite(days) && days > 0 ? Date.now() - days * 86400000 : null;
    const periodRecords = gdp.filter(row => row.status === "confirmed" &&
      (!cutoff || new Date(row.period_end).getTime() >= cutoff) &&
      (period !== "custom" || ((!customStart || row.period_end >= customStart) && (!customEnd || row.period_end <= customEnd))));
    const latest = new Map<string, Row>();
    for (const record of periodRecords) if (!latest.has(record.country_id)) latest.set(record.country_id, record);
    const filtered = countries.map(country => ({...country,
      gdp: cutoff ? latest.get(country.id)?.total_value ?? null : country.gdp,
      gdp_period_end: cutoff ? latest.get(country.id)?.period_end ?? null : country.gdp_period_end,
    })).filter(country =>
      String(country.name ?? "").toLowerCase().includes(search.toLowerCase()) &&
      (continent === "all" || country.continent === continent) &&
      (status === "all" || (status === "active" && country.is_active) || (status === "inactive" && !country.is_active) ||
        (status === "with-gdp" && country.gdp != null) || (status === "without-gdp" && country.gdp == null))
    );
    const columns: [string,string][] = [["name","País"]];
    if (indicator !== "treasury") columns.push(["gdp","PIB no período"],["gdp_period_end","Data do PIB"]);
    if (indicator !== "gdp") columns.push(["treasury_balance","Saldo do Tesouro"],["currency_label","Unidade monetária"]);
    if (indicator !== "treasury") columns.push(["gdp_growth","Crescimento %"]);
    return <section className="eco-panel"><SectionTitle title="Panorama econômico global" subtitle="Consolidação dos registros disponíveis por país. Valores de moedas diferentes não são convertidos."/>
      <div className="eco-metrics"><Metric title="Países ativos" value={String(dashboard.countries_active ?? 0)} icon={<Activity/>}/><Metric title="Sem PIB registrado" value={String(dashboard.countries_without_gdp ?? 0)} icon={<BarChart3/>}/><Metric title="Crescimento positivo" value={String(dashboard.countries_growth_positive ?? 0)} icon={<TrendingUp/>}/><Metric title="Crescimento negativo" value={String(dashboard.countries_growth_negative ?? 0)} icon={<TrendingDown/>}/><Metric title="PIB nominal agregado" value={money(dashboard.gdp_total)} icon={<BarChart3/>}/><Metric title="Tesouros consolidados" value={money(dashboard.treasury_total)} icon={<Landmark/>}/><Metric title="Receitas realizadas" value={money(dashboard.revenue_total)} icon={<TrendingUp/>}/><Metric title="Despesas realizadas" value={money(dashboard.expenses_total)} icon={<TrendingDown/>}/><Metric title="Investimentos aprovados" value={money(dashboard.investment_total)} icon={<Coins/>}/><Metric title="Arrecadação tributária" value={money(dashboard.tax_revenue_total)} icon={<ShieldCheck/>}/><Metric title="Inflação média global" value={dashboard.inflation_average == null ? "Dados insuficientes" : Number(dashboard.inflation_average).toFixed(2)+"%"} icon={<Activity/>}/></div>
      <div className="eco-filters"><input aria-label="Pesquisar país" placeholder="Pesquisar país..." value={search} onChange={e=>setSearch(e.target.value)}/>
        <select aria-label="Continente" value={continent} onChange={e=>setContinent(e.target.value)}><option value="all">Todos os continentes</option>{[...new Set(countries.map(c=>c.continent).filter(Boolean))].sort().map(value=><option key={value} value={value}>{value}</option>)}</select>
        <select aria-label="Período" value={period} onChange={e=>setPeriod(e.target.value)}><option value="all">Todo o histórico</option><option value="30">Mensal · 30 dias</option><option value="90">Trimestral · 90 dias</option><option value="180">Semestral · 180 dias</option><option value="365">Anual · 12 meses</option><option value="custom">Personalizado</option></select>
        {period === "custom" && <><input aria-label="Data inicial" type="date" value={customStart} onChange={e=>setCustomStart(e.target.value)}/><input aria-label="Data final" type="date" value={customEnd} onChange={e=>setCustomEnd(e.target.value)}/></> }
        <select aria-label="Situação econômica" value={status} onChange={e=>setStatus(e.target.value)}><option value="all">Todas as situações</option><option value="active">Países ativos</option><option value="inactive">Países inativos</option><option value="with-gdp">Com PIB no período</option><option value="without-gdp">Sem PIB no período</option><option value="growth-positive">Crescimento positivo</option><option value="growth-negative">Crescimento negativo</option><option value="stable">Estabilidade</option></select>
        <select aria-label="Indicador" value={indicator} onChange={e=>setIndicator(e.target.value)}><option value="both">PIB e Tesouro</option><option value="gdp">Somente PIB</option><option value="treasury">Somente Tesouro</option></select>
      </div>
      <DataTable rows={filtered} columns={columns}/><p className="eco-muted">O PIB e os saldos são somas nominais, sem conversão cambial ou comparação de poder de compra. A inflação média é uma média simples apenas dos países com cesta completa.</p>
    </section>;
  }
  const nationalDays = Number(period);
  const nationalCutoff = Number.isFinite(nationalDays) && nationalDays > 0 ? Date.now() - nationalDays * 86400000 : null;
  const nationalGdp = gdp.filter(row => row.status === "confirmed" &&
    (!nationalCutoff || new Date(row.period_end).getTime() >= nationalCutoff) &&
    (period !== "custom" || ((!customStart || row.period_end >= customStart) && (!customEnd || row.period_end <= customEnd))));
  const growth = dashboard.gdp_growth;
  const fiscal = Number(dashboard.revenue ?? 0) - Number(dashboard.expenses ?? 0);
  return <section className="eco-panel"><SectionTitle title={dashboard.country_name ?? "Economia Nacional"} subtitle="Indicadores calculados a partir dos registros confirmados deste país."/>
    <div className="eco-country-heading"><strong>{dashboard.country_flag ?? "🌐"} {dashboard.country_name}</strong><span>{dashboard.currency_code || dashboard.currency_label || "Unidade monetária provisória"}</span></div>
    <div className="eco-metrics">
      <Metric title="PIB mais recente" value={money(dashboard.gdp)} icon={<BarChart3/>}/><Metric title="Crescimento" value={growth == null ? "Sem base de comparação" : Number(growth).toFixed(2)+"%"} icon={growth > 0 ? <TrendingUp/> : <TrendingDown/>}/>
      <Metric title="Inflação" value={dashboard.inflation == null ? "Dados insuficientes" : Number(dashboard.inflation).toFixed(2)+"%"} icon={<Activity/>}/><Metric title="Saldo do Tesouro" value={money(dashboard.treasury_balance)} icon={<Wallet/>}/>
      <Metric title="Receitas realizadas" value={money(dashboard.revenue)} icon={<TrendingUp/>}/><Metric title="Despesas realizadas" value={money(dashboard.expenses)} icon={<TrendingDown/>}/>
      <Metric title="Arrecadação tributária" value={money(dashboard.tax_collected)} icon={<Coins/>}/><Metric title="Obrigações em aberto" value={money(dashboard.tax_open)} icon={<ShieldCheck/>}/>
      <Metric title="Orçamento aprovado" value={money(dashboard.budget_approved)} icon={<FileSpreadsheet/>}/><Metric title="Investimentos aprovados" value={money(dashboard.investment_approved)} icon={<Landmark/>}/>
    </div>
    <p className="eco-muted">Resultado fiscal = receitas realizadas − despesas realizadas: <b>{money(fiscal)}</b>. Unidade: {dashboard.currency_code || "não configurada; unidade provisória"}. {dashboard.gdp == null ? "Dados insuficientes para calcular o PIB." : "Último período do PIB encerrado em "+date(dashboard.gdp_period_end)+"."}</p>
    <div className="eco-chart"><ResponsiveContainer width="100%" height={240}><LineChart data={[...nationalGdp].reverse()}><CartesianGrid strokeDasharray="3 3" opacity={.15}/><XAxis dataKey="period_end"/><YAxis/><Tooltip formatter={(v: any)=>money(v)}/><Line type="monotone" dataKey="total_value" stroke="#39a9ff" strokeWidth={2} dot={false}/></LineChart></ResponsiveContainer></div>
  </section>;
}
function SectionTitle({title,subtitle,onExport}:{title:string;subtitle:string;onExport?:()=>void}){return <header className="eco-section-title"><div><h3>{title}</h3><p>{subtitle}</p></div>{onExport&&<button type="button" onClick={onExport}><FileSpreadsheet size={15}/> CSV</button>}</header>}
function Metric({title,value,icon}:{title:string;value:string;icon:ReactNode}){return <article className="eco-metric"><span>{icon}</span><small>{title}</small><strong>{value}</strong></article>}
function Field(props: InputHTMLAttributes<HTMLInputElement> & {label:string}){const {label,...rest}=props;return <label>{label}<input {...rest}/></label>}
function DataTable({rows,columns}:{rows:Row[];columns:[string,string][]}){return <div className="eco-table-wrap"><table className="eco-table"><thead><tr>{columns.map(([key,label])=><th key={key}>{label}</th>)}</tr></thead><tbody>{rows.length===0?<tr><td colSpan={columns.length}>Nenhum registro disponível.</td></tr>:rows.map((row,i)=><tr key={row.id??i}>{columns.map(([key])=><td key={key}>{["created_at","period_start","period_end","reference_date","due_date","effective_from","gdp_period_end"].includes(key)?date(String(row[key]??"")):key==="price"||key.includes("amount")||key==="total_value"||key==="total_planned"||key==="treasury_balance"||key==="gdp"||key==="revenue_total"||key==="expenses_total"||key==="investment_total"?money(row[key]):key==="name" && row.economic_price_items?.name?row.economic_price_items.name:key==="gdp_growth" && row[key]!=null?Number(row[key]).toFixed(2)+"%":String(row[key]??"—")}</td>)}</tr>)}</tbody></table></div>}
function ReviewList({rows,onReview,reversal=false}:{rows:Row[];onReview:(id:string,decision:string)=>void;reversal?:boolean}){if(!rows.length)return null;return <div className="eco-review-list"><h3>{reversal?"Estornos administrativos":"Itens aguardando revisão"}</h3>{rows.map(row=><article key={row.id}><span>{row.name??row.description??row.id}</span>{reversal?<button onClick={()=>onReview(row.id,"reversal")}><XCircle size={15}/> Estornar</button>:<><button onClick={()=>onReview(row.id,"approved")}>Aprovar</button><button onClick={()=>onReview(row.id,"rejected")}>Rejeitar</button></>}</article>)}</div>}
