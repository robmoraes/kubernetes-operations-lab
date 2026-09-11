# Trilha de certificações

**CKA é o alvo principal** por combinar instalação, administração e diagnóstico com a direção DevOps/SRE do curso. CKAD é uma trilha complementar de aplicação. CKS exige estudo adicional de segurança e aprovação prévia na CKA; os capítulos deste repositório não cobrem toda a CKS.

Na consulta de 2026-09-10, as páginas oficiais de CKA e CKAD anunciavam Kubernetes 1.35 e duração de duas horas. Verifique ambiente, documentação permitida e políticas novamente antes de comprar ou agendar. Fontes: [CKA](https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/), [CKAD](https://training.linuxfoundation.org/certification/certified-kubernetes-application-developer-ckad/), [CKS](https://training.linuxfoundation.org/certification/certified-kubernetes-security-specialist/).

## Mapa CKA

Pesos consultados na página oficial; a distribuição não determina quanto tempo você precisará para aprender cada tema.

| Domínio | Peso | Onde treinar | Prova de domínio |
|---|---|---|---|
| Arquitetura, instalação e configuração | 25% | 01, 06, 08, 09, 10 | kubeadm, RBAC, HA, upgrade, Helm/Kustomize, CRDs/operators, CRI/CNI/CSI |
| Workloads e scheduling | 15% | 02, 05 | rollback, configuração, probes, recursos, agendamento e HPA |
| Services e rede | 20% | 03, 06, 07 | DNS, EndpointSlices, tipos de Service, políticas, Ingress e Gateway API |
| Storage | 10% | 04 | PV/PVC, StorageClass, binding, acesso e recuperação |
| Troubleshooting | 30% | 07, 08 e falhas de todos os módulos | recuperar nó, runtime, API, rede, volumes e workload com evidências |

Não pule Gateway API, instalação de operators e Helm/Kustomize só porque materiais antigos de CKA não os abordam. O currículo mantido pela CNCF é a referência para verificar lacunas: [currículos oficiais](https://github.com/cncf/curriculum).

## Complemento CKAD

Depois dos módulos 02–07 e 09, faça os exercícios de [aplicações](ckad-complementar.md). Pratique workloads de batch, sidecars/init containers, probes, quotas, segurança do Pod e estratégias de implantação. Use seu conhecimento de construção de imagens e confirme suporte multiarch. A grade completa deve ser conferida na página oficial da CKAD; o curso não é um pacote oficial de preparação.

## Rotina de prova

Antes de cada tarefa, confira **contexto, namespace e host**. Use `kubectl explain` para descobrir campos e `--dry-run=client -o yaml` para gerar ponto de partida. Depois de aplicar, confira o resultado funcional: um `apply` bem-sucedido não significa tarefa concluída.

Treine sessões de 120 minutos com consultas limitadas ao conjunto de documentação autorizado na prova vigente. Reserve o fim para revisar tarefas, use SSH só quando o enunciado exigir e evite perder uma sessão inteira em um item.

Não faça `alias` ou mudanças persistentes de contexto em um shell compartilhado sem conferir onde o comando será executado. Nunca salve credentials de exame ou laboratório no portfólio.

## Quando considerar agendar

- Fez os dois simulados deste curso, depois os refez com estado novo sem decorar nomes.
- Atingiu a meta interna de 80/100 em duas sessões separadas e resolveu as lacunas identificadas.
- Executou os labs de kubeadm, backup/restore, upgrade, Gateway API e HPA, inclusive os que não aparecem em todos os simulados.
- Consegue explicar por que a correção funciona e qual é seu impacto.
- Conferiu o handbook, a versão e as regras no portal da certificação.

Treinos autorais não medem exatamente a dificuldade ou a nota da prova oficial. O resultado esperado é evidência de competência; aprovação e contratação dependem também do desempenho real e dos requisitos de cada vaga.
