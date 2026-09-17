# Aplicação base do curso

Execute **LOCAL**, na raiz do repositório e com contexto `curso-kubeadm` selecionado:

```bash
kubectl config current-context
kubectl apply -k laboratorios/02-workloads/
kubectl rollout status deployment/web -n curso --timeout=180s
kubectl get pods,svc -n curso
kubectl port-forward -n curso svc/web 8080:80
```

Em outro terminal LOCAL: `curl -fsS http://127.0.0.1:8080/healthz`. O port-forward usa localhost e fica aberto até Ctrl+C. Ele verifica acesso via API a um backend, não todo o dataplane do Service; os testes de tráfego interno estão na [aula 02](../../curso/02-workloads.md) e na [aula 03](../../curso/03-rede.md).

Contrato usado pelos demais módulos: namespace `curso`, Deployment/Service `web`, seletor `app: web`, container `web`, porta do Service 80 e do container 8080 (`http`). `web-conteudo` contém `/`, `/healthz` e `/readyz`. O servidor BusyBox é propositalmente mínimo e não representa recomendação de servidor de produção.

A tag `busybox:1.37.0` publica AMD64 e ARM64. Tags ainda podem ser reconstruídas: registre o `imageID` efetivamente executado; no projeto final, fixe o digest do índice multiarch aprovado.

`extras/batch.yaml` não faz parte da base Kustomize. Aplique-o somente no exercício de Job/CronJob. Para removê-lo, use `kubectl delete -f laboratorios/02-workloads/extras/batch.yaml`; ele contém somente os recursos de batch do exercício.

`extras/daemonset.yaml` também fica fora da base: é o exemplo guiado de um agente não privilegiado por nó Linux elegível. Siga a explicação da aula 02 e remova apenas esse arquivo depois de comparar Pods e nós.

Mantenha a aplicação ao seguir para os demais módulos. A remoção de toda a base também remove o namespace `curso` e seus outros recursos; não use `kubectl delete -k` como limpeza rotineira de um exercício.

## Referências opcionais

- [Catálogo oficial Docker para BusyBox](https://github.com/docker-library/official-images/blob/master/library/busybox) — detalhes de publicação das imagens; consulta opcional, base conferida em 10/09/2026.
