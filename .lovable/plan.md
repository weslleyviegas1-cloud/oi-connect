# Plano de reconstrução — OI CONNECT (servidor Bedrock próprio)

Somente planejamento. Nada será alterado até a aprovação de cada etapa.

## 1. Estado atual detectado

- Stack: TanStack Start (React 19) publicado em Cloudflare Workers; backend é o Supabase externo `minirkotshmgidgymndt` (chave publicável em `src/lib/supabase.ts`). Lovable Cloud não é usado e continuará desligado.
- App atual é o simulador "WORLD ECONOMY": uma única rota `/` (`src/routes/index.tsx`) troca entre 10+ portais grandes (governo, economia, câmbio, banco central, bancos, empresas, documentos, veículos, justiça, admin) e `/auth`.
- `index.tsx` ainda guarda saldo/transações demo em `localStorage` (código morto a remover).
- Banco: `setup.sql`, `etapa2/3` aplicados manualmente; 27 migrações em `supabase/migrations` (etapa 4 a 13) com ~150 tabelas de simulação (países, bancos, empresas, tribunais, veículos etc.).
- `profiles` já tem `role` (`citizen|president|super_admin`), `minecraft_username`, `account_status`, `player_number`. Papel guardado no próprio perfil (risco de escalonamento; será movido para tabela separada).
- `profiles` é legível por `anon` (política "visível a todos") — expõe dados; será restringido.
- CI: workflows GitHub aplicam migrações com `supabase db push` usando segredos do repositório.
- Nenhuma integração de pagamento ou servidor Minecraft existe.

## 2. Arquitetura recomendada

```text
 Navegador (jogador/admin)
        |  HTTPS (sessão Supabase)
        v
 App OI CONNECT (Cloudflare Worker)
   - páginas React
   - server functions (autenticadas, RBAC)
   - /api/public/mercadopago-webhook
   - /api/public/agent/*   (agente do servidor)
        |                     |                         ^
        | service role (só     | API Mercado Pago        | HTTPS de saída
        | no servidor)         v (token secreto)          | (agente faz polling)
        v                 Mercado Pago                    |
 Supabase externo                                         |
   - auth, tabelas, RLS            VPS Linux (externo, do proprietário)
   - storage privado de backups      - Bedrock Dedicated Server (BDS)
   - pg_cron (vencimentos)           - Agente OI (serviço systemd)
                                     - firewall: só UDP 19132/19133 abertos
                                     - backups locais + envio p/ storage
```

Princípios:
- O site nunca executa o Minecraft. O agente na VPS **puxa** uma fila de comandos (polling de saída), assim a VPS não abre porta HTTP de administração.
- Comandos só de uma lista fixa (allowlist add/remove, kick, start/stop/restart, backup, restore, list). Nada de shell ou caminho de arquivo livre.
- Agente autentica com token próprio (hash guardado no banco) + assinatura HMAC por requisição com timestamp e nonce; token revogável no painel.
- Bedrock não possui API HTTP nativa nem RCON. O console do BDS é controlado via stdin/stdout do processo, que o agente gerencia.

### Limitações do Bedrock a deixar claras
- Acesso: `allowlist.json` + `allow-list=true` em `server.properties`; comandos de console `allowlist add/remove <nome>` e `allowlist reload`. Exige `online-mode=true` (conta Xbox).
- O nickname é o gamertag Xbox. Gamertags modernos podem ter sufixo numérico (ex.: `Nome#1234`) e o nome exibido pode diferir; a allowlist aceita nome e grava o XUID na primeira entrada.
- BDS puro não tem `/ban`. Bloqueio = remover da allowlist + `kick`. Ban persistente por XUID exige plugin (ex.: Endstone ou LeviLamina) — decisão pendente, com risco de quebrar a cada atualização do BDS.
- Atualizações do BDS são manuais (download da Mojang) e add-ons podem quebrar.

### Verificação de posse do nickname
O formulário não prova posse. Plano: nickname fica "não verificado" até o primeiro login no servidor; o agente lê no log a linha `Player connected: <nome>, xuid: <xuid>` e vincula o XUID. Verificação forte (código digitado no chat) só com plugin — opcional.

## 3. Módulos e páginas

Jogador:
- `/entrar`, `/cadastro`, `/recuperar-senha`
- `/conta` — dados da conta, nickname (bloqueado após confirmação), status de verificação
- `/assinatura` — plano, status, vencimento, botão/link de pagamento, histórico de pagamentos
- `/servidor` — endereço e porta de conexão, status online (público só o necessário)
- `/privacidade` — termos e LGPD, pedido de exclusão

Admin (somente proprietário):
- `/admin` — visão geral (assinantes ativos, vencidos, receita da semana, status do servidor)
- `/admin/jogadores` — busca, detalhe, alterar nickname (auditado), suspender, banir (explícito, com motivo)
- `/admin/assinaturas` e `/admin/pagamentos` — estados, conciliação, reembolso
- `/admin/planos` — preço, duração, tolerância, regras
- `/admin/servidor` — status, start/stop/restart, online, logs, comandos permitidos
- `/admin/mundo` — backups, download, upload validado, restauração
- `/admin/auditoria` — log de todas as ações
- `/admin/agente` — registrar/revogar agente, último contato

Visual: layout sóbrio, tipografia distinta, tabelas e listas em vez de cartões, sem emojis, sem dados fictícios, responsivo.

## 4. Modelo de dados e estados

Tabelas novas (schema `public`, RLS ativa em todas):
- `user_roles(user_id, role)` com enum `owner|player` + função `has_role()` security definer.
- `players(user_id, nickname, nickname_normalized unique, nickname_status: pending|confirmed|verified, xuid unique, status: active|suspended|banned, created_at)`.
- `nickname_changes(player_id, old, new, admin_id, reason, at)`.
- `plans(id, name, price_cents, currency, period_days=7, grace_hours, active)`.
- `subscriptions(id, player_id, plan_id, status, current_period_start, paid_until, grace_until, cancelled_at)`.
- `payments(id, subscription_id, period_start, mp_preference_id, mp_payment_id unique, amount, currency, status, idempotency_key unique, raw_status_detail, created_at, confirmed_at)`.
- `webhook_events(id, mp_request_id unique, type, data_id, received_at, processed_at, result)` — deduplicação.
- `server_commands(id, type enum, args jsonb validado, requested_by, status: queued|sent|done|failed, result, created_at)`.
- `server_status(last_heartbeat, online, players_online jsonb, version)`.
- `backups(id, storage_path, size, sha256, kind: auto|manual|upload, created_at)`.
- `agents(id, token_hash, last_seen, revoked_at)`.
- `audit_logs(actor_id, action, target, metadata sem dados sensíveis, at)`.
- `app_settings` (endereço do servidor, tolerância padrão, retenção).

Estados da assinatura:
```text
 awaiting_payment -> active -> (vence) past_due/grace -> suspended
        |              |                                  |
        |              +-> cancelled                      +-> pagou -> active
        +-> expired (link sem pagamento)
 payment: pending -> approved | rejected | cancelled | refunded | charged_back
 refunded/charged_back -> assinatura suspended + alerta ao admin
```
Acesso ao servidor (allowlist) = `subscription.status in (active, grace)` e `player.status = active`. Ban é só ação manual.

## 5. Pagamentos Mercado Pago

- Todas as chamadas no servidor. Opção A: conector Mercado Pago do Lovable (credencial guardada fora do código). Opção B: Access Token próprio em Secrets. Public Key não é necessária com Checkout Pro / Pix.
- Modelo recomendado: **pagamento por período** (Checkout Pro ou Pix) — cada pagamento compra 7 dias; cobre Pix. Alternativa: assinatura recorrente de cartão (`preapproval`, só cartão).
- Idempotência: `X-Idempotency-Key = sub-<id>-<período>-<tentativa>`; índice único em `(subscription_id, period_start)` para pagamentos aprovados impede cobrança dupla do mesmo período.
- Webhook `/api/public/mercadopago-webhook`: valida o cabeçalho `x-signature` (`ts`, `v1`) com HMAC-SHA256 sobre `id:<data.id>;request-id:<x-request-id>;ts:<ts>;` usando a **assinatura secreta gerada ao configurar Webhooks na aplicação em "Suas integrações"** (ela só existe depois que o proprietário configura o webhook lá; não é automática). Rejeita `ts` antigo. Mesmo assinado, o webhook é só gatilho: o status real vem de `GET v1/payments/{id}`.
- Confirmação: valor, moeda e `external_reference` conferidos; update protegido (`where status='pending'`).
- Conciliação: job (pg_cron chamando rota protegida) a cada 15 min busca `v1/payments/search` por `date_last_updated` e corrige divergências; página de retorno também consulta.
- Retries: webhook responde 500 só em falha de leitura/escrita; erros 429/5xx com backoff.

## 6. Inadimplência

- Vence `paid_until` -> `grace` por N horas (configurável, sugestão 48 h), aviso no painel e e-mail opcional.
- Fim da tolerância -> `suspended`: comando `allowlist remove` + `kick` enfileirado e auditado.
- Pagamento aprovado -> `allowlist add` automático.
- Ban permanente: botão admin com motivo obrigatório, auditado, reversível por admin.

## 7. Arquivos e mundo

- Backups: agente para o mundo com `save hold` / `save query` / `save resume` (backup a quente suportado pelo BDS), compacta, calcula SHA-256 e envia para bucket privado via URL assinada de curta duração.
- Retenção sugerida: 7 diários + 4 semanais (configurável); limite de tamanho por arquivo.
- Download: URL assinada curta, só owner.
- Upload/restauração: só `.mcworld`/`.zip`, limite de tamanho, agente valida estrutura (`level.dat`, `db/`), rejeita links simbólicos, caminhos com `..`, absolutos e executáveis; faz backup antes de restaurar e para o servidor durante a troca.
- Sem navegador de arquivos genérico.

## 8. Infraestrutura (estimativas, dependem de jogadores e add-ons)

- VPS Linux (Ubuntu LTS), x86_64 (BDS oficial não roda em ARM).
- Até 10 jogadores: 2 vCPU, 2–4 GB RAM. 10–30: 4 vCPU, 4–8 GB. Add-ons e distância de visão aumentam muito.
- Disco SSD 20–80 GB (mundo + backups locais).
- Portas: UDP 19132 (IPv4) e 19133 (IPv6). SSH só por chave, porta restrita; nenhuma porta de administração web aberta.
- Monitoramento: heartbeat do agente a cada 30 s; painel marca offline após 2 min.
- Custo típico: VPS de ~R$ 30 a R$ 150/mês + taxas do Mercado Pago por transação.

## 9. Segurança e LGPD

- RLS em todas as tabelas; jogador lê só as próprias linhas; owner via `has_role`. Sem leitura `anon` de dados pessoais.
- Escritas sensíveis (pagamento, status, comandos) só por server functions/rotas no servidor; chave service role guardada em Secrets, usada só após verificar o chamador.
- IDOR: nunca aceitar `user_id` do navegador; usar o da sessão.
- Validação com Zod; nickname: 3–16 caracteres visíveis, letras, números, espaço e sufixo `#0000` opcional, normalizado sem caixa.
- Limites de tentativa: no login (Supabase Auth) e contadores simples no banco para gerar link de pagamento; avisar que não há rate-limit nativo no Worker.
- Logs sem e-mail completo, tokens ou dados de cartão.
- LGPD: coletar só e-mail, nickname, XUID, histórico de pagamentos; política de privacidade; exclusão de conta anonimiza e mantém pagamentos pelo prazo fiscal.

## 10. Sequência de implementação

```text
E0 Backup/export do banco e storage (proprietário)   -> obrigatório antes de E2
E1 Reset visual/funcional: remover portais antigos, novo layout, rotas novas (sem mexer no banco)
E2 Migração aditiva: tabelas novas, roles, RLS (antigas intactas)
E3 Cadastro, perfil e nickname bloqueado
E4 Admin: planos, jogadores, auditoria
E5 Mercado Pago: link, webhook, conciliação          (precisa credenciais + publicar)
E6 Inadimplência e jobs agendados
E7 Agente + API do agente + fila de comandos          (precisa VPS)
E8 Status, logs, start/stop/restart, online           (precisa VPS)
E9 Backups, download, upload, restauração             (precisa VPS)
E10 Testes de aceitação e publicação
E11 (Separado, só com autorização) remoção das tabelas antigas
```
E1–E4 podem começar já. E5 depende de E3–E4. E7–E9 dependem da VPS.

Código antigo: os 10 portais, seus CSS, `admin-governance`, `localStorage` demo e workflows de CI das etapas antigas serão removidos em E1. Migrações antigas permanecem no histórico (não se editam migrações aplicadas).

## 11. O que não pode ser automatizado sem VPS e acesso admin

- Instalar BDS, agente, firewall e systemd.
- Qualquer allowlist/kick/ban real, start/stop/restart, jogadores online, logs, backups e restauração.
- Vincular XUID ao nickname.
- Testar a conexão real de um jogador.
Até lá, o painel mostra "servidor não conectado" e a fila de comandos fica parada (sem simulação falsa).

## 12. Decisões pendentes do proprietário

1. Pix por período (recomendado) ou assinatura de cartão recorrente?
2. Usar o conector Mercado Pago do Lovable ou Access Token próprio?
3. Preço semanal, moeda e tolerância (horas).
4. Ban persistente exige plugin (Endstone/LeviLamina): aceitar ou ficar só com allowlist + kick?
5. Verificação forte de nickname por código no chat (exige plugin)?
6. Provedor e tamanho da VPS; quantidade esperada de jogadores; add-ons.
7. Permitir troca de nickname pelo admin? Com que regra?
8. Retenção de backups e de dados pessoais.
9. Remover agora o conteúdo antigo da interface (E1)? As tabelas antigas só em E11.
10. Envio de e-mails de aviso (vencimento/pagamento)?

## 13. Custos, limitações e riscos

- Taxas do Mercado Pago por pagamento; chargebacks possíveis.
- Rotas novas e webhook só funcionam no site publicado após publicar.
- Atualizações do Bedrock podem quebrar plugins e exigir manutenção.
- Supabase plano gratuito: limite de storage (backups grandes podem exigir plano pago ou storage na própria VPS/objeto externo).
- Sem rate-limit nativo no backend do app.
- Risco de nome trocado no Xbox: XUID mitiga após primeira conexão.

## 14. Testes de aceitação

- Jogador não consegue ler/alterar dados de outro (teste RLS com 2 contas).
- Jogador não consegue alterar nickname confirmado nem o próprio papel.
- Nickname duplicado (variação de maiúsculas) é rejeitado.
- Webhook com assinatura inválida ou `ts` antigo -> 401, nada muda.
- Mesmo pagamento notificado 3 vezes -> um único período liberado.
- Valor ou moeda divergente -> não ativa.
- Vencimento -> grace -> suspended nos tempos configurados; pagamento reativa.
- Reembolso/chargeback -> suspensão + alerta.
- Agente com token revogado ou HMAC inválido -> rejeitado; comando fora da lista -> rejeitado.
- Upload com `..`, symlink ou tamanho excedido -> rejeitado.
- Restauração faz backup prévio e servidor volta online.
- Regras de preço/tolerância com testes automatizados (Vitest).

## 15. Migração e rollback

- E0: proprietário exporta o banco (`supabase db dump` dados + schema) e baixa os buckets; guardar fora do projeto.
- E1 é só código: rollback = restaurar commit anterior no histórico do Lovable.
- E2 é aditivo (tabelas novas, não toca nas antigas); rollback = migração inversa que remove só as tabelas novas.
- Migração de usuários: reaproveitar `auth.users`; copiar `minecraft_username` existente para `players` como `pending` (sem confirmar); papel `super_admin` atual vira `owner` após confirmação do proprietário.
- `profiles` antiga é mantida até E11; política `anon` é fechada em E2 (rollback: reabrir).
- E11 (destrutivo) só após novo backup, período de observação e autorização escrita.
