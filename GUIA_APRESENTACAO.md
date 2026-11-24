# Guia de preparação e apresentação — PM-04 (GCP)

## Custos e conta de teste

O Google Cloud Free Trial oferece US$ 300 de crédito por 90 dias e não cobra o uso coberto durante o trial. A inscrição exige uma forma de pagamento válida e pode gerar uma autorização temporária de US$ 0 a US$ 1. Se o trial terminar sem upgrade, o billing de teste fecha e os recursos param; dados podem ser removidos após o período de recuperação. Ao atualizar para conta paga, custos não cobertos pelo crédito/free tier podem ser cobrados. Consulte as [condições oficiais](https://cloud.google.com/free/docs/free-cloud-features).

As VMs `e2-medium`, Persistent Disks e Cloud NAT deste projeto não devem ser presumidas como gratuitas. Cloud NAT cobra por VM associada, IP externo, processamento e egress; a página oficial lista preços e exemplos na [calculadora de NAT](https://cloud.google.com/nat/pricing). Antes do deploy, estime o custo para a região, horas de uso, retenção dos backups e tráfego esperados na [calculadora GCP](https://cloud.google.com/products/calculator). O orçamento e alertas não interrompem recursos automaticamente.

## 1 — Preparar Google Cloud

- [ ] Copiar o **Project ID** do projeto GCP (não o nome visível).
- [ ] Associar billing e habilitar a **Compute Engine API**.
- [ ] Criar service account de automação e conceder `Compute Admin` no projeto.
- [ ] Configurar Workload Identity Federation (WIF) para `victorsilv19/todoapp`; não criar chave nem tentar contornar a política que bloqueia chaves.
- [ ] Confirmar região/zona e capacidade/cotas; o padrão é `us-central1` / `us-central1-a`.
- [ ] Monitorar crédito/saldo e nunca fazer upgrade para billing pago sem aceitar cobranças.

O usuário da service account pode criar e destruir recursos no projeto. Restrinja permissões quando possível e nunca publique o JSON.

## 2 — Preparar HCP Terraform

- [ ] Confirmar que [terraform/backend.tf](terraform/backend.tf) aponta para a organização HCP `todoapp-pm4`.
- [ ] Criar workspaces `pm04-todoapp-dev`, `pm04-todoapp-homolog` e `pm04-todoapp-prod`.
- [ ] Adicionar a tag `application=pm04-todoapp` e configurar **Execution Mode: Local** em cada workspace; Terraform roda no GitHub runner e o HCP mantém o state remoto.
- [ ] Cadastrar `TF_API_TOKEN` como GitHub Secret.

## 3 — Configurar GitHub Actions

Em **Settings > Secrets and variables > Actions**, adicione:

**Secrets**

- `SSH_PRIVATE_KEY`: chave privada Ed25519 para SSH e Ansible.
- `TF_API_TOKEN`: token HCP Terraform.
- `MONGODB_ROOT_PASSWORD`: senha forte.
- `MONGODB_APP_PASSWORD`: senha forte separada para a aplicação.

**Repository variables**

- `GCP_PROJECT_ID`: Project ID.
- `GCP_REGION`: região, por exemplo `us-central1`.
- `GCP_ZONE`: zona dessa região, por exemplo `us-central1-a`.
- `GCP_WORKLOAD_IDENTITY_PROVIDER`: nome completo do provider WIF.
- `GCP_SERVICE_ACCOUNT`: e-mail de `pm04-github-actions`.

A autenticação GCP usa GitHub OIDC e credenciais temporárias, sem chave JSON. A workflow deriva a chave SSH pública e a injeta no metadata das instâncias. Ela obtém o IP de saída do runner e limita a porta 22 da VM app a esse IP; MongoDB não recebe IP público e a porta 27017 é limitada à subnet app.

## 4 — Cenário 1: criação inicial

1. Confira organização/workspace HCP, secrets, variables, APIs, cotas e orçamento.
2. Abra **Actions > Deploy ToDo App on GCP > Run workflow**.
3. Use `dev`, `vm-todo-pm04`, `e2-medium`, `todo-app`, tag `1.0.0`, `update_os=false` e `curl,git,unzip`. `source_ref` vazio usa a referência escolhida ao iniciar a workflow.
4. Acompanhe validações, Terraform plan/apply, espera SSH nas duas VMs e execução Ansible.
5. Abra a URL HTTPS final; o certificado é autoassinado e gera aviso no navegador.
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
3. Na VM DB, recrie somente o container MongoDB mantendo o Persistent Disk; confirme que a tarefa criada permanece.
4. Guarde evidências em `evidencias/cenario-3-idempotencia/`.

## 7 — Backup e restauração isolada

Na VM DB, crie um backup e execute o teste que restaura em container temporário, sem alterar a base principal:

```bash
sudo systemctl start todo-mongo-backup.service
sudo /usr/local/sbin/test-todo-mongodb-restore
```

Guarde a evidência do backup e do teste de restauração. Copie os backups para fora antes de destruir a infraestrutura se precisar preservá-los.

## O que demonstrar ao professor

1. Arquitetura com VM app pública e VM DB privada, VPC/subnets e HCP state remoto.
2. Regras de firewall: HTTP/HTTPS públicos; SSH app limitado ao runner; SSH/Mongo DB permitidos somente pela subnet app.
3. CRUD completo pelo HTTPS, com frontend/API/Mongo integrados.
4. Persistência após reiniciar/recriar container MongoDB com o disco mantido.
5. Três cenários: criação, atualização/rollback e idempotência.
6. Backup automatizado e restauração testada em ambiente isolado.
7. Versão do código (`source_ref`) e tags de imagem (`docker_tag`).
8. Estimativa mensal e do período com Compute, discos, NAT, IPv4 e tráfego; mostre crédito de trial separadamente.
9. Limitações do TLS autoassinado e plano de certificado público se exigido.

## Encerrar os recursos

1. Exporte o que precisar; Destroy apaga discos e dados.
2. Abra **Actions > Destroy ToDo App on GCP > Run workflow**.
3. Selecione o mesmo ambiente, informe exatamente o `instance_name` e digite `DESTROY`.
4. Confira o workflow e aguarde finalizar.
5. No Console GCP, confira VMs, discos, VPC, firewalls, router e Cloud NAT. Verifique a página de faturamento e recursos restantes.

Desligar apenas as VMs não remove discos, IPs, VPC ou NAT e pode não encerrar custos. O workflow Destroy remove os recursos Terraform-managed; o state HCP e as evidências permanecem.
