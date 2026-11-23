import { createFileRoute, Link } from "@tanstack/react-router";
import { AppShell, PageHeader, StatusRow, Unavailable } from "@/components/app-shell";
import { usePlayer } from "@/hooks/use-player";

export const Route = createFileRoute("/conta")({
  head: () => ({ meta: [
    { title: "Minha conta — OI CONNECT" },
    { name: "description", content: "Sua conta, nickname Bedrock e assinatura no OI CONNECT." },
    { property: "og:title", content: "Minha conta — OI CONNECT" },
    { property: "og:description", content: "Sua conta, nickname Bedrock e assinatura no OI CONNECT." },
    { property: "og:type", content: "website" },
    { name: "twitter:card", content: "summary" },
  ] }),
  component: Account,
});

function Account() {
  const player = usePlayer();
  return (
    <AppShell>
      <PageHeader eyebrow="Jogador" title="Minha conta" description="Dados da sua conta, nickname Bedrock e assinatura." />
      {!player.ready ? (
        <p className="text-muted-foreground">Carregando...</p>
      ) : !player.user ? (
        <div className="border p-6">
          <p>Entre na sua conta para ver seus dados.</p>
          <Link to="/auth" className="mt-4 inline-block bg-primary px-4 py-2 font-medium text-primary-foreground">Entrar</Link>
        </div>
      ) : (
        <div className="grid gap-10 lg:grid-cols-[1.4fr_1fr]">
          <dl className="border-t">
            <StatusRow label="E-mail" value={player.user.email ?? "—"} />
            <StatusRow label="Nome na plataforma" value={player.profile?.username ?? "—"} />
            <StatusRow label="Nickname Bedrock" value={player.profile?.minecraft_username || "Não informado"} note="O cadastro e a confirmação do nickname serão liberados na próxima etapa. Depois de confirmado, ele fica bloqueado." />
            <StatusRow label="Assinatura" value="Sem assinatura" note="Planos e pagamentos ainda não estão disponíveis." />
          </dl>
          <div className="grid content-start gap-4">
            <Unavailable title="Pagamento" text="O link de pagamento individual pelo Mercado Pago aparecerá aqui quando a cobrança for ativada." />
            <Unavailable title="Acesso ao servidor" text="O endereço e a liberação do seu nickname aparecerão aqui quando o servidor estiver conectado." />
          </div>
        </div>
      )}
    </AppShell>
  );
}
