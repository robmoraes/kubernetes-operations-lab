# 12 — Confiabilidade, incidentes e projeto profissional

**Tempo sugerido:** 24–32 horas, mais observação ao longo das semanas.
**Pré-requisitos:** aplicação `curso/web` saudável, módulos anteriores e capacidade
livre nos workers. Execute no laboratório, com contexto confirmado.
O objetivo é demonstrar operação: detectar impacto, mitigar, recuperar e justificar decisões.

## Comece pelo serviço que o usuário percebe

Uma máquina saudável pode servir respostas erradas. CPU alta pode ser utilização
eficiente sem impacto. Defina o que o usuário precisa e depois escolha os sinais.
SLI é a medida, SLO é a meta em uma janela, SLA é um compromisso contratual que pode
ter consequências comerciais. Não trate esses termos como sinônimos.

Neste exercício, o SLI é a fração de sondas HTTP bem-sucedidas. A meta didática é
99,9% em 30 dias; o orçamento é 0,1% das sondas. Em uma medição contínua baseada em
tempo, 0,1% de 30 dias equivale a 43,2 minutos. Uma meta baseada em requisições exige
contar requisições: não converta automaticamente erros de requests em minutos.

Uma sonda interna só cobre DNS interno, Service, endpoints e aplicação. Para medir
experiência externa, adicione sonda fora do cluster passando por DNS público, TLS e
Traefik. Colocar observabilidade no mesmo domínio de falha pode esconder uma queda total.

Preencha [`slo.md`](../laboratorios/12-sre/slo.md) antes de abrir o dashboard. Especifique
janela, cobertura, destino dos alertas e política de alterações quando o orçamento acabar.

## Laboratório A — Coleta mínima e verificável

O conjunto entregue usa Prometheus e blackbox exporter, sem operator. Você já pode
inspecionar todos os objetos nativos. As imagens têm tags explícitas para o exercício;
revise patches de segurança e compatibilidade antes de uso duradouro.

```bash
kubectl config current-context
kubectl -n curso get deployment/web service/web
kubectl kustomize laboratorios/12-sre
kubectl apply -k laboratorios/12-sre
kubectl -n curso-sre rollout status deployment/prometheus --timeout=3m
kubectl -n curso-sre rollout status deployment/blackbox --timeout=3m
kubectl -n curso-sre port-forward service/prometheus 9090:9090
```

Abra `http://127.0.0.1:9090`, verifique Targets e consulte `probe_success`. Após a
primeira coleta, deve existir uma série de valor 1 para `http://web.curso.svc.cluster.local/`.
`up=1` indica que Prometheus conseguiu coletar o exporter; não significa HTTP saudável.

Se o módulo de segurança deixou ingress default-deny em `curso`, acrescente à política
da aplicação uma permissão de `curso-sre` para pods `app=web`, TCP/8080. Permita DNS e
saída do exporter se houver egress default-deny. Preserve as permissões do Traefik.
Observe que NetworkPolicy avalia a porta do pod, aqui 8080, enquanto Service oferece 80.

Para depurar o exporter, use outro terminal:

```bash
kubectl -n curso-sre port-forward service/blackbox 9115:9115
```

Em um terceiro, consulte o resultado detalhado da sonda:

```bash
curl -sS 'http://127.0.0.1:9115/probe?target=http://web.curso.svc.cluster.local/&module=http_2xx&debug=true'
```

Compare resolução DNS, conexão e código HTTP. O endpoint não deve ficar exposto à
internet: ele permite iniciar sondas a endereços escolhidos pelo chamador.

## Consultas que você deve compreender

```promql
probe_success{job="web-blackbox"}
probe_duration_seconds{job="web-blackbox"}
100 * avg_over_time(probe_success{job="web-blackbox"}[5m])
(1 - avg_over_time(probe_success{job="web-blackbox"}[1h])) / 0.001
```

A terceira consulta calcula proporção de amostras boas, não uma integração exata de
uptime. A quarta é uma aproximação de burn rate: 1 gasta o orçamento no ritmo da meta;
14,4 gasta muito mais rápido. Exija janelas curta e longa para reduzir alertas espúrios.
Sem dados, a consulta pode ficar vazia: ausência de métrica não equivale a sucesso.

O alerta `ColetaWebAusente` cobre ausência/falha da coleta enquanto Prometheus está
funcionando. Monitorar a queda do próprio Prometheus exige observação externa.
O laboratório guarda apenas 24 horas em `emptyDir`: recriar o pod perde histórico.
Não é possível provar um SLO de 30 dias com essa retenção. Para o projeto, dimensione
PVC e retenção ou backend remoto, incluindo backup e custo. Não basta instalar um dashboard.

## Laboratório B — Incidente de selector

Leia `rules.yml`. `WebIndisponivel` entra em pending antes de firing devido ao `for: 1m`.
Alertas aparecem em `/alerts`; este laboratório não envia notificações a pessoas.
Um teste de notificação exige Alertmanager configurado e um destino de teste seu.

Com a sonda saudável, introduza um selector sem pods correspondentes:

```bash
kubectl -n curso patch service web --type=merge \
  -p '{"spec":{"selector":{"app":"web-quebrado"}}}'
kubectl -n curso get endpointslice -l kubernetes.io/service-name=web
kubectl -n curso get pods -l app=web
```

Pods continuam Running, mas o serviço fica sem backend. Aguarde a coleta e o período
do alerta, registre detecção, hipótese e evidência. Recupere o selector original:

```bash
kubectl -n curso patch service web --type=merge \
  -p '{"spec":{"selector":{"app":"web"}}}'
kubectl -n curso get endpointslice -l kubernetes.io/service-name=web
```

Comprove HTTP e `probe_success=1`. O alerta rápido deve limpar após avaliação; as
janelas de burn rate conservam a memória da falha por mais tempo. Se GitOps já gerencia
esse Service, declare uma janela/alteração de teste no Git para evitar autorrecuperação
imediata apagar o cenário. Não desative reconciliação globalmente.

Repita com a aplicação saudável e blackbox temporariamente escalado para zero:

```bash
kubectl -n curso-sre scale deployment/blackbox --replicas=0
# Observe coleta ausente; depois recupere o exporter:
kubectl -n curso-sre scale deployment/blackbox --replicas=1
```

Explique por que a aplicação não caiu nesse segundo incidente. Preencha o
[postmortem](../laboratorios/12-sre/postmortem.md) com linha do tempo e ação verificável.
Se você alterou outro selector originalmente, restaure seu valor registrado antes do teste.

## Evolução da observabilidade

Para tráfego real, instrumente counters de requests e erros e histogramas de latência.
Use `rate` em counters, agregue por dimensões úteis e defina buckets de acordo com o
SLO. Não use usuário, request ID ou URL não normalizada como label: cardinalidade
consome memória e armazenamento. Não tire média de percentis de instâncias diferentes.

Logs complementam métricas para investigação; traces mostram o caminho entre serviços.
Capture stdout/stderr, normalize campos, aplique retenção e elimine segredos antes do
envio. Como extensão, instale Loki com object storage e agente de coleta suportado;
registre IAM, retenção, custo de ingestão e processo de consulta durante incidente.
Use OpenTelemetry se o projeto precisar de tracing, com uma amostra e objetivo claros.

Prometheus Operator, ServiceMonitor, Grafana, Alertmanager e backend de longo prazo
são extensões justificáveis agora. Compare custo de operar com serviço gerenciado.
Meça requests/limits, uso real, disco, cardinalidade, retenção e tráfego entre AZs.
O desenho de armazenamento deve seguir RPO/RTO e acesso dos dados, não o nome da ferramenta.

## Projeto final — Migrar e operar uma aplicação real

Escolha um serviço do seu Swarm com dependências compreensíveis. Preserve o ambiente
original e use dados sintéticos. Entregue a aplicação em Kubernetes com HTTP/TLS,
configuração externa, persistência quando necessária, deploy revisado e recuperação.

Construa uma demonstração de 20 minutos: arquitetura, commit causando rollout, falha
controlada, detecção, recuperação e explicação do tradeoff de storage entre AZs.
Mostre medidas reais; declare explicitamente o que só foi validado estaticamente.

| Critério | Pontos | Evidência exigida |
|---|---:|---|
| Arquitetura e decisões | 10 | diagrama, requisitos, alternativas e três ADRs |
| Workloads | 10 | probes, requests/limits, rollout e rollback funcionando |
| Rede e entrada | 10 | DNS, Service, Traefik/Gateway ou Ingress, TLS e diagnóstico |
| Segurança | 10 | RBAC mínimo, ServiceAccount, policies e ausência de segredos no Git |
| Persistência e recuperação | 15 | dados após recriação, restore real, RTO/RPO e limite de AZ |
| Entrega e infraestrutura | 10 | Helm/Kustomize, GitOps e plano IaC revisado |
| Operação e HA | 10 | upgrade ensaiado, falha de CP/worker e retorno saudável |
| SRE e incidentes | 15 | SLO, alerta testado, timeline e postmortem com prevenção |
| Portfólio e comunicação | 10 | reprodução, custos, limpeza e apresentação sem roteiro |
| **Total** | **100** | **mínimo 80 e nenhum critério eliminatório** |

São eliminatórios: publicar segredos, não conseguir restaurar os dados escolhidos,
depender de uma aplicação privilegiada sem justificativa e apresentar como executado
um teste não realizado. Se optar por cluster local, declare EKS como projeto planejado;
para reivindicar experiência prática em EKS, execute e documente também o módulo 11.

O repositório de portfólio deve conter README reproduzível, diagrama, decisões, manifests,
versões, runbooks, evidências sanitizadas e uma seção de limitações. Não inclua kubeconfig
administrativo, chaves, snapshot etcd, state Terraform ou logs com dados de clientes.

## Perguntas para entrevista e prova oral

1. Um pod está Running mas o usuário recebe 503. Qual é sua sequência de investigação?
2. Um deploy com três réplicas sobrevive à perda de AZ? Quais dados faltam para responder?
3. Por que `up=1` e `probe_success=0` podem ocorrer simultaneamente?
4. O PV tem Retain: quais ações ainda podem fazer você perder dados?
5. O drain está bloqueado. Como distinguir proteção legítima de configuração impossível?
6. Como você diferencia IAM da aplicação, autenticação de humanos e RBAC?
7. Uma alteração urgente conflita com GitOps. Como mitigar e manter uma fonte de verdade?
8. Qual evidência demonstra restore e qual apenas demonstra que o backup foi gerado?

Responda com uma hipótese, o teste mais barato para verificá-la, possível mitigação e
risco residual. Para prova prática, repita tarefas cronometradas de kubectl, troubleshooting
e recuperação usando apenas recursos permitidos pelo regulamento atual da certificação.
O projeto demonstra capacidade; a aprovação em exame depende também de execução sob tempo.

## Encerramento

```bash
kubectl delete -k laboratorios/12-sre
```

Essa exclusão remove só os componentes e namespace da observabilidade didática,
incluindo seu histórico temporário. Preserve evidências antes de executar.
Mantenha sua aplicação e as evidências do projeto enquanto revisar os simulados.

## Fontes primárias consultadas em 2026-09-10

- [Google SRE: SLOs](https://sre.google/workbook/implementing-slos/).
- [Google SRE: burn rate](https://sre.google/workbook/alerting-on-slos/).
- [Prometheus: regras](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/) e [alertas](https://prometheus.io/docs/practices/alerting/).
- [Blackbox exporter](https://github.com/prometheus/blackbox_exporter).
- [Postmortems](https://sre.google/sre-book/postmortem-culture/).
