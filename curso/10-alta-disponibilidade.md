# 10 — Alta disponibilidade, quórum e falhas por zona

**Tempo sugerido:** 18–24 horas. **Pré-requisitos:** backup/restore do módulo 08 concluído,
cluster descartável, inventário dos nós e orçamento para a janela de laboratório.
O resultado é uma topologia de três control planes, compreendida e testada, com um
relatório que distingue disponibilidade da API, disponibilidade da aplicação e durabilidade.

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

Na AWS, crie um Network Load Balancer interno de laboratório com subnets em três AZs.
O cliente deve chegar à VPC por VPN/bastion. Crie target group TCP/6443, registre os
IPs ou instâncias dos control planes e listener TCP/6443. Ative balanceamento entre
zonas ou mantenha targets saudáveis em cada AZ e compreenda o comportamento escolhido.
Use TCP passthrough: o certificado da API continua sendo validado pelo cliente.

Crie um registro DNS privado estável apontando para o NLB. Registre o ARN e tags de
projeto para posterior limpeza. Restrinja 6443 a clientes e nós do curso; 2379/2380
devem conectar apenas os pares/control planes necessários. 10250 e o tráfego CNI
precisam seguir a matriz de portas dos módulos 01/03. Não exponha etcd publicamente.

Health check TCP confirma abertura de porta; para avaliar prontidão real, teste também
`/readyz` da API. Não configure um balanceador de HTTP da aplicação para mediar a API.

```bash
getent hosts lab-k8s.internal
nc -vz lab-k8s.internal 6443
kubectl get --raw='/readyz?verbose'
```

Como alternativa econômica de estudo, o arquivo
[`haproxy.cfg.example`](../laboratorios/10-alta-disponibilidade/haproxy.cfg.example)
implementa passthrough TCP. Instale HAProxy em uma máquina própria, ajuste os IPs,
valide com `haproxy -c -f /etc/haproxy/haproxy.cfg` e reinicie o serviço.
Um único HAProxy continua sendo ponto único de falha; esse arranjo não passa no gate HA.

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

Use `etcdctl endpoint status --cluster -w table` e `endpoint health --cluster` com os
certificados e procedimento do módulo 08. Confirme três membros e um líder. Ter três
pods com nome etcd não demonstra que o conjunto esteja saudável.
Depois das adesões, remova o token temporário pelo ID com `kubeadm token delete ID`.

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

## Entrega e avaliação

Produza diagrama com AZs, endpoint, membros etcd, workers e volumes. Informe RTO medido
da API e da aplicação separadamente. RPO é a quantidade de dados que se aceita perder;
backup a cada hora não garante RPO de uma hora se o último backup não puder ser restaurado.

Gate: API acessível com um CP parado; três membros saudáveis após retorno; ausência de
perda no arquivo persistente da aplicação; explicação do caso PVC preso à AZ.
Desafio autônomo: planejar capacidade N-1 por zona e comparar etcd stacked com externo.
Pergunta de entrevista: por que dois CPs podem ser pior investimento que um sem elevar
a tolerância a falhas de etcd? Responda usando quórum e domínios de falha.

Ao terminar a janela, remova somente o NLB/target group/DNS e máquinas adicionais
identificados no inventário, após migrar ou encerrar o cluster de exercício. Verifique
EBS, snapshots, IPs públicos e balanceadores retidos; parar EC2 não interrompe toda cobrança.

## Fontes primárias consultadas em 2026-09-10

- [kubeadm HA](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/).
- [Escolha de topologia](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ha-topology/).
- [Endpoint compartilhado no init](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/).
- [etcd: tolerância a falhas](https://etcd.io/docs/v3.6/faq/).
- [AWS NLB: target groups](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-target-groups.html).
