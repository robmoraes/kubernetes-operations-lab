# 10 — Alta disponibilidade, quórum e falhas por zona

## Antes de começar

Reserve **18–24 horas**. Conclua [instalação manual](01-control-plane.md),
[rede](03-rede.md), [storage](04-storage.md), [scheduling](05-scheduling.md) e
[backup/restore](08-manutencao.md). Tenha a aplicação e o arquivo persistente desses
laboratórios disponíveis, sem dados reais. Use kubectl na estação; os utilitários etcd
precisam ser preparados também no CP1 principal, conforme indicado antes de seu uso.
Não execute os ensaios em produção nem misture máquinas de outros clusters.

O ambiente suportado para HA regional aqui é EC2 em **três AZs da mesma VPC**, com
três control planes dedicados e workers com capacidade nas zonas sobreviventes. Reserve
uma janela com orçamento para máquinas, NLB, DNS e discos. Anote IPs privados, IDs EC2,
subnets, AZs e Security Groups. O acesso à VPC por VPN ou bastion e ao console AWS deve
estar funcionando, como no módulo 01. Uma estação fora da VPC precisa dessa rota para
chegar ao endpoint interno; criar um NLB interno não abre essa rota automaticamente.

Antes de iniciar, confirme `kubectl -n curso-storage get deployment/arquivo pvc/dados`.
Se você encerrou o módulo 04, repita seu laboratório A de storage no cluster principal,
incluindo volume/PV/PVC/consumidor e arquivo de prova, ou a alternativa local declarando
sua menor mobilidade. Não basta reaplicar só o Deployment com um PVC inexistente.
Registre o conteúdo de `/dados/prova.txt` e os IDs de volume antes das falhas; esse
será o dado comparado na recuperação. Inclua a recriação do volume no orçamento.

O exemplo HAProxy abaixo permite aprender o balanceamento em uma máquina Ubuntu extra;
um único HAProxy não satisfaz a prova de HA do endpoint. O caminho NLB multi-AZ que o
substitui também é ensinado. Use o [plano de falha](../laboratorios/10-alta-disponibilidade/plano-falha.md)
para registrar exatamente o que será interrompido e como restaurar.

## O que você vai conseguir fazer

- Preparar e verificar um endpoint TCP estável para a API.
- Adicionar dois control planes ao cluster e comprovar três membros etcd saudáveis.
- Interromper uma API ou um nó de laboratório, observar o impacto e recuperar o conjunto.
- Separar HA de control plane, capacidade da aplicação e limitação de zona dos dados.

## O que três control planes resolvem

No modelo stacked, cada control plane executa seu etcd local. O scheduler e o
controller-manager elegem líderes; os API servers atendem requisições via balanceador.
etcd replica registros e precisa de maioria para confirmar operações.

| Membros etcd | Maioria | Falhas toleradas |
|---:|---:|---:|
| 1 | 1 | 0 |
| 2 | 2 | 0 |
| 3 | 2 | 1 |
| 5 | 3 | 2 |

Adicionar um segundo membro não produz tolerância a falhas; complete a terceira adesão
na mesma janela. Distribuir três membros em três AZs permite perder uma AZ, desde que
rede, balanceador e demais dependências sobrevivam. A latência entre membros afeta etcd.
Um cluster regional não protege contra a perda da região.

Workers e dados têm requisitos próprios: API disponível não torna um EBS multi-AZ.
Um PVC EBS fica associado à zona do volume. Replicação de banco ocorre na aplicação;
um StatefulSet sozinho não replica dados. Planeje capacidade restante para reagendar pods.

## Antes do primeiro join

Use três EC2s dedicadas ao control plane, uma por AZ, com a mesma minor Kubernetes,
containerd configurado e IPs privados alcançáveis. Adicione workers em outras AZs para
ensaiar continuidade da aplicação. Repita o preparo de SO do módulo 01, sem executar
`kubeadm init` nos control planes adicionais.
O ensaio de upgrade do módulo 08 acontece em cluster auxiliar separado. Aqui use o
cluster principal **1.35**, preservado para GitOps e o projeto final; não faça downgrade.
Copie o inventário do módulo 01, atribuindo nomes únicos `cp2` e `cp3`; mantenha o
hostname `cp1` original. Use Ubuntu 24.04 AMD64, 2 vCPU/4 GiB e disco gp3 por CP como
baseline didático. Confira o patch com `kubeadm version -o short` nos três antes do join.

No primeiro init, `controlPlaneEndpoint` deve ser um DNS estável. Confira:

```bash
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'
kubectl -n kube-system get configmap kubeadm-config -o yaml
kubectl get nodes -L topology.kubernetes.io/zone
```

O DNS pode inicialmente apontar para CP1 e depois para o balanceador, se o endpoint
e os SANs já foram planejados. Se o cluster nasceu sem `controlPlaneEndpoint`, a
conversão não é um procedimento suportado diretamente pelo kubeadm. Neste curso,
recrie um cluster HA descartável, reaplique Git e restaure os dados de laboratório.
Não tente corrigir a topologia editando apenas o kubeconfig do seu notebook.

Confirme as zonas usando o inventário EC2. Em kubeadm sem cloud controller os labels
de zona podem não existir: atribua os valores reais antes dos testes de distribuição.

```bash
# Troque nomes e zonas pelos valores do inventário; não invente domínios de falha.
kubectl label node cp1 topology.kubernetes.io/zone=us-east-1a --overwrite
kubectl label node cp2 topology.kubernetes.io/zone=us-east-1b --overwrite
kubectl label node cp3 topology.kubernetes.io/zone=us-east-1c --overwrite
```

Execute o label de cada nó somente após ele ingressar. Labels descrevem topologia;
não movem instâncias nem volumes entre zonas.

## Laboratório A — Endpoint estável

Um balanceador TCP recebe conexões em uma porta e escolhe um backend saudável. Ele
não precisa terminar o TLS: em passthrough, o cliente continua validando o certificado
do API server para `lab-k8s.internal`. Health check TCP prova apenas abertura de porta;
`/readyz` da API acrescenta a verificação de prontidão do componente.

**Exemplo local guiado:** em uma VM Ubuntu dedicada chamada `lb1`, instale
`sudo apt-get update` e `sudo apt-get install -y haproxy`. Para os testes de conexão,
instale `netcat-openbsd` na estação e nos nós Ubuntu com `sudo apt-get install -y netcat-openbsd`.
`getent` já faz parte do sistema. Copie o arquivo
[`haproxy.cfg.example`](../laboratorios/10-alta-disponibilidade/haproxy.cfg.example)
da estação para `/tmp/haproxy-curso.cfg` dessa VM com `scp`. Substitua seus três IPs
pelos IPs privados reais de CP1/CP2/CP3. Backends ainda sem API permanecerão fora da
rotação até o join; CP1 deve estar funcionando antes de mudar o endpoint.

```bash
# Em lb1, máquina exclusiva do exercício:
sudo cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.antes-curso
sudo install -m 0644 /tmp/haproxy-curso.cfg /etc/haproxy/haproxy.cfg
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl restart haproxy
sudo systemctl status haproxy --no-pager
sudo ss -lntp 'sport = :6443'
```

Espere `Configuration file is valid`, serviço ativo e listener 6443. Na repetição,
não sobrescreva o backup original. Restrinja o firewall de lb1 aos clientes/nós do
laboratório e libere lb1 → CPs TCP/6443. Na estação e **em todos os nós**, edite
`/etc/hosts` com `sudoedit`: substitua a entrada antiga de `lab-k8s.internal` pelo IP
de lb1, mantendo uma única entrada para esse nome. Teste resolução e TCP em todos;
`kubectl` usa kubeconfig administrativo apenas na estação ou CP1, nunca copiado aos workers.
Se falhar, restaure o mapeamento anterior para CP1 e diagnostique lb1 sem perder acesso.

```bash
getent hosts lab-k8s.internal
nc -vz lab-k8s.internal 6443
# Somente na estação com kubeconfig, não em workers:
kubectl get --raw='/readyz?verbose'
```

Esse exemplo permite provar balanceamento, mas lb1 continua sendo ponto único de
falha. Para a entrega HA AWS, substitua-o por um NLB seguindo estes passos no console,
todos na mesma região/VPC do inventário:

1. Em **EC2 → Target Groups → Create**, escolha tipo **Instances**, protocolo TCP,
   porta 6443 e a VPC do laboratório. Use health check TCP/6443. Registre CP1; registre
   CP2/CP3 após iniciarem suas APIs. Não registre os workers.
2. Em **EC2 → Load Balancers → Create → Network Load Balancer**, escolha **Internal**,
   IPv4 e uma subnet por AZ. Crie/anexe um Security Group que aceite 6443 apenas dos
   SGs dos nós e do CIDR de administração via VPN/bastion. Sua saída deve permitir
   6443 para os CPs. No SG dos CPs, permita essa porta a partir do SG do NLB.
3. Crie listener **TCP:6443 → target group**. Em atributos do NLB, habilite
   **Cross-zone load balancing** para que as três entradas possam alcançar CP1 durante
   o crescimento. Isso também deve entrar no modelo de custos/tráfego entre AZs.
4. Aguarde NLB **Active** e CP1 **Healthy** no target group. Registre DNS e ARN do NLB.
   Em **Route 53 → Hosted zones**, identifique primeiro a zona privada do laboratório
   usada no módulo 01. Se ela já contiver o nome, atualize somente o registro
   `lab-k8s.internal` para A **Alias** desse NLB, preservando os demais registros.
   Se ainda não houver zona para o nome, crie a zona **privada** `lab-k8s.internal`,
   associada à VPC, e o registro A no ápice (nome vazio), Alias para esse NLB.
   Não crie uma zona duplicada nem altere uma zona de produção. DNS support e DNS
   hostnames devem estar habilitados na VPC.
5. Remova a entrada estática `lab-k8s.internal` de `/etc/hosts` em todos os nós e na
   estação que usa o resolvedor privado. Uma entrada antiga tem precedência e poderia
   mascarar uma falha do balanceador. Execute `getent`/`nc` nos nós e `/readyz` pela estação.

A estação fora da VPC pode executar kubectl no bastion já configurado para usar o DNS
da VPC; não basta consultar um DNS público. Resultado esperado: o mesmo nome alcança
o NLB, CP1 atende a API e certificados continuam válidos. Não fixe um IP transitório
do NLB no `/etc/hosts`. Preserve acesso administrativo direto para recuperação.

As portas entre CPs, etcd e kubelet seguem o módulo 01: etcd 2379/2380 não é público;
CNI e 10250 precisam continuar alcançáveis entre os pares autorizados. O balanceador
da API não substitui o Traefik da aplicação.

## Laboratório B — Adicionar control planes

Em CP1, gere material temporário para a adesão. A saída contém segredos: use sessão
privada, não grave no histórico compartilhado nem nas evidências do curso.

```bash
sudo kubeadm init phase upload-certs --upload-certs
sudo kubeadm token create --ttl 30m --print-join-command
```

O primeiro comando exibe a chave de certificados; o segundo, endpoint, token e hash
da CA. A chave permite acesso ao material necessário para um control plane e merece
o mesmo cuidado de uma credencial administrativa. O Secret de certificados enviados
é temporário; gere novamente se a janela expirar.

Execute em CP2 o comando retornado, acrescentando `--control-plane`, a chave e o IP
privado **de CP2**. Este exemplo tem placeholders e não deve ser copiado sem preenchê-los:

```text
sudo kubeadm join lab-k8s.internal:6443 \
  --token TOKEN_GERADO \
  --discovery-token-ca-cert-hash sha256:HASH_GERADO \
  --control-plane --certificate-key CHAVE_GERADA \
  --apiserver-advertise-address IP_PRIVADO_CP2
```

Espere CP2 ficar saudável. Repita em CP3 usando o IP de CP3. Registre ambos no target
group e confira health checks. Não copie o diretório inteiro de etcd entre máquinas.

```bash
kubectl get nodes -o wide
kubectl -n kube-system get pods -l component=kube-apiserver -o wide
kubectl -n kube-system get pods -l component=etcd -o wide
kubectl -n kube-system get leases
kubectl get --raw='/readyz?verbose'
```

O módulo 08 instalou ferramentas em um **CP auxiliar**, não necessariamente no CP1
principal. Antes de usar etcdctl aqui, confira a imagem real com
`sudo sed -n '1,100p' /etc/kubernetes/manifests/etcd.yaml` no CP1. Repita **somente a
instalação/verificação de etcdctl e etcdutl** ensinada na preparação do módulo 08,
selecionando a versão upstream correspondente a essa imagem e arquitetura AMD64.
Não execute backup/restore nem copie binários de versão diferente por suposição.
Confirme `etcdctl version` no CP1. O endpoint local fornece os endereços dos demais
membros; `--cluster` verifica o conjunto descoberto:

```bash
sudo etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key endpoint status --cluster -w table
sudo etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key endpoint health --cluster
```

Confirme três membros, todos saudáveis, e apenas um líder. Ter três pods com nome etcd
não demonstra que o conjunto esteja saudável. Se o binário não estiver no PATH do sudo,
use o caminho absoluto instalado no módulo 08.
Depois das adesões, no CP1, remova o token temporário pelo ID com `sudo kubeadm token delete ID`.

## Laboratório C — Falha de API sem perder o nó

Preencha o [plano de falha](../laboratorios/10-alta-disponibilidade/plano-falha.md).
Em dois terminais, monitore a API pelo endpoint e a aplicação pelo endpoint HTTP.

```bash
while true; do
  date -Is
  kubectl --request-timeout=5s get --raw=/readyz
  sleep 2
done
```

Em **CP3 do laboratório**, confirme `hostname` e mova somente o manifest da API para
fora da pasta observada. Não deixe cópias `.bak` dentro de `manifests`.

```bash
hostname
sudo test ! -e /var/tmp/kube-apiserver-curso.yaml || { printf 'Já existe um manifesto pausado; identifique a tentativa anterior.\n'; exit 1; }
sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /var/tmp/kube-apiserver-curso.yaml
# Após observar a falha e a retirada do target, restaure imediatamente:
sudo mv /var/tmp/kube-apiserver-curso.yaml /etc/kubernetes/manifests/kube-apiserver.yaml
```

Kubelet recriará o static pod. `systemctl stop kubelet` sozinho não é um ensaio
confiável de queda da API: containers existentes podem continuar executando.
Correlacione erros transitórios com o intervalo do health check e a prontidão do target.

## Laboratório D — Perda de membro e zona

Com todos os membros recuperados, pare **uma** EC2 control plane pelo console AWS,
identificada no plano. Não termine a instância. Observe que dois membros mantêm quórum.
Ligue a mesma instância, aguarde prontidão de etcd e API e valide novamente o conjunto.

Faça um ensaio separado parando os nós do laboratório de uma AZ, apenas quando houver
capacidade de aplicação e dois CPs saudáveis nas demais. Registre quais pods recuperam
e quais PVCs ficam bloqueados pela zona. `cordon`/`drain` ensaiam manutenção voluntária,
não reproduzem fielmente perda abrupta de AZ. PDB não impede falhas involuntárias.

Interrompa o teste se houver um segundo membro etcd indisponível. Restaurar disponibilidade
dos membros originais é diferente de recuperar um snapshot após perda definitiva de quórum.
A segunda situação pertence ao runbook de disaster recovery e a um laboratório isolado.

## Dimensionamento e desafio independente

Produza diagrama com AZs, endpoint, membros etcd, workers e volumes. Informe RTO medido
da API e da aplicação separadamente. RPO é a quantidade de dados que se aceita perder;
backup a cada hora não garante RPO de uma hora se o último backup não puder ser restaurado.

Para planejar capacidade N-1, retire uma zona da conta. Exemplo: cada AZ oferece 4
vCPU alocáveis de workers; perder uma deixa 8. Se a soma dos requests das aplicações
e componentes agendáveis for 9 vCPU, três zonas não tornam essa aplicação recuperável.
Repita para memória e número de pods, reservando espaço para rollouts e componentes.
Restrições rígidas de topologia e volumes podem impedir agendamento mesmo com folga total.

Desafio: usando o inventário real, calcule CPU/memória disponíveis após perder cada AZ,
liste workloads que cabem e os PVCs bloqueados por zona. Faça uma única simulação de
perda de AZ com plano preenchido, recuperação pronta e capacidade suficiente.
O exercício termina quando hipóteses e observações forem comparadas, incluindo limitações.
Pergunta de entrevista: por que dois CPs podem ser pior investimento que um sem elevar
a tolerância a falhas de etcd? Responda usando quórum e domínios de falha.

Mantenha o cluster manual, Argo CD e endpoint para concluir o módulo 12; o EKS11 será
temporário e separado. Agende as janelas próximas para controlar custos. Se decidir
encerrar este cluster antes, preserve Git/backups/evidências e registre que reconstruí-lo
pelos módulos 01/03/04/09 será necessário antes do projeto final, com nova janela e custo.

**Após concluir o projeto final**, remova somente NLB/target group/DNS e máquinas
identificados no inventário, após migrar ou encerrar esse cluster de exercício. Verifique
EBS, snapshots, IPs públicos e balanceadores retidos; parar EC2 não interrompe toda cobrança.

## Fechamento

Três CPs toleram a perda de um membro etcd; o endpoint, a capacidade dos workers e os
dados precisam de seus próprios mecanismos de continuidade. Explique por que um
cluster com três CPs e um HAProxy único ainda tem ponto único de falha.

Avance quando: o endpoint NLB estiver funcional; a API permanecer acessível com um CP
parado; os três membros recuperarem saúde; o arquivo persistente permanecer igual;
e seu relatório separar RTO da API, RTO da aplicação e o caso EBS preso à zona.
Se praticou apenas HAProxy/local, marque o mecanismo de balanceamento como concluído
e a prova multi-AZ como pendente. etcd externo e HA entre regiões não são exigidos aqui.

## Referências opcionais

Fontes verificadas em 12/09/2026; nenhuma delas é etapa obrigatória do laboratório.

- [kubeadm HA](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/) detalha variações de adesão e distribuição de certificados.
- [Topologias](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ha-topology/) permite comparar custos e isolamento de etcd externo e stacked.
- [Init e endpoint](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/) aprofunda o bootstrap e suas opções.
- [etcd e falhas](https://etcd.io/docs/v3.6/faq/) explica quórum, latência e dimensionamento de membros.
- [NLB target groups](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-target-groups.html) amplia health checks, tipos de target e comportamento entre zonas.
