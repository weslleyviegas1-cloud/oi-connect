import { createFileRoute, Link } from "@tanstack/react-router";
import { AppShell } from "@/components/app-shell";

export const Route = createFileRoute("/")({
  head: () => ({ meta: [
    { title: "WORLD ECONOMY — Servidor Minecraft Bedrock" },
    { name: "description", content: "Crie sua conta, informe seu nickname Bedrock e acompanhe sua assinatura semanal do servidor WORLD ECONOMY." },
    { property: "og:title", content: "WORLD ECONOMY — Servidor Minecraft Bedrock" },
    { property: "og:description", content: "Conta, assinatura semanal e acesso ao servidor Bedrock do WORLD ECONOMY." },
    { property: "og:type", content: "website" },
    { name: "twitter:card", content: "summary" },
  ] }),
  component: Home,
});

const steps = [
  ["01", "Crie sua conta", "Cadastro com e-mail e senha."],
  ["02", "Informe seu nickname Bedrock", "O nome exato da sua conta Xbox. Depois de confirmado, só o administrador pode alterar."],
  ["03", "Pague a assinatura semanal", "Pagamento pelo Mercado Pago, com link individual."],
  ["04", "Entre no servidor", "Com a assinatura ativa, seu nickname é liberado no servidor."],
];

function Home() {
  return (
    <AppShell>
      <section className="grid gap-10 lg:grid-cols-[1.3fr_1fr]">
        <div>
          <img src="/brand/world-economy-brand.webp" alt="WORLD ECONOMY — identidade oficial" className="mb-6 w-full max-w-[192px] border object-cover" />
          <p className="font-mono text-xs uppercase tracking-widest text-primary">Minecraft Bedrock</p>
          <h1 className="mt-3 text-4xl font-semibold leading-tight tracking-tight sm:text-5xl">Um servidor. Acesso por assinatura semanal.</h1>
          <p className="mt-4 max-w-xl text-lg text-muted-foreground">O WORLD ECONOMY administra o acesso ao servidor Bedrock: sua conta, seu nickname e o status do seu pagamento em um só lugar.</p>
          <div className="mt-8 flex flex-wrap gap-3">
            <Link to="/auth" className="bg-primary px-5 py-2.5 font-medium text-primary-foreground hover:opacity-90">Criar conta ou entrar</Link>
            <Link to="/conta" className="border px-5 py-2.5 hover:bg-accent">Minha conta</Link>
          </div>
        </div>
        <aside className="border bg-surface p-5">
          <h2 className="font-semibold">Situação da plataforma</h2>
          <dl className="mt-3 text-sm">
            <div className="flex justify-between border-b py-3"><dt className="text-muted-foreground">Contas</dt><dd>Disponível</dd></div>
            <div className="flex justify-between border-b py-3"><dt className="text-muted-foreground">Assinaturas e pagamentos</dt><dd className="text-warning">Em preparação</dd></div>
            <div className="flex justify-between py-3"><dt className="text-muted-foreground">Servidor</dt><dd className="text-warning">Não conectado</dd></div>
          </dl>
          <p className="mt-2 text-xs text-muted-foreground">O endereço de conexão será publicado quando o servidor estiver no ar.</p>
        </aside>
      </section>
      <section className="mt-16">
        <h2 className="text-xl font-semibold">Como funciona</h2>
        <ol className="mt-6 grid border-t sm:grid-cols-2 lg:grid-cols-4">
          {steps.map(([n, t, d]) => (
            <li key={n} className="border-b p-5 sm:border-r">
              <span className="font-mono text-sm text-primary">{n}</span>
              <h3 className="mt-2 font-medium">{t}</h3>
              <p className="mt-1 text-sm text-muted-foreground">{d}</p>
            </li>
          ))}
        </ol>
      </section>
    </AppShell>
  );
}