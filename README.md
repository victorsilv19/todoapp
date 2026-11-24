# PM-04 — ToDo App no Google Cloud

Infraestrutura como código e implantação manual por GitHub Actions, Terraform Cloud e Ansible. A arquitetura usa duas VMs Ubuntu 24.04 em uma VPC: uma VM pública para Nginx, frontend e API; e uma VM privada para MongoDB. O banco não recebe IP externo.

## Análise do escopo e decisões

O [escopo do ToDo App](docs/escopo.md) permite escolher provedor, região e ferramentas, desde que as decisões sejam justificadas. Ele exige pelo menos duas VMs, MongoDB isolado em rede privada, HTTPS, persistência, backup com restauração testada, pipelines, custos documentados e operação pelos alunos.

O frontend React é servido pelo Nginx. A API Node.js/Express escuta somente em `127.0.0.1:5000`; o Nginx publica `/` e encaminha `/todos` à API no mesmo endereço. MongoDB escuta em `27017` na interface privada e usa credenciais separadas. Dados e backups ficam em Persistent Disks diferentes. O banco e a aplicação têm política de reinício e health checks.

A solução cria VMs `e2-medium` (ajustáveis no workflow), discos persistentes `pd-standard` e Cloud NAT para permitir saída da VM privada sem IP externo. Essa configuração é reproduzível e atende ao isolamento, mas **não é totalmente coberta pelo Free Tier**: o crédito do Free Trial pode ser usado e os recursos continuam consumindo crédito enquanto ativos. Após upgrade para conta paga, uso que exceda créditos/cotas pode ser cobrado.

O Cloud NAT tem custo de gateway por VM associada, IP externo e tráfego processado, além do egress da internet. Para 1 VM associada e 1 IP NAT durante 730 horas, os preços oficiais atuais dão aproximadamente **US$ 4,67/mês antes do processamento e do egress**; o processamento custa US$ 0,045/GiB. Verifique a [página oficial de NAT](https://cloud.google.com/nat/pricing) e use a [calculadora de preços](https://cloud.google.com/products/calculator) para completar o custo da região e do período do evento.

> **Free Trial:** a documentação do Google informa US$ 300 de crédito por 90 dias. Durante o trial, o uso coberto não é cobrado; a inscrição exige forma de pagamento válida e pode gerar uma autorização temporária de US$ 0 a US$ 1. Se não houver upgrade, o billing de teste fecha ao fim do crédito/prazo e os recursos param; os dados podem ser excluídos depois do período de recuperação. Se a conta for atualizada para paga, custos fora do crédito/free tier são cobrados. Consulte as [regras oficiais](https://cloud.google.com/free/docs/free-cloud-features).

## Arquitetura

```text
Visitante
  └── HTTPS :443 / HTTP :80
      └── VM app (IP externo + IP privado)
          ├── Nginx: TLS e proxy reverso
          ├── frontend React/Nginx em 127.0.0.1:8080
          └── API Express em 127.0.0.1:5000
                └── VPC privada:27017
                    └── VM MongoDB (sem IP externo)
                        ├── Persistent Disk de dados
                        └── Persistent Disk de backups
```

- **Terraform:** VPC e duas subnets, regras de firewall, Cloud Router/NAT, duas VMs, discos MongoDB e inventário dinâmico Ansible.
- **Segurança:** 80/443 públicos somente na VM app; SSH à app limitado ao IP de saída do runner; SSH e MongoDB na VM DB aceitos da subnet da app. A VM DB não tem IP externo.
- **Persistência:** dois discos de dados independentes (20 GiB cada por padrão), separados dos discos de boot.
- **Ansible:** atualizações opcionais do SO, Docker Engine/Compose, MongoDB, aplicação, Nginx, TLS, backups diários e script de restauração isolada.
- **Deploy reproduzível:** `source_ref` escolhe branch/tag/commit; `docker_tag` identifica as imagens frontend/API. As imagens são construídas na VM app, não publicadas em registry.
- **HTTPS:** o laboratório cria certificado autoassinado porque domínio não foi informado. HTTPS funciona, mas navegadores mostram aviso; certificado público confiável depende de domínio e configuração adicional.

## Terraform Cloud

O state é armazenado remotamente no HCP Terraform. [terraform/backend.tf](terraform/backend.tf) já está configurado para a organização `todoapp-pm4` e seleciona workspaces pela tag chave/valor `application=pm04-todoapp`. Adicione essa tag a cada um dos workspaces `pm04-todoapp-dev`, `pm04-todoapp-homolog` e `pm04-todoapp-prod`, e mantenha **Execution Mode: Local**. Os workflows selecionam os nomes completos; o runner do GitHub executa Terraform com credenciais temporárias via Workload Identity Federation (WIF), e o HCP guarda o state. O Secret `TF_API_TOKEN` deve conter um **Team API token** com permissão de escrita nos workspaces (por exemplo, o token do time Owners); um Organization API token não pode iniciar plans nem gravar state.

## Preparar o Google Cloud

1. Use o projeto GCP criado e copie o **Project ID** (não o nome de exibição).
2. Associe billing e habilite a **Compute Engine API**. Enquanto a conta estiver em Free Trial, monitore o crédito; não faça upgrade se não aceitar cobranças.
3. Crie a service account `pm04-github-actions` e conceda `Compute Admin` no projeto. A política da organização bloqueia chaves de service account; não tente contornar essa política. A pipeline usa WIF, sem chave permanente.
4. Configure região e zona compatíveis. O padrão do Terraform é `us-central1` / `us-central1-a`; altere os GitHub variables se escolher outra região.
5. A chave SSH Ed25519 já criada pode ser reutilizada. A pipeline deriva a chave pública da `SSH_PRIVATE_KEY` e a injeta no metadata das VMs; não é necessário cadastrar a chave no Console GCP.
6. Abra o Cloud Shell no Console GCP, confirme que o projeto ativo é `project-813fbb1c-30ea-40e1-93f` e execute os comandos abaixo para criar a federação restrita ao repositório `victorsilv19/todoapp` e permitir a impersonação da service account:

   ```bash
   PROJECT_ID="project-813fbb1c-30ea-40e1-93f"
   SA_EMAIL="pm04-github-actions@${PROJECT_ID}.iam.gserviceaccount.com"
   PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"

   gcloud services enable iamcredentials.googleapis.com --project="$PROJECT_ID"

   gcloud iam workload-identity-pools create github-actions \
     --project="$PROJECT_ID" \
     --location=global \
     --display-name="GitHub Actions"

   gcloud iam workload-identity-pools providers create-oidc github \
     --project="$PROJECT_ID" \
     --location=global \
     --workload-identity-pool=github-actions \
     --display-name="todoapp-github" \
     --issuer-uri="https://token.actions.githubusercontent.com" \
     --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
     --attribute-condition="assertion.repository == 'victorsilv19/todoapp'"

   gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
     --project="$PROJECT_ID" \
     --role="roles/iam.workloadIdentityUser" \
     --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-actions/attribute.repository/victorsilv19/todoapp"

   echo "Provider: projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-actions/providers/github"
   echo "Service account: ${SA_EMAIL}"
   ```

   Esses comandos configuram identidade, não criam VMs. Se algum comando disser que o pool ou provider já existe, pare e confira a configuração antes de tentar novamente.

## GitHub Secrets e variables

Em **Settings > Secrets and variables > Actions**, cadastre:

| Tipo | Nome | Conteúdo |
| --- | --- | --- |
| Secret | `SSH_PRIVATE_KEY` | Chave privada Ed25519 de acesso/Ansible |
| Secret | `TF_API_TOKEN` | Team API token do HCP com permissão de escrita nos workspaces; não use Organization token |
| Secret | `MONGODB_ROOT_PASSWORD` | Senha forte para a conta administrativa MongoDB |
| Secret | `MONGODB_APP_PASSWORD` | Senha forte exclusiva da aplicação |
| Variable | `GCP_WORKLOAD_IDENTITY_PROVIDER` | Nome completo do provider exibido pelo último comando Cloud Shell |
| Variable | `GCP_SERVICE_ACCOUNT` | E-mail da service account exibido pelo último comando Cloud Shell |
| Variable | `GCP_PROJECT_ID` | Project ID do projeto |
| Variable | `GCP_REGION` | Região escolhida, padrão `us-central1` |
| Variable | `GCP_ZONE` | Zona da região, padrão `us-central1-a` |

O workflow autentica na GCP por OIDC e credenciais temporárias; não é necessário nem esperado configurar `GCP_CREDENTIALS`. Não comite nem imprima credenciais. Senhas são protegidas com `no_log` nas tasks Ansible correspondentes.

Depois da migração, remova secrets antigos que não são mais utilizados, como `OCI_*`, `DIGITALOCEAN_TOKEN` e `SSH_KEY_FINGERPRINT`, e apague variables antigas de OCI.

## Deploy e encerramento

1. Execute **Actions > Deploy ToDo App on GCP > Run workflow**.
2. Escolha `environment`, `instance_name`, `instance_type`, `source_ref`, `docker_image`, `docker_tag`, `update_os` e `extra_packages`.
3. O workflow valida o build frontend e a sintaxe do backend/Ansible; executa `terraform init`, `validate`, `plan` e `apply`; aguarda SSH nas duas VMs; executa o playbook via `ProxyJump`; e mostra a URL HTTPS.
4. Teste criar/listar/concluir/reabrir/excluir tarefa e recarregue a página. Os dados devem permanecer no MongoDB.
5. Para encerrar, execute **Actions > Destroy ToDo App on GCP > Run workflow**, informe o mesmo ambiente e `instance_name` e digite `DESTROY`. O workflow verifica a identidade da implantação antes de planejar a destruição.

**Destroy remove VMs, discos, VPC, regras de firewall, router e NAT.** Copie para fora os dados de que precisar antes. Verifique no Console GCP se recursos e itens faturáveis foram removidos; o state do HCP permanece.

## Validação dos cenários, persistência e recuperação

Guarde evidências sem credenciais em [evidencias/](evidencias):

1. **Criação inicial:** plan/apply, rede, duas VMs, discos, firewall/NAT, inventário, Ansible e aplicação HTTPS funcional.
2. **Atualização:** mantenha ambiente/nome, mude `instance_type` de `e2-medium` para `e2-standard-2`, selecione um `source_ref` diferente e uma nova `docker_tag`. Mostre a atualização da VM via stop/start sem substituição do recurso e os health checks da aplicação. Para rollback, reexecute com o tipo, `source_ref` e `docker_tag` anteriores.
3. **Idempotência:** repita exatamente os parâmetros do cenário 2; apresente Terraform sem mudanças e Ansible sem alterações desnecessárias.

Para validar persistência, crie uma tarefa, recrie apenas o container MongoDB sem remover o disco e confirme que a tarefa continua lá. Para validar backup/restauração sem afetar produção, execute na VM DB:

```bash
sudo systemctl start todo-mongo-backup.service
sudo /usr/local/sbin/test-todo-mongodb-restore
```

O segundo comando restaura o backup mais recente em um MongoDB temporário com filesystem efêmero e remove o container de teste ao terminar. Registre a execução e o resultado em [evidencias/](evidencias).

## Desenvolvimento local com Docker Compose

Copie `.env.example` para `.env`, substitua a senha local de demonstração por uma senha sua e confirme que `MONGODB_URI` usa a mesma credencial. O `.env` é ignorado pelo Git. Depois execute `docker compose up --build -d`; acesse `http://localhost` e a API em `http://localhost:5000/todos`. O MongoDB não publica porta no host. `docker compose down -v` remove também o volume local e os dados.

### Estimativa de custos a fechar para a entrega

O valor exato depende de região/zona, tipo de VM, horas ligadas, tráfego, retenção de dados e duração da feira, informações ainda não fixadas. Use a calculadora oficial para estimar pelo menos: 2 VMs pelo total de horas; 2 boot disks de 20 GiB; 2 Persistent Disks de 20 GiB; Cloud NAT (uma VM associada, IP e processamento); IPv4 público da VM app; tráfego de saída; e armazenamento de backups. Registre data, moeda, região, cenário mensal e período de preparação/evento/encerramento. Crédito de trial deve aparecer separado do custo bruto. Alertas de orçamento não desligam recursos automaticamente.

O guia de execução está em [GUIA_APRESENTACAO.md](GUIA_APRESENTACAO.md). Antes da apresentação ainda é necessário registrar a estimativa final, realizar os três cenários, testar a restauração e decidir se o requisito de HTTPS exige certificado público.
