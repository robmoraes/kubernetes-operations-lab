# Fontes e política de versões

Data de consulta desta edição: **2026-09-10**. O curso usa Kubernetes **1.35** como base didática, versão anunciada pela página oficial da CKA na consulta. Isso não significa “a versão mais nova” nem congela o exame: confira novamente a versão e as regras quando agendar.

## Material principal

| Assunto | Fonte primária |
|---|---|
| Instalar e manter kubeadm | [Instalação](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/), [criar cluster](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/) |
| Compatibilidade de versões | [Version skew policy](https://kubernetes.io/releases/version-skew-policy/) |
| Recursos e API | [Conceitos](https://kubernetes.io/docs/concepts/), [referência kubectl](https://kubernetes.io/docs/reference/kubectl/) |
| Diagnóstico | [Debug de clusters](https://kubernetes.io/docs/tasks/debug/debug-cluster/) |
| Currículos de certificação | [CNCF curriculum](https://github.com/cncf/curriculum), [CKA](https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/), [CKAD](https://training.linuxfoundation.org/certification/certified-kubernetes-application-developer-ckad/) |
| Condições de exame | [Portal de políticas da Linux Foundation](https://docs.linuxfoundation.org/tc-docs/certification) — consultar handbook e instruções na página da prova |
| etcd | [Operação](https://etcd.io/docs/v3.6/op-guide/), [recuperação](https://etcd.io/docs/v3.6/op-guide/recovery/) |
| EBS CSI | [Repositório mantido pela AWS](https://github.com/kubernetes-sigs/aws-ebs-csi-driver) |
| EKS | [Guia oficial](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html), [EKS Workshop](https://www.eksworkshop.com/) |

Cada módulo adiciona suas fontes específicas. Exercícios e rubricas são autorais; não são questões vazadas ou uma reprodução da prova.

## Antes de instalar

1. Escolha uma minor suportada por Kubernetes, CNI, CSI e versão de SO.
2. Fixe o patch de kubeadm/kubelet/kubectl nos nós. Consulte o repositório APT e registre o pacote exato.
3. Leia notas da versão do CNI e do chart; registre também a versão das CRDs que ele requer.
4. Inspecione as arquiteturas das imagens: ARM64 no lab EC2 e AMD64 se usar máquinas x86.
5. Salve versões, datas e decisões em [PROGRESSO.md](../PROGRESSO.md). Não use `latest` como registro de versão.

Tags de imagens e charts são referências legíveis, mas só o digest identifica exatamente o conteúdo. Antes do projeto final, registre digests e lockfiles. Uma API válida no YAML pode não existir no servidor: valide também por dry-run no cluster de laboratório com o cliente compatível.

## Se uma fonte mudou

Leia o release note, atualize versões e manifests em conjunto e refaça os testes de aceitação. Não troque silenciosamente apenas a versão do Kubernetes. Links são referências à fonte atual; instruções desta edição precisam ser reconciliadas com a versão que você escolheu.
