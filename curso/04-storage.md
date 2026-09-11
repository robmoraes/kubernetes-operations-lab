# 04 — Persistência: do arquivo ao disco da AWS

Reserve **16–20 horas**. Pré-requisitos: módulos 01–03, dois workers EC2 na mesma AZ, acesso administrativo ao laboratório, Helm e AWS CLI na estação. Alternativa sem AWS: PV local, ao final. Todos os `kubectl`, `helm` e `aws` abaixo rodam na **estação**, na raiz deste repositório, salvo indicação contrária. Confirme `kubectl config current-context` antes de cada sessão.

Seu resultado será escrever um arquivo, substituir o pod, mudar seu worker e demonstrar o que persiste. Você também precisa explicar quando essa movimentação é impossível.

## O que você precisa compreender

No Swarm, um volume local pode existir com o mesmo nome em vários hosts e ainda conter dados diferentes. Kubernetes não torna um disco local distribuído. Ele separa o pedido da aplicação (`PVC`), o recurso disponível (`PV`) e o mecanismo de provisionamento (`StorageClass` + CSI). PVC é namespaced; PV e StorageClass pertencem ao cluster. O vínculo entre um PVC e um PV é individual.

| Recurso | Sobrevive a quê? | Quem fornece os bytes? |
|---|---|---|
| Camada gravável do container | Não conte com ela após recriar o container | Disco do nó |
| `emptyDir` | Reinício de container dentro do mesmo pod, não exclusão do pod | Nó; ou RAM com `medium: Memory` |
| PV `local` | Recriação do pod no mesmo nó; não perda do disco/nó | Diretório ou disco daquele nó |
| PVC com EBS | Recriação do pod e troca de nó dentro da AZ | Volume EBS |
| Serviço de objetos | Independente do pod, por sua API | S3 ou equivalente |

`ReadWriteOnce` limita a montagem gravável a **um nó**, não necessariamente um pod. `ReadWriteOncePod`, quando suportado pelo CSI e seus sidecars, impõe um pod. `ReadWriteMany` exige um backend com essa capacidade; mudar o YAML não transforma gp3 em filesystem compartilhado. StatefulSet cria identidade estável e pode gerar um PVC por réplica; não replica os dados do banco. [PV e modos de acesso](https://kubernetes.io/docs/concepts/storage/persistent-volumes/).

## Laboratório A — Um EBS conhecido, permissões restritas

Comece pelo provisionamento **estático**: crie o EBS explicitamente e registre-o como PV. Isso deixa visível cada parte e permite restringir escrita do driver a um disco e dois workers. Você criará recursos cobrados na AWS. Use apenas conta e instâncias do laboratório.

1. Liste os workers, seus nomes e IDs EC2; confira a zona real na AWS. Não invente labels de zona.

```bash
kubectl get nodes -o wide
aws sts get-caller-identity
aws ec2 describe-instances --region sa-east-1 \
  --filters Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].[InstanceId,PrivateIpAddress,Placement.AvailabilityZone,IamInstanceProfile.Arn]' \
  --output table
```

Use sua região em todos os comandos. Os exemplos `sa-east-1a`, `worker-1`, IDs e ARNs são placeholders; os nomes dos nós são os mostrados por `kubectl`, não necessariamente o nome da tag EC2. Se os workers estiverem em zonas distintas, não será possível executar a prova de mobilidade deste laboratório.

2. Crie **um volume novo e vazio**, com a chave gerenciada padrão `aws/ebs`. Uma CMK própria exige política KMS adicional, fora deste laboratório inicial.

```bash
aws ec2 create-volume --region sa-east-1 --availability-zone sa-east-1a \
  --volume-type gp3 --size 4 --encrypted --kms-key-id alias/aws/ebs \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=curso-storage},{Key=Curso,Value=kubernetes}]'
```

Anote `VolumeId`, aguarde `aws ec2 wait volume-available --region sa-east-1 --volume-ids VOL_ID` e confira tamanho, zona e estado. Não use o EBS raiz de uma EC2: o CSI poderá formatar o volume vazio ao montá-lo.

3. Prepare a identidade AWS do controller. O diretório do lab contém `iam-static.template.json` e `trust-ec2.json`. Copie o primeiro para uma área local de trabalho, substitua **todos** os placeholders por região, conta, volume e IDs dos dois workers. A política permite apenas leitura de metadados e Attach/Detach nos três ARNs. Não permite criar, apagar ou expandir volumes. `Resource: "*"` nos `Describe` existe porque essas consultas EC2 não têm esse mesmo escopo por ARN.

```bash
# Estação: somente conta de laboratório, após revisar o JSON preenchido.
aws iam create-role --role-name CursoEbsController \
  --assume-role-policy-document file://laboratorios/04-storage/trust-ec2.json
aws iam put-role-policy --role-name CursoEbsController \
  --policy-name CursoUmVolume --policy-document file:///CAMINHO/iam-static.json
aws iam create-instance-profile --instance-profile-name CursoEbsController
aws iam add-role-to-instance-profile --instance-profile-name CursoEbsController \
  --role-name CursoEbsController
aws ec2 associate-iam-instance-profile --region sa-east-1 \
  --instance-id ID_WORKER_1 --iam-instance-profile Name=CursoEbsController
```

**Antes de associar:** confirme no passo 1 que o worker escolhido não tem instance profile. Se já tiver (por exemplo, SSM), não o substitua; use um worker descartável sem perfil, ou incorpore a política revisada à role exclusiva daquele worker. Uma role compartilhada com outras máquinas ampliaria o escopo de identidade. IAM pode levar alguns instantes para propagar.

Instance profile é uma **exceção didática**: qualquer workload que alcance IMDS nesse worker pode usar a mesma identidade. Não agende aplicações não confiáveis ali. Em produção, projete credenciais temporárias por workload com OIDC/web identity e uma trust policy restrita a issuer, audience e ServiceAccount. Em kubeadm, anotar `eks.amazonaws.com/role-arn` sozinho não configura issuer público, trust ou injeção de token; EKS Pod Identity também não é um recurso nativo desse cluster. [Instalação self-managed e credenciais](https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/docs/install.md).

4. O node plugin precisa dos metadados EC2; o controller precisa de credenciais. Para esta configuração de laboratório com pods sem host network, exija IMDSv2 e hop limit 2 **nos dois workers**. Isso permite alcançar IMDS a partir de pods e reforça a limitação de segurança acima.

```bash
aws ec2 modify-instance-metadata-options --region sa-east-1 \
  --instance-id ID_WORKER_1 --http-tokens required --http-endpoint enabled \
  --http-put-response-hop-limit 2
# Repita explicitamente para ID_WORKER_2.
kubectl label node worker-1 curso.ebs/controller=true
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update
helm search repo aws-ebs-csi-driver/aws-ebs-csi-driver --versions
```

Selecione e registre uma versão publicada do chart compatível com Kubernetes 1.35; não instale `master` ou uma versão arbitrariamente nova. Revise `helm show values ... --version VERSAO` e preencha `controller.region` no arquivo fornecido. Ele fixa **apenas o controller CSI**, uma réplica para o lab, no nó com IAM. O node DaemonSet continuará nos workers.

```bash
helm upgrade --install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
  --namespace kube-system --version VERSAO_CHART \
  -f laboratorios/04-storage/ebs-values.yaml
kubectl -n kube-system rollout status deployment/ebs-csi-controller --timeout=180s
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-ebs-csi-driver -o wide
kubectl get csinode -o yaml
kubectl get nodes -L topology.ebs.csi.aws.com/zone
```

Se a label de topologia CSI estiver ausente, corrija IMDS/registro do driver antes de criar PVC. A política estática não sustenta provisionamento dinâmico. Erros `UnauthorizedOperation` devem ser resolvidos identificando ação, role efetiva e ARN; não adicionando `AdministratorAccess`.

5. Edite `ebs-static.yaml`: `volumeHandle` recebe o VolumeId e `nodeAffinity` recebe a AZ real. O PV reserva o vínculo ao PVC `curso-storage/dados`; `storageClassName: ""` evita uma classe default inesperada.

```bash
kubectl apply -f laboratorios/04-storage/namespace.yaml
kubectl apply --dry-run=server -f laboratorios/04-storage/ebs-static.yaml
kubectl apply -f laboratorios/04-storage/ebs-static.yaml
kubectl apply -f laboratorios/04-storage/arquivo.yaml
kubectl -n curso-storage rollout status deployment/arquivo --timeout=180s
kubectl -n curso-storage get pvc,pods -o wide
kubectl get pv curso-ebs
kubectl -n curso-storage exec deploy/arquivo -- sh -c 'date -u > /dados/prova.txt; sync; cat /dados/prova.txt'
```

O namespace é exclusivo. O container escreve como UID 1000, e `fsGroup` permite escrita no volume. A estratégia `Recreate` e uma réplica evitam tentar montar o mesmo RWO em dois nós durante um rollout.

6. Recrie o pod com `kubectl -n curso-storage rollout restart deployment/arquivo`, aguarde o rollout e leia `/dados/prova.txt`. Compare conteúdo e UID do pod; persistência deve continuar, identidade do pod muda.

Para provar outro nó, registre o nó atual e use `kubectl cordon NOME_REAL` seguido de `rollout restart` no Deployment. Cordon impede novos pods ali, mas não remove pods existentes. Com dois workers compatíveis e sem regras extras, a nova réplica irá ao outro worker. Aguarde o detach/attach; leia o arquivo e execute `kubectl uncordon NOME_REAL` ao terminar. Se o worker cordonado hospeda o controller CSI, o pod existente do controller continua rodando; não o reinicie durante o teste.

**Evidência:** capture PVC Bound, `spec.csi.volumeHandle` do PV, nó antes/depois, conteúdo igual e `aws ec2 describe-volumes --volume-ids VOL_ID --region sa-east-1`. Não force detach com o escritor ainda ativo. EBS não acompanha o pod para outra AZ.

## Laboratório B — Provisionamento dinâmico e expansão

Agora entenda o fluxo habitual: PVC → provisioner CSI → EBS novo + PV → vínculo → montagem. `WaitForFirstConsumer` coordena zona do disco com o agendamento inicial; não copia discos entre zonas. Um PVC sozinho pode ficar Pending legitimamente enquanto não houver consumidor. [StorageClasses](https://kubernetes.io/docs/concepts/storage/storage-classes/).

Antes desta etapa, adapte a identidade do controller para provisionamento dinâmico usando a [política upstream da versão escolhida](https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/docs/example-iam-policy.json). Compare as condições por tags e restrinja a conta/região e recursos do lab onde cada ação permitir. Preserve condições em `CreateVolume`, `CreateTags` e `DeleteVolume`; não substitua por `ec2:*`. O lab A já está completo se você ainda não quer ampliar a identidade. A política estática intencionalmente fará o lab B falhar com acesso negado.

```bash
kubectl apply -f laboratorios/04-storage/ebs-gp3.yaml
kubectl apply -f laboratorios/04-storage/dinamico.yaml
kubectl -n curso-storage get pvc dados-dinamicos
kubectl -n curso-storage describe pvc dados-dinamicos
# O Pod consumidor está no mesmo arquivo; aguarde Ready e PVC Bound.
kubectl -n curso-storage wait --for=condition=Ready pod/arquivo-dinamico --timeout=180s
kubectl -n curso-storage patch pvc dados-dinamicos --type=merge \
  -p '{"spec":{"resources":{"requests":{"storage":"6Gi"}}}}'
kubectl -n curso-storage get pvc dados-dinamicos -w
```

`allowVolumeExpansion` e permissões `ModifyVolume` são necessárias. Compare request, status capacity, filesystem via `df -h /dados` e AWS; expansão pode levar tempo. Redução não é o caminho inverso. `Retain` mantém o backend após liberar o vínculo; **não é backup**, não impede apagar arquivos dentro do pod e não protege contra perda de AZ. Snapshot exige snapshot-controller, CRDs e driver compatível; consistência de banco pode exigir flush/quiesce ou backup lógico.

## Laboratório C — StatefulSet e um PVC por réplica

Requer que o provisionamento dinâmico do lab B já funcione; criará **mais dois EBS de 4 GiB**. O StatefulSet fornecido cria `registro-0` e `registro-1`, cada qual com PVC próprio, e um Service headless para identidade DNS. Estude `volumeClaimTemplates` e compare ao Deployment que compartilha um único claim. [StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/).

```bash
kubectl apply -f laboratorios/04-storage/statefulset.yaml
kubectl -n curso-storage rollout status statefulset/registro --timeout=240s
kubectl -n curso-storage get pods,pvc
kubectl -n curso-storage exec registro-0 -- sh -c 'echo replica-zero > /dados/prova.txt; sync'
kubectl -n curso-storage exec registro-1 -- ls -la /dados
kubectl -n curso-storage delete pod registro-0
kubectl -n curso-storage wait --for=condition=Ready pod/registro-0 --timeout=180s
kubectl -n curso-storage exec registro-0 -- cat /dados/prova.txt
```

O arquivo não deve aparecer na réplica 1: StatefulSet **não replica arquivos**. Depois da recriação, `registro-0` mantém nome e claim, mas recebe UID novo. Como desafio, escale para uma réplica, observe que `dados-registro-1` permanece, volte para duas e comprove seu conteúdo anterior. A política de retenção de PVC está explícita no manifesto; acompanhe também a política do PV/backend. Esses registros são só arquivos de treino, não um banco distribuído.

## Alternativa sem AWS — PV local estático

Use outro cluster ou encerre o lab A antes: as alternativas reutilizam o PVC `dados`, cujo binding não pode ser trocado livremente. No worker escolhido, crie `sudo install -d -o 1000 -g 1000 -m 0770 /srv/curso-storage`. Edite o hostname em `local-static.yaml` para a label real `kubernetes.io/hostname`.

```bash
kubectl apply -f laboratorios/04-storage/namespace.yaml
kubectl apply -f laboratorios/04-storage/local-static.yaml
kubectl apply -f laboratorios/04-storage/arquivo.yaml
```

Repita a prova do arquivo. Ao cordonar o único nó do PV local e recriar o pod, ele ficará Pending: esse é o comportamento correto. Recupere com `uncordon`. O local PV ensina binding e topologia, mas não oferece a mobilidade do EBS.

## Incidente, desafio e aprovação

Incidente: tente agendar um consumidor em nó incompatível com a `nodeAffinity` do PV por meio de uma cópia do manifesto. Diagnostique com `describe pod`, `describe pvc`, topologia do PV e logs do CSI. Recupere removendo a regra conflitante da cópia; não edite a zona do PV para uma zona onde o disco não existe.

Desafio sem receita: desenhe três réplicas de banco em três AZs, cada uma com PVC próprio. Explique quem replica os dados, por que `replicas: 3` sozinho não basta, o que ocorre na perda de um nó e da AZ, e como restaurar um backup em nova zona. Implemente apenas a persistência de uma réplica descartável, documentando as demais decisões.

Rubrica, 10 pontos: vínculo PVC/PV/volume e arquivo (3); troca de nó com evidência (2); diagnóstico correto de zona ou local PV (2); política IAM explicada sem credenciais no Git (1); plano de backup/restauração e descarte financeiro (2). Avance com 8/10 e sem confundir Retain com proteção dos dados.

Ao encerrar, pare consumidores e confira volumes anexados antes de excluir o namespace `curso-storage`. PVs Retain e EBS continuam existindo e cobrando. Registre os IDs exatos, exporte apenas dados necessários, exclua os PVs liberados e, **somente após validar que os discos pertencem ao lab e não precisam ser preservados**, apague os EBS correspondentes pelo console. Retire a role/perfil criado e restaure a configuração anterior de IMDS quando encerrar todo uso do CSI. Não aplique um `delete -f` recursivo no diretório: há alternativas e arquivos com placeholders.

Fontes consultadas em 10/09/2026: [volumes e emptyDir](https://kubernetes.io/docs/concepts/storage/volumes/), [PV/PVC](https://kubernetes.io/docs/concepts/storage/persistent-volumes/), [StorageClass](https://kubernetes.io/docs/concepts/storage/storage-classes/), [EBS CSI self-managed](https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/docs/install.md), [EBS CSI valores Helm](https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/charts/aws-ebs-csi-driver/values.yaml), [limites de EBS Multi-Attach](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-volumes-multi.html).
