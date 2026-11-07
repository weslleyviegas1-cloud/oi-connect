import { useCallback, useEffect, useState, type FormEvent } from "react";
import { Check, Flag, Plus, RefreshCw, ShieldCheck, X } from "lucide-react";
import { supabase } from "@/lib/supabase";

type Country = { id: string; name: string; flag: string | null; is_active: boolean; president_available: boolean };
type Application = {
  id: string;
  player_id: string;
  country_id: string;
  status: string;
  requested_at: string;
  player?: { username: string; player_number: number | null };
  country?: { name: string; flag: string | null };
};

export function AdminGovernance({ notify }: { notify: (message: string) => void }) {
  const [countries, setCountries] = useState<Country[]>([]);
  const [applications, setApplications] = useState<Application[]>([]);
  const [name, setName] = useState("");
  const [flag, setFlag] = useState("");
  const [presidentAvailable, setPresidentAvailable] = useState(false);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    const [countryResult, appResult] = await Promise.all([
      supabase.from("countries").select("id,name,flag,is_active,president_available").order("name"),
      supabase.from("president_applications").select("id,player_id,country_id,status,requested_at").eq("status", "pending").order("requested_at"),
    ]);
    if (countryResult.error) notify("Não foi possível carregar os países: " + countryResult.error.message);
    else setCountries((countryResult.data ?? []) as Country[]);
    if (appResult.error) notify("Não foi possível carregar as solicitações: " + appResult.error.message);
    else {
      const rows = (appResult.data ?? []) as Application[];
      const playerIds = [...new Set(rows.map(row => row.player_id))];
      const countryIds = [...new Set(rows.map(row => row.country_id))];
      const [players, requestedCountries] = await Promise.all([
        playerIds.length ? supabase.from("profiles").select("id,username,player_number").in("id", playerIds) : Promise.resolve({ data: [], error: null }),
        countryIds.length ? supabase.from("countries").select("id,name,flag").in("id", countryIds) : Promise.resolve({ data: [], error: null }),
      ]);
      setApplications(rows.map(row => ({
        ...row,
        player: (players.data ?? []).find((item: any) => item.id === row.player_id),
        country: (requestedCountries.data ?? []).find((item: any) => item.id === row.country_id),
      })));
    }
    setLoading(false);
  }, [notify]);

  useEffect(() => { void load(); }, [load]);

  const createCountry = async (event: FormEvent) => {
    event.preventDefault();
    setBusy(true);
    const { error } = await supabase.rpc("admin_save_country", {
      p_name: name.trim(), p_flag: flag.trim() || null, p_is_active: true,
      p_president_available: presidentAvailable,
    });
    setBusy(false);
    if (error) { notify("Não foi possível salvar o país: " + error.message); return; }
    setName(""); setFlag(""); setPresidentAvailable(false);
    notify("País cadastrado e salvo no banco.");
    await load();
  };

  const toggleAvailability = async (country: Country) => {
    const { error } = await supabase.rpc("admin_save_country", {
      p_name: country.name, p_flag: country.flag, p_is_active: country.is_active,
      p_president_available: !country.president_available,
    });
    if (error) { notify("Não foi possível alterar a disponibilidade: " + error.message); return; }
    notify("Disponibilidade de presidência atualizada.");
    await load();
  };

  const review = async (application: Application, decision: "approved" | "rejected") => {
    setBusy(true);
    const { error } = await supabase.rpc("review_president_application", {
      p_application_id: application.id, p_decision: decision, p_note: null,
    });
    setBusy(false);
    if (error) { notify("Não foi possível revisar a solicitação: " + error.message); return; }
    notify(decision === "approved" ? "Presidência aprovada. O jogador agora é presidente desse país." : "Solicitação rejeitada.");
    await load();
  };

  return <div className="we-stack">
    <section className="we-panel">
      <header><h2><Flag/> Cadastro e disponibilidade de países</h2></header>
      <form className="we-form" onSubmit={createCountry}>
        <label>Nome do país<input value={name} onChange={event => setName(event.target.value)} placeholder="Ex.: Brasil" minLength={2} required /></label>
        <label>Bandeira (emoji opcional)<input value={flag} onChange={event => setFlag(event.target.value)} placeholder="Ex.: 🇧🇷" maxLength={8} /></label>
        <label className="we-check"><input type="checkbox" checked={presidentAvailable} onChange={event => setPresidentAvailable(event.target.checked)} /> Aceitar solicitações de presidência</label>
        <button className="we-primary" type="submit" disabled={busy}><Plus/> Adicionar país</button>
      </form>
      <div className="we-list">
        {countries.length === 0 ? <div className="we-empty">Nenhum país cadastrado. Adicione os países que poderão aparecer no cadastro.</div> : countries.map(country =>
          <article key={country.id}>
            <span>{country.flag || "🌐"}</span>
            <div><b>{country.name}</b><small>{country.is_active ? "Ativo" : "Inativo"} • {country.president_available ? "Aceitando pedidos de presidência" : "Presidência fechada"}</small></div>
            <button className="we-secondary" type="button" onClick={() => void toggleAvailability(country)}>{country.president_available ? "Fechar vaga" : "Abrir vaga"}</button>
          </article>
        )}
      </div>
    </section>
    <section className="we-panel">
      <header><h2><ShieldCheck/> Solicitações de presidência</h2><button className="we-icon" onClick={() => void load()} aria-label="Atualizar"><RefreshCw/></button></header>
      {loading ? <div className="we-empty">Carregando solicitações...</div> : applications.length === 0 ? <div className="we-empty">Não há solicitações aguardando análise.</div> :
        <div className="we-list">{applications.map(application =>
          <article key={application.id}>
            <ShieldCheck/>
            <div><b>{application.player?.username ?? "Jogador"} — #{application.player?.player_number ?? "—"}</b><small>{application.country?.flag ?? ""} {application.country?.name ?? "País"} • {new Date(application.requested_at).toLocaleString("pt-BR")}</small></div>
            <button className="we-primary" type="button" disabled={busy} onClick={() => void review(application, "approved")}><Check/> Aceitar</button>
            <button className="we-danger" type="button" disabled={busy} onClick={() => void review(application, "rejected")}><X/> Rejeitar</button>
          </article>
        )}</div>}
    </section>
  </div>;
}
