# 04 — Persistência: do arquivo ao disco da AWS

**Duração:** 18–24 horas para a trilha AWS completa; divida em preparação, volume estático, provisionamento dinâmico e recuperação. A alternativa local ensina binding/topologia, mas não substitui as evidências específicas de EBS.

## Antes de começar

Conclua [01 — Control plane](01-control-plane.md), [02 — Workloads](02-workloads.md) e [03 — Rede](03-rede.md). Você deve reconhecer Pod, Deployment, volumes montados e Helm. O roteiro AWS usa dois workers EC2 descartáveis na mesma AZ, Ubuntu 24.04, Kubernetes 1.35 e a chave gerenciada `aws/ebs`; não usa discos existentes com dados nem chave KMS própria.

Na estação **LOCAL**, trabalhe na raiz do repositório com o kubeconfig do laboratório. Helm 4.2.3 já foi preparado no módulo 03. A instalação de AWS CLI v2 e a autenticação são ensinadas abaixo para Ubuntu 24.04 amd64/arm64. Para executá-las, você precisa de uma conta sandbox com acesso IAM Identity Center já concedido, URL/região de SSO e permission set autorizado a gerenciar os recursos deste lab: EBS, uma role/perfil dedicados, associação ao worker, IMDS e `iam:PassRole` para a role criada. Criar conta/organização/Identity Center e alterar SCPs são pré-requisitos administrativos, fora da aula; credenciais root não são usadas.

Confira o contexto antes de cada sessão. Os arquivos locais ficam em [laboratorios/04-storage](../laboratorios/04-storage/). Eles contêm alternativas e templates, então não aplique esse diretório recursivamente. Os passos AWS criam quatro discos de treino — 4 GiB estático, 4 GiB dinâmico expandido para 6 GiB e dois de 4 GiB do StatefulSet — além de IAM. Há cobrança até apagar os discos.

## O que você vai conseguir fazer

- Relacionar arquivo no container, mount, PVC, PV e VolumeId EBS sem confundi-los.
- Demonstrar persistência após recriar o Pod e trocar o worker dentro da AZ.
- Instalar CSI com uma identidade restrita, depois autorizar criação/expansão de discos identificados por tags.
- Observar binding tardio, expandir um volume e explicar os limites de Retain, StatefulSet e AZ.
- Diagnosticar incompatibilidade de topologia e encerrar os recursos de treino sem atingir outros discos.

## Do pedido da aplicação ao armazenamento

Um arquivo gravado no disco de um nó não fica automaticamente disponível nos demais. Kubernetes precisa conhecer o armazenamento e as restrições de acesso para permitir que um Pod o use; o mecanismo não transforma um disco local em armazenamento distribuído. Um **PVC** solicita capacidade e modo de acesso dentro de um namespace; um **PV** representa um volume disponível no cluster. Cada claim se vincula a um PV. Uma **StorageClass** descreve como provisionar novos volumes; o **CSI driver** implementa operações de criar, anexar, montar e expandir conforme o backend.

O driver tem dois papéis: seu controller conversa com a AWS e coordena volumes; seu node plugin executa as operações locais de montagem em cada worker. O controller precisa de IAM; o node plugin precisa identificar sua EC2 e registrar a topologia no Kubernetes. Um PVC Bound prova o vínculo, mas não prova que o filesystem já está montado nem que a aplicação consegue escrever.

A política `Retain` do PV mantém o volume quando seu claim é removido; ele fica aguardando uma decisão explícita de recuperação ou descarte. Com `Delete`, a liberação pode solicitar ao driver que apague também o backend. Escolheremos Retain para enxergar essas etapas separadamente. Nenhuma das duas políticas protege contra apagar um arquivo dentro do filesystem.

| Armazenamento | Persistência que oferece | Limite importante |
| --- | --- | --- |
| Camada gravável do container | Temporária | Não conte com ela após recriar o container |
| `emptyDir` | Reinício do container dentro do mesmo Pod | Some quando o Pod é excluído; pode usar disco ou RAM |
| PV `local` | Recriação do Pod no nó compatível | Depende daquele disco/nó |
| PVC com EBS | Recriação e troca de nó na mesma AZ | O EBS não pode ser anexado a uma EC2 de outra AZ |
| S3 ou outro serviço externo | Independente do Pod | A aplicação usa uma API de objetos, não um filesystem POSIX |

`ReadWriteOnce` permite montagem gravável por um nó, que pode hospedar mais de um Pod consumidor. `ReadWriteOncePod`, quando suportado pelo CSI/sidecars, restringe a um Pod. `ReadWriteMany` exige backend adequado; mudar esse campo não transforma gp3 em filesystem compartilhado. O EBS raiz da EC2 armazena sistema e runtime; este laboratório cria discos adicionais para a aplicação.

## 1. Preparar CLI, autenticação e inventário

**LOCAL — Ubuntu 24.04.** Se AWS CLI v2 e jq já estiverem instalados, registre suas versões e pule a instalação. Caso contrário, habilite o repositório assinado Universe da distribuição e escolha explicitamente uma versão 2.x publicada:

```bash
sudo apt-get update
sudo apt-get install -y software-properties-common jq
sudo add-apt-repository -y universe
sudo apt-get update
apt-cache madison awscli
read -r -p 'Versão exata 2.x do pacote awscli listada acima: ' AWSCLI_DEB
[[ "$AWSCLI_DEB" =~ ^2\. ]] || { printf 'Escolha AWS CLI v2.\n'; exit 1; }
sudo apt-get install -y "awscli=$AWSCLI_DEB"
aws --version
jq --version
aws configure sso --profile curso
aws sso login --profile curso
export AWS_PROFILE=curso
aws sts get-caller-identity
```

O assistente SSO pede nome da sessão, Start URL, região onde o Identity Center está configurado, escopo `sso:account:access`, conta, permission set e região padrão de trabalho. A região do SSO pode diferir da região EC2. Autorize no navegador apenas a sessão que você iniciou. Confira o ID da conta e o ARN retornados por STS; um login bem-sucedido na conta errada não autoriza executar o laboratório nela. Sessões expiradas são renovadas com `aws sso login --profile curso`.

As credenciais temporárias ficam no cache local de SSO, fora do Git; não as copie para manifests, Secrets ou evidências. A identidade humana usada por `aws` é diferente da role que criaremos para o controller CSI. Um `AccessDenied` da CLI e um `UnauthorizedOperation` do CSI podem ter causas e identidades diferentes.

```bash
kubectl config current-context
kubectl get nodes -o wide
read -r -p 'Região EC2 do laboratório, por exemplo sa-east-1: ' AWS_REGION
export AWS_REGION
aws ec2 describe-instances --query 'Reservations[].Instances[].[InstanceId,PrivateIpAddress,Placement.AvailabilityZone,IamInstanceProfile.Arn,State.Name]' --output table
read -r -p 'Nome Kubernetes do primeiro worker: ' WORKER_1
read -r -p 'InstanceId EC2 desse worker: ' WORKER_1_ID
read -r -p 'Nome Kubernetes do segundo worker: ' WORKER_2
read -r -p 'InstanceId EC2 desse worker: ' WORKER_2_ID
read -r -p 'AZ real comum aos dois workers: ' LAB_AZ
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
STORAGE_DIR=$(mktemp -d)
aws ec2 describe-instances --instance-ids "$WORKER_1_ID" "$WORKER_2_ID" --query 'Reservations[].Instances[].{Id:InstanceId,IP:PrivateIpAddress,AZ:Placement.AvailabilityZone,Profile:IamInstanceProfile,Metadata:MetadataOptions}' --output json > "$STORAGE_DIR/instancias-antes.json"
jq . "$STORAGE_DIR/instancias-antes.json"
```

Compare IPs ao `kubectl get nodes -o wide`, confirme dois IDs distintos e a AZ antes de continuar. Os nomes Kubernetes podem não coincidir com tags EC2. Ambos os workers devem estar sem instance profile: não substitua um perfil de SSM/outra aplicação nem amplie o acesso dos Pods às credenciais dele pelo IMDS. Se já houver perfil, use workers descartáveis sem perfil; adaptar uma role compartilhada fica fora deste roteiro. O arquivo registra o estado inicial do IMDS para reversão ao final.

## 2. Laboratório A — Volume estático e IAM de escopo pequeno

Comece com um disco novo, vazio e explicitamente identificado. O CSI pode formatá-lo ao montar; nunca informe um volume raiz ou um VolumeId de dados existentes.

```bash
VOLUME_ID=$(aws ec2 create-volume --availability-zone "$LAB_AZ" --volume-type gp3 --size 4 --encrypted --kms-key-id alias/aws/ebs --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=curso-storage},{Key=Curso,Value=kubernetes}]' --query VolumeId --output text)
aws ec2 wait volume-available --volume-ids "$VOLUME_ID"
aws ec2 describe-volumes --volume-ids "$VOLUME_ID" --query 'Volumes[].{Id:VolumeId,AZ:AvailabilityZone,Size:Size,State:State,Tags:Tags}'
```

O [template IAM estático](../laboratorios/04-storage/iam-static.template.json) permite consultas EC2 e Attach/Detach somente desse volume e dos dois workers. As consultas usam `Resource: "*"` porque essas ações Describe não suportam o mesmo recorte por ARN. As escritas usam ARNs exatos. A role é a identidade; a trust policy permite que EC2 a assuma; o instance profile é a associação entregue à EC2.

Preencha a cópia local com os valores do inventário. `jq` substitui somente os placeholders conhecidos; o comando final deve mostrar os ARNs reais, sem `REGIAO`, `CONTA` ou IDs simbólicos.

Antes de criar, consulte `aws iam get-role --role-name CursoEbsController` e `aws iam get-instance-profile --instance-profile-name CursoEbsController`. Ambos devem retornar **NoSuchEntity**. Se existir algum desses nomes, pare: não aplique políticas sobre um recurso possivelmente alheio. Se a consulta retornar AccessDenied, obtenha a permissão de consulta, pois esse erro não prova que o nome está livre. Os parênteses abaixo executam as mutações em um subshell; `|| exit 1` interrompe esse bloco em caso de falha, sem fechar seu terminal nem perder as variáveis da sessão. Não avance para o próximo bloco se houver erro.

```bash
jq --arg region "$AWS_REGION" --arg account "$ACCOUNT_ID" --arg volume "$VOLUME_ID" --arg w1 "$WORKER_1_ID" --arg w2 "$WORKER_2_ID" 'walk(if type == "string" then gsub("REGIAO"; $region) | gsub("CONTA"; $account) | gsub("VOLUME_ID"; $volume) | gsub("WORKER_1_ID"; $w1) | gsub("WORKER_2_ID"; $w2) else . end)' laboratorios/04-storage/iam-static.template.json > "$STORAGE_DIR/iam-static.json"
jq . "$STORAGE_DIR/iam-static.json"
(
aws iam create-role --role-name CursoEbsController --assume-role-policy-document file://laboratorios/04-storage/trust-ec2.json || exit 1
aws iam put-role-policy --role-name CursoEbsController --policy-name CursoUmVolume --policy-document "file://$STORAGE_DIR/iam-static.json" || exit 1
aws iam create-instance-profile --instance-profile-name CursoEbsController || exit 1
aws iam add-role-to-instance-profile --instance-profile-name CursoEbsController --role-name CursoEbsController || exit 1
aws ec2 associate-iam-instance-profile --instance-id "$WORKER_1_ID" --iam-instance-profile Name=CursoEbsController || exit 1
)
```

Se IAM ainda não propagou a associação, aguarde e repita somente a chamada que falhou; não reinicie a criação da role/profile. Guarde os recursos já criados no inventário para retomada ou descarte. O mesmo vale para qualquer outra falha parcial: investigue antes de continuar.

Instance profile é uma exceção didática: qualquer workload que alcance IMDS nesse worker pode usar sua identidade. Não execute aplicações não confiáveis nele. IMDS é o endpoint local de metadados/credenciais EC2; exigir IMDSv2 usa um token de sessão, mas não isola identidades entre Pods. O hop limit 2 permite o acesso a partir destes Pods. Em produção, a identidade por workload precisa de um mecanismo próprio de trust e tokens; anotar `eks.amazonaws.com/role-arn` em kubeadm sozinho não configura essa infraestrutura.

```bash
aws ec2 modify-instance-metadata-options --instance-id "$WORKER_1_ID" --http-tokens required --http-endpoint enabled --http-put-response-hop-limit 2
aws ec2 modify-instance-metadata-options --instance-id "$WORKER_2_ID" --http-tokens required --http-endpoint enabled --http-put-response-hop-limit 2
kubectl label node "$WORKER_1" curso.ebs/controller=true
kubectl label node "$WORKER_1" "$WORKER_2" curso.ebs/node=true
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update
helm show chart aws-ebs-csi-driver/aws-ebs-csi-driver --version 2.63.1
helm template aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver --version 2.63.1 --namespace kube-system --kube-version 1.35.0 -f laboratorios/04-storage/ebs-values.yaml --set-string controller.region="$AWS_REGION"
helm upgrade --install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver --namespace kube-system --version 2.63.1 -f laboratorios/04-storage/ebs-values.yaml --set-string controller.region="$AWS_REGION" --wait --timeout 5m
kubectl -n kube-system rollout status deployment/ebs-csi-controller --timeout=180s
kubectl -n kube-system rollout status daemonset/ebs-csi-node --timeout=180s
kubectl get csinode
kubectl get nodes -L topology.ebs.csi.aws.com/zone
```

Fixamos **chart 2.63.1, driver 1.63.1**; `helm show chart` deve confirmar esses números e o requisito Kubernetes compatível com 1.35. No values, `controller.nodeSelector` coloca uma réplica no worker com IAM; `node.nodeSelector` instala o plugin nos dois workers marcados. A label de zona é detectada pelo CSI, não inventada pelo aluno. Se faltar, examine `kubectl logs -n kube-system daemonset/ebs-csi-node -c ebs-plugin --tail=80` e confirme acesso ao IMDS. No controller, use `kubectl logs -n kube-system deployment/ebs-csi-controller -c ebs-plugin --tail=80` para diferenciar credencial indisponível de permissão insuficiente.

Abra [ebs-static.yaml](../laboratorios/04-storage/ebs-static.yaml) e preencha `SUBSTITUA_VOLUME_ID` com o VolumeId criado e `SUBSTITUA_AZ` com a AZ real. `claimRef` reserva o vínculo a `curso-storage/dados`, `volumeName` escolhe esse PV, e `storageClassName: ""` evita provisionamento por uma classe default. `nodeAffinity` impede consumir o EBS em outra zona.

```bash
kubectl apply -f laboratorios/04-storage/namespace.yaml
kubectl apply --dry-run=server -f laboratorios/04-storage/ebs-static.yaml
kubectl apply -f laboratorios/04-storage/ebs-static.yaml
kubectl apply -f laboratorios/04-storage/arquivo.yaml
kubectl -n curso-storage rollout status deployment/arquivo --timeout=180s
kubectl -n curso-storage get pvc,pods -o wide
kubectl get pv curso-ebs
kubectl -n curso-storage exec deploy/arquivo -- sh -c 'date -u > /dados/prova.txt; sync; cat /dados/prova.txt'
kubectl -n curso-storage rollout restart deployment/arquivo
kubectl -n curso-storage rollout status deployment/arquivo --timeout=180s
kubectl -n curso-storage exec deploy/arquivo -- cat /dados/prova.txt
```

Espere PVC Bound, novo UID de Pod e mesmo conteúdo. O container escreve como UID 1000; `fsGroup` permite acesso ao filesystem montado. A estratégia Recreate e uma réplica encerram o escritor anterior antes de iniciar outro, evitando um rollout que tente montar o mesmo RWO em dois nós simultaneamente.

Para testar mobilidade, capture o nó atual, impeça novos agendamentos nele com **cordon**, recrie a aplicação e depois libere o nó. Cordon não desliga o nó nem remove Pods que já estão nele.

```bash
ORIGINAL_NODE=$(kubectl get pod -n curso-storage -l app=arquivo -o jsonpath='{.items[0].spec.nodeName}')
kubectl cordon "$ORIGINAL_NODE"
kubectl -n curso-storage rollout restart deployment/arquivo
kubectl -n curso-storage rollout status deployment/arquivo --timeout=300s
kubectl -n curso-storage get pods -o wide
kubectl -n curso-storage exec deploy/arquivo -- cat /dados/prova.txt
aws ec2 describe-volumes --volume-ids "$VOLUME_ID" --query 'Volumes[].Attachments'
kubectl uncordon "$ORIGINAL_NODE"
```

São necessárias capacidade e topologia compatíveis no outro worker. Registre nó/InstanceId antes e depois e conteúdo igual. Detach/attach pode levar alguns minutos. Se o rollout não concluir, execute o uncordon antes de encerrar a sessão, examine eventos do Pod/CSI e preserve o volume. Não force detach enquanto um escritor possa continuar ativo. Se o controller CSI estiver no nó cordonado, seu Pod existente continua rodando; não o reinicie durante este teste.

## 3. Laboratório B — Provisionamento dinâmico e expansão

Agora o PVC solicita um disco ainda inexistente. A StorageClass escolhe tipo/formato e o provisioner; o CSI cria o EBS e o PV. Com `WaitForFirstConsumer`, a seleção de zona espera o primeiro consumidor: um PVC sem Pod pode ficar Pending legitimamente. Isso evita criar um volume numa zona incompatível, mas não copia um volume existente entre zonas.

O [template IAM dinâmico](../laboratorios/04-storage/iam-dynamic.template.json) completa a role anterior para **este** laboratório. Ele autoriza criação de volumes novos na conta/região escolhidas somente quando a requisição possui `Curso=kubernetes` e `ebs.csi.aws.com/cluster=true`; autoriza tags somente durante CreateVolume; e permite modificar/apagar/anexar volumes que já possuam ambas as tags. Attach/Detach também exige autorização para as duas instâncias exatas. O [StorageClass](../laboratorios/04-storage/ebs-gp3.yaml) envia a tag Curso, e o driver envia a tag CSI automaticamente.

Não há permissão de criar snapshots, restaurar/clonar deles, alterar CMK nem manipular outros volumes. Essa política é suficiente para discos vazios, montagem, expansão e descarte dos labs B/C; não é uma política universal para todos os recursos do driver. As permissões estáticas continuam cobrindo o volume A. Tag é uma condição de escopo, não uma fronteira de isolamento contra quem já tem poder de alterar IAM/tags na conta.

```bash
jq --arg region "$AWS_REGION" --arg account "$ACCOUNT_ID" --arg w1 "$WORKER_1_ID" --arg w2 "$WORKER_2_ID" 'walk(if type == "string" then gsub("REGIAO"; $region) | gsub("CONTA"; $account) | gsub("WORKER_1_ID"; $w1) | gsub("WORKER_2_ID"; $w2) else . end)' laboratorios/04-storage/iam-dynamic.template.json > "$STORAGE_DIR/iam-dynamic.json"
jq . "$STORAGE_DIR/iam-dynamic.json"
aws iam put-role-policy --role-name CursoEbsController --policy-name CursoVolumesDinamicos --policy-document "file://$STORAGE_DIR/iam-dynamic.json"
kubectl apply -f laboratorios/04-storage/ebs-gp3.yaml
kubectl apply -f laboratorios/04-storage/dinamico.yaml
kubectl -n curso-storage describe pvc dados-dinamicos
kubectl -n curso-storage wait --for=condition=Ready pod/arquivo-dinamico --timeout=240s
DYNAMIC_PV=$(kubectl -n curso-storage get pvc dados-dinamicos -o jsonpath='{.spec.volumeName}')
DYNAMIC_VOLUME=$(kubectl get pv "$DYNAMIC_PV" -o jsonpath='{.spec.csi.volumeHandle}')
aws ec2 describe-volumes --volume-ids "$DYNAMIC_VOLUME" --query 'Volumes[].{Id:VolumeId,AZ:AvailabilityZone,Tags:Tags,Size:Size}'
kubectl -n curso-storage exec arquivo-dinamico -- sh -c 'echo dinamico > /dados/prova.txt; sync'
kubectl -n curso-storage patch pvc dados-dinamicos --type=merge -p '{"spec":{"resources":{"requests":{"storage":"6Gi"}}}}'
kubectl -n curso-storage get pvc dados-dinamicos -w
```

Encerre o watch com Ctrl+C quando `status.capacity` chegar a 6Gi. Compare `kubectl exec -n curso-storage arquivo-dinamico -- df -h /dados`, o arquivo e `aws ec2 describe-volumes --volume-ids "$DYNAMIC_VOLUME" --query 'Volumes[].Size'`. Expansão exige `allowVolumeExpansion`, permissão ModifyVolume e suporte do driver/filesystem; o request sozinho não prova conclusão. Redução não é o caminho inverso. Não reaplique o manifesto original de 4Gi após expandir: atualize sua cópia para 6Gi antes de futuras aplicações.

Se aparecer acesso negado, identifique a ação e o ARN nos logs, confirme a role associada ao worker do controller, as duas tags e a região dos recursos. Política aplicada pela CLI não significa que o SDK do Pod já renovou suas credenciais; aguarde a propagação antes de repetir. Não acrescente `AdministratorAccess` para esconder a causa.

## 4. Laboratório C — StatefulSet e um PVC por réplica

O StatefulSet mantém nome/ordem estáveis e seu `volumeClaimTemplates` gera um claim para cada identidade. Nosso exemplo cria `registro-0` e `registro-1`, com `dados-registro-0` e `dados-registro-1`: são mais dois EBS de 4Gi. O Service headless, `clusterIP: None`, oferece descoberta das identidades sem um ClusterIP virtual. Ele não transforma os dois diretórios em armazenamento compartilhado; o processo de treino apenas dorme e não implementa um banco ou protocolo de replicação.

```bash
kubectl apply -f laboratorios/04-storage/statefulset.yaml
kubectl -n curso-storage rollout status statefulset/registro --timeout=240s
kubectl -n curso-storage get pods,pvc
kubectl -n curso-storage exec registro-0 -- sh -c 'echo replica-zero > /dados/prova.txt; sync'
kubectl -n curso-storage exec registro-1 -- sh -c 'echo replica-um > /dados/prova.txt; sync'
kubectl -n curso-storage delete pod registro-0
kubectl -n curso-storage wait --for=condition=Ready pod/registro-0 --timeout=180s
kubectl -n curso-storage exec registro-0 -- cat /dados/prova.txt
kubectl -n curso-storage exec registro-1 -- cat /dados/prova.txt
kubectl -n curso-storage scale statefulset/registro --replicas=1
kubectl -n curso-storage get pvc
kubectl -n curso-storage scale statefulset/registro --replicas=2
kubectl -n curso-storage rollout status statefulset/registro --timeout=240s
kubectl -n curso-storage exec registro-1 -- cat /dados/prova.txt
```

Cada réplica deve ler seu próprio texto. O Pod recriado recebe novo UID, mas mantém nome e claim. O PVC da réplica reduzida permanece porque `persistentVolumeClaimRetentionPolicy` está explicitamente Retain. Essa política governa a retenção dos claims; a `reclaimPolicy` do PV governa o backend quando o vínculo é liberado. São decisões diferentes.

## Falha, recuperação e limite de topologia

Vamos forçar uma restrição impossível em uma aplicação que já provou sua montagem. Um `nodeSelector` exige label de nó; o valor abaixo não existe no laboratório. O evento deve apontar incompatibilidade de agendamento, não corrupção do volume.

```bash
kubectl -n curso-storage patch deployment arquivo --type=merge -p '{"spec":{"template":{"spec":{"nodeSelector":{"curso.storage/destino":"inexistente"}}}}}'
kubectl -n curso-storage get pods -o wide
kubectl -n curso-storage describe pods -l app=arquivo
kubectl -n curso-storage describe pvc dados
kubectl get pv curso-ebs -o yaml
kubectl -n curso-storage patch deployment arquivo --type=merge -p '{"spec":{"template":{"spec":{"nodeSelector":null}}}}'
kubectl -n curso-storage rollout status deployment/arquivo --timeout=180s
kubectl -n curso-storage exec deployment/arquivo -- cat /dados/prova.txt
```

A aplicação pode ficar indisponível durante esse teste por usar Recreate. Recupere a restrição e confirme o arquivo. Se houvesse nó apenas em outra AZ, a topologia do EBS produziria incompatibilidade mesmo com recursos livres. Alterar a label ou o `nodeAffinity` do PV para mentir sobre a zona não move o disco.

`Retain` não é backup: não desfaz arquivo apagado nem oferece HA de AZ. Um plano de recuperação precisa definir dados, consistência, destino separado e teste. Para arquivos, uma cópia consistente pode ser restaurada em um volume novo. Um snapshot EBS pode originar um EBS novo numa AZ escolhida da região; esse novo VolumeId precisa de PV/topologia correspondentes. Para banco, use backup/replicação do próprio banco ou pause/flush conforme seu mecanismo antes do snapshot. Copiar o disco de um escritor ativo pode capturar estado insuficiente para recuperação da aplicação. Instalar o snapshot-controller/CRDs não faz parte desta aula; a competência cobrada aqui é explicar o plano e suas condições, não alegar um restore de banco que não foi testado.

## Alternativa prática sem AWS — PV local estático

Esta alternativa reaproveita o PVC `dados`: execute-a em outro cluster ou após encerrar a trilha EBS, pois não se troca o binding de um claim em uso. **HOST WORKER escolhido:** `sudo install -d -o 1000 -g 1000 -m 0770 /srv/curso-storage`. **LOCAL:** descubra a label com `kubectl get nodes -L kubernetes.io/hostname` e preencha esse valor em [local-static.yaml](../laboratorios/04-storage/local-static.yaml).

```bash
kubectl apply -f laboratorios/04-storage/namespace.yaml
kubectl apply -f laboratorios/04-storage/local-static.yaml
kubectl apply -f laboratorios/04-storage/arquivo.yaml
kubectl -n curso-storage rollout status deployment/arquivo --timeout=180s
kubectl -n curso-storage exec deployment/arquivo -- sh -c 'echo local > /dados/prova.txt; sync'
```

Repita a recriação e o teste de cordon, sempre liberando o nó depois. Ao cordonar o único nó compatível, o consumidor fica Pending; com uncordon, recupera e lê o arquivo. A capacidade 4Gi declarada num PV de diretório não cria sozinha uma quota física de filesystem. Guarde esta evidência como local PV; mobilidade EBS, IAM e expansão permanecem pendentes para a trilha AWS completa.

## Encerrar recursos e custo

Primeiro registre todos os PVs e VolumeIds: `kubectl get pv -o custom-columns=PV:.metadata.name,CLAIM:.spec.claimRef.namespace,VOLUME:.spec.csi.volumeHandle,STATE:.status.phase`. Guarde a lista filtrada/revisada do namespace `curso-storage`; IDs não são credenciais, mas a lista precisa ser precisa para descarte. Caso queira continuar os labs, preserve discos e contabilize seu custo.

1. Pare os consumidores: `kubectl scale deployment/arquivo statefulset/registro -n curso-storage --replicas=0` e `kubectl delete pod arquivo-dinamico -n curso-storage --ignore-not-found`. Use apenas os recursos que você criou. Espere não haver Pods consumidores e confira Attachments de cada EBS por ID.
2. Após salvar o necessário e confirmar que o namespace é exclusivo do treino, execute `kubectl delete namespace curso-storage`. Os PVs com Retain ficam Released; não é sinal de vazamento do CSI, é a política escolhida.
3. Para cada PV da lista revisada, confira claim anterior e VolumeId, então `kubectl delete pv NOME_EXATO_DO_PV`. Remova também `kubectl delete storageclass curso-ebs-gp3` se não houver mais consumidores. A alternativa local usa `curso-local` e mantém `/srv/curso-storage`; remova seus arquivos de treino no worker somente depois de confirmar o caminho e eventual backup.
4. Para cada EBS da lista, rode `aws ec2 describe-volumes --volume-ids ID_EXATO_DO_VOLUME` e confira tag Curso, AZ, estado available e Attachments vazio. Apenas quando os dados forem descartáveis, execute `aws ec2 delete-volume --volume-id ID_EXATO_DO_VOLUME`. Isso apaga o disco; a recuperação exige backup/snapshot prévio. Não use filtros amplos como alvo de exclusão automática.
5. Depois de encerrar **todo** uso do driver, `helm uninstall aws-ebs-csi-driver -n kube-system`. Retire as labels criadas com `kubectl label node "$WORKER_1" curso.ebs/controller-` e `kubectl label node "$WORKER_1" "$WORKER_2" curso.ebs/node-`.
6. Descubra a associação com `aws ec2 describe-iam-instance-profile-associations --filters Name=instance-id,Values="$WORKER_1_ID"`; confirme que aponta a CursoEbsController e use `aws ec2 disassociate-iam-instance-profile --association-id ID_EXATO_DA_ASSOCIACAO`. Remova a role do profile com `aws iam remove-role-from-instance-profile --instance-profile-name CursoEbsController --role-name CursoEbsController`, apague o profile com `aws iam delete-instance-profile --instance-profile-name CursoEbsController`, e apague as inline policies CursoUmVolume e CursoVolumesDinamicos usando `aws iam delete-role-policy --role-name CursoEbsController --policy-name NOME_EXATO`. Por fim, `aws iam delete-role --role-name CursoEbsController`.
7. Confira `instancias-antes.json` e restaure por worker os valores originais de HttpTokens, HttpEndpoint e HttpPutResponseHopLimit com `aws ec2 modify-instance-metadata-options --instance-id ID_EXATO --http-tokens VALOR_ANTERIOR --http-endpoint VALOR_ANTERIOR --http-put-response-hop-limit VALOR_ANTERIOR`. Não use valores de exemplo; restaure somente depois de nenhum CSI depender do IMDS modificado.

Todos os nomes em maiúsculas no descarte são substituições explícitas da lista que você revisou, não comandos prontos para colar. Verifique no console/CLI que os discos foram removidos e que não restaram volumes do lab cobrando. Preserve o inventário até terminar a verificação. `aws sso logout` encerra o cache de sessões SSO da estação; use-o apenas quando também puder encerrar as demais sessões SSO locais.

## Desafio independente

Em um volume descartável adicional, repita provisionamento, arquivo, troca de Pod e expansão sem copiar a sequência, consultando somente os manifests e `kubectl explain persistentvolume.spec`/`kubectl explain storageclass`. Termine quando puder provar vínculo, montagem, conteúdo, capacidade e descarte por IDs exatos.

Desenhe também três réplicas de banco em três AZs, cada uma com PVC próprio. Indique quem replica os dados, o efeito da perda de nó/AZ, qual backup recupera uma nova réplica e como testa seu conteúdo. Não é necessário implementar o banco distribuído nesta aula, mas `replicas: 3` sem protocolo/backup não satisfaz a explicação.

## Fechamento

Responda: qual camada preservou seu arquivo? Por que o Pod pode mover de worker e não de AZ? Qual condição IAM impede o controller de modificar um disco sem tags? Por que um PVC Pending pode estar correto? Qual diferença existe entre retenção de PVC do StatefulSet e reclaimPolicy do PV?

**Rubrica, 10 pontos:** vínculo e arquivo nos fluxos estático/dinâmico (2); troca de worker com conteúdo igual (2); expansão e claims por réplica comprovados (2); diagnóstico/recuperação de topologia e política IAM explicados (2); plano de backup e descarte financeiro verificável (2). Avance com 8/10, sem zero em recuperação/descarte e sem chamar Retain de backup. A alternativa local é um marco parcial; registre claramente os resultados AWS ainda não executados. Próximo: [05 — Agendamento e capacidade](05-scheduling.md).

## Referências opcionais

Fontes verificadas em **12/09/2026**. Os procedimentos necessários ao roteiro estão acima.

- [Volumes](https://kubernetes.io/docs/concepts/storage/volumes/) e [PV/PVC](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) aprofundam modos de acesso e ciclo de vida.
- [StorageClasses](https://kubernetes.io/docs/concepts/storage/storage-classes/) e [StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/) detalham binding, expansão e retenção por réplica.
- [Chart EBS CSI 2.63.1](https://github.com/kubernetes-sigs/aws-ebs-csi-driver/tree/helm-chart-aws-ebs-csi-driver-2.63.1/charts/aws-ebs-csi-driver) registra os values e a versão do driver usada no lab.
- [Política de referência do driver 1.63.1](https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/v1.63.1/docs/example-iam-policy.json) inclui permissões para recursos avançados que nossa política didática deliberadamente não habilita.
- [Autorização EC2](https://docs.aws.amazon.com/service-authorization/latest/reference/list_ec2.html) explica quais ações aceitam ARNs e condições por tags.
- [SSO na AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html) detalha sessões, perfis e cenários de login adicionais.
- [Pacotes Ubuntu](https://ubuntu.com/server/docs/how-to/software/package-management/) descreve repositórios e seleção de versões assinadas.
