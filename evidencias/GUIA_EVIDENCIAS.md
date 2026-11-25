# Guia de evidências — PM-04

Registre somente resultados realmente observados. Uma captura da página inicial, sozinha, não comprova integração, persistência ou recuperação.

## Pastas e critérios

| Pasta | Conteúdo esperado |
| --- | --- |
| `cenario-1-criacao-inicial/` | ACE-01/02/04/06: execução inicial, plan/apply, duas VMs, inventário, URL HTTPS e CRUD completo. |
| `cenario-2-atualizacao/` | ACE-05/06: mudança de tipo de VM e release/tag, saúde após atualização e rollback para a versão anterior. |
| `cenario-3-idempotencia/` | ACE-05/06: inputs repetidos, plano Terraform sem alterações e Ansible idempotente. |
| `ace-03-isolamento/` | ACE-03: VM MongoDB sem IP público, regras de firewall com source tag `todo-app` e tentativa de acesso externo bloqueada. |
| `ace-07-recuperacao/` | ACE-07: backup sob demanda e restauração isolada bem-sucedida, sem sobrescrever dados de demonstração. |
| `ace-09-custos/` | ACE-09: estimativa com premissas, fontes, USD e período de uso. |
| `ace-10-transferencia/` | ACE-10: registro do ensaio conduzido pelos alunos com o manual e diagnóstico. |

## Capturas sugeridas

1. **Pipeline:** resumo do run de deploy/operate/destroy e etapas concluídas; oculte campos de segredo e IPs que não queira divulgar.
2. **Terraform:** trechos relevantes do plan/apply com recursos criados ou `No changes`; não capture state nem valores sensíveis.
3. **Console GCP:** duas VMs e seus endereços, discos persistentes, VPC/subnets, firewalls, Cloud NAT e ausência de IP externo na VM DB.
4. **Aplicação:** em outro dispositivo, URL HTTPS com certificado válido e tarefas criadas, concluídas, reabertas e excluídas; faça reload para verificar a lista persistida.
5. **Atualização/rollback:** mesmo `environment`/`instance_name`, novo tipo/tag, saúde após deploy e retorno controlado aos parâmetros anteriores.
6. **Idempotência:** execução repetida com os mesmos parâmetros e evidência de ausência de mudanças imprevistas.
7. **Persistência:** tarefa identificável antes e depois da ação `recreate_database`, mais run concluído que recria apenas o container MongoDB.
8. **Recuperação:** runs `backup` e `restore_test`, arquivo de backup listado e resultado de restauração isolada.
9. **Operação:** runs das ações `health`, `logs` e reinício, mais o workflow Destroy concluído e Console sem recursos faturáveis remanescentes.
10. **Transferência:** alunos executando o roteiro, registrando resultado e resolvendo ao menos uma falha simulada sem expor credenciais.

Use nomes sequenciais e legíveis, por exemplo `01-run-deploy.png`, `02-vms-e-discos.png`, `03-crud-https.png` e `04-persistencia-recriar-mongo.png`. Registre a data/hora, run ID, versão (`source_ref`/`docker_tag`), ambiente, resultado e responsável no [modelo](modelo-registro.md).

**Não invente capturas nem marque testes pendentes como aprovados.** Os itens ACE-04 e ACE-10 exigem validação por outro dispositivo e condução dos alunos, respectivamente.
