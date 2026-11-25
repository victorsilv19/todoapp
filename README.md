# PM-04 — ToDo App no Google Cloud

Infraestrutura como código e implantação manual por GitHub Actions, Terraform Cloud e Ansible. A arquitetura usa duas VMs Ubuntu 24.04 em uma VPC: uma VM pública para Nginx, frontend e API; e uma VM privada para MongoDB. O banco não recebe IP externo.

## Análise do escopo e decisões

O [escopo do ToDo App](docs/escopo.md) permite escolher provedor, região e ferramentas, desde que as decisões sejam justificadas. Ele exige pelo menos duas VMs, MongoDB isolado em rede privada, HTTPS, persistência, backup com restauração testada, pipelines, custos documentados e operação pelos alunos.

A GCP foi escolhida porque o projeto já usa uma conta e um fluxo de GitHub Actions com Workload Identity Federation, permitindo autenticação sem chaves permanentes, rede privada e operação reproduzível com Terraform. A escolha não implica custo zero: as VMs, discos, NAT, IPv4 e tráfego devem ser orçados e destruídos quando não forem necessários.

O frontend React é servido pelo Nginx. A API Node.js/Express escuta somente em `127.0.0.1:5000`; o Nginx publica `/` e encaminha `/todos` à API no mesmo endereço. MongoDB escuta em `27017` na interface privada e usa credenciais separadas. Dados e backups ficam em Persistent Disks diferentes. O banco e a aplicação têm política de reinício e health checks.

A solução cria VMs `e2-medium` (ajustáveis no workflow), discos persistentes `pd-standard` e Cloud NAT para permitir saída da VM privada sem IP externo. Essa configuração é reproduzível e atende ao isolamento, mas **não é totalmente coberta pelo Free Tier**: o crédito do Free Trial pode ser usado e os recursos continuam consumindo crédito enquanto ativos. Após upgrade para conta paga, uso que exceda créditos/cotas pode ser cobrado.

O Cloud NAT cobra por gateway, IP externo usado, processamento e egress. Para 1 VM associada e 1 IP NAT por 730 horas, o gateway e o IP somam cerca de **US$ 4,67/mês**, antes de US$ 0,045/GiB de processamento e do egress. Verifique a [página oficial de NAT](https://cloud.google.com/nat/pricing).

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
- **Segurança:** 80/443 públicos somente na VM app; SSH em ambas as VMs somente por IAP (`35.235.240.0/20`) e autorizado por IAM; MongoDB na VM DB aceita conexões somente de VMs com a tag `todo-app`. A VM DB não tem IP externo.
- **Persistência:** dois discos de dados independentes (20 GiB cada por padrão), separados dos discos de boot.
- **Ansible:** atualizações opcionais do SO, Docker Engine/Compose, MongoDB, aplicação, Nginx, TLS, backups diários e script de restauração isolada.
- **Deploy reproduzível:** `source_ref` escolhe branch/tag/commit; `docker_tag` identifica as imagens frontend/API. As imagens são construídas na VM app, não publicadas em registry.
- **HTTPS gratuito:** o hostname `<IP>.nip.io` resolve para o IP público da app sem compra de domínio. Certbot obtém certificado público Let's Encrypt via HTTP-01 e o timer do sistema renova-o automaticamente. O hostname acompanha o IP efêmero e pode mudar após recriação da VM; `nip.io` é DNS de terceiro, sem SLA sob controle do projeto.
- **Limite do hostname:** `nip.io` não é domínio próprio. A URL é gratuita, mas depende de DNS de terceiro e pode mudar junto com o IP; para a feira, confirme o hostname gerado após o último deploy e teste-o em outro dispositivo.

## Terraform Cloud

O state é armazenado remotamente no HCP Terraform. [terraform/backend.tf](terraform/backend.tf) já está configurado para a organização `todoapp-pm4` e seleciona workspaces pela tag chave/valor `application=pm04-todoapp`. Adicione essa tag a cada um dos workspaces `pm04-todoapp-dev`, `pm04-todoapp-homolog` e `pm04-todoapp-prod`, e mantenha **Execution Mode: Local**. Os workflows selecionam os nomes completos; o runner do GitHub executa Terraform com credenciais temporárias via Workload Identity Federation (WIF), e o HCP guarda o state. O Secret `TF_API_TOKEN` deve conter um **Team API token** com permissão de escrita nos workspaces (por exemplo, o token do time Owners); um Organization API token não pode iniciar plans nem gravar state.

## Preparar o Google Cloud

1. Use o projeto GCP criado e copie o **Project ID** (não o nome de exibição).
2. Associe billing e habilite a **Compute Engine API**. Enquanto a conta estiver em Free Trial, monitore o crédito; não faça upgrade se não aceitar cobranças.
3. Crie a service account `pm04-github-actions`, conceda `Compute Admin` e `IAP-secured Tunnel User` (`roles/iap.tunnelResourceAccessor`) no projeto. A política da organização bloqueia chaves de service account; não tente contornar essa política. A pipeline usa WIF, sem chave permanente.
4. Configure região e zona compatíveis. O padrão do Terraform é `us-central1` / `us-central1-a`; altere os GitHub variables se escolher outra região.
5. A chave SSH Ed25519 já criada pode ser reutilizada. A pipeline deriva a chave pública da `SSH_PRIVATE_KEY` e a injeta no metadata das VMs; não é necessário cadastrar a chave no Console GCP.
6. Abra o Cloud Shell no Console GCP, confirme que o projeto ativo é `project-813fbb1c-30ea-40e1-93f` e execute os comandos abaixo para criar a federação restrita ao repositório `victorsilv19/todoapp` e permitir a impersonação da service account:

   ```bash
   PROJECT_ID="project-813fbb1c-30ea-40e1-93f"
   SA_EMAIL="pm04-github-actions@${PROJECT_ID}.iam.gserviceaccount.com"
   PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"

   gcloud services enable iamcredentials.googleapis.com iap.googleapis.com --project="$PROJECT_ID"

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

   gcloud projects add-iam-policy-binding "$PROJECT_ID" \
     --member="serviceAccount:${SA_EMAIL}" \
     --role="roles/iap.tunnelResourceAccessor"

   echo "Provider: projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-actions/providers/github"
   echo "Service account: ${SA_EMAIL}"
   ```

   Esses comandos configuram identidade e acesso IAP, não criam VMs. `Compute Admin` também deve estar concedido à service account. Se algum comando disser que o pool ou provider já existe, pare e confira a configuração antes de tentar novamente.

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
3. O workflow valida build e sintaxe; executa `terraform init`, `validate`, `plan` e `apply`; aguarda SSH nas duas VMs por IAP; executa o playbook via `gcloud compute start-iap-tunnel`; obtém/renova o certificado Let's Encrypt; valida HTTPS com verificação da cadeia; e mostra a URL pública.
4. Teste criar/listar/concluir/reabrir/excluir tarefa e recarregue a página. Os dados devem permanecer no MongoDB.
5. Para encerrar, execute **Actions > Destroy ToDo App on GCP > Run workflow**, informe o mesmo ambiente e `instance_name` e digite `DESTROY`. O workflow verifica a identidade da implantação antes de planejar a destruição.

**Destroy remove VMs, discos, VPC, regras de firewall, router e NAT.** Copie para fora os dados de que precisar antes. Verifique no Console GCP se recursos e itens faturáveis foram removidos; o state do HCP permanece.

### Operação e diagnóstico

Execute **Actions > Operate ToDo App on GCP > Run workflow**, selecionando o mesmo ambiente e `instance_name` da implantação:

| Ação | Resultado |
| --- | --- |
| `health` | Confere Nginx, estado saudável dos containers frontend/API/MongoDB, API HTTPS com certificado confiável e ping do MongoDB. |
| `logs` | Exibe até 60 linhas recentes de frontend, API e MongoDB nos logs do workflow. |
| `restart_app` | Reinicia frontend/API e confirma a saúde HTTPS. |
| `restart_database` | Reinicia o container MongoDB, sem remover os discos, e aguarda o ping. |
| `recreate_database` | Remove somente o container e recria-o via role Ansible com os discos persistentes montados; use para testar persistência. |
| `backup` | Executa backup sob demanda e lista arquivos encontrados no disco de backup. |
| `restore_test` | Restaura o backup mais recente em um container temporário isolado. |

As ações de reinício, recriação e restauração podem causar breve indisponibilidade. `recreate_database` exige `MONGODB_ROOT_PASSWORD` e `MONGODB_APP_PASSWORD` já cadastrados como Secrets. Logs podem conter dados operacionais; revise-os antes de compartilhá-los.

## Validação dos cenários, persistência e recuperação

Guarde evidências sem credenciais em [evidencias/](evidencias):

1. **Criação inicial:** plan/apply, rede, duas VMs, discos, firewall/NAT, inventário, Ansible e aplicação HTTPS funcional.
2. **Atualização:** mantenha ambiente/nome, mude `instance_type` de `e2-medium` para `e2-standard-2`, selecione um `source_ref` diferente e uma nova `docker_tag`. Mostre a atualização da VM via stop/start sem substituição do recurso e os health checks da aplicação. Para rollback, reexecute com o tipo, `source_ref` e `docker_tag` anteriores.
3. **Idempotência:** repita exatamente os parâmetros do cenário 2; apresente Terraform sem mudanças e Ansible sem alterações desnecessárias.

Para validar persistência, crie uma tarefa, execute `recreate_database` e confirme que ela continua após o container ser recriado com os discos intactos. Em seguida use `backup` e `restore_test`; a restauração é feita em um MongoDB temporário e não sobrescreve a base de demonstração. Registre as execuções e os resultados em [evidencias/](evidencias).

## Desenvolvimento local com Docker Compose

Copie `.env.example` para `.env`, substitua a senha local de demonstração por uma senha sua e confirme que `MONGODB_URI` usa a mesma credencial. O `.env` é ignorado pelo Git. Depois execute `docker compose up --build -d`; acesse `http://localhost` e a API em `http://localhost:5000/todos`. O MongoDB não publica porta no host. `docker compose down -v` remove também o volume local e os dados.

### Estimativa de custos de referência

Estimativa indicativa em **USD, us-central1, 730 h/mês**, para dois `e2-medium`, dois boot disks `pd-balanced` de 20 GiB, dois discos `pd-standard` de 20 GiB (dados e backup), Cloud NAT atendendo a uma VM e um IPv4 público da app. Valores por hora/GiB são aproximados; tarifas, moeda e cobrança real variam. **Não inclui** egress público, processamento de NAT, snapshots, impostos ou créditos.

| Componente | Base de cálculo | Mensal aproximado |
| --- | --- | ---: |
| 2 VMs `e2-medium` | US$ 0,0335/h por VM × 2 × 730 h | US$ 48,91 |
| Boot disks `pd-balanced` | 40 GiB × US$ 0,10/GiB-mês | US$ 4,00 |
| Discos de dados/backup `pd-standard` | 40 GiB × US$ 0,04/GiB-mês | US$ 1,60 |
| Cloud NAT | 1 VM × US$ 0,0014/h + 1 IP × US$ 0,005/h | US$ 4,67 |
| IPv4 público da app | US$ 0,005/h × 730 h | US$ 3,65 |
| **Total de referência** | Sem tráfego/egress e sem descontos | **US$ 62,83/mês** |

Uma janela de **72 horas** ligada (2 dias de preparação/ensaio + 1 dia de feira, hipótese de planejamento) custa cerca de **US$ 6,20**, incluindo discos alocados nesse período, NAT e IPv4, antes de tráfego/egress. Se ambos os VMs forem `e2-standard-2` durante 72 horas, o subtotal estimado sobe para cerca de **US$ 11,02**. Máquinas paradas continuam gerando custo de discos e outros recursos persistentes; o workflow Destroy remove esses itens. Esta estimativa deve ser recalculada na [calculadora oficial](https://cloud.google.com/products/calculator) após confirmar data, duração, tráfego e preços da conta.

Fontes: [preços Compute Engine](https://cloud.google.com/compute/vm-instance-pricing), [preços de discos](https://cloud.google.com/compute/disks-image-pricing), [preços do Cloud NAT](https://cloud.google.com/nat/pricing), [preços de rede e IP](https://cloud.google.com/vpc/network-pricing). HCP Terraform, GitHub Actions, `nip.io` e Let's Encrypt não têm custo adicional para o uso descrito, sujeito a limites e políticas de seus serviços. Créditos promocionais/trial reduzem a fatura, mas não alteram o custo bruto acima; alertas de orçamento não desligam recursos.

O guia de execução está em [GUIA_APRESENTACAO.md](GUIA_APRESENTACAO.md). As execuções de cenários e testes reais continuam necessárias antes de declarar ACE-01 a ACE-10 aceitos; capturas de evidência não devem ser simuladas.
