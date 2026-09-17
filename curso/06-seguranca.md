# 06 — Identidade, autorização e isolamento

## Antes de começar

Reserve **16–20 horas**, em três sessões: identidade/RBAC, segurança do processo e políticas de rede. Você precisa ter concluído [02 — Workloads](02-workloads.md) e [03 — Rede](03-rede.md): saber ler um Pod/Deployment, usar ConfigMap, testar Service e resolver DNS dentro de um pod. Use o cluster kubeadm 1.35 com Calico e CoreDNS do curso, dois workers Ready e credencial administrativa do laboratório. Nenhuma ferramenta nova precisa ser instalada.

Execute os comandos na **estação**, na raiz do repositório, contexto `curso-kubeadm`. Os arquivos de [laboratorios/06-seguranca](../laboratorios/06-seguranca/) criam somente `curso-seguranca`. Não aplique negação global ou Restricted em `kube-system`. NodeLocal DNSCache, outro CNI, identidade AWS e configuração de KMS no API Server são adaptações fora deste laboratório guiado.

## O que você vai conseguir fazer

- Comprovar quais chamadas uma ServiceAccount pode e não pode realizar, inclusive restringindo leitura a um ConfigMap pelo nome.
- Explicar e inspecionar um token projetado sem expor seu conteúdo.
- Corrigir um pod recusado por Restricted e demonstrar execução não root e filesystem protegido.
- Provar, de dentro de pods, que DNS funciona e apenas o cliente autorizado alcança a aplicação.
- Criar um Secret com dados explicitamente fictícios, demonstrar montagem e atualização sem conceder leitura da API à aplicação, e descrever a rotação de uma credencial real fora do Git.

O objetivo é demonstrar três decisões distintas: **quem** faz uma chamada (autenticação), **o que** essa identidade pode fazer (autorização), e **quais configurações** podem ser admitidas (admission). Acrescente segurança do processo e do tráfego para obter defesa em camadas.

## Identidades e RBAC

Um kubeconfig normalmente reúne endpoint, CA e uma identidade cliente. Compartilhar `admin.conf` equivale a compartilhar poder administrativo. ServiceAccount identifica um workload dentro de um namespace; não é usuário Linux nem IAM Role. RBAC Kubernetes não concede permissões AWS. Uma Role declara verbos e recursos dentro de um namespace; RoleBinding liga a identidade a essas permissões. ClusterRole pode ser vinculada por RoleBinding com alcance namespaced; ClusterRoleBinding concede alcance de cluster.

Abra `rbac.yaml` antes de aplicá-lo. A regra `apiGroups: [""]` seleciona a API principal, onde estão Pods e ConfigMaps; `resources: [pods, pods/log]` distingue o objeto Pod do subrecurso de logs. `get` lê um objeto, `list` lista objetos e `watch` acompanha mudanças. O `subject` do binding é a identidade que recebe acesso; `roleRef` é a regra concedida. Nenhuma dessas regras inicia pods por si só.

```bash
kubectl config current-context
kubectl apply -f laboratorios/06-seguranca/base.yaml
kubectl apply -f laboratorios/06-seguranca/rbac.yaml
kubectl -n curso-seguranca rollout status deploy/web-seguro --timeout=120s
kubectl auth can-i list pods -n curso-seguranca \
  --as=system:serviceaccount:curso-seguranca:leitor
kubectl auth can-i delete pods -n curso-seguranca \
  --as=system:serviceaccount:curso-seguranca:leitor
kubectl auth can-i get secrets -n curso-seguranca \
  --as=system:serviceaccount:curso-seguranca:leitor
kubectl auth can-i list pods -n kube-system \
  --as=system:serviceaccount:curso-seguranca:leitor
```

Esperado: `yes`, `no`, `no`, `no`. `can-i` consulta autorização; não executa a ação nem testa a rede do pod. O operador que usa `--as` precisa de poder para impersonar; o laboratório usa administrador. `get pods --subresource=log` deve ser permitido; `create pods --subresource=exec`, negado. Troque o verbo/recurso nas chamadas anteriores para verificar essas duas decisões. Evite `verbs: ["*"]` e `resources: ["*"]`; ler Secrets ou criar pods privilegiados pode permitir escalada indireta.

Incidente controlado: execute `kubectl -n curso-seguranca delete rolebinding leitor`; repita o primeiro teste e confirme `no`. Recupere com `kubectl apply -f laboratorios/06-seguranca/rbac.yaml`. A identidade e a Role continuavam existindo, mas não havia ligação entre elas. Por isso recriar a ServiceAccount não resolveria.

Para restringir a leitura a **um nome**, existe `resourceNames`. Crie, com seu editor, `/tmp/curso-configmap-role.yaml` com este exemplo; o namespace deve existir antes:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: uma-configuracao
  namespace: curso-seguranca
rules:
  - apiGroups: [""]
    resources: [configmaps]
    resourceNames: [configuracao-web] # Somente este nome, no namespace da Role.
    verbs: [get] # Não concede list nem watch indiscriminados.
```

```bash
kubectl apply -f /tmp/curso-configmap-role.yaml
kubectl -n curso-seguranca create rolebinding uma-configuracao \
  --role=uma-configuracao --serviceaccount=curso-seguranca:leitor
kubectl auth can-i get configmap/configuracao-web -n curso-seguranca \
  --as=system:serviceaccount:curso-seguranca:leitor
kubectl auth can-i get configmap/outra -n curso-seguranca \
  --as=system:serviceaccount:curso-seguranca:leitor
```

Espere `yes` e `no`, mesmo sem criar os ConfigMaps: autorização avalia a chamada, não a existência do objeto. Permissões RBAC são aditivas; este binding acrescenta leitura ao acesso de Pods anterior. Uma outra Role ampla não seria anulada pela regra restrita. Para repetir a criação imperativa do binding, primeiro confira se ele já existe com `kubectl -n curso-seguranca get rolebinding uma-configuracao`.

## Tokens e Secrets

Um token é uma credencial apresentada ao servidor, não uma lista autossuficiente de permissões. Tokens de ServiceAccount podem ser projetados no pod, ter audience — o destinatário que pode aceitá-los — e validade, e ser renovados pelo kubelet. A autorização continuará vindo do RBAC. A aplicação precisa reler o arquivo, não guardar o token original indefinidamente. Desabilite o automount quando o processo não chama a API. O exemplo `web-seguro` faz isso; o pod `identidade` recebe um volume projetado explícito, portanto não depende do automount.

No arquivo `identidade.yaml`, `serviceAccountName: leitor` escolhe a identidade. O volume `projected` combina três fontes em um diretório: token solicitado por uma hora, CA do cluster e namespace obtido do próprio Pod por Downward API. Audience omitida usa o destinatário padrão da API. Montar esses arquivos não envia chamadas automaticamente e não transforma o pod em administrador.

```bash
kubectl apply -f laboratorios/06-seguranca/identidade.yaml
kubectl -n curso-seguranca wait --for=condition=Ready pod/identidade --timeout=120s
kubectl -n curso-seguranca exec identidade -- ls -l /var/run/curso
kubectl -n curso-seguranca get pod identidade -o yaml
```

Inspecione nomes, permissões, ServiceAccount e `expirationSeconds`; **não imprima o token** nas evidências. O kubelet obtém o token via TokenRequest e atualiza a projeção. Um token curto criado por `kubectl create token leitor --duration=10m -n curso-seguranca` é útil para um teste humano explícito, mas sua saída é segredo: não o execute em gravações nem o salve no Git. Não crie Secrets de token permanente por hábito.

Secret codificado em base 64 não está criptografado. Uma aplicação comum pode receber um Secret montado como arquivo; a ServiceAccount do processo não precisa ganhar `get secrets` para o kubelet fazer essa montagem autorizada. Quem consegue criar workloads que montam Secrets também pode obter seus dados, então limitar apenas chamadas de leitura não basta. Montagem por volume pode receber atualizações; variável de ambiente só muda quando o processo é recriado. O aplicativo ainda precisa reler ou recarregar a configuração.

Para o plano exigido no fim da aula, descreva esta sequência: um operador ou integração autorizada obtém o valor no cofre, entrega-o à API sem arquivo versionado, o kubelet projeta o Secret só no workload correto, o aplicativo o utiliza e, na rotação, recebe um valor novo antes de revogar o antigo. Uma senha guardada num Secret não expira por causa do Kubernetes; seu emissor precisa revogá-la. A proteção deve cobrir trânsito TLS, RBAC, acesso ao nó, backups e criptografia no etcd. A configuração do API Server para criptografia/KMS e a integração com um cofre específico não fazem parte desta prática; você explicará as responsabilidades e o fluxo, sem implantar esses serviços.

## Segurança do processo e Pod Security Admission

Pod Security Admission examina o manifesto antes de aceitar um pod. O nível `baseline` bloqueia configurações de risco conhecidas; `restricted` acrescenta exigências como execução não root e redução de privilégios; `privileged` não aplica essas restrições. O namespace já usa `restricted` na versão **v1.35**, evitando mudança silenciosa das regras por `latest`. `enforce` recusa, `warn` avisa o cliente e `audit` marca a decisão para auditoria; uma label `audit` não instala coleta de logs.

Leia o `securityContext` da base: `runAsUser: 1000` determina o UID; `runAsNonRoot` impede iniciar como root; `allowPrivilegeEscalation: false` impede adquirir privilégios adicionais via exec; `capabilities.drop: [ALL]` remove capabilities Linux; `seccompProfile: RuntimeDefault` aplica o filtro de syscalls do runtime. Nenhum desses campos concede RBAC. `readOnlyRootFilesystem: true` é proteção adicional do exemplo, não exigência de Restricted. O `emptyDir` em `/tmp` conserva o espaço temporário de que o servidor precisa.

```bash
kubectl -n curso-seguranca exec deploy/web-seguro -- id
kubectl -n curso-seguranca exec deploy/web-seguro -- sh -c 'touch /prova'
kubectl -n curso-seguranca exec deploy/web-seguro -- sh -c 'touch /tmp/prova'
kubectl -n curso-seguranca run pod-inseguro --image=busybox:1.37.0 \
  --restart=Never --dry-run=server --command -- sleep 60
```

Espere UID 1000, falha no filesystem raiz, sucesso em `/tmp` e recusa de admissão para o pod sem contexto restrito. O dry-run não cria o pod inseguro. Restricted não significa imagem confiável, ausência de vulnerabilidades ou isolamento perfeito de tenants. Proveniência e atualização de imagens continuam sendo decisões separadas.

Prática guiada: use `kubectl -n curso-seguranca run pod-corrigido --image=busybox:1.37.0 --restart=Never --dry-run=client -o yaml --command -- sleep 3600` e salve a saída, pelo editor, em `/tmp/curso-pod-corrigido.yaml`. Adicione a `spec.securityContext` do Pod `cliente` da base e o `containers[0].securityContext` correspondente; esses são exemplos completos já explicados. Valide `kubectl apply --dry-run=server -f /tmp/curso-pod-corrigido.yaml`, depois aplique sem dry-run e espere Ready. Inspecione `id`. A evidência é um pod admitido e não root, mantendo a política do namespace intacta.

## Laboratório de Secret — montar e atualizar um valor fictício

O arquivo [segredo-ficticio.yaml](../laboratorios/06-seguranca/segredo-ficticio.yaml) contém somente o texto público `valor-publico-ficticio-v1`, sem senha ou token utilizável. Por isso esse exemplo pode ser versionado e lido nas evidências. Não substitua seu conteúdo por credenciais reais. O campo `stringData` permite informar texto ao criar/atualizar o Secret; a API o guarda no campo `data`, representado em base 64.

O Pod `consumidor-segredo` usa `leitor`, automount de token desabilitado e o mesmo contexto Restricted explicado acima. Em `volumes`, `secret.secretName` seleciona o Secret; em `volumeMounts`, `mountPath` escolhe onde os arquivos aparecem no container. A chave `mensagem` vira o arquivo `/var/run/segredo/mensagem`. Não usamos `subPath`, para permitir atualização da projeção.

```bash
kubectl apply -f laboratorios/06-seguranca/segredo-ficticio.yaml
kubectl -n curso-seguranca wait --for=condition=Ready pod/consumidor-segredo --timeout=120s
kubectl auth can-i get secret/segredo-ficticio -n curso-seguranca \
  --as=system:serviceaccount:curso-seguranca:leitor
kubectl -n curso-seguranca exec consumidor-segredo -- cat /var/run/segredo/mensagem
kubectl -n curso-seguranca get pod consumidor-segredo -o jsonpath='{.metadata.uid}'
```

Espere `no` na autorização e `valor-publico-ficticio-v1` na leitura do arquivo. A montagem foi realizada pelo kubelet para o pod admitido; o processo não precisou buscar o Secret pela API. Guarde o UID do pod para comparar após a atualização.

```bash
kubectl -n curso-seguranca patch secret segredo-ficticio --type=merge \
  -p '{"stringData":{"mensagem":"valor-publico-ficticio-v2"}}'
kubectl -n curso-seguranca exec consumidor-segredo -- cat /var/run/segredo/mensagem
```

A atualização não é instantânea: aguarde os ciclos de cache/sincronização do kubelet e repita somente a leitura até aparecer `v2`. Confirme que UID do Pod e restartCount não mudaram. Isso demonstra projeção de um arquivo atualizado, não que toda aplicação recarrega seu segredo automaticamente. Um processo que leu apenas ao iniciar continuaria usando sua cópia; uma variável de ambiente também exigiria recriação do processo.

Recupere o estado didático com `kubectl apply -f laboratorios/06-seguranca/segredo-ficticio.yaml` e aguarde o arquivo voltar a `v1`. Explique o limite: atualizar um Secret não revoga uma senha antiga já copiada. Uma rotação real exige criar a credencial nova no emissor, entregá-la, comprovar seu uso e revogar a anterior. Aqui só praticamos entrega e atualização usando texto público fictício.

## Laboratório de rede — negar, permitir DNS, permitir aplicação

NetworkPolicy é aplicada pelo plugin de rede. Criar o objeto sem um CNI que a implemente não bloqueia nada. `podSelector` escolhe **quais pods receberão a política**, não o destino do tráfego. `ingress` contém origens permitidas; `egress`, destinos. Sem políticas que isolem uma direção, ela é permitida por padrão. A política `01-negar.yaml` seleciona todos os pods do namespace (`{}`), isola as duas direções e não inclui permissões: conexões novas ficam bloqueadas. Políticas são aditivas; uma permissão em outra política aplicável libera aquele fluxo.

Para uma conexão funcionar, egress da origem e ingress do destino precisam permitir quando cada lado está isolado. Em `03-web.yaml`, uma regra permite saída do `papel: cliente` ao `app: web-seguro`; a outra permite entrada no web a partir do cliente. As respostas pertencem à conexão autorizada, portanto não é necessário criar uma regra inversa indiscriminada.

Os pods `cliente` e `intruso` rodam no mesmo namespace, ambos sob Restricted. Primeiro comprove conectividade sem políticas:

```bash
kubectl -n curso-seguranca wait --for=condition=Ready pod/cliente pod/intruso --timeout=120s
kubectl -n curso-seguranca exec cliente -- wget -T 3 -qO- http://web-seguro:8080
kubectl -n curso-seguranca exec intruso -- wget -T 3 -qO- http://web-seguro:8080
kubectl apply -f laboratorios/06-seguranca/01-negar.yaml
kubectl -n curso-seguranca exec cliente -- nslookup web-seguro
```

Após a política, o DNS pode falhar por timeout porque também foi negado. Use conexão nova e timeout; conexões previamente estabelecidas podem ter comportamento dependente do CNI. Confirme CoreDNS e labels reais:

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns --show-labels
kubectl get namespace kube-system --show-labels
kubectl apply -f laboratorios/06-seguranca/02-dns.yaml
kubectl -n curso-seguranca exec cliente -- nslookup web-seguro
kubectl -n curso-seguranca exec cliente -- wget -T 3 -qO- http://web-seguro:8080
```

Agora DNS resolve, mas HTTP ainda deve falhar. A política DNS permite UDP **e TCP** 53 aos pods CoreDNS em `kube-system`. Veja com `kubectl -n curso-seguranca exec cliente -- cat /etc/resolv.conf` qual servidor o pod usa. Nesta base não há NodeLocal DNSCache; se você mudou esse pressuposto, volte à rede dos pré-requisitos para executar a prova fornecida. Permitir todo egress para resolver DNS destruiria a prova.

```bash
kubectl apply -f laboratorios/06-seguranca/03-web.yaml
kubectl -n curso-seguranca exec cliente -- wget -T 3 -qO- http://web-seguro:8080
kubectl -n curso-seguranca exec intruso -- wget -T 3 -qO- http://web-seguro:8080
kubectl -n curso-seguranca get networkpolicy
```

Esperado: cliente lê `seguro`, intruso falha. Portas são as portas de destino do pod (8080), não necessariamente a porta publicada no Service. `kubectl port-forward` não é uma prova válida de isolamento entre pods.

O exemplo DNS mostra AND: `namespaceSelector` e `podSelector` dentro do **mesmo item** exigem pod com a label correta **e** no namespace correto. Colocá-los em itens separados, cada qual iniciado por `-`, produz OR e amplia acesso. Um `podSelector` sozinho em `from`/`to` seleciona pods do próprio namespace da política. Para permitir Traefik de outro namespace ao frontend, combine a label `kubernetes.io/metadata.name: traefik` com as labels reais dos pods do controller, obtidas por `kubectl -n traefik get pods --show-labels`; permita a porta real do frontend. Se Traefik também tiver egress isolado, será preciso autorizá-lo do lado de saída.

Recuperação específica: execute `kubectl -n curso-seguranca delete networkpolicy cliente-para-web`, observe falha no cliente e reaplique `03-web.yaml`. Se a prova não mudar ao negar, investigue em ordem: namespace/contexto do teste, labels dos pods selecionados, políticas adicionais que autorizam o fluxo e saúde de Calico (`kubectl get tigerastatus`). A hipótese só fica confirmada quando a mesma conexão nova muda de resultado com a regra esperada.

## Desafio independente e evidências

Crie um namespace novo com frontend e backend. Apenas frontend deve alcançar backend na porta 8080; ambos precisam de DNS. Uma ServiceAccount só pode ler um ConfigMap específico, sem ler Secrets. Use Restricted, valide negação de cliente não autorizado e apresente como a aplicação receberia um segredo temporário sem Git. Explique o que muda quando Traefik precisa alcançar o frontend a partir de outro namespace.

Rubrica, 10 pontos: decisões RBAC, incluindo `resourceNames`, demonstradas (2); token projetado e automount explicados sem vazar credenciais (2); pod corrigido sob Restricted (2); DNS e matriz cliente/intruso comprovados (3); montagem/atualização do Secret fictício e plano de rotação (1). Registre comandos e resultados, mas nunca JWTs, kubeconfigs ou valores de Secrets reais. Para limpar depois de guardar evidências, execute `kubectl delete namespace curso-seguranca`; regras deste módulo não modificam outros namespaces. Remova separadamente apenas o namespace que você escolheu para o desafio, após conferir seu nome.

## Fechamento

Você separou identidade, permissão, admissão, processo e tráfego. Comprove essa separação respondendo: um token válido pode receber `Forbidden`? Por que adicionar uma Role sem binding não concede acesso? Por que Restricted não resolve egress? Por que DNS pode funcionar enquanto HTTP está bloqueado? Explique também como a rotação chega ao processo sem uma senha no Git.

Avance com **8/10**, decisões negativas realmente testadas e serviço recuperado. O aprendizado não inclui implantar um secret manager, KMS, identidade AWS ou isolamento de tenants hostis; inclui reconhecer o que cada mecanismo cobre. No próximo módulo, [07 — Troubleshooting](07-troubleshooting.md), você usará essas distinções para investigar falhas sem trocar permissões por tentativa e erro.

## Referências opcionais

Nenhuma leitura abaixo é necessária para concluir a prática. As fontes oficiais aprofundam os seguintes recortes:

- [RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) — amplia exemplos de subrecursos, agregação de ClusterRoles e limites de `resourceNames`.
- [ServiceAccounts](https://kubernetes.io/docs/concepts/security/service-accounts/) — detalha identidades, TokenRequest e vínculo do token ao Pod.
- [Volumes projetados](https://kubernetes.io/docs/concepts/storage/projected-volumes/) — explica outras fontes projetáveis e requisitos de audience/expiração.
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) — lista todas as restrições de cada perfil, além das praticadas aqui.
- [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/) — aprofunda configuração global, isenções e modos de aplicação.
- [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/) — cobre composição de seletores, limitações e interações com implementação de rede.
- [Boas práticas de Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/) — aprofunda proteção em repouso, acesso e entrega de credenciais.
