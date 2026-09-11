# 09 — Entrega: Helm, Kustomize e GitOps

**Tempo sugerido:** 20–24 horas. **Pré-requisitos:** módulos 02–08, Helm e Git no cliente,
dois workers saudáveis e permissão administrativa apenas no cluster de laboratório.
Execute comandos na raiz do repositório, salvo indicação contrária.
Ao concluir, uma alteração revisada em Git deve produzir um rollout observável e reversível.

## O que muda em relação ao Swarm

Você já descreve estado desejado no Swarm; Kubernetes amplia a quantidade de recursos e
controllers envolvidos. Um chart é um pacote de manifests parametrizados. Uma release é
uma instalação desse pacote. Kustomize combina YAML e patches sem um motor de templates.
Nenhum dos dois, sozinho, monitora continuamente o Git em busca de alterações.

O Argo CD compara Git com o cluster e reconcilia diferenças. Sua CRD `Application`
registra um tipo novo na API; o pod `argocd-application-controller` executa a automação.
Instalar CRDs de uma ferramenta pronta é diferente de desenvolver seu próprio operator.
Não existe migração automática de uma Swarm Stack: examine cada requisito da aplicação.

| Ferramenta | Entrada | Trabalho feito |
|---|---|---|
| Helm | chart e values | renderizar, instalar e versionar releases |
| Kustomize | base e overlay | compor manifests para cada ambiente |
| Argo CD | Application apontando para Git | comparar e sincronizar estado |

Neste módulo `web-entrega` é gerenciado por Helm e `web-gitops` por Argo CD. Ambos
ficam em `curso-entrega`, separado da aplicação original `curso/web`. Não entregue o
mesmo Deployment simultaneamente a Helm, `kubectl apply` e Argo CD.

## Laboratório A — Inspecionar, instalar e reverter uma release

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

Neste momento apenas valide: o Argo CD fará a instalação definitiva. Altere `count`
para 3 no overlay e observe o YAML gerado; restaure 2 antes da etapa seguinte.
Crie como desafio um overlay `homologacao` com namespace e réplicas diferentes.
Use um patch explícito para mudar resources; não copie toda a base.

Kustomize embutido no kubectl varia com a versão do cliente. Registre
`kubectl version --client` junto da saída gerada. Os exemplos usam `replicas` e
`resources`, sem depender de campos obsoletos como `bases`.

## Laboratório C — Bootstrap do Argo CD

Instale uma release estável compatível com Kubernetes 1.35 e fixe o tag exato. Na
[página de releases](https://github.com/argoproj/argo-cd/releases), consulte também a
matriz de versões testadas. Não deixe `stable` ou `HEAD` como versão da instalação.

```bash
read -r -p 'Tag do Argo CD revisado (ex.: vX.Y.Z): ' ARGOCD_VERSION
test -n "$ARGOCD_VERSION"
kubectl create namespace argocd
kubectl apply -n argocd --server-side \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
kubectl -n argocd rollout status deployment/argocd-server --timeout=5m
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
pela interface; não cole credenciais em evidências, commits ou screenshots.

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

Publique este curso em um repositório Git seu. Em
[`argocd.yaml`](../laboratorios/09-entrega/argocd.yaml), ajuste as duas URLs e a branch.
Repositório público com material de laboratório simplifica a primeira execução; um
privado exige credencial de leitura adicionada ao Argo CD, fora do Git.
Faça commit/push dos manifests antes de criar a Application.

```bash
kubectl apply -f laboratorios/09-entrega/argocd.yaml
kubectl -n argocd get applications
kubectl -n curso-entrega get deployment,service,pods
```

Espere `Synced` e `Healthy`; na interface consulte o commit aplicado e os eventos de
sincronização. `AppProject` limita o destino e os tipos de recursos permitidos, mas
não substitui a segurança do próprio Argo CD, dos repositórios e de seus administradores.

## Drift, rollback e autoria da alteração

```bash
kubectl -n curso-entrega scale deployment/web-gitops --replicas=5
kubectl -n curso-entrega get deployment web-gitops -w
```

O `selfHeal` configurado deve devolver o estado para duas réplicas após reconciliação.
Agora altere `count` para 3 no Git, revise o diff, faça commit/push e observe a
convergência. Reverter o commit é o rollback coerente com GitOps.
Um `kubectl rollout undo` isolado pode ser sobrescrito pelo estado ainda presente no Git.

`prune: false` exige remover recursos obsoletos deliberadamente. Ao habilitar prune em
outro exercício, revise a exclusão antes do sync. Exclusão de PVC exige decisão de dados,
não apenas um diff verde. Não habilite `allowEmpty` sem entender a consequência.

## Pipeline que você deve desenhar

O CI compila, testa, gera SBOM, analisa vulnerabilidades e publica uma imagem identificada
por digest. Uma revisão atualiza o digest no repositório de deploy. Argo CD sincroniza.
A credencial do CI não precisa ser `cluster-admin`. Valide manifests renderizados no CI,
pois o YAML de um template Helm ainda não é um recurso Kubernetes.

As tags do laboratório simplificam o estudo. No projeto final, registre o digest do
índice multi-arquitetura ou do artefato da arquitetura correta; valide procedência e
assinatura com a política escolhida. Uma imagem assinada ainda pode conter vulnerabilidades.

## Entrega, avaliação e limpeza

Salve o diff de uma mudança, histórico Helm, commit sincronizado, captura textual do
drift corrigido e a recuperação do rollout ruim. Remova tokens e endpoints privados.

Você passa quando consegue explicar release versus chart, renderizar sem instalar,
reverter uma mudança de forma consistente com Git e diagnosticar um `OutOfSync`.
Desafio autônomo: transportar um serviço real do Swarm para o chart, com testes HTTP,
configuração externa e promoção entre dois ambientes sem duplicar os templates.

```bash
# Exclusão intencional apenas dos recursos deste módulo; Argo não tem finalizer aqui.
kubectl -n argocd delete application curso-web
helm uninstall web-entrega -n curso-entrega
kubectl -n curso-entrega delete deployment web-gitops
kubectl -n curso-entrega delete service web-gitops
```

Mantenha Argo CD para o projeto final. Não apague CRDs indiscriminadamente: remover uma
CRD pode eliminar todas as instâncias daquele tipo em todos os namespaces.

## Fontes primárias consultadas em 2026-09-10

- [Helm: templates](https://helm.sh/docs/chart_template_guide/getting_started/).
- [Kustomize no kubectl](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/).
- [Argo CD: instalação](https://argo-cd.readthedocs.io/en/stable/getting_started/).
- [Argo CD: sincronização automática](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/).
- [Argo CD: projetos](https://argo-cd.readthedocs.io/en/stable/user-guide/projects/).
