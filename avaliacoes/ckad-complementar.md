# Complemento de aplicações — preparação CKAD

Execute no namespace novo `curso-ckad`, a partir dos módulos 02–07 e09. Três sessões de 60 minutos, com evidências funcionais. Use sua experiência de construir imagens; não é necessário publicar uma imagem privada ou credenciais neste repositório. Confira o [currículo oficial CKAD](https://training.linuxfoundation.org/certification/certified-kubernetes-application-developer-ckad/) antes de agendar.

## Sessão 1 — ciclos de vida e recursos

1. Construa uma imagem HTTP multiarch de uma aplicação sua. Registre Dockerfile, architectures e digest; comprove execução ARM64. Se não houver registry de laboratório, faça build local e registre que o teste de pull remoto ficou pendente.
2. Crie Pod com initContainer que prepara arquivo em emptyDir e container principal que serve o arquivo. Prove ordem de execução pelos logs e mostre que reiniciar só o container principal não executa novamente um initContainer já concluído no mesmo Pod.
3. Acrescente sidecar de observação com encerramento apropriado para o tipo de workload; compare com sidecar nativo em initContainers/restartPolicy Always quando suportado. Explique por que um sidecar convencional que nunca termina pode impedir uma Job de concluir.
4. Crie CronJob a cada 5 min, concurrencyPolicy Forbid, limites de histórico e deadline; crie uma Job manual a partir dela. Observe Complete e histórico. CronJob exige tarefas idempotentes; não é garantia de execução exatamente uma vez.

Critérios: imagem executa (25 p), initContainer/volume comprovados (25 p), sidecar explicado/testado (25 p), CronJob/Job e encerramento corretos (25 p). Meta80/100.

## Sessão 2 — configuração e isolamento

1. Crie ResourceQuota e LimitRange no namespace; provoque e explique rejeição de uma criação que ultrapassa quota. Repare a carga sem remover a quota.
2. Consuma um ConfigMap como arquivo e um Secret fictício como env. Altere os dois; prove quando cada valor aparece no processo e quando é necessário rollout. Não use segredo verdadeiro.
3. Configure startup, readiness e liveness com propósitos distintos. Simule demora de inicialização, dependência indisponível e processo travado; observe reinícios e EndpointSlices.
4. Rode sem root, sem privilege escalation, com capabilities removidas e filesystem somente leitura; monte emptyDir só no caminho que precisa escrita. Demonstre a falha de escrita fora dele.

Critérios: quota/limites (25 p), configuração/rotação (25 p), probes/efeitos distintos (25 p), contexto de segurança (25 p). Não basta incluir os campos no YAML: guarde testes.

## Sessão 3 — entrega e diagnóstico

1. Faça blue/green com dois Deployments e troca de selector do Service. Prove rollback e explique por que ele não desfaz migração de banco.
2. Faça canary simples com backends estável/canário e roteamento compatível com seu controller; justifique a diferença entre proporção de réplicas e peso de requisições. Não atribua pesos a um Service comum sem implementação de roteamento.
3. Corrija uma imagem inexistente, uma porta errada e um erro de DNS em três aplicações isoladas. Registre hipótese, evento/log e alteração mínima.
4. Instale sua app por Helm, altere values e faça rollback. Renderize variação por Kustomize em namespace diferente. Identifique APIs deprecadas nas versões de origem/destino usando documentação/release notes.

Critérios: blue/green (25 p), canary medido (25 p), diagnósticos (25 p), pacotes/APIs (25 p). Se um pré-requisito de roteamento faltar, instale e documente antes do relógio em vez de marcar o item como feito.

## Revisão oral

Explique: quando Deployment é melhor que StatefulSet; quando Job é melhor que Pod avulso; ServiceAccount versus identidade de usuário; autenticação versus RBAC versus admissão; configuração via arquivo versus env; limites de memória versus CPU; finalidade de CRD e controller; quem recebe tráfego quando readiness falha. Use resultados dos experimentos para responder.
