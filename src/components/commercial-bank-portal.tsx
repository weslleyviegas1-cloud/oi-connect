import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import { ArrowDownUp, Building2, RefreshCw, Wallet, Landmark, ShieldCheck } from "lucide-react";
import { supabase } from "@/lib/supabase";
import "./commercial-bank-portal.css";

type Profile = { id:string; role?:string; country_id?:string|null; country_name?:string|null };
type Bank = {id:string;name:string;identifier:string;country_id:string;country_name:string;type:string};
type Account = {id:string;bank_id:string;bank_name:string;bank_identifier:string;account_number:string;account_type:string;status:string;balance:number;currency_id:string;currency_code:string;currency_symbol:string;country_id:string};
type Tx = {id:string;account_id:string;type:string;amount:number;currency_id:string;balance_after:number;description:string;created_at:string;status:string};
type Currency = {id:string;internal_code:string;name:string;symbol:string};\ntype Country = {id:string;name:string};
const fmt=(n:number,c:string)=>new Intl.NumberFormat("pt-BR",{style:"currency",currency:c==="BRL"?"BRL":"USD",maximumFractionDigits:2}).format(n);
export function CommercialBankPortal({profile,notify}:{profile:Profile;notify:(s:string)=>void}){
 const [data,setData]=useState<{accounts:Account[];banks:Bank[];transactions:Tx[];countries?:Country[]}>({accounts:[],banks:[],transactions:[]});
 const [currencies,setCurrencies]=useState<Currency[]>([]);
 const [busy,setBusy]=useState(false),[loading,setLoading]=useState(true),[tab,setTab]=useState("contas");
 const [bankName,setBankName]=useState(""),[identifier,setIdentifier]=useState(""),[bankType,setBankType]=useState("private"),[owner,setOwner]=useState("");
 const [selectedBank,setSelectedBank]=useState(""),[currency,setCurrency]=useState(""),[accountType,setAccountType]=useState("checking");
 const [from,setFrom]=useState(""),[to,setTo]=useState(""),[amount,setAmount]=useState(""),[loanAmount,setLoanAmount]=useState(""),[loanTerm,setLoanTerm]=useState("12"),[loanRate,setLoanRate]=useState("12"),[purpose,setPurpose]=useState("");
 const admin=profile.role==="super_admin";
 const load=useCallback(async()=>{
  setLoading(true);
  const [dash,curs]=await Promise.all([supabase.rpc("get_my_bank_dashboard"),supabase.from("currencies").select("id,internal_code,name,symbol").eq("status","active").order("name")]);
  if(dash.error) notify(dash.error.message);
  else setData(dash.data??{accounts:[],banks:[],transactions:[]});
  if(curs.error) notify(curs.error.message); else setCurrencies(curs.data??[]);
  setLoading(false);
 },[notify]);
 useEffect(()=>{void load()},[load]);
 const selected=data.accounts.find(a=>a.id===from)??data.accounts[0];
 const accountOptions=useMemo(()=>data.accounts.filter(a=>a.status==="active"),[data.accounts]);
 const submit=async(e:FormEvent,fn:string,args:Record<string,unknown>,message:string)=>{
  e.preventDefault();setBusy(true);
  const {error}=await supabase.rpc(fn,args);
  setBusy(false);
  if(error){notify(error.message);return;}
  notify(message);await load();
 };
 const createBank=(e:FormEvent)=>submit(e,"admin_create_commercial_bank",{p_country_id:profile.country_id,p_name:bankName,p_identifier:identifier.toUpperCase(),p_type:bankType,p_owner:owner||null,p_logo:null,p_director:null},"Banco cadastrado e aguardando aprovação.");
 const createAccount=(e:FormEvent)=>submit(e,"open_bank_account",{p_bank_id:selectedBank,p_currency_id:currency,p_account_type:accountType,p_branch_id:null},"Conta bancária aberta.");
 const transfer=(e:FormEvent)=>submit(e,"bank_transfer",{p_from_account:from,p_to_account:to,p_amount:Number(amount),p_idempotency_key:crypto.randomUUID(),p_description:"Transferência bancária entre contas"},"Transferência concluída e registrada.");
 const loan=(e:FormEvent)=>submit(e,"request_bank_loan",{p_account_id:from,p_amount:Number(loanAmount),p_term_months:Number(loanTerm),p_rate:Number(loanRate),p_purpose:purpose},"Solicitação de empréstimo enviada ao banco.");
 const review=async(id:string,status:string)=>{setBusy(true);const {error}=await supabase.rpc("admin_review_commercial_bank",{p_bank_id:id,p_status:status,p_note:"Revisão administrativa"});setBusy(false);if(error)notify(error.message);else{notify("Situação do banco atualizada.");await load();}};
 const banks=data.banks;
 return <div className="cbank-root">
  <header className="cbank-head"><div><small>WORLD ECONOMY / SISTEMA BANCÁRIO</small><h2>Minha Conta Bancária</h2><p>Contas, transferências e extratos persistidos no banco de dados.</p></div><button onClick={()=>void load()} disabled={loading}><RefreshCw size={16}/> Atualizar</button></header>
  <nav className="cbank-tabs">{[["contas","Minhas contas"],["abrir","Abrir conta"],["transferir","Transferir"],["credito","Empréstimos"],...(admin?[["gestao","Gestão bancária"]]:[])].map(([id,label])=><button key={id} className={tab===id?"active":""} onClick={()=>setTab(id)}>{label}</button>)}</nav>
  {loading?<p className="cbank-muted">Carregando dados bancários…</p>:<>
  {tab==="contas"&&<><div className="cbank-cards">{data.accounts.map(a=><article key={a.id} className="cbank-account"><span><Landmark size={19}/>{a.bank_name}</span><small>{a.account_type==="checking"?"Conta corrente":"Conta poupança"} · {a.account_number}</small><strong>{fmt(Number(a.balance),a.currency_code)}</strong><em>{a.currency_code} · {a.status==="active"?"Ativa":a.status}</em></article>)}</div>{data.accounts.length===0&&<div className="cbank-empty"><Wallet/><b>Você ainda não possui conta bancária.</b><p>Abra uma conta em um banco ativo do seu país.</p><button onClick={()=>setTab("abrir")}>Abrir minha primeira conta</button></div>}
  <section className="cbank-panel"><h3>Extrato e movimentações</h3><div className="cbank-table"><table><thead><tr><th>Data</th><th>Descrição</th><th>Tipo</th><th>Valor</th><th>Saldo após</th></tr></thead><tbody>{data.transactions.map(t=><tr key={t.id}><td>{new Date(t.created_at).toLocaleString("pt-BR")}</td><td>{t.description}</td><td>{t.type}</td><td>{Number(t.amount).toLocaleString("pt-BR",{maximumFractionDigits:6})}</td><td>{Number(t.balance_after).toLocaleString("pt-BR",{maximumFractionDigits:6})}</td></tr>)}</tbody></table>{data.transactions.length===0&&<p className="cbank-muted">Nenhuma movimentação registrada.</p>}</div></section></>}
  {tab==="abrir"&&<section className="cbank-panel"><h3>Abrir conta bancária</h3>{banks.length===0?<p className="cbank-muted">Não há bancos ativos disponíveis no seu país. O Super Admin precisa autorizar uma instituição.</p>:<form onSubmit={createAccount}><label>Banco<select required value={selectedBank} onChange={e=>setSelectedBank(e.target.value)}><option value="">Selecione</option>{banks.map(b=><option key={b.id} value={b.id}>{b.name} · {b.identifier}</option>)}</select></label><label>Moeda<select required value={currency} onChange={e=>setCurrency(e.target.value)}><option value="">Selecione</option>{currencies.map(c=><option key={c.id} value={c.id}>{c.internal_code} — {c.name}</option>)}</select></label><label>Tipo de conta<select value={accountType} onChange={e=>setAccountType(e.target.value)}><option value="checking">Conta corrente</option><option value="savings">Conta poupança</option></select></label><button disabled={busy||!selectedBank||!currency}>Abrir conta</button></form>}</section>}
  {tab==="transferir"&&<section className="cbank-panel"><h3>Transferência entre contas</h3><p className="cbank-muted">A operação é processada no servidor em transação atômica. A transferência internacional está bloqueada até que exista autorização e liquidação internacional específicas.</p><form onSubmit={transfer}><label>Conta de origem<select value={from} onChange={e=>setFrom(e.target.value)} required><option value="">Selecione</option>{accountOptions.map(a=><option key={a.id} value={a.id}>{a.bank_name} · {a.account_number} · {a.currency_code}</option>)}</select></label><label>Conta de destino (ID interno)<input value={to} onChange={e=>setTo(e.target.value)} placeholder="UUID da conta destinatária" required/></label><label>Valor<input type="number" min="0.000001" step="0.000001" value={amount} onChange={e=>setAmount(e.target.value)} required/></label><button disabled={busy||!from||!to}>Confirmar transferência <ArrowDownUp size={16}/></button></form></section>}
  {tab==="credito"&&<section className="cbank-panel"><h3>Solicitar empréstimo</h3><p className="cbank-muted">A solicitação não credita dinheiro. O banco precisa analisar e aprovar, e a liquidez disponível será validada no processamento.</p><form onSubmit={loan}><label>Conta para crédito<select value={from} onChange={e=>setFrom(e.target.value)} required><option value="">Selecione</option>{accountOptions.map(a=><option key={a.id} value={a.id}>{a.bank_name} · {a.account_number}</option>)}</select></label><label>Valor solicitado<input type="number" min="0.000001" step="0.000001" value={loanAmount} onChange={e=>setLoanAmount(e.target.value)} required/></label><div className="cbank-grid"><label>Prazo (meses)<input type="number" min="1" max="360" value={loanTerm} onChange={e=>setLoanTerm(e.target.value)}/></label><label>Juros anual (%)<input type="number" min="0" max="10000" step="0.000001" value={loanRate} onChange={e=>setLoanRate(e.target.value)}/></label></div><label>Finalidade<textarea value={purpose} onChange={e=>setPurpose(e.target.value)} required minLength={5}/></label><button disabled={busy||!from}>Solicitar crédito</button></form></section>}
  {tab==="gestao"&&admin&&<><section className="cbank-panel"><h3><ShieldCheck size={18}/> Cadastrar banco comercial</h3><form onSubmit={createBank}><label>Nome oficial<input value={bankName} onChange={e=>setBankName(e.target.value)} required minLength={3}/></label><label>Identificador bancário<input value={identifier} onChange={e=>setIdentifier(e.target.value)} required minLength={3}/></label><label>País<select value={profile.country_id??""} disabled><option>{profile.country_name??"País do perfil"}</option></select></label><label>Tipo<select value={bankType} onChange={e=>setBankType(e.target.value)}><option value="private">Privado</option><option value="public">Público</option></select></label><label>Responsável<input value={owner} onChange={e=>setOwner(e.target.value)}/></label><button disabled={busy||!bankCountry}>Cadastrar para aprovação</button></form></section><section className="cbank-panel"><h3>Instituições disponíveis no país</h3>{banks.map(b=><article className="cbank-row" key={b.id}><div><b>{b.name}</b><small>{b.identifier} · {b.type}</small></div><span>{b.country_name}</span></article>)}</section></>}
  </>}
 </div>;
}
