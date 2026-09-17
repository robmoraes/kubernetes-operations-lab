# Fontes e política de versões

Data de consulta desta edição: **2026-09-10**. O curso usa Kubernetes **1.35** como base didática, versão anunciada pela página oficial da CKA na consulta. Isso não significa “a versão mais nova” nem congela o exame: confira novamente a versão e as regras quando agendar.

Este catálogo é opcional para o aluno. A primeira execução segue os procedimentos completos de cada capítulo; não é necessário percorrer estes sites antes de começar. Para quem mantém ou adapta o curso, as fontes permitem verificar mudanças técnicas e administrativas.

## Catálogo de aprofundamento e manutenção

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

Cada módulo reúne suas fontes específicas na seção final `Referências opcionais`, explicando o ganho de cada consulta. Exercícios e rubricas são autorais; não são questões vazadas ou uma reprodução da prova.

## Na primeira execução da trilha

Mantenha a linha Kubernetes 1.35 e os conjuntos de componentes definidos nas aulas. O módulo 01 ensina a selecionar um patch publicado pelo APT, repetir a mesma versão nos nós e instalar o cliente local. Os capítulos seguintes fornecem versões ou consultas de API delimitadas para obter a combinação do laboratório. Registre a saída real em [PROGRESSO.md](../PROGRESSO.md), sem marcar o que ainda não instalou.

Se um artefato deixar de existir ou sua conta não oferecer a versão indicada, há uma divergência de ambiente a resolver. Não troque silenciosamente apenas um componente nem assuma que precisa dominar toda a documentação para continuar. Preserve o diagnóstico e revise a combinação como uma tarefa de manutenção.

## Para manter ou adaptar uma edição

1. Escolha uma minor suportada por Kubernetes, CNI, CSI e versão de SO.
2. Fixe o patch de kubeadm/kubelet/kubectl nos nós. Consulte o repositório APT e registre o pacote exato.
3. Leia notas da versão do CNI e do chart; registre também a versão das CRDs que ele requer.
4. Inspecione as arquiteturas das imagens: AMD64 no lab EC2 e outras variantes quando validar imagens multiarch.
5. Salve versões, datas e decisões em [PROGRESSO.md](../PROGRESSO.md). Não use `latest` como registro de versão.

Tags de imagens e charts são referências legíveis, mas só o digest identifica exatamente o conteúdo. Antes do projeto final, registre digests e lockfiles. Uma API válida no YAML pode não existir no servidor: valide também por dry-run no cluster de laboratório com o cliente compatível.

## Se uma fonte mudou durante a manutenção

Leia o release note, atualize versões e manifests em conjunto e refaça os testes de aceitação. Não troque silenciosamente apenas a versão do Kubernetes. Links são referências à fonte atual; instruções desta edição precisam ser reconciliadas com a versão que você escolheu.
