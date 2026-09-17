# 12 — Confiabilidade, incidentes e projeto profissional

## Antes de começar

Reserve **24–32 horas**, mais observação ao longo das semanas. Conclua
[workloads](02-workloads.md), [rede](03-rede.md), [storage](04-storage.md),
[segurança](06-seguranca.md), [troubleshooting](07-troubleshooting.md) e
[entrega](09-entrega.md). Para a rubrica final, acrescente as provas de manutenção/HA
dos módulos 08/10 e a execução ou declaração de limite EKS do módulo 11.

Use `curso/web` com Service porta 80 → pod 8080, dois workers saudáveis e capacidade
livre de pelo menos 160 MiB/120m para os requests adicionais; reserve folga até os
limites declarados nos manifests. O laboratório usa kubectl, curl e navegador na
estação. Para a prática de restauração de arquivo, use também Bash, `mktemp`, `date`
e `sha256sum` na estação e o workload/PVC do módulo 04, conforme a preparação da seção.
Prometheus e blackbox serão instalados como pods pelos manifests locais,
sem instalação de agentes na sua máquina. Todos os comandos partem da raiz do repositório.

Métricas do exercício são descartáveis, sem dados de clientes. Não exponha Prometheus
ou blackbox à internet. Confirme o contexto; os componentes ficarão em `curso-sre`.
Na estação, execute `export KUBECONFIG="$HOME/.kube/curso-kubeconfig"` e confira os nós
manuais com `kubectl get nodes`. O EKS temporário do módulo 11 já foi encerrado; o
cluster principal e o Argo CD foram mantidos para este projeto.
Os templates de [SLO](../laboratorios/12-sre/slo.md) e
[postmortem](../laboratorios/12-sre/postmortem.md) serão preenchidos após exemplos guiados.

## O que você vai conseguir fazer

- Definir um SLI, uma meta e um orçamento de erro, explicando sua cobertura.
- Instalar a coleta, interpretar métricas/alertas e distinguir falha do serviço de falha da sonda.
- Provocar e recuperar um incidente de laboratório com linha do tempo e evidências.
- Apresentar uma aplicação operada em Kubernetes, com confiabilidade e operação avaliadas por uma rubrica de 100 pontos.

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

**Exemplo preenchido:** serviço `web`, jornada “buscar a página inicial”, sonda HTTP
interna a cada 15 segundos, boa quando recebe 2xx. Meta: 99,9% das sondas elegíveis em
30 dias. Se houver 6.000 sondas, o orçamento será seis falhas; com 20 falhas,
`5.980 / 6.000 = 99,667%`, a meta foi descumprida e o orçamento gasto mais de três vezes.
Esse exemplo mede sondas; não afirma que 20 usuários falharam.

Política didática: quando o orçamento acabar, priorizar correções de confiabilidade e
revisar risco antes de novas funcionalidades; correções urgentes continuam possíveis
com teste e rollback. Responsável: você no laboratório; destino do alerta: interface
local, sem plantão real. Cobertura: rota interna; exclusões: coleta ausente fica
**desconhecida**, não é contabilizada como sucesso. Próxima revisão: após o incidente.

Agora preencha [`slo.md`](../laboratorios/12-sre/slo.md) com esse contrato e depois
adapte-o à aplicação escolhida. O documento deve permitir que outra pessoa refaça a
conta e saiba qual decisão será tomada ao consumir o orçamento.

## Entender a coleta antes de instalar

Prometheus coleta periodicamente um endpoint de métricas e armazena séries temporais:
nome da métrica + conjunto de labels + valores ao longo do tempo. **Scrape** é uma
coleta; **target** é o destino dessa coleta; **job** agrupa targets com a mesma configuração.
O blackbox exporter faz uma requisição HTTP ao alvo e descreve o resultado em métricas.
Prometheus pergunta ao exporter; o exporter acessa `curso/web`. São duas conexões diferentes.

`probe_success` é um **gauge** que vale 0 ou 1 naquela observação. Um **counter** só cresce,
salvo reinício, e serviria para contar requests; `rate(counter[5m])` estima sua taxa.
Um **histograma** distribui observações em faixas e ajuda a medir latência. Aqui usamos
gauges da sonda; não inventamos contadores de tráfego real que a aplicação não exporta.

Abra `prometheus.yml`, `blackbox.yml` e `rules.yml` em
[laboratorios/12-sre](../laboratorios/12-sre/). O primeiro define coleta a cada 15s e
encaminha o alvo como parâmetro `/probe`; o segundo exige HTTP 2xx com timeout de 5s;
o terceiro define condições e tempo de confirmação dos alertas. Kustomize transforma
esses arquivos em ConfigMaps e liga-os aos pods. Você já estudou esse empacotamento no módulo 09.

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
kubectl -n curso-sre exec deployment/prometheus -- promtool check config /etc/prometheus/prometheus.yml
kubectl -n curso-sre port-forward service/prometheus 9090:9090
```

Abra `http://127.0.0.1:9090`, verifique Targets e consulte `probe_success`. Após a
primeira coleta, deve existir uma série de valor 1 para `http://web.curso.svc.cluster.local/`.
`up=1` indica que Prometheus conseguiu coletar o exporter; não significa HTTP saudável.
A checagem `promtool` dentro da imagem instalada deve informar configuração/regras válidas;
ela não prova que há conectividade até o alvo. Se os pods não ficarem Ready, use describe,
eventos e logs antes de abrir o dashboard.

O módulo 06 usa seu próprio namespace; o baseline deste exercício não tem default-deny
em `curso`. Se você o estendeu para a aplicação, use a técnica de NetworkPolicy já
praticada: permita origem namespace `curso-sre` para pods `app=web`, TCP/8080; permita
DNS e saída do exporter se também isolou egress. Preserve as permissões do Traefik.
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

Na página de consulta Prometheus, cole **uma expressão por vez**. `{job="web-blackbox"}`
filtra labels; `[5m]` seleciona amostras dos últimos cinco minutos; `avg_over_time`
faz a média por série. Como a métrica só vale 0/1, essa média é a proporção de sondas
boas disponíveis. Multiplicar por 100 transforma em porcentagem.

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
Resultado guiado: após cinco minutos saudáveis, terceira consulta próxima de 100 e
quarta próxima de 0. Se 1% das amostras da janela falha e o orçamento é 0,1%, o burn
rate é `0,01 / 0,001 = 10`. Não interprete `10` como dez segundos ou dez requests.

O alerta `ColetaWebAusente` cobre ausência/falha da coleta enquanto Prometheus está
funcionando. Monitorar a queda do próprio Prometheus exige observação externa.
O laboratório guarda apenas 24 horas em `emptyDir`: recriar o pod perde histórico.
Não é possível provar um SLO de 30 dias com essa retenção. Para o projeto, dimensione
PVC e retenção usando o mecanismo do módulo 04, incluindo backup e custo; um backend
remoto é uma extensão opcional. Declare a janela efetivamente observada: definir uma
meta de 30 dias não exige esperar 30 dias para praticar o incidente, mas o ensaio curto
também não comprova cumprimento dessa meta. Não basta instalar um dashboard.

## Laboratório B — Incidente de selector

Em `rules.yml`, `expr` define a condição; `for` exige que ela permaneça verdadeira pelo
tempo indicado. `labels` classificam o alerta; `annotations` explicam o sintoma.
`WebIndisponivel` entra em **pending** antes de **firing** devido ao `for: 1m`.
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

Explique por que a aplicação não caiu nesse segundo incidente. Antes de preencher o
[postmortem](../laboratorios/12-sre/postmortem.md), use este exemplo de estrutura,
substituindo os horários ilustrativos pelos seus:

- 14:00 UTC: selector alterado; EndpointSlice fica sem backend pronto.
- 14:00:15: primeira sonda falha; pods web continuam Ready.
- 14:01:15: alerta confirmado; hipótese inicial de processo é descartada pelos pods/logs.
- 14:02:00: selector restaurado; endpoints voltam e HTTP retorna 200.
- Causa: configuração de descoberta divergente das labels, sem validação após mudança.
- Prevenção: teste de HTTP pelo Service após rollout; responsável definido; prova será
  repetir a falha e demonstrar que a etapa de validação a detecta antes da promoção.

Impacto, detecção e recuperação devem vir das suas evidências, não desse exemplo.
Agora preencha o template com condições contribuintes e uma ação verificável.
Se você alterou outro selector originalmente, restaure seu valor registrado antes do teste.

## Desafio independente e evolução da observabilidade

Repita o incidente do exporter e o do selector em ordem sorteada, sem olhar a receita
de diagnóstico. Para cada um, determine se `up`, `probe_success`, endpoints e HTTP
direto indicam falha de aplicação ou de medição. Termine quando conseguir explicar
a causa e recuperar em até 15 minutos, com evidência e sem reinstalar a observabilidade.

Faça também uma conta de retenção usando uma medição, não um tamanho arbitrário:
anote a taxa de crescimento do diretório de métricas ao longo de uma hora com carga
representativa, projete o período desejado e acrescente espaço para WAL, índices e
folga. Essa projeção é hipótese a validar com uso real. A migração de `emptyDir` para
um PVC segue o mecanismo do módulo 04; não copie arquivos TSDB de um escritor ativo.

Para tráfego real, instrumente counters de requests e erros e histogramas de latência.
Use `rate` em counters, agregue por dimensões úteis e defina buckets de acordo com o
SLO. Não use usuário, request ID ou URL não normalizada como label: cardinalidade
consome memória e armazenamento. Não tire média de percentis de instâncias diferentes.

Logs complementam métricas para investigação; traces mostram o caminho entre serviços.
Capture stdout/stderr, normalize campos, aplique retenção e elimine segredos antes do
envio. Loki com object storage e OpenTelemetry para traces são extensões opcionais.
Você não precisa instalar outra plataforma para concluir o diagnóstico e os alertas
deste capítulo. Para investigar o incidente guiado, use
`kubectl logs -n curso -l app=web --since=10m --timestamps` e compare com a timeline;
ausência de requests nos pods durante a falha de selector é compatível com a hipótese.

Prometheus Operator, ServiceMonitor, Grafana, Alertmanager e backend de longo prazo
são extensões justificáveis agora. Compare custo de operar com serviço gerenciado.
Meça requests/limits, uso real, disco, cardinalidade, retenção e tráfego entre AZs.
O desenho de armazenamento deve seguir RPO/RTO e acesso dos dados, não o nome da ferramenta.
Na rubrica abaixo, “alerta testado” significa condição acionada e resolvida com evidência;
notificação externa e plantão não são presumidos por instalar Prometheus.

## Prática complementar — Recuperar um arquivo a partir de backup

A aplicação-base HTTP não possui dados persistentes próprios. Para exercitar essa
competência sem desenvolver outro sistema, reutilize `curso-storage/arquivo`, o PVC
`dados` e a montagem `/dados` do módulo 04. Se já encerrou esses recursos, prepare
novamente apenas a alternativa de storage escolhida, local ou EBS, seguindo aquela
aula. Não aplique o diretório inteiro: ele contém alternativas incompatíveis.

O processo `arquivo` apenas dorme; mantenha uma réplica, como no manifesto do módulo 04,
e confirme que o PVC `dados` está Bound e montado. Os comandos abaixo serão o único
escritor de um diretório novo, com conteúdo sintético. O backup ficará na estação, fora do PVC e do
cluster. Mantenha a mesma sessão de terminal para preservar as variáveis e pare ao
primeiro erro. `mktemp -d` cria diretórios exclusivos, sem sobrepor arquivos anteriores.

```bash
kubectl config current-context
kubectl -n curso-storage get deployment arquivo
kubectl -n curso-storage rollout status deployment/arquivo --timeout=180s
kubectl -n curso-storage get pvc dados
SRE_BACKUP_DIR=$(mktemp -d)
SRE_DADOS_DIR=$(kubectl -n curso-storage exec deployment/arquivo -- mktemp -d /dados/restore-sre.XXXXXX)
kubectl -n curso-storage exec deployment/arquivo -- sh -c 'printf "estado=antes\n" > "$1/marcador.txt" && sync' sh "$SRE_DADOS_DIR"
kubectl -n curso-storage exec deployment/arquivo -- cat "$SRE_DADOS_DIR/marcador.txt" > "$SRE_BACKUP_DIR/marcador.txt"
test -s "$SRE_BACKUP_DIR/marcador.txt"
date -u
sha256sum "$SRE_BACKUP_DIR/marcador.txt"
kubectl -n curso-storage exec deployment/arquivo -- sha256sum "$SRE_DADOS_DIR/marcador.txt"
```

Registre o horário do backup e confirme hashes iguais antes de simular a perda.
A leitura é consistente porque esse arquivo não muda durante a cópia; isso não
generaliza para um banco ou TSDB ativo. Agora faça uma alteração posterior ao backup
e retire o arquivo de seu caminho original, preservando-o com outro nome:

```bash
kubectl -n curso-storage exec deployment/arquivo -- sh -c 'test ! -e "$1/marcador-preservado.txt" && printf "estado=depois\n" > "$1/marcador.txt" && sync && mv "$1/marcador.txt" "$1/marcador-preservado.txt"' sh "$SRE_DADOS_DIR"
date -u
kubectl -n curso-storage exec deployment/arquivo -- test ! -e "$SRE_DADOS_DIR/marcador.txt"
```

O último comando deve terminar com sucesso: o caminho original está ausente. Anote
esse instante como início da recuperação. Restaure **a cópia da estação** usando
`exec -i`, que transmite a entrada padrão ao container. O teste impede sobrepor um
arquivo que reapareceu; o `&&` só inicia a escrita se esse teste passar.

```bash
kubectl -n curso-storage exec -i deployment/arquivo -- sh -c 'test ! -e "$1/marcador.txt" && cat > "$1/marcador.txt" && sync' sh "$SRE_DADOS_DIR" < "$SRE_BACKUP_DIR/marcador.txt"
kubectl -n curso-storage exec deployment/arquivo -- cat "$SRE_DADOS_DIR/marcador.txt"
kubectl -n curso-storage exec deployment/arquivo -- sha256sum "$SRE_DADOS_DIR/marcador.txt"
date -u
kubectl -n curso-storage rollout restart deployment/arquivo
kubectl -n curso-storage rollout status deployment/arquivo --timeout=180s
kubectl -n curso-storage exec deployment/arquivo -- cat "$SRE_DADOS_DIR/marcador.txt"
kubectl -n curso-storage exec deployment/arquivo -- sha256sum "$SRE_DADOS_DIR/marcador.txt"
```

Espere `estado=antes` e o hash do backup antes e depois da recriação do Pod.
Registre o tempo até validar a recuperação e a alteração `estado=depois` que o backup
não continha. Relacione-os ao RTO e ao RPO definidos para esse dado. Se a cópia falhar,
preserve backup, arquivo renomeado e volume; investigue montagem, permissão e espaço
antes de repetir. Não declare sucesso apenas porque o comando terminou.

Essa prova recupera um arquivo no PVC existente. Ela não comprova restauração de
volume perdido, banco, histórico Prometheus ou outra AZ; documente esses limites e o
plano correspondente. Preserve as evidências e descarte os recursos pelo roteiro do
módulo 04 quando encerrar seu uso. No desafio final, repita a prova sem os comandos
acima, com outro conteúdo e diretório sintéticos, usando seu próprio runbook.

## Projeto final — Entregar e operar uma aplicação em Kubernetes

Uma **ADR** registra uma decisão de arquitetura: contexto/requisito, opções consideradas,
escolha, motivo, consequências e quando revisar. Exemplo: “usar EBS por réplica porque
a aplicação precisa de filesystem e não compartilha escrita; aceitar afinidade à AZ;
revisar ao exigir recuperação em outra zona”. Use esse formato para três decisões
reais do projeto. Um **runbook** é o procedimento operacional com gatilho, verificações,
ações, rollback e comprovação; os planos de falha já preenchidos são seu primeiro modelo.

Retome os requisitos e critérios de sucesso registrados no módulo 00. O caminho
fornecido usa a aplicação-base de
[laboratorios/02-workloads](../laboratorios/02-workloads/), evoluída com os mecanismos
de rede, segurança, entrega e observabilidade praticados ao longo do curso. Seus
manifests, imagens e conteúdo de exemplo permitem executar o projeto inteiro sem
código próprio ou acesso a um ambiente empresarial.

Uma aplicação própria containerizada pode substituir essa base. Ela pode vir de
Compose, Docker isolado, outro ambiente ou de um projeto novo; não precisa estar em
produção. Nesse caso, delimite um componente inicial e acrescente dependências apenas
quando conseguir operá-las e recuperá-las com os mecanismos estudados. Se houver uma
implantação existente, preserve-a e use uma cópia com dados sintéticos no laboratório.
Ter uma aplicação maior não acrescenta pontos por si só.

Entregue HTTP/TLS, configuração externa, deploy revisado e recuperação, comparando
o resultado aos requisitos iniciais. A aplicação-base é stateless e seu conteúdo
vem de ConfigMap; não acrescente estado artificialmente ao servidor HTTP apenas para
cumprir a rubrica. Para as provas de persistência, use separadamente o workload
`arquivo` e seu PVC de [laboratorios/04-storage](../laboratorios/04-storage/).
Declare que ele é um exercício complementar de dados e demonstre persistência,
backup e restauração de um arquivo sintético como na prática acima. Uma aplicação
própria com dados pode cumprir esse mesmo critério, desde que haja uma restauração verificável; snapshot de
etcd e rollback de manifests não substituem recuperação do conteúdo de um volume.

Construa uma demonstração de 20 minutos: arquitetura, commit causando rollout, falha
controlada, detecção, recuperação e explicação do tradeoff de storage entre AZs.
Mostre medidas reais; declare explicitamente o que só foi validado estaticamente.

| Critério | Pontos | Evidência exigida |
|---|---:|---|
| Arquitetura e decisões | 10 | diagrama, requisitos, alternativas e três ADRs |
| Workloads | 10 | probes, requests/limits, rollout e rollback funcionando |
| Rede e entrada | 10 | DNS, Service, Traefik/Gateway ou Ingress, TLS e diagnóstico |
| Segurança | 10 | RBAC mínimo, ServiceAccount, policies e ausência de segredos no Git |
| Persistência e recuperação | 15 | dados após recriação, restore executado do dado escolhido, RTO/RPO e limites do storage, incluindo AZ |
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

## Limpeza

```bash
kubectl delete -k laboratorios/12-sre
```

Essa exclusão remove só os componentes e namespace da observabilidade didática,
incluindo seu histórico temporário. Preserve evidências antes de executar.
Mantenha sua aplicação e as evidências do projeto enquanto revisar os simulados.

## Fechamento

Você transformou um requisito de disponibilidade em coleta, condição de alerta e
procedimento de resposta. Explique por que pods Ready não provam sucesso do serviço,
por que coleta ausente não é sucesso e por que 24 horas de dados não demonstram um SLO de 30 dias.

O capítulo está praticado quando há: SLO com cálculo reproduzível; targets saudáveis;
os dois incidentes detectados e recuperados; postmortem baseado na timeline; e projeto
final com **80/100 ou mais**, sem eliminatórios. A rubrica preserva os critérios de
rede, segurança, dados, entrega e HA; componentes opcionais não substituem essas provas.
Se algum ensaio só foi planejado, declare-o no portfólio e mantenha sua evidência pendente.

## Referências opcionais

Fontes verificadas em 12/09/2026; ampliação do repertório, sem leitura obrigatória para a rubrica.

- [Google SRE: SLOs](https://sre.google/workbook/implementing-slos/) aprofunda negociação de metas e política de orçamento com produto.
- [Burn rate](https://sre.google/workbook/alerting-on-slos/) mostra outras combinações de janelas e severidades.
- [Regras Prometheus](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/) expande expressões, avaliações e otimização de consultas.
- [Práticas de alertas](https://prometheus.io/docs/practices/alerting/) ajuda a reduzir ruído e desenhar notificações acionáveis.
- [Blackbox exporter](https://github.com/prometheus/blackbox_exporter) detalha sondas DNS/TCP/TLS além do HTTP do exercício.
- [Postmortems](https://sre.google/sre-book/postmortem-culture/) aprofunda análise sem culpabilização e acompanhamento de ações.
