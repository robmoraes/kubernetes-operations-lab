# Correção do simulado A

Leia depois da tentativa. Uma solução alternativa é válida se cumprir os mesmos requisitos com escopo equivalente. Um recurso `Running` pode não estar Ready; YAML aceito pode não produzir o comportamento pedido.

## 1 — RBAC (10)

A Role contém apenas recurso `pods`, apiGroup vazio e verbos get/list/watch; RoleBinding referencia ServiceAccount auditor no namespace prova-a. A conta não recebe ClusterRoleBinding. Evidências:

```bash
kubectl auth can-i list pods --as=system:serviceaccount:prova-a:auditor -n prova-a
kubectl auth can-i list secrets --as=system:serviceaccount:prova-a:auditor -n prova-a
kubectl auth can-i list pods --as=system:serviceaccount:prova-a:auditor -n default
```

Resultado: yes/no/no. O usuário avaliador precisa poder impersonar essa conta. A anotação/label do Pod não concede RBAC.

## 2 — Kustomize (10)

Corrija a partir de `kubectl kustomize CAMINHO_DO_OVERLAY` e `kubectl -n prova-a get deploy relatorio -o yaml`. Deve existir uma base reutilizada pelo overlay, namespace prova-a, imagem pedida, requests/limits e label tanto no objeto quanto no Pod. Selector e Pod labels devem concordar. Deployment com sleep permanece ativo; uma Job seria outro ciclo de vida.

## 3 — CRD (5)

Verifique names/group/scope/versão/schema. A exigência de `destino` dentro de spec só vale se spec também for obrigatório no schema raiz. Deve haver `required: [spec]` na raiz e `required: [destino]` dentro de spec. O recurso válido aparece com `kubectl -n prova-a get relatorios`; uma tentativa numérica deve falhar no dry-run do servidor.

A CRD não deve lançar Pods sozinha: falta controller para implementar comportamento. Saber demonstrar essa ausência é parte da explicação, não defeito da solução.

## 4–5 — Workloads (15)

Para pagina, monte o ConfigMap como diretório `/www`, evite subPath se demonstrar atualização automática e execute `httpd -f -p 8080 -h /www`. Startup/readiness devem consultar um caminho existente. ConfigMap projetado pode levar algum tempo para atualizar; variáveis de ambiente só mudam ao recriar containers. Compare conteúdo por HTTP antes/depois e espere rollout quando necessário.

Contagem deve terminar Complete com os cinco números nos logs. `for i in 1 2 3 4 5; do echo "$i"; done` produz resultado adequado; manter Pod rodando com sleep não cumpre o ciclo de vida de Job.

## 6–8 — Rede (20)

Confira Service/EndpointSlice e resposta de cliente permitido:

```bash
kubectl -n prova-a get service pagina -o yaml
kubectl -n prova-a get endpointslice -l kubernetes.io/service-name=pagina
```

NetworkPolicy deve selecionar apenas app:pagina, policyTypes Ingress, origem `podSelector` acesso:permitido e portaTCP8080. Sem namespaceSelector, a origem está no mesmo namespace. Não use selector vazio nos destinos, pois isso restringiria todos os Pods. Um cliente sem label deve falhar por timeout e um com label deve responder, com o backend Ready. `port-forward` não serve como prova da política de tráfego entre Pods.

DNS deve resolver os nomes dos dois namespaces. Falha no nome curto não é evidência de Service ausente; o namespace do cliente muda o sufixo de busca.

## 9 — Storage (10)

Evidencie UID antigo/novo do Pod, mesmo UID de PVC/PV e conteúdo do marcador. Não basta reexecutar um comando que escreve o marcador na inicialização: ele deve ser criado só na primeira execução. Mostre `kubectl get pv NOME -o yaml` e a StorageClass. EBS restringe AZ, volume local restringe nó; ambos diferem de um filesystem compartilhado.

Retain preserva o recurso/dado após liberação, mas não cria backup. Delete pode apagar o disco quando o provisionador processar a exclusão. PVC Bound sozinho vale só a parte do binding, não a comprovação de persistência.

## 10 — Selector incorreto (10)

```bash
kubectl -n prova-a get pods -l app=api --show-labels
kubectl -n prova-a get endpointslice -l kubernetes.io/service-name=api
kubectl -n prova-a patch service api --type=merge -p '{"spec":{"selector":{"app":"api"}}}'
```

O Service usava app:api-antiga e não selecionava os Pods. Espere EndpointSlice pronto, teste HTTP a partir de um cliente e registre o corpo api-ok.

## 11 — Restrição impossível (10)

Eventos do Pod fila indicam ausência de nó que satisfaça selector. A correção de menor alcance é remover/corrigir o selector do template:

```bash
kubectl -n prova-a patch deployment fila --type=json -p '[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]'
kubectl -n prova-a rollout status deployment/fila --timeout=120s
```

Mudar um label em worker para um pool legítimo também pode funcionar, mas deve ser justificado e revertido ao terminar. Retirar o taint do CP não corrige um selector inexistente e amplia o impacto.

## 12 — Probe na porta errada (10)

Processo atende8080, probe usa9090. Containers Running com Pod não Ready levam a eventos de conexão recusada. Corrija a porta preservando a probe:

```bash
kubectl -n prova-a patch deployment saude --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/port","value":8080}]'
kubectl -n prova-a rollout status deployment/saude --timeout=120s
```

Arquive evidência antes/depois e a soma dos pontos em [PROGRESSO.md](../../PROGRESSO.md). Se precisou ler esta correção para completar, registre ajuda e refaça depois.
