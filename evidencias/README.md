# Portfólio de evidências

Guarde aqui **relatos sanitizados** e pequenos resultados, organizados por módulo. Use os modelos de [diário](../templates/diario.md), [ADR](../templates/adr.md), [runbook](../templates/runbook.md) e [postmortem](../templates/postmortem.md).

Exemplo de entrega: `04-storage.md` com o nome fictício do volume, nó/zona antes e depois, arquivo de teste e resultado da recuperação. Inclua trechos pequenos que comprovem o resultado e sua interpretação.

Kubeconfig, chaves, tokens, snapshots do etcd, Terraform state e dumps de Secrets pertencem ao armazenamento privado do laboratório. `.gitignore` reduz acidentes, mas não identifica todos os formatos possíveis de segredo: revise o diff antes de cada commit.

Para uma entrevista, apresente uma aplicação implantada e operada em Kubernetes, três decisões de arquitetura, dois incidentes solucionados e uma restauração medida. A aplicação pode ser uma evolução da base do curso ou um projeto próprio containerizado. Diferencie experimento de laboratório de experiência de produção.
