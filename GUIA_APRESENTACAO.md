# Guia de preparação e apresentação — PM-04 (GCP)

## Custos e conta de teste

Estimativa indicativa em USD para `us-central1`, 730 h/mês: 2 VMs `e2-medium` (~US$ 48,91), boot disks `pd-balanced` (40 GiB, ~US$ 4,00), discos `pd-standard` para dados/backup (40 GiB, ~US$ 1,60), Cloud NAT para 1 VM + 1 IP (~US$ 4,67) e IPv4 público da app (~US$ 3,65): **~US$ 62,83/mês**, sem egress, processamento NAT, impostos ou descontos. Uma janela de 72 h ligada é **~US$ 6,20** antes do tráfego; confirme em [preços Compute](https://cloud.google.com/compute/vm-instance-pricing), [discos](https://cloud.google.com/compute/disks-image-pricing), [NAT](https://cloud.google.com/nat/pricing), [rede/IP](https://cloud.google.com/vpc/network-pricing) e na [calculadora GCP](https://cloud.google.com/products/calculator). O valor varia com região, câmbio e uso real; alertas de orçamento não desligam recursos.

O Google Cloud Free Trial oferece crédito promocional limitado e exige meio de pagamento; crédito não é desconto permanente. Consulte as [condições oficiais](https://cloud.google.com/free/docs/free-cloud-features) e não faça upgrade para conta paga sem aceitar cobranças.

## 1 — Preparar Google Cloud

- [ ] Copiar o **Project ID** do projeto GCP (não o nome visível).
- [ ] Associar billing e habilitar a **Compute Engine API**.
- [ ] Criar service account de automação e conceder `Compute Admin` e `IAP-secured Tunnel User` (`roles/iap.tunnelResourceAccessor`) no projeto.
- [ ] Configurar Workload Identity Federation (WIF) para `victorsilv19/todoapp`; não criar chave nem tentar contornar a política que bloqueia chaves.
- [ ] Confirmar região/zona e capacidade/cotas; o padrão é `us-central1` / `us-central1-a`.
- [ ] Monitorar crédito/saldo e nunca fazer upgrade para billing pago sem aceitar cobranças.

O usuário da service account pode criar e destruir recursos no projeto. Restrinja permissões quando possível e nunca publique o JSON.

## 2 — Preparar HCP Terraform

- [ ] Confirmar que [terraform/backend.tf](terraform/backend.tf) aponta para a organização HCP `todoapp-pm4`.
- [ ] Criar workspaces `pm04-todoapp-dev`, `pm04-todoapp-homolog` e `pm04-todoapp-prod`.
- [ ] Adicionar a tag `application=pm04-todoapp` e configurar **Execution Mode: Local** em cada workspace; Terraform roda no GitHub runner e o HCP mantém o state remoto.
- [ ] Cadastrar `TF_API_TOKEN` como GitHub Secret usando um Team API token com permissão de escrita nos workspaces (por exemplo, o token do time Owners). Organization API tokens não podem iniciar plans nem gravar state.

## 3 — Configurar GitHub Actions

Em **Settings > Secrets and variables > Actions**, adicione:

**Secrets**

- `SSH_PRIVATE_KEY`: chave privada Ed25519 para SSH e Ansible.
- `TF_API_TOKEN`: Team API token do HCP com permissão de escrita nos workspaces; não use Organization token.
- `MONGODB_ROOT_PASSWORD`: senha forte.
- `MONGODB_APP_PASSWORD`: senha forte separada para a aplicação.

**Repository variables**

- `GCP_PROJECT_ID`: Project ID.
- `GCP_REGION`: região, por exemplo `us-central1`.
- `GCP_ZONE`: zona dessa região, por exemplo `us-central1-a`.
- `GCP_WORKLOAD_IDENTITY_PROVIDER`: nome completo do provider WIF.
- `GCP_SERVICE_ACCOUNT`: e-mail de `pm04-github-actions`.

A autenticação GCP usa GitHub OIDC e credenciais temporárias, sem chave JSON. A workflow deriva a chave SSH pública e a injeta no metadata das instâncias. O acesso SSH às duas VMs usa IAP e exige `roles/iap.tunnelResourceAccessor`; o firewall aceita a faixa fixa do IAP (`35.235.240.0/20`). MongoDB não recebe IP público e a porta 27017 aceita somente a tag `todo-app`.

## 4 — Cenário 1: criação inicial

1. Confira organização/workspace HCP, secrets, variables, APIs, cotas e orçamento.
2. Abra **Actions > Deploy ToDo App on GCP > Run workflow**.
3. Use `dev`, `vm-todo-pm04`, `e2-medium`, `todo-app`, tag `1.0.0`, `update_os=false` e `curl,git,unzip`. `source_ref` vazio usa a referência escolhida ao iniciar a workflow.
4. Acompanhe validações, Terraform plan/apply, espera SSH nas duas VMs e execução Ansible.
5. Abra a URL HTTPS final (`https://<IP>.nip.io`). O hostname grátis resolve para o IP da VM e Certbot obtém um certificado Let's Encrypt confiável via HTTP-01; o timer renova-o automaticamente. `nip.io` é DNS de terceiro e o hostname muda se o IP mudar.
6. Crie, conclua/reabra, exclua e recarregue uma tarefa.
7. Guarde evidências sem secrets em `evidencias/cenario-1-criacao-inicial/`.

## 5 — Cenário 2: atualização e rollback

1. Execute de novo no mesmo workspace, ambiente e `instance_name`.
2. Altere `instance_type` de `e2-medium` para `e2-standard-2`, selecione outro `source_ref` (branch/tag/commit com uma mudança) e uma nova `docker_tag`, por exemplo `1.0.1`.
3. Mostre no plano que a VM será parada e atualizada sem substituição do recurso, depois imagens versionadas, serviços saudáveis e aplicação atualizada.
4. Para rollback, reexecute usando o `instance_type`, `source_ref` e `docker_tag` anteriores; registre a versão implantada.
5. Guarde evidências em `evidencias/cenario-2-atualizacao/`.

`docker_tag` identifica as imagens construídas, e `source_ref` identifica o código usado para construí-las; registre os dois juntos.

## 6 — Cenário 3: idempotência e persistência

1. Repita exatamente os inputs do cenário 2, incluindo `instance_type`, `source_ref`, `docker_tag`, ambiente e nome.
2. Mostre Terraform sem mudanças e Ansible sem alterações desnecessárias; mantenha `update_os=false`.
3. Execute **Actions > Operate ToDo App on GCP** com `recreate_database`; a ação remove e recria só o container, sem apagar os Persistent Disks. Confirme que a tarefa criada permanece.
4. Guarde evidências em `evidencias/cenario-3-idempotencia/`.

## 7 — Backup e restauração isolada

Execute **Actions > Operate ToDo App on GCP** com `backup` e depois `restore_test`. O primeiro aciona o serviço de backup e lista os arquivos; o segundo restaura o arquivo mais recente em container temporário, sem alterar a base principal. Guarde evidências. Copie os backups para fora antes de destruir a infraestrutura se precisar preservá-los.

## O que demonstrar ao professor

1. Arquitetura com VM app pública e VM DB privada, VPC/subnets e HCP state remoto.
2. Regras de firewall: HTTP/HTTPS públicos; SSH às VMs via IAP; MongoDB permitido somente a VMs com a tag `todo-app`.
3. CRUD completo pelo HTTPS, com frontend/API/Mongo integrados.
4. Persistência após reiniciar/recriar container MongoDB com o disco mantido.
5. Três cenários: criação, atualização/rollback e idempotência.
6. Backup automatizado e restauração testada em ambiente isolado.
7. Versão do código (`source_ref`) e tags de imagem (`docker_tag`).
8. Estimativa mensal e do período com Compute, discos, NAT, IPv4 e tráfego; mostre crédito de trial separadamente.
9. Certificado Let's Encrypt válido e limitação do hostname grátis (`nip.io` depende de DNS de terceiro e acompanha o IP).
10. Operações `health`, `logs`, `restart_app`, `restart_database`, `recreate_database`, `backup`, `restore_test` e destruição pelo workflow.

## Encerrar os recursos

1. Exporte o que precisar; Destroy apaga discos e dados.
2. Abra **Actions > Destroy ToDo App on GCP > Run workflow**.
3. Selecione o mesmo ambiente, informe exatamente o `instance_name` e digite `DESTROY`.
4. Confira o workflow e aguarde finalizar.
5. No Console GCP, confira VMs, discos, VPC, firewalls, router e Cloud NAT. Verifique a página de faturamento e recursos restantes.

Desligar apenas as VMs não remove discos, IPs, VPC ou NAT e pode não encerrar custos. O workflow Destroy remove os recursos Terraform-managed; o state HCP e as evidências permanecem.

## Evidências e limite de conclusão

Use [evidencias/GUIA_EVIDENCIAS.md](evidencias/GUIA_EVIDENCIAS.md) e o [modelo de registro](evidencias/modelo-registro.md). As pastas são placeholders, não comprovam que os testes foram executados. ACE-04 exige abrir a URL em outro dispositivo e ACE-10 exige que os alunos conduzam o ensaio; registre somente observações reais.
