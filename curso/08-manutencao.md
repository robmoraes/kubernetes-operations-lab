# 08 — Backup, recuperação, certificados e upgrade

Reserve **20–28 horas**, em sessões separadas. Pré-requisitos: módulos 01–07, acesso SSH e console às VMs, inventário de versões e domínio de static pods. Faça a restauração em um **cluster kubeadm descartável de um único control plane com etcd local**, sem dados importantes. Este runbook não restaura um cluster HA nem um etcd externo. Um CP implica interrupção da API durante parte dos exercícios; pods existentes nos workers podem continuar, mas isso não equivale a cluster operacional.

O resultado exigido é evidência de restauração, não apenas um arquivo chamado backup. Diferencie RPO (quanto estado pode ser perdido) de RTO (tempo até recuperar serviço). Snapshot do etcd guarda objetos da API, inclusive Secrets; não guarda o conteúdo de EBS/PVC, imagens, PKI do disco nem infraestrutura AWS. Git, backup do etcd, PKI protegida e backup de aplicação resolvem partes diferentes.

## 1. Inventário e preparação

**Na estação**, confirme o contexto e capture somente inventário sem segredos:

```bash
kubectl config current-context
kubectl get nodes -o wide
kubectl version
kubectl -n kube-system get pods -o wide
kubectl get --raw='/readyz?verbose'
kubectl apply -f laboratorios/08-manutencao/prova.yaml
kubectl -n curso-manutencao get configmap prova -o yaml
```

**Por SSH no CP**, examine os argumentos reais; não presuma os caminhos se seu cluster foi customizado:

```bash
sudo sed -n '1,240p' /etc/kubernetes/manifests/etcd.yaml
sudo kubeadm certs check-expiration
sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock ps
df -h /var/lib/etcd /var/backups
```

Anote imagem/versão do etcd, `--name`, `--initial-advertise-peer-urls`, `--initial-cluster`, caminhos de CA/cert/key e hostPath de `etcd-data`. Prepare `etcdctl` e `etcdutl` da **mesma versão upstream** do etcd usado pelo cluster (a imagem Kubernetes pode adicionar um sufixo como `-0`). Em ARM64 use o tarball `linux-arm64`, não `linux-amd64`. Siga [instalação oficial](https://etcd.io/docs/v3.6/install/) e [releases assinadas/publicadas](https://github.com/etcd-io/etcd/releases).

Exemplo de preparação, **no CP**, preenchendo a versão upstream primeiro:

```bash
CURSO_ETCD_VERSION='v3.6.X'
CURSO_ETCD_TMP=$(mktemp -d)
curl --fail --location \
  "https://github.com/etcd-io/etcd/releases/download/${CURSO_ETCD_VERSION}/etcd-${CURSO_ETCD_VERSION}-linux-arm64.tar.gz" \
  --output "${CURSO_ETCD_TMP}/etcd.tar.gz"
sha256sum "${CURSO_ETCD_TMP}/etcd.tar.gz"
# Compare ao checksum publicado da release exata antes de extrair/instalar.
tar -xzf "${CURSO_ETCD_TMP}/etcd.tar.gz" -C "${CURSO_ETCD_TMP}"
sudo install -m 0755 "${CURSO_ETCD_TMP}/etcd-${CURSO_ETCD_VERSION}-linux-arm64/etcdctl" /usr/local/bin/etcdctl
sudo install -m 0755 "${CURSO_ETCD_TMP}/etcd-${CURSO_ETCD_VERSION}-linux-arm64/etcdutl" /usr/local/bin/etcdutl
etcdctl version
etcdutl version
```

Não prossiga com placeholder X, checksum divergente ou versões incompatíveis. Não atualize o servidor etcd manualmente ao instalar os utilitários. Se a imagem do seu lab usa outra série, leia a documentação dessa série, especialmente suporte aos parâmetros de restore.

## 2. Backup consistente e verificável

**No CP**, estes caminhos são os padrões kubeadm. Valide-os com o manifesto. O certificado healthcheck-client permite a conexão mTLS local. Garanta que `/var/backups/curso-etcd/antes.db` não existe antes da primeira execução; para novas sessões use outro nome e registre-o, sem sobrescrever backups anteriores.

```bash
sudo install -d -m 0700 /var/backups/curso-etcd
sudo test ! -e /var/backups/curso-etcd/antes.db
sudo etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key endpoint health
sudo etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key snapshot save /var/backups/curso-etcd/antes.db
sudo chmod 0600 /var/backups/curso-etcd/antes.db
sudo etcdutl snapshot status /var/backups/curso-etcd/antes.db --write-out=table
sudo sha256sum /var/backups/curso-etcd/antes.db
sudo cp -a /etc/kubernetes /var/backups/curso-etcd/kubernetes-antes
```

O `test` é uma checagem, não um bloqueio automático de um terminal interativo: se falhar, pare e escolha outro destino. Registre revision, tamanho, número de chaves, hash, horário UTC e versão. Proteja também a cópia da PKI, kubeconfigs e eventual chave de criptografia de Secrets. Transfira o conjunto cifrado para um destino de backup fora da VM, valide o hash na cópia e teste acesso de recuperação. Não envie o snapshot ou arquivos PKI ao repositório.

Snapshot online via `etcdctl snapshot save` fornece integridade verificável. Copiar um arquivo de banco arbitrário de um etcd em execução não equivale a esse procedimento. [Operação do etcd no Kubernetes](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/).

## 3. Restaurar e provar a volta do estado

**Na estação**, mude somente o marcador após o backup:

```bash
kubectl -n curso-manutencao patch configmap prova --type=merge -p '{"data":{"fase":"depois"}}'
kubectl -n curso-manutencao get configmap prova -o jsonpath='{.data.fase}'
```

Espere `depois`. A restauração a seguir reverte **todo o estado da API** ao instante do snapshot, não só o ConfigMap; por isso ela exige o cluster descartável dedicado.

**No CP**, confirme `etcdutl snapshot restore --help` contendo `--bump-revision` e `--mark-compacted`. Em restauração Kubernetes, essas opções evitam revisões retrocedendo para watchers e invalidam caches de controllers. O incremento de 1 bilhão é conservador para a pequena carga do lab; em operação dimensione segundo taxa de escrita e idade do snapshot. Se a versão não suportar, use o procedimento oficial correspondente e planeje compatibilidade; não remova as flags silenciosamente. [Recuperação e revision bump](https://etcd.io/docs/v3.6/op-guide/recovery/).

Pare os componentes **retirando manifests do diretório observado**, com kubelet ainda ativo. Use um destino novo e vazio; preserve a cópia original do passo 2.

```bash
sudo install -d -m 0700 /var/backups/curso-etcd/manifests-pausados
sudo mv /etc/kubernetes/manifests/kube-controller-manager.yaml /var/backups/curso-etcd/manifests-pausados/
sudo mv /etc/kubernetes/manifests/kube-scheduler.yaml /var/backups/curso-etcd/manifests-pausados/
sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /var/backups/curso-etcd/manifests-pausados/
```

Aguarde ao menos um `fileCheckFrequency` do kubelet, normalmente 20 segundos. Confira com `crictl ps` que os três containers pararam antes de continuar. API indisponível agora é esperado. Em seguida retire etcd:

```bash
sudo mv /etc/kubernetes/manifests/etcd.yaml /var/backups/curso-etcd/manifests-pausados/
sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock ps
```

Aguarde novamente e confirme que não há etcd **Running**. `ps -a` ainda mostra containers encerrados. Não confunda reiniciar kubelet com parar automaticamente containers existentes.

Restaure em um diretório **novo**, conservando `/var/lib/etcd` para recuperação do exercício. Preencha nome e URL de peer com os valores anotados; não use o hostname de exemplo cegamente.

```bash
sudo test ! -e /var/lib/etcd-restaurado-curso
sudo etcdutl snapshot restore /var/backups/curso-etcd/antes.db \
  --data-dir=/var/lib/etcd-restaurado-curso \
  --name=NOME_ETCD_DO_MANIFESTO \
  --initial-cluster=NOME_ETCD_DO_MANIFESTO=https://IP_PRIVADO_CP:2380 \
  --initial-advertise-peer-urls=https://IP_PRIVADO_CP:2380 \
  --initial-cluster-token=curso-restauracao-1 \
  --bump-revision=1000000000 --mark-compacted
sudoedit /var/backups/curso-etcd/manifests-pausados/etcd.yaml
```

No manifesto pausado, altere **somente** `volumes[].hostPath.path` do volume chamado `etcd-data` de `/var/lib/etcd` para `/var/lib/etcd-restaurado-curso`. O `volumeMount.mountPath` e o argumento `--data-dir=/var/lib/etcd` **dentro do container** continuam iguais. Confirme nome, peer URL e certificados adequados à mesma VM. Compare com o backup usando `sudo diff -u /var/backups/curso-etcd/kubernetes-antes/manifests/etcd.yaml /var/backups/curso-etcd/manifests-pausados/etcd.yaml`; somente o hostPath deverá ter mudado.

```bash
sudo mv /var/backups/curso-etcd/manifests-pausados/etcd.yaml /etc/kubernetes/manifests/
# Aguarde etcd Running, leia logs e repita endpoint health do passo 2.
sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock ps
sudo mv /var/backups/curso-etcd/manifests-pausados/kube-apiserver.yaml /etc/kubernetes/manifests/
# Aguarde API responder antes dos controllers:
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get --raw='/readyz?verbose'
sudo mv /var/backups/curso-etcd/manifests-pausados/kube-controller-manager.yaml /etc/kubernetes/manifests/
sudo mv /var/backups/curso-etcd/manifests-pausados/kube-scheduler.yaml /etc/kubernetes/manifests/
```

Não execute as movimentações seguintes até satisfazer cada espera. **Na estação**, valide nodes, pods, DNS, uma criação de Deployment e o marcador:

```bash
kubectl -n curso-manutencao get configmap prova -o jsonpath='{.data.fase}'
kubectl get nodes
kubectl -n kube-system get pods
kubectl get --raw='/readyz?verbose'
```

O valor deve ser `antes`. Isso prova retorno do snapshot; um simples endpoint health não provaria recuperação do estado desejado. Registre tempo total, estado perdido e diferenças de UID/objetos. Recrie uma aplicação simples para comprovar scheduler e reconciliação.

Se falhar, mantenha API/controllers pausados, leia `crictl logs ID_ETCD` e valide caminhos/certificados/permissões. Como saída do exercício, pare o etcd restaurado da mesma forma e recoloque o **manifesto original** apontando para o diretório antigo intacto; então volte API/controllers. Essa saída abandona a tentativa de restore e retorna ao estado anterior à parada. Não copie arquivos entre dois data dirs ativos. Em cluster HA, restaurar um membro desse jeito isoladamente é incorreto: membership, quórum e fencing exigem outro runbook.

## 4. Certificados: renovar e carregar os novos arquivos

Faça em sessão separada, com snapshot e cópia de `/etc/kubernetes` atuais. **No CP**:

```bash
sudo kubeadm certs check-expiration
sudo openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -serial -dates
sudo kubeadm certs renew all
sudo kubeadm certs check-expiration
```

`renew all` não resolve indiscriminadamente CAs externas, rotação de CA ou todo certificado do kubelet. O comando gera arquivos; componentes precisam carregá-los. Reinicie os static pods **um de cada vez**, movendo o manifesto correspondente para um diretório fora de `/etc/kubernetes/manifests`, aguardando parada via `crictl`, movendo de volta e aguardando saúde. Use a técnica já praticada, primeiro etcd, depois API Server, controller-manager e scheduler; valide etcd/API a cada etapa. Não use `kubectl delete pod` no mirror pod como substituto.

Em HA, faça a renovação/reinícios em um CP por vez preservando quórum. Neste lab um CP, haverá breves interrupções. Compare serial e datas antes/depois e confira `/readyz`. Uma cópia antiga de `admin.conf` na estação não se atualiza sozinha: distribua o kubeconfig renovado por canal seguro, mantendo endpoint correto e modo 0600. Não sobrescreva um kubeconfig com vários clusters sem mesclar conscientemente. [Renovação de certificados kubeadm](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/).

## 5. Upgrade sequencial: 1.35 → 1.36

Primeiro pratique atualização de patch dentro de 1.35. Depois faça **um minor de cada vez**. Não salte de 1.35 para 1.37. Consulte suporte de Calico, CSI, Traefik, Metrics Server e APIs depreciadas antes de escolher o alvo; a versão do curso não é uma promessa sobre versões futuras.

Na estação, registre `kubectl version`, imagens dos componentes e saúde da aplicação. No CP, faça novo backup, confira espaço e `kubeadm certs check-expiration`. Leia a [política de version skew](https://kubernetes.io/releases/version-skew-policy/) e o [runbook da versão alvo](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/). Kubelet não pode ser mais novo que API Server; atualize control plane antes dos workers. Planeje janela de indisponibilidade da API com um CP.

**Por SSH no primeiro CP**, edite o repo apt explicitamente para o minor alvo. O bootstrap utiliza `/etc/apt/sources.list.d/kubernetes.list`; confirme com `sed` antes. Faça uma cópia para fora de `sources.list.d` e altere só a URL `v1.35` → `v1.36` usando `sudoedit`. Mantenha `signed-by` e a chave válida do repositório oficial. Consulte a migração de repositório se o caminho local for diferente.

```bash
sudo cp -a /etc/apt/sources.list.d/kubernetes.list /var/backups/curso-etcd/kubernetes-apt-antes.list
sudoedit /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
apt-cache madison kubeadm
apt-cache madison kubelet
apt-cache madison kubectl
```

Escolha uma **versão exata de pacote presente nas três listas**, no minor pretendido. Exemplo de formato: `1.36.PATCH-1.1`; substitua PATCH, não use esse literal nem wildcard que instale algo diferente sem você perceber. Registre a escolha nas evidências.

```bash
CURSO_PKG_VERSION='1.36.PATCH-1.1'
CURSO_K8S_VERSION='v1.36.PATCH'
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm="${CURSO_PKG_VERSION}"
sudo apt-mark hold kubeadm
kubeadm version
sudo kubeadm upgrade plan
sudo kubeadm upgrade apply "${CURSO_K8S_VERSION}"
```

Só prossiga se o plano é o esperado. `upgrade apply` atualiza o control plane e, por padrão, renova certificados kubeadm. Não faça downgrade de binários como plano de rollback; falha de upgrade pede diagnóstico e procedimento oficial, com recuperação testada.

**Na estação**, drene o CP pelo nome real antes de atualizar seu kubelet:

```bash
kubectl get pods -A -o wide --field-selector spec.nodeName=NOME_CP
kubectl drain NOME_CP --ignore-daemonsets --timeout=180s
```

Mirror pods do control plane não são evictados pelo drain; revise bloqueios de PDB/emptyDir antes de qualquer flag extra. **No CP**, depois do drain:

```bash
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet="${CURSO_PKG_VERSION}" kubectl="${CURSO_PKG_VERSION}"
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet
sudo systemctl is-active kubelet
```

**Na estação**, aguarde nó Ready, valide API e execute `kubectl uncordon NOME_CP`. Em um cluster com outros CPs, faça neles a preparação apt, atualização do kubeadm e `sudo kubeadm upgrade node` (não outro `upgrade apply`), depois drain/kubelet/uncordon um a um. Só então avance aos workers.

Para **cada worker**, complete a sequência inteira antes do próximo:

1. Na estação, confira todos os pods no worker, PDBs e capacidade de destino; execute drain sem seletor, como no módulo 05. Se bloquear, resolva a causa.
2. Por SSH nesse worker, atualize o repo apt para o mesmo minor, escolha exatamente o mesmo pacote, instale/segure kubeadm e execute `sudo kubeadm upgrade node`.
3. Atualize/segure kubelet e kubectl para a mesma versão, faça daemon-reload e reinicie kubelet.
4. Na estação, espere Ready e versão correta, execute uncordon e teste aplicação/DNS/PVC antes de tocar no outro worker.

Não rode `bootstrap ... init` novamente para fazer upgrade. Compare no fim `kubectl get nodes`, `kubectl version`, `kubectl -n kube-system get pods`, `kubectl top nodes`, aplicação HTTP e arquivo no PVC. Documente quais componentes Helm exigem upgrade próprio. [Troca do repositório de pacotes](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/change-package-repository/).

## Avaliação operacional

Desafio sem receita: outra pessoa recebe seu runbook e deve restaurar o marcador num cluster descartável equivalente, medir RTO e explicar o RPO. Em seguida planeje um upgrade com um PDB inicialmente bloqueando um worker. Você precisa justificar a correção de capacidade/disponibilidade e demonstrar uma execução concluída.

Rubrica: backup com integridade e proteção (2), restauração comprovada por marcador e reconciliação (3), renovação efetivamente carregada (2), upgrade sequencial com versões e saúde verificadas (3). Aprovação: 8/10; sem prova de restore o módulo não está concluído. Preencha [registro da manutenção](../laboratorios/08-manutencao/registro.md), sem anexar segredos. Não apague diretórios de backup/data antigos durante o aprendizado; arquive cifrado e decida retenção após a validação.

Fontes consultadas em 10/09/2026: [backup/restore etcd](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/), [etcd 3.6 recovery](https://etcd.io/docs/v3.6/op-guide/recovery/), [certificados kubeadm](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/), [upgrade kubeadm](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/), [upgrade Linux nodes](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/upgrading-linux-nodes/), [version skew](https://kubernetes.io/releases/version-skew-policy/).
