# 03 — Rede, Traefik, Ingress e Gateway API

**Duração:** 18–24 horas. **Pré-requisitos:** aplicação do módulo 02 saudável, Calico funcional e acesso LOCAL por kubectl. **Entrega:** DNS e ClusterIP testados dentro do cluster, mesma aplicação publicada por Ingress e HTTPRoute, TLS validado e um incidente de roteamento diagnosticado. Todos os comandos são **LOCAL**, na raiz do repositório, salvo indicação contrária.

## Separe as camadas para conseguir diagnosticar

O CNI atribui/configura a conectividade dos Pods. No laboratório, o Calico usa VXLAN entre nós. O dataplane de Service mantém o acesso a um conjunto de endpoints; no kubeadm desta trilha, kube-proxy implementa esse caminho. CoreDNS oferece descoberta por nome. Traefik implementa o roteamento HTTP/TLS declarado em APIs de entrada. Nenhum desses componentes substitui todos os demais.

O Service seleciona Pods por labels, não por nome do Deployment. O endereço ClusterIP permanece estável durante a substituição de Pods. `port` é a porta oferecida pelo Service; `targetPort` identifica a porta do backend. EndpointSlices registram os backends descobertos e sua prontidão. [Services](https://kubernetes.io/docs/concepts/services-networking/service/) e [EndpointSlices](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/).

| Recurso | O que entrega | O que não entrega sozinho |
| --- | --- | --- |
| ClusterIP | Endereço interno do Service | IP público acessível pela Internet |
| NodePort | Porta nos nós para alcançar o Service | DNS/TLS/roteamento HTTP por hostname |
| LoadBalancer | Solicitação de integração com um balanceador | Balanceador sem controller/provedor configurado |
| Ingress | Regras HTTP/TLS consumidas por controller | Processo de proxy em execução |
| GatewayClass/Gateway/HTTPRoute | API de entrada com papéis separados | Implementação sem Gateway controller |

Em kubeadm na EC2, criar Service LoadBalancer não configura a AWS por mágica: sem a integração correspondente, o endereço externo fica pendente. Por isso, primeiro isolamos as rotas com ClusterIP e port-forward. A integração AWS será tratada no módulo 11.

## 1. DNS, backend direto e Service

```bash
kubectl config current-context
kubectl apply -f laboratorios/03-rede/diagnostico.yaml
kubectl wait -n curso --for=condition=Ready pod/diagnostico --timeout=120s
kubectl exec -n curso diagnostico -- cat /etc/resolv.conf
kubectl exec -n curso diagnostico -- nslookup kubernetes.default.svc.cluster.local
kubectl exec -n curso diagnostico -- nslookup web.curso.svc.cluster.local
kubectl exec -n curso diagnostico -- wget -T 5 -qO- http://web/healthz
kubectl get pods -n curso -o wide
kubectl get endpointslice -n curso -l kubernetes.io/service-name=web -o yaml
```

No namespace `curso`, o nome curto `web` pode ser expandido pela busca DNS para `web.curso.svc.cluster.local`. De outro namespace, use `web.curso` ou o FQDN. `cluster.local` é o domínio padrão desta instalação, não um nome mágico universal. O `/etc/resolv.conf` do Pod mostra nameserver, search e ndots realmente utilizados. [DNS de Pods e Services](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/).

Escolha o IP de um Pod web da saída anterior e teste `kubectl exec -n curso diagnostico -- wget -T 5 -qO- http://IP_REAL:8080/healthz`, substituindo `IP_REAL`. Compare também `http://CLUSTER_IP_REAL:80/healthz`. Se backend direto funciona mas ClusterIP falha, a suspeita muda para Service/endpoints/dataplane. Se ClusterIP funciona e o nome falha, investigue DNS. Se ambos falham apenas entre nós, investigue CNI, MTU e firewall.

Para afirmar conectividade **entre nós**, escolha um backend em nó diferente do diagnóstico e registre ambos. Duas requisições a Pods do mesmo nó não comprovam o túnel VXLAN. Se o scheduler concentrou todos os Pods, registre essa limitação e complete o teste após estudar distribuição no módulo 05.

## 2. Preparar Helm e instalar Traefik

Você já conhece Traefik no Swarm. Agora os providers Kubernetes observam objetos da API; labels Docker não criam routers aqui. Usaremos Ingress nativo e Gateway API, sem precisar escrever CRDs próprias do Traefik. Gateway API também é distribuída por CRDs, mantidas pelo projeto Kubernetes SIG Network; usá-las é diferente de desenvolver seu próprio Operator.

Se Helm já estiver instalado, registre `helm version --short` e confira sua compatibilidade. Para uma instalação Linux nova, o trecho abaixo fixa **Helm 4.2.3** e verifica o checksum publicado na [release oficial](https://github.com/helm/helm/releases/tag/v4.2.3). A arquitetura escolhida é a do computador LOCAL.

```bash
HELM_DIR=$(mktemp -d)
case "$(uname -m)" in
  x86_64) HELM_ARCH=amd64; HELM_SHA=e9b88b4ee95b18c706839c28d3a0220e5bc470e9cd9262410c90793c45ff8b7c ;;
  aarch64|arm64) HELM_ARCH=arm64; HELM_SHA=21abd9354d39b2cd79a8d76be6912cd137a983cbf997193503fb8a6a6e2f2785 ;;
  *) printf 'Consulte os binários oficiais para sua arquitetura.\n'; exit 1 ;;
esac
curl -fL "https://get.helm.sh/helm-v4.2.3-linux-${HELM_ARCH}.tar.gz" -o "$HELM_DIR/helm.tar.gz"
printf '%s  %s\n' "$HELM_SHA" "$HELM_DIR/helm.tar.gz" | sha256sum --check - || exit 1
tar -xzf "$HELM_DIR/helm.tar.gz" -C "$HELM_DIR"
sudo install -m 0755 "$HELM_DIR/linux-$HELM_ARCH/helm" /usr/local/bin/helm
helm version --short
```

Interrompa em caso de checksum incorreto; só extraia/instale após resultado `OK`. Outros sistemas operacionais devem seguir a [instalação oficial](https://helm.sh/docs/intro/install/).

O conjunto deste laboratório é **chart Traefik 41.5.0 → Traefik v3.7.13 → Gateway API Standard v1.6.1**. A versão do chart e a da aplicação não são o mesmo número. Consulte o [Chart.yaml fixado](https://github.com/traefik/traefik-helm-chart/blob/v41.5.0/traefik/Chart.yaml) e o [provider Gateway](https://doc.traefik.io/traefik/reference/install-configuration/providers/kubernetes/kubernetes-gateway/) antes de atualizar uma parte isolada.

```bash
curl -fL -o /tmp/gateway-api-standard-1.6.1.yaml https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml
kubectl apply --server-side -f /tmp/gateway-api-standard-1.6.1.yaml
kubectl wait --for=condition=Established crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm show chart traefik/traefik --version 41.5.0
helm template traefik traefik/traefik --version 41.5.0 --namespace traefik --kube-version 1.35.0 -f laboratorios/03-rede/traefik-values.yaml
helm upgrade --install traefik traefik/traefik --version 41.5.0 --namespace traefik --create-namespace -f laboratorios/03-rede/traefik-values.yaml --wait --timeout 5m
kubectl get pods,svc -n traefik
kubectl get ingressclass,gatewayclass
```

O values fornecido cria duas réplicas, Service ClusterIP, IngressClass/GatewayClass `traefik`, e mantém o dashboard desabilitado. Leia a saída renderizada antes da instalação. A existência das CRDs apenas registra os tipos; controller saudável e permissões corretas são necessários para reconciliar seus objetos. [Instalação Gateway API](https://gateway-api.sigs.k8s.io/guides/).

## 3. Publicar por Ingress

```bash
kubectl apply -f laboratorios/03-rede/ingress.yaml
kubectl describe ingress web -n curso
kubectl port-forward -n traefik svc/traefik 8088:80 8443:443
# Outro terminal LOCAL; manter port-forward aberto
curl --fail -H 'Host: web.curso.test' http://127.0.0.1:8088/
```

O caminho testado é cliente → túnel da API → Pod Traefik → backend web. O recurso Ingress referencia o **Service porta 80**, não a porta 8080 diretamente. Traefik pode usar os endpoints do Service diretamente, dependendo de seu modo de balanceamento; ter uma referência a Service não implica que todo proxy sempre encaminhe para seu ClusterIP.

Ingress define host/path/TLS e `ingressClassName` escolhe a implementação. O campo `ADDRESS` vazio neste laboratório privado com ClusterIP não significa, sozinho, falha de roteamento. Faça o teste HTTP e consulte o controller. Ingress continua existindo; sua API está congelada e novas capacidades de entrada são desenvolvidas em Gateway API. [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/).

## 4. Publicar por Gateway API

Na divisão de responsabilidades, GatewayClass identifica a implementação; Gateway descreve listeners e quais rotas podem se ligar; HTTPRoute descreve hosts, matches e backends da aplicação. O chart criou a classe; você criará o Gateway e a rota no namespace `curso`.

```bash
kubectl apply -f laboratorios/03-rede/gateway.yaml
kubectl apply -f laboratorios/03-rede/httproute.yaml
kubectl get gateway,httproute -n curso
kubectl describe gateway web-gateway -n curso
kubectl get httproute web -n curso -o yaml
curl --fail -H 'Host: gateway.curso.test' http://127.0.0.1:8088/
```

Leia `status.conditions` e `status.parents[].conditions`, especialmente `Accepted`, `Programmed` e `ResolvedRefs` onde aplicáveis. Um HTTPRoute criado pela API pode não ter sido aceito pelo controller. `sectionName: web` escolhe o listener de nome `web`; no Traefik deste chart, o listener interno HTTP usa porta **8000**, enquanto o Service publica **80**. Confundir essas portas gera um Gateway sem listener compatível.

As rotas deste Gateway estão limitadas ao mesmo namespace. Para referências de backend entre namespaces, será necessário estudar `ReferenceGrant`; não abra acesso global para resolver um erro de referência. Como exercício, altere o parentRef para um nome inexistente, observe o status e restaure o arquivo. [HTTPRoute](https://gateway-api.sigs.k8s.io/api-types/httproute/) e [papéis da Gateway API](https://gateway-api.sigs.k8s.io/concepts/roles-and-personas/).

## 5. TLS local, sem depender de ACME público

Você domina certificados; o objetivo é localizar sua responsabilidade no cluster. O Secret TLS pertence ao namespace do Ingress. Crie um certificado efêmero de laboratório fora do repositório e confie explicitamente nele para este teste. Não use `curl -k`: precisamos provar nome e confiança, não só criptografia.

```bash
TLS_DIR=$(mktemp -d)
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 2 -keyout "$TLS_DIR/tls.key" -out "$TLS_DIR/tls.crt" -subj '/CN=web.curso.test' -addext 'subjectAltName=DNS:web.curso.test'
kubectl create secret tls web-tls -n curso --cert="$TLS_DIR/tls.crt" --key="$TLS_DIR/tls.key" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f laboratorios/03-rede/extras/ingress-tls.yaml
curl --fail --cacert "$TLS_DIR/tls.crt" --resolve web.curso.test:8443:127.0.0.1 https://web.curso.test:8443/healthz
```

O arquivo extra atualiza o mesmo Ingress `web` para o entrypoint HTTPS. A rota Gateway HTTP continua independente em `gateway.curso.test`. O certificado expira em dois dias: para repetir, gere outro e atualize o Secret. Em produção, automatize emissão/renovação e valide o método ACME/PKI apropriado; o módulo de entrega aprofundará a gestão de dependências.

**Extensão Gateway:** crie um listener HTTPS na porta interna 8443 com `certificateRefs` para um Secret no namespace `curso`, um certificado cujo SAN inclua `gateway.curso.test`, e ligue a HTTPRoute ao novo `sectionName`. Prove TLS com `--cacert` e `--resolve`. O certificado do exemplo Ingress não cobre esse segundo hostname. [TLS em Gateway API](https://gateway-api.sigs.k8s.io/guides/tls/).

## Falha guiada: Pods verdes, Service sem backend

```bash
kubectl patch service web -n curso --type=merge -p='{"spec":{"selector":{"app":"web-inexistente"}}}'
kubectl get pods -n curso -l app=web
kubectl get endpointslice -n curso -l kubernetes.io/service-name=web -o yaml
kubectl exec -n curso diagnostico -- wget -T 3 -qO- http://web/healthz
kubectl get service web -n curso -o yaml
```

O wget deve falhar, apesar de os Pods continuarem prontos. DNS ainda pode resolver o ClusterIP: isso não significa que haja backend. Um port-forward antigo diretamente para um Pod pode continuar funcionando e mascarar o incidente. Compare selector do Service com labels dos Pods e com endpoints, sem reiniciar componentes.

**Recuperação:** `kubectl apply -f laboratorios/02-workloads/service.yaml`; espere endpoints prontos e repita wget pelo nome e curl pela rota Gateway. Confirme também o Ingress TLS se seu port-forward/certificado estiverem ativos. Registre causa, impacto e evidência da correção.

## Exercício autônomo e rubrica

**Tempo: 90–120 minutos.** Publique uma segunda aplicação no mesmo Traefik com hostname diferente. Forneça uma rota Ingress e outra HTTPRoute, faça um teste que deve ser aceito e outro que deve ser rejeitado por hostname/path. Faça um backendRef incorreto produzir diagnóstico pelo status e recupere. Explique como o tráfego chegaria ao Traefik sem port-forward numa implantação AWS.

**Rubrica, 10 pontos:** 2 para isolar DNS/CNI/Service/proxy; 2 para endpoints e tráfego entre nós; 2 para Ingress e Gateway funcional; 2 para TLS com nome/confiança validados; 2 para recuperar falha e apresentar evidências. Avance com 8/10, anotando qualquer teste entre nós ainda pendente. NetworkPolicy será trabalhada no módulo 06 sobre esta conectividade já conhecida.

Fontes oficiais consultadas em **10/09/2026**. Próximo: [04 — Storage e persistência](04-storage.md).
