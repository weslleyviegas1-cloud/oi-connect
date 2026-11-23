import { createFileRoute, Link } from "@tanstack/react-router";
import { AppShell, PageHeader, Unavailable } from "@/components/app-shell";
import { usePlayer } from "@/hooks/use-player";

export const Route = createFileRoute("/admin")({
  head: () => ({ meta: [
    { title: "Administração — OI CONNECT" },
    { name: "description", content: "Área do proprietário do servidor OI CONNECT." },
    { property: "og:title", content: "Administração — OI CONNECT" },
    { property: "og:description", content: "Área do proprietário do servidor OI CONNECT." },
    { property: "og:type", content: "website" },
    { name: "twitter:card", content: "summary" },
    { name: "robots", content: "noindex" },
  ] }),
  component: Admin,
});

const areas: [string, string][] = [
  ["Jogadores", "Busca, nickname, suspensão e banimento com motivo registrado."],
  ["Assinaturas", "Estados: aguardando, ativa, em tolerância, vencida, cancelada."],
  ["Pagamentos", "Pagamentos do Mercado Pago, conciliação, reembolsos e contestações."],
  ["Planos e regras", "Preço semanal, moeda e período de tolerância."],
  ["Servidor", "Status, iniciar, parar, reiniciar, jogadores online e registros. Requer servidor externo conectado."],
  ["Mundo e backups", "Backups automáticos, download, envio validado e restauração. Requer servidor externo conectado."],
  ["Auditoria", "Registro de todas as ações administrativas."],
];

function Admin() {
  const player = usePlayer();
  if (!player.ready) return <AppShell><p className="text-muted-foreground">Carregando...</p></AppShell>;
  if (player.profile?.role !== "super_admin") {
    return (
      <AppShell>
        <PageHeader eyebrow="Restrito" title="Acesso restrito" description="Esta área é exclusiva do proprietário do servidor." />
        {!player.user && <Link to="/auth" className="bg-primary px-4 py-2 font-medium text-primary-foreground">Entrar</Link>}
      </AppShell>
    );
  }
  return (
    <AppShell>
      <PageHeader eyebrow="Proprietário" title="Administração" description="As áreas abaixo serão ativadas nas próximas etapas. Nenhum dado é exibido até estarem conectadas." />
      <div className="grid gap-4 md:grid-cols-2">
        {areas.map(([t, d]) => <Unavailable key={t} title={t} text={d} />)}
      </div>
    </AppShell>
  );
}
