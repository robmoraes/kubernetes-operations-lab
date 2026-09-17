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

## Revisão pedagógica — 12/09/2026

A revisão segue a [especificação pedagógica](../SPEC-PEDAGOGICA.md). Os 13 módulos receberam pré-requisitos, objetivos observáveis, explicações e exemplos complementados, fechamento e referências opcionais finais. Houve revisão cruzada do conteúdo, incluindo a ordem de instalação de ferramentas, desafios antes sem exemplo e continuidade dos ambientes. O contrato editorial foi integrado a `make check`.

Lacunas concretas tratadas: instalação do kubectl na estação antes do primeiro uso; teste HTTP/DNS que permite concluir o módulo 01 sem depender do 02; demonstrações de DaemonSet, Secret fictício e Gateway TLS; procedimentos locais de IAM, CSRs e coleta de métricas; e preparação do auxiliar de restore/upgrade com retorno explícito ao cluster principal. EKS tem kubeconfig separado. Isso não transforma as aulas em referência exaustiva de cada tecnologia.

| Verificação desta revisão | Resultado |
| --- | --- |
| Testes do contrato editorial | 11 testes passaram: seções, ordem, links de leitura, referências e exceções para código |
| Estrutura dos capítulos | 13 capítulos aprovados; nenhum link externo de leitura no corpo obrigatório |
| `make check` | Links locais, fences, YAML/JSON e regras editoriais sem falhas |
| Blocos Bash das aulas | Análise `bash -n`, sem executar o conteúdo, passou nos 13 capítulos |
| Manifests nativos da árvore de laboratórios e fixture | kubeconform 0.8.0 estrito, schema 1.35.0: 69 objetos em 35 arquivos, zero inválidos/erros/ignorados nesse conjunto |
| Chart local de entrega | `helm lint` passou novamente |
| Traefik 41.5.0 com Helm 4.2.3 | Render do módulo 03 confirmou `ClusterIP`; render com values EKS confirmou `LoadBalancer`, classe NLB e source ranges `/32` |
| EBS CSI 2.63.1 e Metrics Server 3.13.0 | Renders aprovados; conferidos imagem, seletores e configuração TLS do Metrics Server |
| Renders Traefik EKS e AWS LBC 1.14.0 | 17 objetos nativos válidos no schema 1.35.0; GatewayClass e IngressClassParams excluídos explicitamente desse conjunto por dependerem de CRDs externas |
| Terraform | `fmt -check` passou; código de infraestrutura da edição anterior foi preservado |
| `git diff --check` | Sem erros de whitespace |

A inspeção de render encontrou uma correção técnica no values do Traefik: nesta versão, o tipo de Service é definido em `service.spec.type`. A chave anterior não expressava o `ClusterIP` pretendido. O baseline foi corrigido e o Service resultante foi conferido; aprovação de YAML ou schema dos values, isoladamente, não teria comprovado esse resultado.

Os totais de schemas descrevem conjuntos explícitos, não todos os documentos YAML do repositório. Values Helm, patches parciais, configurações de programas e recursos de CRDs têm contratos próprios. O IAM dinâmico passou por leitura de JSON e revisão de ações/recursos/condições, mas não foi validado em uma conta AWS. O exemplo de Secret contém somente texto público fictício, sem credencial utilizável.

Nenhuma instalação em cluster, chamada autenticada AWS, provisionamento, restore, upgrade, falha induzida ou envio ao Git remoto foi realizado nesta revisão. Os testes funcionais continuam sendo entregas do laboratório. Verificação estrutural e revisão editorial reduzem lacunas, mas não certificam aprendizagem, segurança de produção ou aprovação em exame.

## Trilha independente do ambiente de origem — 12/09/2026

A apresentação, o plano, os capítulos e os critérios de entrega foram revisados para
quem conhece Linux, containers, redes, DNS e TLS, sem exigir outro orquestrador,
aplicação própria ou acesso corporativo. Comparações entre plataformas ficam em
`extras/`, fora da rota principal. O inventário do módulo 00 agora inclui um cenário
autossuficiente e distingue requisitos, hipóteses e testes ainda não executados.

Os desafios de workloads, rede e entrega e o projeto final admitem os materiais
fornecidos. Para que a base HTTP stateless permita comprovar também recuperação de
dados, o módulo 12 acrescenta uma prática de backup e restauração de arquivo sintético
com o workload/PVC do módulo 04. O texto delimita o que esse teste comprova e não o
equipara à restauração de banco, volume inteiro ou perda de zona.

Validação desta alteração:

- Busca textual sem referências ao orquestrador de origem na apresentação, plano,
  módulos, avaliações, laboratórios, referências e orientação de evidências.
- Revisão editorial do percurso sem aplicação própria; preparação do módulo 00
  permanece sem execução de cluster e usa seu checklist específico.
- `make check` passou: 11 testes, estrutura dos 13 capítulos, links locais e sintaxe
  dos dados. Nenhum manifesto ou versão de ferramenta foi alterado nesta revisão.
- `bash -n` aprovou os 19 blocos shell dos módulos 09 e 12, sem executar seu conteúdo.
- `git diff --check` passou; caminhos de arquivos movidos foram revisados.

O registro cronológico pessoal foi preservado; entradas históricas não são requisitos
do curso. O nome do repositório, o histórico Git e as marcações de progresso foram
mantidos. Não houve provisionamento, execução do novo restore nem publicação remota.

## Laboratório AWS manual e reconstrução — 15/09/2026

O módulo 01 foi reeditado para a capacidade disponível: a primeira VPC, subnet,
rotas, SGs, EC2 Instance Connect Endpoint e três EC2 serão criados e destruídos
manualmente na AWS. A instalação kubeadm permanece manual. O Terraform passa a ser
usado somente depois dessa aprovação, para reconstruir o primeiro CP e preparar os
workers de futuras sessões; token, joins e restauração do estado continuam na
fronteira do aluno.

Foi adotado um schema único de tags para inventário e custo: `Projeto`, `Ambiente`,
`Modulo`, `ClusterName`, `Owner`, `CostCenter`, `ManagedBy`, `LabRun`,
`ExpiresOn` e `Name`. Os valores de `Name` usam o prefixo `kubelab`, seguido por
`LabRun` e pelo componente. `LabRun` é imutável e independente de `Modulo`;
`Modulo` é apenas contexto informativo de relatório. Conta, região e IDs persistidos
localmente definem o alvo da destruição; tags fazem a conferência cruzada. O material
explica que tags não impõem orçamento, expiração nem remoção automática e que
precisam ser ativadas para aparecer nos relatórios de custo.

Validação desta alteração:

- `make check` passou: 11 testes e verificação de 45 Markdown, 186 links, 91 YAML,
  3 JSON, 1 shell e 13 capítulos.
- `terraform fmt -check -recursive` e `terraform validate` passaram no laboratório
  01 com o provider já inicializado.
- A sintaxe do túnel, chave temporária e endpoint foi comparada à ajuda da AWS CLI
  v2 local; comportamento de SG, tags de custo e Free Tier foi reconferido nas fontes
  oficiais listadas no fim do módulo.
- `git diff --check` passou.

Não houve `terraform plan/apply`, chamada mutável à AWS, criação ou destruição de
recurso nesta revisão. Os comandos e o comportamento em conta real ainda precisam
ser comprovados pelo exercício do aluno.
