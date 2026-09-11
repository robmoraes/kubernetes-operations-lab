# 06 — Identidade, autorização e isolamento

Reserve **16–20 horas**. Pré-requisitos: Deployments, Service, DNS e Calico funcionando com NetworkPolicy. Execute na **estação**, no contexto do laboratório, a partir da raiz do repo. Este módulo usa somente o namespace `curso-seguranca`; não aplique negação global em `kube-system`.

O objetivo é demonstrar três decisões distintas: **quem** faz uma chamada (autenticação), **o que** essa identidade pode fazer (autorização), e **quais configurações** podem ser admitidas (admission). Acrescente segurança do processo e do tráfego para obter defesa em camadas.

## Identidades e RBAC

Um kubeconfig normalmente reúne endpoint, CA e uma identidade cliente. Compartilhar `admin.conf` equivale a compartilhar poder administrativo. ServiceAccount identifica um workload dentro de um namespace; não é usuário Linux nem IAM Role. RBAC Kubernetes não concede permissões AWS. Uma Role declara verbos e recursos dentro de um namespace; RoleBinding liga a identidade a essas permissões. ClusterRole pode ser vinculada por RoleBinding com alcance namespaced; ClusterRoleBinding concede alcance de cluster.

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

Esperado: `yes`, `no`, `no`, `no`. O operador que usa `--as` precisa de poder para impersonar; o laboratório usa administrador. Teste também `get pods/log` e `create pods/exec`: subresources têm permissões distintas. Evite `verbs: ["*"]` e `resources: ["*"]`; ler Secrets ou criar pods privilegiados pode permitir escalada indireta. [RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/).

Incidente controlado: apague **apenas** `rolebinding/leitor` em `curso-seguranca`; repita o primeiro teste e confirme `no`. Recupere reaplicando `rbac.yaml`. Explique por que recriar a ServiceAccount ou adicionar uma Role sem binding não resolveria.

## Tokens e Secrets

Tokens atuais de ServiceAccount podem ser projetados no pod, ter audience e validade e ser renovados pelo kubelet. A aplicação precisa reler o arquivo, não guardar o token original indefinidamente. Desabilite o automount quando o processo não chama a API. O exemplo `web-seguro` faz isso; o pod `identidade` recebe um volume projetado explícito para estudar o mecanismo.

```bash
kubectl apply -f laboratorios/06-seguranca/identidade.yaml
kubectl -n curso-seguranca wait --for=condition=Ready pod/identidade --timeout=120s
kubectl -n curso-seguranca exec identidade -- ls -l /var/run/curso
kubectl -n curso-seguranca get pod identidade -o yaml
```

Inspecione nomes, permissões, ServiceAccount e `expirationSeconds`; **não imprima o token** nas evidências. O kubelet obtém o token via TokenRequest e atualiza a projeção. Um token curto criado por `kubectl create token leitor --duration=10m -n curso-seguranca` é útil para um teste humano explícito, mas sua saída é segredo: não o execute em gravações nem o salve no Git. Não crie Secrets de token permanente por hábito. [ServiceAccounts](https://kubernetes.io/docs/concepts/security/service-accounts/), [volumes projetados](https://kubernetes.io/docs/concepts/storage/projected-volumes/).

Secret codificado em base64 não está criptografado. Defina quem pode ler, como criptografar no etcd, como obter/rotacionar o valor e como auditar acesso. Evite senha em argumento de shell e em YAML versionado. Para produção, compare integração com secret manager, criptografia em repouso e mecanismos de injeção. Nesta aula não é necessário criar credenciais reais.

## Segurança do processo e Pod Security Admission

O namespace já aplica `restricted` na versão **v1.35**, evitando mudança silenciosa das regras por `latest`. Os pods executam UID não root, seccomp RuntimeDefault, sem capabilities nem privilege escalation. O servidor tem root filesystem read-only e um `emptyDir` gravável só em `/tmp`; segurança não elimina a necessidade de locais temporários.

```bash
kubectl -n curso-seguranca exec deploy/web-seguro -- id
kubectl -n curso-seguranca exec deploy/web-seguro -- sh -c 'touch /prova'
kubectl -n curso-seguranca exec deploy/web-seguro -- sh -c 'touch /tmp/prova'
kubectl -n curso-seguranca run pod-inseguro --image=busybox:1.37.0 \
  --restart=Never --dry-run=server --command -- sleep 60
```

Espere UID 1000, falha no filesystem raiz, sucesso em `/tmp` e recusa de admissão para o pod sem contexto restrito. O dry-run não cria o pod inseguro. Restricted não significa imagem confiável, ausência de vulnerabilidades ou isolamento perfeito de tenants. Examine supply chain, atualização de imagens, syscall surface e credenciais como decisões adicionais. [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/).

Desafio curto: gere o YAML do pod recusado por `--dry-run=client -o yaml`, acrescente os campos exigidos, valide com `--dry-run=server`, então crie-o como `pod-corrigido`. Não relaxe a política do namespace para fazê-lo entrar.

## Laboratório de rede — negar, permitir DNS, permitir aplicação

NetworkPolicy é aplicada pelo plugin de rede. Criar o objeto sem um CNI que a implemente não bloqueia nada. Políticas são aditivas: tráfego permitido por alguma política aplicável continua permitido; para uma conexão funcionar, egress da origem e ingress do destino precisam permitir quando cada lado está isolado.

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

Agora DNS resolve, mas HTTP ainda deve falhar. A política DNS permite UDP **e TCP** 53 aos pods CoreDNS em `kube-system`. Se instalou NodeLocal DNSCache, o destino é diferente: inspecione `/etc/resolv.conf` e adapte uma regra específica. Permitir todo egress para resolver DNS destruiria a prova.

```bash
kubectl apply -f laboratorios/06-seguranca/03-web.yaml
kubectl -n curso-seguranca exec cliente -- wget -T 3 -qO- http://web-seguro:8080
kubectl -n curso-seguranca exec intruso -- wget -T 3 -qO- http://web-seguro:8080
kubectl -n curso-seguranca get networkpolicy
```

Esperado: cliente lê `seguro`, intruso falha. A regra combina namespace e pod selectors no **mesmo item** quando quer AND; itens separados virariam OR. Portas são as portas de destino do pod (8080), não necessariamente a porta publicada no Service. `kubectl port-forward` não é uma prova válida de isolamento entre pods. [Semântica de NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/).

Recuperação específica: remova somente `networkpolicy/cliente-para-web`, observe falha no cliente e reaplique `03-web.yaml`. Se a prova não mudar ao negar, interrompa o avanço e investigue se o CNI implementa política, seletores batem e teste realmente saiu de um pod.

## Desafio independente e evidências

Crie um namespace novo com frontend e backend. Apenas frontend deve alcançar backend na porta 8080; ambos precisam de DNS. Uma ServiceAccount só pode ler um ConfigMap específico, sem ler Secrets. Use Restricted, valide negação de cliente não autorizado e apresente como a aplicação receberia um segredo temporário sem Git. Explique o que muda quando Traefik precisa alcançar o frontend a partir de outro namespace.

Rubrica, 10 pontos: quatro decisões RBAC demonstradas (2); token projetado e automount explicados sem vazar credenciais (2); pod corrigido sob Restricted (2); DNS e matriz cliente/intruso comprovados (3); plano de Secrets (1). Avance com 8/10 e isolamento efetivamente testado. Registre comandos e resultados, mas nunca JWTs, kubeconfigs ou valores de Secrets. Para limpar, exclua o namespace **curso-seguranca** depois de guardar evidências; regras deste módulo não modificam outros namespaces.

Fontes consultadas em 10/09/2026: referências oficiais junto às seções e [boas práticas de Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/), [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/).
