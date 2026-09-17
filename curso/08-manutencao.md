# 08 — Backup, recuperação, certificados e upgrade

## Antes de começar

Reserve **20–28 horas**, em sessões separadas para backup/restore, certificados e upgrade. Você precisa ter concluído [01 — Control plane](01-control-plane.md), [04 — Storage](04-storage.md), [05 — Scheduling](05-scheduling.md) e [07 — Troubleshooting](07-troubleshooting.md): conhecer static pods, separar estado da API de dados em PVC, drenar um nó respeitando PDB e investigar containerd/kubelet.

O ambiente suportado é **um cluster auxiliar kubeadm 1.35, Ubuntu 24.04 AMD64, um único control plane com etcd 3.6 local e dois workers**, seguindo os caminhos do módulo 01. Ele será descartável e separado do cluster principal: restore reverte o estado global da API e o ensaio minor termina em 1.36. O principal deve permanecer em 1.35 para os módulos 09/10. HA, etcd externo, CAs externas e outro layout de disco exigem outro runbook e não são necessários para concluir este.

Antes de iniciar esta aula, repita a instalação do módulo 01 em **três VMs novas**, com os mesmos nomes internos `cp1`, `worker1` e `worker2`, mas IPs/instâncias diferentes dos originais. Isso é uma repetição deliberada do procedimento já aprendido e acrescenta o custo de três instâncias e seus discos durante a janela; mantenha o auxiliar isolado de qualquer ambiente de produção e use apenas dados de laboratório. Use estas substituições durante a preparação:

| Item | Valor no cluster auxiliar |
| --- | --- |
| Endpoint privado | `lab-manutencao.internal:6443`, DNS ou hosts apontando ao novo CP |
| Kubeconfig da estação | `$HOME/.kube/curso-manutencao-kubeconfig`, sem sobrepor o principal |
| Nome de contexto | `curso-manutencao`, renomeado a partir de `kubernetes-admin@kubernetes` |
| Nós e rede | Instâncias/IPs próprios; CIDRs livres sem conflito com VPC/VPN e com a rede do principal |
| Kubernetes e CNI | Mesmo patch 1.35 registrado no módulo 01 e Calico 3.32.2 |

Confirme os três nós Ready e execute **as seções 4–6 do módulo 05**, que preparam rede, TLS serving dos kubelets e Metrics Server, nesse contexto; Helm já foi instalado na estação no módulo 03 e não precisa ser reinstalado. No teste final, use `kubectl top nodes`; omita apenas `kubectl -n curso-scheduling top pods`, pois esse namespace não foi criado no auxiliar. Não é necessário repetir os incidentes de scheduling nem instalar EBS/Traefik no auxiliar. A aplicação de prova será criada neste capítulo pelo manifesto local do módulo 07. Reserve uma primeira sessão para essa preparação; o restante da aula trabalha apenas no auxiliar.

Tenha SSH/sudo e acesso ao console das VMs auxiliares, estação Linux com a credencial exclusiva `curso-manutencao` e espaço livre para snapshot, cópia de `/etc/kubernetes` e **um segundo data directory**. Reserve pelo menos o dobro do tamanho atual de `/var/lib/etcd`, mais margem para arquivos temporários. `kubectl`, `crictl`, curl, tar, openssl, GnuPG e ferramentas básicas do sistema já vêm dos preparativos anteriores; os utilitários etcd serão instalados abaixo antes do primeiro uso. Na estação Linux, instale GnuPG com `sudo apt-get install -y gnupg` se `gpg --version` não funcionar.

Use [prova.yaml](../laboratorios/08-manutencao/prova.yaml) para o marcador e [registro.md](../laboratorios/08-manutencao/registro.md) para evidências sem segredos. Execute `kubectl`/Helm na estação; os blocos identificados como **CP** ou **worker** rodam por SSH naquele host. Um CP implica interrupção da API em parte da prática; pods existentes nos workers podem continuar, mas isso não equivale a cluster operacional. Não execute o capítulo como um script único: cada etapa tem uma condição de avanço.

## O que você vai conseguir fazer

- Produzir snapshot consistente, verificar integridade e manter uma cópia cifrada fora da VM, com chave de recuperação disponível.
- Restaurar todo o estado da API nesse laboratório de um CP e provar a volta do marcador, da API e da reconciliação.
- Renovar certificados kubeadm, reiniciar seus consumidores e comprovar que o certificado servido mudou.
- Fazer upgrade de patch e de um minor, na ordem control plane → workers, preservando holds e validando serviço entre nós.
- Medir RPO/RTO e entregar um runbook reproduzível com critérios de parada e recuperação.

## O que o backup precisa recuperar

RPO é quanto estado pode ser perdido; RTO é quanto tempo até recuperar o serviço. Se o snapshot é de 10:00 e a falha ocorre às 10:10, até dez minutos de alterações da API podem ficar de fora. Se a operação volta às 10:25, foram quinze minutos de recuperação. Esses números só fazem sentido junto com o escopo: recuperar API não comprova que o banco da aplicação voltou.

Snapshot do etcd guarda objetos da API, inclusive Secrets; não guarda conteúdo de EBS/PVC, imagens, PKI do disco nem infraestrutura AWS. Git, snapshot, PKI protegida e backup de aplicação resolvem partes diferentes. Um PVC reaparecer após restore não faz um EBS excluído reaparecer. Nosso marcador exercita apenas estado da API; o módulo 04 é a referência interna para dados de volumes.

## 1. Inventário e preparação

**Na estação**, confirme o contexto e capture somente inventário sem segredos:

```bash
export KUBECONFIG="$HOME/.kube/curso-manutencao-kubeconfig"
kubectl config current-context
kubectl get nodes -o wide
kubectl version
kubectl -n kube-system get pods -o wide
kubectl get --raw='/readyz?verbose'
kubectl apply -f laboratorios/08-manutencao/prova.yaml
kubectl -n curso-manutencao get configmap prova -o yaml
kubectl apply -f laboratorios/07-troubleshooting/base.yaml
kubectl -n curso-incidentes rollout status deploy/web --timeout=180s
kubectl -n curso-incidentes wait --for=condition=Ready pod/diagnostico --timeout=120s
kubectl -n curso-incidentes exec diagnostico -- wget -T 3 -qO- http://web:8080
```

O contexto deve ser `curso-manutencao`, os IPs devem pertencer às VMs auxiliares e HTTP deve retornar `incidente-resolvido`. Se aparecer `curso-kubeadm` ou o IP do CP principal, pare e corrija o alvo antes de qualquer alteração. Ao conectar por SSH, confira `hostnamectl` e `ip -br address`; nomes iguais entre clusters não substituem validar o IP.

**Por SSH no CP**, examine os argumentos reais; não presuma os caminhos se seu cluster foi customizado:

```bash
sudo sed -n '1,240p' /etc/kubernetes/manifests/etcd.yaml
sudo kubeadm certs check-expiration
sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock ps
df -h /var/lib/etcd /var/backups
```

Anote imagem/versão do etcd, `--name`, `--initial-advertise-peer-urls`, `--initial-cluster`, caminhos de CA/cert/key e hostPath de `etcd-data`. O nome e a URL de peer serão usados literalmente no restore da mesma VM. `etcdctl` fala com o servidor; `etcdutl` inspeciona/restaura o snapshot offline. Usaremos utilitários da **mesma versão upstream** do servidor; a imagem Kubernetes pode adicionar sufixo como `-0`, que não faz parte da versão do tarball.

Preparação **no CP**: encontre a linha `image:` do manifesto e informe a versão upstream `v3.6.N` correspondente. Exemplo: imagem terminada em `:3.6.8-0` corresponde a `v3.6.8`. O exemplo explica a conversão; a versão a instalar é a que você acabou de observar.

```bash
read -r -p 'Versão upstream do etcd observado (v3.6.N): ' CURSO_ETCD_VERSION
[[ "$CURSO_ETCD_VERSION" =~ ^v3\.6\.[0-9]+$ ]] || { printf 'Este runbook requer etcd 3.6; confira o manifesto.\n'; exit 1; }
CURSO_ETCD_TMP=$(mktemp -d)
CURSO_ETCD_ASSET="etcd-${CURSO_ETCD_VERSION}-linux-amd64.tar.gz"
curl --fail --location \
  "https://github.com/etcd-io/etcd/releases/download/${CURSO_ETCD_VERSION}/${CURSO_ETCD_ASSET}" \
  --output "${CURSO_ETCD_TMP}/${CURSO_ETCD_ASSET}" || exit 1
curl --fail --location \
  "https://github.com/etcd-io/etcd/releases/download/${CURSO_ETCD_VERSION}/SHA256SUMS" \
  --output "${CURSO_ETCD_TMP}/SHA256SUMS" || exit 1
CURSO_ETCD_SHA=$(awk -v nome="$CURSO_ETCD_ASSET" '$2 == nome {print $1}' "${CURSO_ETCD_TMP}/SHA256SUMS")
[[ "$CURSO_ETCD_SHA" =~ ^[a-fA-F0-9]{64}$ ]] || { printf 'Checksum do artefato não encontrado.\n'; exit 1; }
printf '%s  %s\n' "$CURSO_ETCD_SHA" "${CURSO_ETCD_TMP}/${CURSO_ETCD_ASSET}" | sha256sum --check - || exit 1
tar -xzf "${CURSO_ETCD_TMP}/${CURSO_ETCD_ASSET}" -C "${CURSO_ETCD_TMP}"
sudo install -m 0755 "${CURSO_ETCD_TMP}/etcd-${CURSO_ETCD_VERSION}-linux-amd64/etcdctl" /usr/local/bin/etcdctl
sudo install -m 0755 "${CURSO_ETCD_TMP}/etcd-${CURSO_ETCD_VERSION}-linux-amd64/etcdutl" /usr/local/bin/etcdutl
etcdctl version
etcdutl version
```

Espere `OK` na verificação e a mesma versão em `etcdctl version` e `etcdutl version`. O checksum detecta divergência em relação ao artefato publicado por HTTPS; não substitui confiança no distribuidor. Nenhuma página externa precisa ser aberta para obter o hash. Estes comandos não atualizam o servidor etcd. Se a série não for 3.6, o cluster está fora desta base guiada: não troque o servidor nem remova flags de restore para encaixar a receita.

## 2. Backup consistente e verificável

**No CP**, estes caminhos são os padrões kubeadm. Valide-os com o manifesto. O certificado healthcheck-client permite a conexão mTLS local. Garanta que `/var/backups/curso-etcd/antes.db` não existe antes da primeira execução; para novas sessões use outro nome e registre-o, sem sobrescrever backups anteriores.

```bash
sudo install -d -m 0700 /var/backups/curso-etcd
sudo test ! -e /var/backups/curso-etcd/antes.db || { printf 'Backup já existe; preserve-o antes de repetir.\n'; exit 1; }
sudo test ! -e /var/backups/curso-etcd/kubernetes-antes || { printf 'Cópia anterior já existe; não sobreponha.\n'; exit 1; }
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

`etcdutl snapshot status` informa hash, revisão, tamanho e número de chaves do banco; a restauração também verificará o checksum incorporado ao snapshot criado por `etcdctl`. `sha256sum` permite comparar cópias byte a byte. Registre esses resultados, horário UTC e versão. A cópia de `/etc/kubernetes` inclui material que concede acesso ao cluster; proteja também eventual chave de criptografia de Secrets fora desse diretório. Não publique snapshots, PKI ou kubeconfigs.

O snapshot online é capturado por uma operação do servidor, com verificação de integridade. Copiar um arquivo de banco arbitrário de etcd em execução não oferece a mesma garantia. Um `endpoint health` bem-sucedido comprova comunicação/saúde naquele momento; só uma restauração comprovará que o backup produz o estado esperado.

### Manter uma cópia recuperável fora do CP

Ainda **no CP**, como usuário normal com sudo, crie um pacote cifrado. GnuPG solicitará uma senha forte pelo terminal; guarde-a num cofre separado da VM. A senha não aparece em argumento de processo nem no histórico. O diretório temporário criado pertence ao seu usuário e permite transferência por SSH sem abrir permissões dos originais.

```bash
set -o pipefail
CURSO_ENVIO_DIR=$(mktemp -d)
sudo tar -C /var/backups/curso-etcd -cf - antes.db kubernetes-antes | \
  gpg --symmetric --cipher-algo AES256 --output "$CURSO_ENVIO_DIR/curso-etcd.tar.gpg" || exit 1
# Se a cadeia acima falhar, pare; não transfira um pacote parcial.
(cd "$CURSO_ENVIO_DIR" && sha256sum curso-etcd.tar.gpg > curso-etcd.tar.gpg.sha256)
printf 'Diretório para copiar por SSH: %s\n' "$CURSO_ENVIO_DIR"
```

**Na estação**, use o diretório exibido, o usuário SSH do curso e o endpoint privado. A cópia fica num diretório dedicado; não sobrescreva uma recuperação anterior.

```bash
CURSO_RECEBIDO_DIR=$(mktemp -d)
read -r -p 'Diretório exibido no CP, começando por /tmp/: ' CURSO_ENVIO_CP
[[ "$CURSO_ENVIO_CP" =~ ^/tmp/tmp\.[a-zA-Z0-9]+$ ]] || { printf 'Confira o diretório exato criado por mktemp.\n'; exit 1; }
scp "ubuntu@lab-manutencao.internal:${CURSO_ENVIO_CP}/curso-etcd.tar.gpg" "$CURSO_RECEBIDO_DIR/"
scp "ubuntu@lab-manutencao.internal:${CURSO_ENVIO_CP}/curso-etcd.tar.gpg.sha256" "$CURSO_RECEBIDO_DIR/"
(cd "$CURSO_RECEBIDO_DIR" && sha256sum --check curso-etcd.tar.gpg.sha256)
set -o pipefail
gpg --decrypt "$CURSO_RECEBIDO_DIR/curso-etcd.tar.gpg" | tar -tf -
```

Espere checksum `OK`, senha aceita e listagem contendo `antes.db` e `kubernetes-antes/`. O último comando lista nomes, sem extrair chaves privadas nem imprimir seus conteúdos. Isso verifica a chave de recuperação e a cópia externa; o restore usará o original do CP, cujo hash é o mesmo registrado antes de empacotar. Registre a localização protegida e a retenção do pacote. Uma cópia cifrada cuja senha também foi perdida não é recuperável.

## 3. Restaurar e provar a volta do estado

**Na estação**, mude somente o marcador após o backup:

```bash
kubectl -n curso-manutencao patch configmap prova --type=merge -p '{"data":{"fase":"depois"}}'
kubectl -n curso-manutencao get configmap prova -o jsonpath='{.data.fase}'
```

Espere `depois`. A restauração a seguir reverte **todo o estado da API** ao instante do snapshot, não só o ConfigMap; por isso ela exige o cluster descartável dedicado.

**No CP**, execute `etcdutl snapshot restore --help` e localize apenas `--bump-revision` e `--mark-compacted`; a consulta termina ao confirmar que existem. A revisão do etcd cresce a cada alteração. Após voltar a um snapshot antigo, controllers poderiam esperar revisões que ainda não existem no estado restaurado. Bump avança o contador e mark-compacted invalida as revisões antigas para que os clientes reconstruam seus caches. O incremento de um bilhão é conservador para a pequena carga do lab. As duas flags devem existir no utilitário 3.6 instalado; ausência indica binário errado ou PATH incorreto, não autorização para removê-las.

Antes de parar componentes, execute no CP o comando mTLS de saúde do passo 2 trocando o final por `member list --write-out=table`. Deve haver **um membro**, com nome e peer URL iguais aos anotados. Se houver mais de um, este procedimento de restauração não se aplica. Informe os valores confirmados:

```bash
read -r -p 'Nome do único membro etcd, igual ao manifesto: ' CURSO_ETCD_NOME
read -r -p 'Peer URL desse membro (https://IP_PRIVADO:2380): ' CURSO_ETCD_PEER
[[ "$CURSO_ETCD_NOME" =~ ^[a-zA-Z0-9._-]+$ ]] || exit 1
[[ "$CURSO_ETCD_PEER" =~ ^https://[0-9.]+:2380$ ]] || exit 1
sudo test ! -e /var/backups/curso-etcd/manifests-pausados || { printf 'Há uma tentativa anterior; identifique sua fase antes de continuar.\n'; exit 1; }
sudo test ! -e /var/lib/etcd-restaurado-curso || { printf 'Diretório de restore já existe; não sobreponha dados.\n'; exit 1; }
```

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
sudo test ! -e /var/lib/etcd-restaurado-curso || exit 1
sudo etcdutl snapshot restore /var/backups/curso-etcd/antes.db \
  --data-dir=/var/lib/etcd-restaurado-curso \
  --name="$CURSO_ETCD_NOME" \
  --initial-cluster="${CURSO_ETCD_NOME}=${CURSO_ETCD_PEER}" \
  --initial-advertise-peer-urls="$CURSO_ETCD_PEER" \
  --initial-cluster-token=curso-restauracao-1 \
  --bump-revision=1000000000 --mark-compacted
sudoedit /var/backups/curso-etcd/manifests-pausados/etcd.yaml
```

No manifesto pausado, altere **somente** `volumes[].hostPath.path` do volume chamado `etcd-data` de `/var/lib/etcd` para `/var/lib/etcd-restaurado-curso`. O `volumeMount.mountPath` e o argumento `--data-dir=/var/lib/etcd` **dentro do container** continuam iguais. Confirme nome, peer URL e certificados adequados à mesma VM. Compare com o backup usando `sudo diff -u /var/backups/curso-etcd/kubernetes-antes/manifests/etcd.yaml /var/backups/curso-etcd/manifests-pausados/etcd.yaml`; somente o hostPath deverá ter mudado.

```bash
sudo mv /var/backups/curso-etcd/manifests-pausados/etcd.yaml /etc/kubernetes/manifests/
sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock ps
```

Aguarde etcd Running, leia seus logs e repita `endpoint health` do passo 2. Só depois de obter saúde confirmada, devolva a API:

```bash
sudo mv /var/backups/curso-etcd/manifests-pausados/kube-apiserver.yaml /etc/kubernetes/manifests/
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get --raw='/readyz?verbose'
```

Repita apenas o comando de consulta até a API ficar pronta. Se falhar, investigue o componente antes de avançar. Com `/readyz` aprovado, devolva os controllers:

```bash
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

O valor deve ser `antes`. Isso prova retorno do snapshot; endpoint health sozinho não provaria recuperação do estado desejado. Registre tempo total, estado perdido e diferenças de UID/objetos. Para comprovar reconciliação e dataplane, execute na estação a base do módulo 07 e seu teste:

```bash
kubectl apply -f laboratorios/07-troubleshooting/base.yaml
kubectl -n curso-incidentes rollout status deploy/web --timeout=180s
kubectl -n curso-incidentes wait --for=condition=Ready pod/diagnostico --timeout=120s
kubectl -n curso-incidentes exec diagnostico -- wget -T 3 -qO- http://web:8080
```

Se já havia política de falha em `curso-incidentes` no momento do backup, ela também voltou: encerre os incidentes conforme módulo 07 antes deste teste. Os critérios são marcador `antes`, `/readyz` aprovado, nós Ready e resposta `incidente-resolvido`.

Depois de comprovar a restauração, registre o diretório ativo na configuração que kubeadm reutilizará. Na estação, execute `kubectl -n kube-system edit configmap kubeadm-config`; dentro da string YAML `data.ClusterConfiguration`, altere **somente** `etcd.local.dataDir` para `/var/lib/etcd-restaurado-curso`, mantendo a indentação. Esse valor não é uma chave solta do ConfigMap. Confira o resultado com `kubectl -n kube-system get configmap kubeadm-config -o jsonpath='{.data.ClusterConfiguration}'`:

```yaml
# Trecho dentro de ClusterConfiguration; preserve os demais campos existentes.
etcd:
  local:
    dataDir: /var/lib/etcd-restaurado-curso
```

Isso não move arquivos nem reinicia o etcd atual. Evita que um upgrade posterior regenere o manifesto com o diretório antigo. O ConfigMap contém YAML como texto e não valida automaticamente seus campos; copie o valor extraído para `/tmp/curso-clusterconfiguration.yaml` no CP e execute `sudo kubeadm config validate --config /tmp/curso-clusterconfiguration.yaml` antes de seguir. No próximo upgrade, kubeadm poderá usar esse caminho tanto no host quanto dentro do container, mantendo o mesmo conjunto restaurado de dados. Não altere `imageTag` para fixar o etcd manualmente.

Se falhar antes de subir a API, mantenha API/controllers pausados, leia logs do container etcd pelo ID em `crictl ps -a` e valide hostPath, nome, peer URL, certificado e permissões. Se a API já tiver voltado, pause novamente os três componentes do control plane, esperando a parada, antes de trocar o data directory. Para abandonar a tentativa e retornar ao estado anterior à parada, retire o `etcd.yaml` restaurado do watch directory, aguarde etcd parar e copie o manifesto **original** de `/var/backups/curso-etcd/kubernetes-antes/manifests/etcd.yaml` para `/etc/kubernetes/manifests/etcd.yaml`. Ele aponta ao diretório antigo intacto. Valide etcd e só então recoloque API/controllers, nessa ordem. Confira também `etcd.local.dataDir` no ConfigMap: o estado antigo contém o caminho original, que deve corresponder ao hostPath ativo.

Preserve o manifesto modificado em arquivo fora do watch directory para diagnóstico; não o sobreponha à cópia original. A saída abandona o restore e retorna ao estado `depois`; não deve ser registrada como restauração bem-sucedida. Nunca copie arquivos entre dois data dirs ativos. Em HA, recuperar um membro isoladamente dessa maneira é incorreto: membership, quórum e impedimento de escritores antigos precisam de outro procedimento.

## 4. Certificados: renovar e carregar os novos arquivos

Faça em sessão separada. Certificados carregam a identidade do servidor/cliente e têm validade; renovar o arquivo no disco não força todos os processos a relê-lo. A CA assina esses certificados. Na base kubeadm, as chaves da CA estão presentes no CP e permitem renovar os certificados geridos por kubeadm; rotação de CA é outra operação.

**No CP**, confira validade e a coluna de gerenciamento externo. O ambiente deste exercício deve mostrar certificados geridos localmente; `EXTERNALLY MANAGED=true` indica que este runbook não se aplica àquela identidade. Faça uma cópia atual antes da renovação, em destino novo:

```bash
sudo kubeadm certs check-expiration
sudo openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -serial -dates
CURSO_CERT_BACKUP="/var/backups/curso-etcd/certificados-$(date -u +%Y%m%dT%H%M%SZ)"
sudo test ! -e "$CURSO_CERT_BACKUP" || exit 1
sudo cp -a /etc/kubernetes "$CURSO_CERT_BACKUP"
sudo kubeadm certs renew all
sudo kubeadm certs check-expiration
```

`renew all` não resolve CAs externas, rotação da CA ou todo certificado do kubelet. Os certificados serving dos kubelets preparados no módulo 05 têm seu próprio mecanismo de CSR/renovação. Reinicie os static pods **um de cada vez** para carregar os novos arquivos. O procedimento abaixo é uma unidade: execute para `etcd`, depois repita escolhendo `kube-apiserver`, `kube-controller-manager` e `kube-scheduler`, nessa ordem.

```bash
# CP — escolha exatamente um componente por vez.
read -r -p 'Componente (etcd, kube-apiserver, kube-controller-manager, kube-scheduler): ' CURSO_COMPONENTE
case "$CURSO_COMPONENTE" in
  etcd|kube-apiserver|kube-controller-manager|kube-scheduler) ;;
  *) printf 'Nome de componente inválido.\n'; exit 1 ;;
esac
CURSO_STATIC_PAUSA=$(sudo mktemp -d /var/backups/curso-etcd/reinicio.XXXXXX)
sudo mv "/etc/kubernetes/manifests/${CURSO_COMPONENTE}.yaml" "$CURSO_STATIC_PAUSA/"
sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock ps --name "$CURSO_COMPONENTE"
```

Aguarde pelo menos um ciclo de leitura de manifests, normalmente 20 segundos, e repita apenas `crictl ps` até esse container não estar Running. **Somente então** recoloque o manifesto:

```bash
sudo mv "$CURSO_STATIC_PAUSA/${CURSO_COMPONENTE}.yaml" /etc/kubernetes/manifests/
sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock ps --name "$CURSO_COMPONENTE"
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get --raw='/readyz?verbose'
```

Espere o componente Running e API saudável antes de escolher o seguinte. Após etcd, repita também seu `endpoint health` mTLS. Se o container novo não subir, mantenha os arquivos atuais, leia seus logs por `crictl` e compare caminhos de certificados ao manifesto; não avance com outro componente quebrado. Não use `kubectl delete pod` no mirror pod como substituto do reinício real.

Neste lab de um CP haverá breves interrupções. Para provar que o API Server carregou o certificado, **no CP**, compare o serial em disco ao servido na conexão TLS:

```bash
sudo openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -serial -dates
openssl s_client -connect lab-manutencao.internal:6443 -servername lab-manutencao.internal \
  -CAfile /etc/kubernetes/pki/ca.crt -verify_hostname lab-manutencao.internal \
  -verify_return_error </dev/null 2>/dev/null | openssl x509 -noout -serial -dates
```

Os seriais devem coincidir e ser novos em relação ao registro anterior. Para atualizar a credencial copiada, **no CP, como usuário SSH normal**, execute `sudo install -o "$(id -u)" -g "$(id -g)" -m 600 /etc/kubernetes/admin.conf "$HOME/.kube/config"`. **Na estação**, recopie para o arquivo exclusivo do curso, sem sobrescrever configurações de outros clusters:

```bash
scp ubuntu@lab-manutencao.internal:.kube/config "$HOME/.kube/curso-manutencao-kubeconfig"
chmod 600 "$HOME/.kube/curso-manutencao-kubeconfig"
export KUBECONFIG="$HOME/.kube/curso-manutencao-kubeconfig"
kubectl config rename-context kubernetes-admin@kubernetes curso-manutencao
kubectl get --raw='/readyz?verbose'
```

A cópia antiga pode continuar válida até sua expiração, pois renovação não é revogação. O objetivo aqui é distribuir e testar a credencial nova. Em HA, além da renovação por CP, seria necessário preservar quórum durante reinícios; essa topologia será praticada posteriormente, não nesta restauração de um membro.

## 5. Upgrade sequencial: 1.35 → 1.36

Primeiro pratique atualização de patch dentro de 1.35; depois repita a sequência para 1.36. Um patch corrige uma linha minor; mudar o minor pode alterar APIs e comportamento. Não salte de 1.35 para 1.37. Durante a transição, kubelet não pode estar à frente do API Server. Neste exercício, deixaremos no máximo uma linha de diferença e terminaremos com todos os componentes na versão escolhida. `kubectl` 1.35 consegue operar API 1.36 durante a mudança, pois o cliente admite diferença de um minor.

### Conferir o conjunto que será atualizado

A compatibilidade deste percurso está delimitada pelas versões anteriores. A tabela registra o critério de compatibilidade declarado pelos fornecedores para **1.35 e 1.36**, e não uma afirmação de teste em seu cluster. O auxiliar precisa apenas de Calico e Metrics Server; Traefik/EBS estão listados para a extensão de quem reproduzir esses componentes, não são instalações obrigatórias desta aula:

| Componente da base | Critério e ação neste upgrade |
| --- | --- |
| Calico 3.32.2 | A série 3.32 declara testes nas duas versões; preserve VXLAN e datastore Kubernetes do módulo 01 |
| Traefik chart 41.5.0 / aplicação 3.7.13 | O chart aceita Kubernetes >= 1.25; mantenha também Gateway API 1.6.1 do módulo 03 |
| Metrics Server chart 3.13.0 / aplicação 0.8.0 | A série 0.8 declara Kubernetes >= 1.31; preserve certificados serving e conectividade 10250 do módulo 05 |
| EBS CSI chart 2.63.1 / driver 1.63.1, quando instalado | O driver suporta linhas Kubernetes mantidas; 1.35/1.36 estão no recorte desta edição. Preserve IAM e topologia do módulo 04 |
| Objetos nativos fornecidos | Deployments `apps/v1`, PDB `policy/v1`, HPA `autoscaling/v2`, StorageClass `storage.k8s.io/v1` e NetworkPolicy `networking.k8s.io/v1` continuam no alvo |

Na estação, confira `helm list -A`, `kubectl -n calico-system get daemonset calico-node -o jsonpath='{.spec.template.spec.containers[*].image}'` e `kubectl -n kube-system get pods -o wide`. Compare ao seu registro dos módulos anteriores. Se adicionou operadores ou mudou versões, essa extensão não está coberta pela tabela; conclua o ensaio na base delimitada antes de projetar a atualização do ambiente modificado.

Um exemplo de consulta limitada, que não instala Traefik, é `helm show chart traefik/traefik --version 41.5.0`: localize `kubeVersion` e conclua quando confirmar que 1.36 está no intervalo. Quem reproduziu Traefik no auxiliar pode também executar `helm template traefik traefik/traefik --version 41.5.0 --namespace traefik --kube-version 1.36.0 -f laboratorios/03-rede/traefik-values.yaml`. Isso confere metadados/templates, não substitui seus testes HTTP/TLS após o upgrade.

Na estação, registre versão, saúde da API, DNS, HTTP, métricas e leitura de um arquivo já existente no PVC, se a trilha AWS estiver ativa. No CP, capture **novo snapshot e cópia de `/etc/kubernetes`** repetindo a seção 2 com nomes novos, como `pre-upgrade.db` e `kubernetes-pre-upgrade`; nunca sobreponha os originais usados na prova de restauração. Preserve a versão do servidor e o caminho de dados atual junto desse backup. Confira espaço e expiração. Reserve uma janela de indisponibilidade da API.

### Primeiro control plane

**Por SSH no CP**, o arquivo do módulo 01 é `/etc/apt/sources.list.d/kubernetes.list`. Confirme seu conteúdo com `sudo sed -n '1,40p' /etc/apt/sources.list.d/kubernetes.list`; deve conter somente a fonte Kubernetes com `signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg`. Para patch permaneça em `v1.35`; para o segundo ensaio altere apenas o segmento da URL para `v1.36`. A linha resultante para o minor novo é:

```text
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /
```

O endereço do repositório escolhe a série disponível, não efetua upgrade do cluster. Guarde sua cópia fora de `sources.list.d`, para o apt não interpretar duas fontes como ativas.

```bash
CURSO_APT_BACKUP="/var/backups/curso-etcd/kubernetes-apt-$(date -u +%Y%m%dT%H%M%SZ).list"
sudo test ! -e "$CURSO_APT_BACKUP" || exit 1
sudo cp -a /etc/apt/sources.list.d/kubernetes.list "$CURSO_APT_BACKUP"
sudoedit /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
apt-cache madison kubeadm
apt-cache madison kubelet
apt-cache madison kubectl
```

Escolha uma **versão exata presente nas três listas**, superior à instalada, no minor do ensaio. O texto tem formato `1.36.N-1.1`: `N` é o patch real e o sufixo é parte da versão Debian. Não use literal `PATCH`, `latest` nem wildcard. Copie a string uma vez e reutilize-a em todos os nós. Se não há patch mais novo na 1.35, registre esse resultado e faça o ensaio minor 1.36; não faça downgrade para fabricar uma atualização.

```bash
read -r -p 'Versão Debian exata escolhida nas três listas: ' CURSO_PKG_VERSION
[[ "$CURSO_PKG_VERSION" =~ ^1\.(35|36)\.[0-9]+-[a-zA-Z0-9.+~]+$ ]] || { printf 'Formato fora da base 1.35/1.36.\n'; exit 1; }
CURSO_K8S_VERSION="v${CURSO_PKG_VERSION%%-*}"
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm="${CURSO_PKG_VERSION}" || { sudo apt-mark hold kubeadm; exit 1; }
sudo apt-mark hold kubeadm
kubeadm version
sudo kubeadm upgrade plan
```

Pare nesse checkpoint: `kubeadm version` deve corresponder ao alvo escolhido; no `upgrade plan`, confirme versão atual/alvo, saúde de componentes e ausência de preflight errors. O alvo deve ser o patch ou o minor imediatamente seguinte escolhido. Só depois dessa conferência, execute no CP:

```bash
sudo kubeadm upgrade apply "${CURSO_K8S_VERSION}"
```

O comando atualiza static pods do control plane, inclui mudanças de etcd quando prescritas por kubeadm e renova certificados geridos localmente por padrão. Ele não troca automaticamente binários kubelet nos hosts nem atualiza charts Helm.

Se o plano indicar outra topologia, downgrade, salto de minor ou falha de preflight, pare antes da aplicação e corrija o desvio observável. Se `upgrade apply` falhar, registre a primeira falha, verifique `/readyz`, `crictl ps -a` e logs do componente afetado. Não atualize workers enquanto o CP não estiver saudável, nem use `--force`/reinstalação como primeira tentativa. O backup e a reconstrução do laboratório na versão anterior são a saída de recuperação; downgrade de pacotes isolados não desfaz uma atualização de estado do cluster.

**Na estação**, drene o CP pelo nome real antes de atualizar seu kubelet:

```bash
kubectl get pods -A -o wide --field-selector spec.nodeName=NOME_CP
kubectl drain NOME_CP --ignore-daemonsets --timeout=180s
```

Mirror pods do control plane não são evictados pelo drain; revise bloqueios de PDB/emptyDir antes de qualquer flag extra. **No CP**, depois do drain:

```bash
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet="${CURSO_PKG_VERSION}" kubectl="${CURSO_PKG_VERSION}" || { sudo apt-mark hold kubelet kubectl; exit 1; }
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet
sudo systemctl is-active kubelet
```

**Na estação**, execute `kubectl wait --for=condition=Ready node/NOME_CP --timeout=180s`, confira versão com `kubectl get nodes` e API com `kubectl get --raw='/readyz?verbose'`; só então `kubectl uncordon NOME_CP`. Em HA a ordem incluiria os outros CPs, usando `kubeadm upgrade node` neles, um por vez, antes dos workers; este ambiente tem apenas o primeiro CP.

### Um worker por vez

**Na estação**, escolha o nome real do primeiro worker e execute:

```bash
read -r -p 'Worker desta rodada, como aparece em kubectl get nodes: ' CURSO_WORKER
kubectl get node "$CURSO_WORKER"
kubectl get pods -A -o wide --field-selector "spec.nodeName=$CURSO_WORKER"
kubectl get pdb -A
kubectl describe node "$CURSO_WORKER"
```

Compare requests dos pods que sairão com capacidade dos outros nós. Um PDB com zero interrupções permitidas, volume local sem destino ou EBS sem outro worker na AZ pode impedir a manutenção. Resolva capacidade/regras como no módulo 05; não use `--force`, `--disable-eviction` ou perda de `emptyDir` sem uma decisão sobre os dados.

O cliente `curso-incidentes/diagnostico` é um Pod sem controller, portanto drain não deve destruí-lo como se houvesse reposição automática. Depois do teste HTTP inicial, retire explicitamente esse cliente descartável com `kubectl -n curso-incidentes delete pod diagnostico`. O servidor `web` é um Deployment e será reconciliado. No inventário dos outros namespaces, encerre também Pods avulsos de exercícios já concluídos usando seus nomes exatos e manifests de recuperação; não remova workloads com dados desconhecidos. Então drene **sem** seletor: `kubectl drain "$CURSO_WORKER" --ignore-daemonsets --timeout=180s`. Se não terminar, não atualize aquele host ainda.

**Por SSH nesse worker**, repita a cópia/edição do repositório apt e a consulta de versões do CP, usando o mesmo minor. Como `/var/backups/curso-etcd` é do CP, no worker guarde a fonte apt em `/var/backups/kubernetes-apt-antes.list`, verificando antes que esse arquivo não existe. As variáveis de uma sessão SSH não passam a outra; informe a **mesma versão Debian exata escolhida no CP**:

```bash
read -r -p 'Mesma versão Debian exata instalada no CP: ' CURSO_PKG_VERSION
[[ "$CURSO_PKG_VERSION" =~ ^1\.(35|36)\.[0-9]+-[a-zA-Z0-9.+~]+$ ]] || exit 1
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm="$CURSO_PKG_VERSION" || { sudo apt-mark hold kubeadm; exit 1; }
sudo apt-mark hold kubeadm
kubeadm version
sudo kubeadm upgrade node || exit 1
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet="$CURSO_PKG_VERSION" kubectl="$CURSO_PKG_VERSION" || { sudo apt-mark hold kubelet kubectl; exit 1; }
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet
sudo systemctl is-active kubelet
```

`upgrade node` atualiza a configuração deste nó; o plano global já foi aplicado no CP. **Na estação**, valide antes de seguir:

```bash
kubectl wait --for=condition=Ready "node/$CURSO_WORKER" --timeout=180s
kubectl get node "$CURSO_WORKER" -o wide
kubectl uncordon "$CURSO_WORKER"
kubectl apply -f laboratorios/07-troubleshooting/base.yaml
kubectl -n curso-incidentes wait --for=condition=Ready pod/diagnostico --timeout=120s
kubectl -n curso-incidentes exec diagnostico -- wget -T 3 -qO- http://web:8080
kubectl top nodes
```

Confirme versão exata, HTTP esperado e métricas numéricas. Se a aplicação usa PVC, repita a leitura do arquivo registrada antes da manutenção. Só então escolha o segundo worker e repita **toda a sequência**. Uncordon não move automaticamente os pods de volta ao nó; o objetivo é torná-lo disponível a novos agendamentos.

Não rode `kubeadm init` novamente para fazer upgrade. Compare no fim versões, pods do sistema, DNS, HTTP, métricas e dados do PVC. Mantenha os pacotes em hold: `apt-mark showhold` deve listar kubeadm, kubelet e kubectl em cada host. Os charts ficaram nas versões da tabela, pois não requerem mudança para este ensaio. Atualizá-los será uma alteração própria, com seu plano, evidência e recuperação.

## Avaliação operacional

Desafio sem receita: outra pessoa recebe seu runbook e deve restaurar o marcador num cluster descartável equivalente, medir RTO e explicar o RPO. Em seguida planeje um upgrade com um PDB inicialmente bloqueando um worker. Você precisa justificar a correção de capacidade/disponibilidade e demonstrar uma execução concluída.

Rubrica: backup com integridade e proteção (2), restauração comprovada por marcador e reconciliação (3), renovação efetivamente carregada (2), upgrade sequencial com versões e saúde verificadas (3). Preencha [registro da manutenção](../laboratorios/08-manutencao/registro.md), sem anexar segredos. Não apague diretórios de backup/data antigos durante o aprendizado; arquive cifrado e decida retenção após a validação.

## Fechamento

Você praticou recuperar estado, renovar identidade e mudar versões como operações diferentes. Responda sem consultar os comandos: o que fica fora do snapshot? Por que o hostPath muda no restore, mas o caminho interno do container não? Qual problema revision bump e compactação resolvem? Como comprovar que o processo carregou o certificado novo? Por que o worker não deve ser atualizado antes da API?

Avance com **8/10 e restauração comprovada**. Um snapshot existente, certificado renovado apenas no disco ou pacote instalado sem serviço validado não conclui os respectivos objetivos. A entrega inclui RPO/RTO medidos, cópia externa decifrável, marcador restaurado, serial servido correto e todos os nós no alvo com holds e aplicação saudável.

HA, restauração em outra máquina/AZ, troca de CA e upgrade de operadores arbitrários ficam fora deste runbook delimitado. Preserve backups e a localização do diretório etcd ativo; excluir `curso-manutencao` remove apenas o marcador, não os backups do host.

Para encerrar os custos, guarde as evidências e o pacote cifrado já testado fora das VMs. Confira no inventário os **três IDs das instâncias auxiliares**, IPs, discos e registros DNS; termine apenas essas instâncias pelo mesmo mecanismo de criação usado no módulo 01. Verifique `DeleteOnTermination` de cada disco e volumes/snapshots que eventualmente ficaram cobrando. Exclua um volume remanescente somente depois de confirmar seu ID, vínculo com o auxiliar e ausência de dados a preservar. Não há comando de destruição por nome ou prefixo nesta aula. Não deixe um registro `lab-manutencao.internal` apontando para uma instância já descartada.

Na estação, volte explicitamente ao principal, que continua em 1.35:

```bash
export KUBECONFIG="$HOME/.kube/curso-kubeconfig"
kubectl config current-context
kubectl get nodes -o wide
```

Espere `curso-kubeadm`, os IPs originais e versão 1.35. O ensaio não exige downgrade nem reconstrução oculta do principal. No próximo módulo, [09 — Entrega](09-entrega.md), você tratará a versão e a promoção das aplicações nesse ambiente preservado.

## Referências opcionais

Os procedimentos necessários ao ambiente desta aula estão acima. Estas leituras aprofundam outros limites e mecanismos; compatibilidade de fornecedores foi conferida em 12/09/2026.

- [Operação do etcd no Kubernetes](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/) — amplia opções de backup, topologias externas e integração com o control plane.
- [Recuperação etcd 3.6](https://etcd.io/docs/v3.6/op-guide/recovery/) — detalha revisões, compactação e alteração de membership, além do membro único praticado.
- [Instalação etcd](https://etcd.io/docs/v3.6/install/) — apresenta distribuições e plataformas diferentes dos binários AMD64 usados aqui.
- [Certificados kubeadm](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/) — aprofunda CA externa, tipos de certificados e processos de renovação separados.
- [Upgrade kubeadm](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/) — cobre outras topologias e diagnóstico de etapas do upgrade.
- [Version skew](https://kubernetes.io/releases/version-skew-policy/) — explica as diferenças máximas admitidas, além do intervalo estreito usado no laboratório.
- [Reconfiguração kubeadm](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-reconfigure/) — detalha a relação entre ConfigMap, manifests locais e campos reutilizados no upgrade.
- [Compatibilidade Calico](https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements) — detalha kernel, rede e plataformas suportadas pela série 3.32.
- [Metadados Traefik 41.5.0](https://github.com/traefik/traefik-helm-chart/blob/v41.5.0/traefik/Chart.yaml) — permite examinar a distinção entre versão do chart, da aplicação e intervalo de Kubernetes.
- [Matriz Metrics Server](https://github.com/kubernetes-sigs/metrics-server#compatibility-matrix) — compara outras séries e seus requisitos de Kubernetes.
- [Compatibilidade EBS CSI](https://github.com/kubernetes-sigs/aws-ebs-csi-driver#compatibility) — aprofunda política de suporte e limites do driver além do lab 1.35/1.36.
