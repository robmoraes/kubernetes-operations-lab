# Validação desta edição

Data: **2026-09-10**. Esta página registra a validação do material, não a conclusão dos laboratórios pelo aluno. [PROGRESSO.md](../PROGRESSO.md) permanece sem atividades concluídas.

## Verificado localmente

| Verificação | Resultado |
|---|---|
| `make check` | Markdown, destinos de links locais, YAML/JSON, chaves YAML duplicadas e sintaxe Bash sem falhas |
| Traefik chart 41.5.0, Helm 4.2.3, target Kubernetes 1.35 | Values validados e 7 objetos renderizados; providers, portas e imagem conferidos |
| Chart de entrega | `helm lint` e `helm template` passaram |
| Kustomize dos módulos 02, 09 e 12 | Renderizações passaram; namespaces e referências de ConfigMaps conferidos |
| Terraform EKS, provider AWS 6.64.0 | `terraform fmt -check` e `terraform validate` passaram após `init -backend=false`; lockfile mantido |
| kubeconform 0.8.0, schemas Kubernetes 1.35.0, modo estrito | 34 arquivos com 62 objetos nativos válidos, zero erros e zero schemas ignorados nesse conjunto |
| Schemas dos renders Helm/Kustomize | 15 objetos adicionais válidos; há duplicação intencional entre fonte e renderização |

Os exemplos de falha continuam com **defeitos operacionais intencionais**. Um selector incorreto, readiness na porta errada ou StorageClass inexistente pode passar no schema e ainda quebrar o comportamento. Essa diferença faz parte do curso.

## Limites do que foi verificado

Não houve `kubeadm init`, instalação em ARM, `kubectl apply`, `terraform plan/apply`, criação de EC2/EBS/EKS ou execução de incidentes. Disponibilidade de imagens, quotas, IAM efetivo, latência, TLS entre componentes e disponibilidade após falhas precisam dos testes de aceitação das aulas.

Gateway, HTTPRoute, AppProject e Application dependem dos schemas de suas CRDs externas e não entram no total de recursos nativos validado pelo kubeconform. Instale as versões indicadas, valide pelo servidor e observe status/controller. Configurações Prometheus/blackbox passaram na leitura de YAML e revisão, mas não foram submetidas ao parser do `promtool` nesta edição; execute a verificação apropriada à versão antes de expandir as regras.

O cliente kubectl disponível para renderização offline foi 1.31.0 (Kustomize 5.4.2); ele não foi conectado ao cluster e não é o cliente recomendado para o laboratório 1.35. Instale o cliente compatível indicado no módulo 01. Helm usado na validação foi baixado temporariamente e teve SHA256 conferido na fonte oficial; não foi instalado no sistema.

## Como manter o material

Execute `make check` após editar referências ou manifests. Para alterações no chart, rode os comandos `helm lint/template` do módulo 09. Para Terraform, rode `fmt` e `validate` antes do plano. Para manifests nativos renderizados, use kubeconform com schema da versão escolhida; não use `-ignore-missing-schemas` para transformar recursos não verificados em um relatório de sucesso.

Finalmente, valide o exemplo no cluster de laboratório com o dry-run do servidor quando aplicável e execute o teste funcional do capítulo. Registre versão, data e evidência. O curso só considera uma competência adquirida quando seu comportamento foi demonstrado.
