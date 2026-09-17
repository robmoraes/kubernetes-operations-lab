# 09 — Entrega: Helm, Kustomize e GitOps

## Antes de começar

Reserve **20–24 horas**. Conclua [workloads](02-workloads.md), [rede e instalação do Helm](03-rede.md),
[segurança](06-seguranca.md) e [diagnóstico](07-troubleshooting.md). Você deve reconhecer
Deployment, Service, readiness, rollout, namespace e permissões de uma ServiceAccount.
Use Kubernetes 1.35 com dois workers saudáveis, Helm instalado no módulo 03, kubectl,
curl e Git na estação. Os comandos partem da raiz deste repositório.
Confirme `helm version --short`, `git --version` e `kubectl config current-context`.
Use o cluster principal 1.35: o ensaio de upgrade do módulo 08 ocorre em outro cluster,
com retorno ao kubeconfig principal ao final. Não reverta versões de um cluster atualizado.
Se Git estiver ausente na estação Ubuntu, instale com `sudo apt-get install git`.

Tenha um repositório remoto seu e acesso para enviar commits; a conexão dele é
demonstrada abaixo. Publique somente material de laboratório, sem credenciais ou dados
privados. A instalação Argo CD exige administração **do cluster de laboratório** e cria
recursos de escopo global;
a aplicação permanece em `curso-entrega`. Use os arquivos em
[laboratorios/09-entrega](../laboratorios/09-entrega/).

## O que você vai conseguir fazer

- Renderizar e instalar um chart, alterar seus valores e recuperar uma release ruim.
- Compor um overlay com réplicas e resources próprios, explicando o YAML gerado.
- Instalar Argo CD, conectar seu Git e comprovar sincronização, correção de drift e rollback.
- Distinguir versão do chart, revisão da release, commit de deploy e digest da imagem.

Assinatura de artefatos, um servidor de CI completo e operação multi-tenant do Argo CD
são aprofundamentos; os conceitos de procedência e privilégio mínimo serão usados aqui.

## Empacotamento, composição e reconciliação

Os manifests descrevem o estado desejado dos recursos Kubernetes; os controllers
reconciliam esse estado com o cluster. Um chart é um pacote de manifests parametrizados.
Uma release é uma instalação desse pacote. Kustomize combina YAML e patches sem um
motor de templates.
Nenhum dos dois, sozinho, monitora continuamente o Git em busca de alterações.

O Argo CD compara Git com o cluster e reconcilia diferenças. Uma **CRD** é a definição
que registra um tipo novo na API; um objeto desse tipo é uma instância da definição.
A instalação registra `Application`: você cria uma instância com caminho Git e destino.
O **controller**, executado como pod `argocd-application-controller`, observa essas
instâncias e aplica os manifests. A definição armazenada no etcd não executa código.
Instalar CRDs de uma ferramenta pronta é diferente de desenvolver seu próprio operator.
Empacotar manifests exige preservar os requisitos da aplicação: portas, configuração,
identidade, recursos e dados continuam precisando de decisões explícitas.

| Ferramenta | Entrada | Trabalho feito |
|---|---|---|
| Helm | chart e values | renderizar, instalar e versionar releases |
| Kustomize | base e overlay | compor manifests para cada ambiente |
| Argo CD | Application apontando para Git | comparar e sincronizar estado |

Neste módulo `web-entrega` é gerenciado por Helm e `web-gitops` por Argo CD. Ambos
ficam em `curso-entrega`, separado da aplicação original `curso/web`. Não entregue o
mesmo Deployment simultaneamente a Helm, `kubectl apply` e Argo CD.

## Laboratório A — Inspecionar, instalar e reverter uma release

Abra `chart/Chart.yaml`, `values.yaml` e `templates/workload.yaml` do laboratório.
`Chart.yaml` identifica o pacote; `values.yaml` fornece valores padrão; expressões como
`{{ .Values.replicaCount }}` são substituídas durante o render. `--set replicaCount=3`
substitui um valor sem editar o template. A release `web-entrega` determina nome e labels.
O resultado será um Deployment e um Service, não um novo tipo de API.

```bash
kubectl config current-context
kubectl create namespace curso-entrega
helm lint laboratorios/09-entrega/chart
helm template web-entrega laboratorios/09-entrega/chart -n curso-entrega
helm upgrade --install web-entrega laboratorios/09-entrega/chart \
  -n curso-entrega --wait --timeout 3m
helm list -n curso-entrega
kubectl -n curso-entrega rollout status deployment/web-entrega
kubectl -n curso-entrega port-forward service/web-entrega 8089:80
```

Em outro terminal, `curl -f http://127.0.0.1:8089/` deve retornar HTML. Pare o
port-forward com Ctrl+C depois da prova. O chart usa porta interna 8080, rootfs
somente leitura e `/tmp` descartável; o Service oferece porta 80.
Leia os manifests renderizados e explique como o selector chega aos pods.

Agora provoque um rollout ruim: uma imagem com tag inexistente. O timeout é esperado.

```bash
helm upgrade web-entrega laboratorios/09-entrega/chart \
  -n curso-entrega --set image=nginxinc/nginx-unprivileged:tag-inexistente-curso \
  --wait --timeout 60s
kubectl -n curso-entrega get pods
kubectl -n curso-entrega get events --sort-by=.metadata.creationTimestamp
helm history web-entrega -n curso-entrega
helm rollback web-entrega 1 -n curso-entrega --wait --timeout 3m
```

Use a revisão saudável mostrada no histórico se não for a primeira execução.
`helm rollback` reverte objetos da release; não desfaz migrações de banco nem recupera
arquivos. Explique por que a estratégia RollingUpdate pode preservar pods saudáveis
enquanto os novos ficam em `ImagePullBackOff`.

## Laboratório B — Construir um overlay

```bash
kubectl kustomize laboratorios/09-entrega/kustomize/overlays/lab
kubectl apply --dry-run=server -k laboratorios/09-entrega/kustomize/overlays/lab
```

Neste momento apenas valide: o Argo CD fará a instalação definitiva. A base contém
os objetos comuns. O overlay aponta para ela, define namespace e altera as réplicas.
Altere `count` para 3, renderize e encontre `spec.replicas: 3`; depois restaure 2.

Para aprender um patch, acrescente temporariamente este bloco ao `kustomization.yaml`
do overlay `lab`, no mesmo nível de `resources` e `replicas`:

```yaml
patches:
  - target:
      kind: Deployment
      name: web-gitops
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/cpu
        value: 75m
```

Renderize de novo: somente o request de CPU do primeiro container muda de `50m` para
`75m`; selector, imagem e Service continuam presentes. `target` escolhe o objeto e
`path` escolhe o campo. Remova esse bloco temporário para voltar ao baseline.
O desafio de homologação ao fim usará exatamente esses mecanismos.

Kustomize embutido no kubectl varia com a versão do cliente. Registre
`kubectl version --client` junto da saída gerada. Os exemplos usam `replicas` e
`resources`, sem depender de campos obsoletos como `bases`.

## Laboratório C — Bootstrap do Argo CD

Este laboratório fixa **Argo CD v3.3.14**, da linha 3.3 testada pelo projeto com
Kubernetes 1.35. A versão explícita torna a instalação reproduzível. O manifest instala
API/UI, repo-server, controller, Redis, ServiceAccounts, RBAC e CRDs. Aguarde os componentes.

```bash
ARGOCD_VERSION=v3.3.14
kubectl create namespace argocd
kubectl apply -n argocd --server-side \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
kubectl -n argocd rollout status deployment/argocd-server --timeout=5m
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=5m
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=5m
kubectl -n argocd get pods
```

Essa instalação cria CRDs e RBAC de escopo de cluster: é uma instalação de plataforma,
não um manifest de aplicação. Argo CD consome CPU/memória; ajuste workers se necessário.
No laboratório, use port-forward e mantenha a interface sem exposição pública.

```bash
kubectl -n argocd port-forward service/argocd-server 8090:443
```

Abra `https://localhost:8090`. O certificado inicial é local/autossinado.
Consulte a credencial temporária em outro terminal, faça login com `admin` e troque-a
pela interface, em **User Info → Update Password**; não cole credenciais em evidências,
commits ou screenshots. Depois de testar a nova senha em outra sessão, apague somente
o Secret da senha inicial com `kubectl -n argocd delete secret argocd-initial-admin-secret`.

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

No serviço Git que você já utiliza, crie um repositório de laboratório. Na estação,
confira `git remote -v`. Se ainda não houver `origin`, adicione-o com
`git remote add origin URL_DO_SEU_REPOSITORIO`; se houver, confirme que é seu antes de
enviar qualquer coisa. Configure nome/email do Git se necessário, confira `git status`,
selecione apenas os arquivos do curso a publicar e faça commit/push para a branch
escolhida. Não use `git add .` sem revisar arquivos locais de credenciais ou estado.

Em
[`argocd.yaml`](../laboratorios/09-entrega/argocd.yaml), ajuste as duas URLs e a branch.
Repositório público com material de laboratório simplifica a primeira execução; um
privado exige credencial de leitura: na interface Argo CD, **Settings → Repositories
→ Connect Repo**, escolha HTTPS, informe a mesma URL, usuário e token com leitura
apenas desse repositório; **Connect** deve mostrar **Successful**. Crie o token no
serviço Git que você utiliza e não o insira no manifesto. A autenticação para push
continua na estação, separada da credencial somente leitura usada pelo Argo CD.
Faça commit/push dos manifests antes de criar a Application.

```bash
kubectl apply -f laboratorios/09-entrega/argocd.yaml
kubectl -n argocd get applications
kubectl -n curso-entrega get deployment,service,pods
```

Espere `Synced` e `Healthy`; na interface consulte o commit aplicado e os eventos de
sincronização. `AppProject` limita o destino e os tipos de recursos permitidos, mas
não substitui a segurança do próprio Argo CD, dos repositórios e de seus administradores.
Se não convergir, selecione a Application e veja **Conditions**: falha de autenticação
pede revisar o repositório; caminho inexistente pede conferir a árvore da branch;
recurso não permitido pede comparar o render com o AppProject. Encerre o diagnóstico
quando URL/branch/caminho corresponderem ao commit e a aplicação estiver saudável.

## Drift, rollback e autoria da alteração

```bash
kubectl -n curso-entrega scale deployment/web-gitops --replicas=5
kubectl -n curso-entrega get deployment web-gitops -w
```

O `selfHeal` configurado deve devolver o estado para duas réplicas após reconciliação.
Agora altere `count` para 3 no Git, revise o diff, faça commit/push e observe a
convergência. Anote o hash do commit dessa única mudança com `git log -1 --oneline`.
Execute `git revert HASH_DESSA_MUDANCA`, revise o novo commit e envie-o com `git push`.
O resultado esperado é retornar a duas réplicas com um **novo** commit que documenta
a reversão. Não reescreva a branch compartilhada. Esse é o rollback coerente com GitOps.
Um `kubectl rollout undo` isolado pode ser sobrescrito pelo estado ainda presente no Git.

`prune: false` exige remover recursos obsoletos deliberadamente. Ao habilitar prune em
outro exercício, revise a exclusão antes do sync. Exclusão de PVC exige decisão de dados,
não apenas um diff verde. Não habilite `allowEmpty` sem entender a consequência.

## Pipeline que você deve desenhar

O **CI** executa verificações antes da entrega. Um fluxo de produção compila e testa,
gera um **SBOM** (inventário de componentes), analisa vulnerabilidades e publica imagem
identificada por **digest** (hash do conteúdo). Uma revisão atualiza o digest no Git
de deploy. Argo CD sincroniza. Tag é um nome potencialmente mutável; digest identifica
o artefato, enquanto commit identifica a configuração que o utiliza.
A credencial do CI não precisa ser `cluster-admin`. Valide manifests renderizados no CI,
pois o YAML de um template Helm ainda não é um recurso Kubernetes.

Faça uma prova local de procedência: após o rollout saudável, execute
`kubectl -n curso-entrega get pods -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.containerStatuses[*].imageID}{"\n"}{end}'`.
Relacione o hash retornado à imagem declarada, ao commit e à arquitetura dos workers.
Esse registro prova qual artefato foi executado; não prova ausência de vulnerabilidades.
No projeto final, registre essa relação e a origem confiável da imagem. Verificação
criptográfica de assinaturas pode ser acrescentada com uma política explícita.

## Desafio independente e limpeza

Salve o diff de uma mudança, histórico Helm, commit sincronizado, captura textual do
drift corrigido e a recuperação do rollout ruim. Remova tokens e endpoints privados.

Crie o overlay `homologacao` com namespace `curso-homologacao`, três réplicas e CPU
`75m`, usando o patch demonstrado. Renderize sem aplicar e compare com `lab`.
Depois prepare uma cópia do chart para a aplicação-base de
[laboratorios/02-workloads](../laboratorios/02-workloads/), incorporando sua configuração
externa e preservando as rotas de saúde praticadas no módulo 02. Use outro nome de
release para manter a aplicação-base disponível aos demais exercícios. Ajuste juntos
os nomes, as referências ao ConfigMap e os selectors; o YAML renderizado deve mostrar
recursos coerentes e sem colisão com `curso/web`.

Se escolheu uma aplicação própria no módulo 00, você pode usar seu componente stateless
no mesmo desafio. A origem da aplicação não altera os critérios. O desafio termina
quando os overlays `lab` e `homologacao` renderizam sem erros, o chart adaptado serve
HTTP e carrega sua configuração no laboratório, e a reversão Git foi demonstrada.
Registre a release criada e desinstale-a por esse nome após guardar as evidências.

```bash
# Exclusão intencional apenas dos recursos deste módulo; Argo não tem finalizer aqui.
kubectl -n argocd delete application curso-web
helm uninstall web-entrega -n curso-entrega
kubectl -n curso-entrega delete deployment web-gitops
kubectl -n curso-entrega delete service web-gitops
```

Mantenha Argo CD para o projeto final. Não apague CRDs indiscriminadamente: remover uma
CRD pode eliminar todas as instâncias daquele tipo em todos os namespaces.

## Fechamento

Você conectou três mecanismos: templates produzem objetos, overlays variam configurações
e um controller mantém o estado descrito no Git. Explique por que uma CRD sozinha não
realiza deploy e por que um rollback de release não restaura um banco.

Avance com cinco evidências: chart renderizado e HTTP saudável; erro de imagem recuperado;
overlay com patch comprovado; drift corrigido pelo Argo CD; commit de reversão sincronizado.
Sem essas provas, registre a etapa pendente em vez de marcar o capítulo como praticado.
Operação multi-tenant, assinatura de imagens e plataforma completa de CI ficam fora do
laboratório guiado; nenhuma leitura abaixo é necessária para concluir esses cinco resultados.

## Referências opcionais

Fontes verificadas em 12/09/2026; use para aprofundar mecanismos já praticados.

- [Helm: templates](https://helm.sh/docs/chart_template_guide/getting_started/) amplia funções, condições e composição de charts.
- [Kustomize no kubectl](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) apresenta geradores e transformações além do patch exercitado.
- [Argo CD: instalação](https://argo-cd.readthedocs.io/en/stable/getting_started/) detalha modos de acesso e administração da ferramenta.
- [Versões testadas](https://argo-cd.readthedocs.io/en/stable/operator-manual/tested-kubernetes-versions/) ajuda a planejar uma atualização futura da combinação Kubernetes/Argo.
- [Sincronização automática](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/) aprofunda tentativas, prune e políticas de reconciliação.
- [Projetos](https://argo-cd.readthedocs.io/en/stable/user-guide/projects/) expande a segregação entre equipes e destinos.
