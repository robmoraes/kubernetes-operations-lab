# 03 — Rede, Traefik, Ingress e Gateway API

**Duração:** 18–24 horas, divididas entre conectividade, entrada HTTP e TLS. O trabalho termina com testes de cliente e recuperação; as referências ao fim são aprofundamento opcional.

## Antes de começar

Conclua [02 — Workloads](02-workloads.md): Deployment e Service `web` no namespace `curso` precisam estar saudáveis. Você já deve distinguir label, seletor, porta do container e readiness. O ambiente é o cluster kubeadm 1.35 com Calico e dois workers; a estação LOCAL suportada pelo roteiro é Linux amd64 ou arm64, com Bash, sudo, kubectl 1.35, curl, OpenSSL, tar e sha256sum. O Helm será instalado nesta aula. Outros sistemas locais são adaptações fora do roteiro guiado.

Os arquivos estão em [laboratorios/03-rede](../laboratorios/03-rede/). Execute comandos na raiz do repositório e exporte o kubeconfig do curso como no módulo 01. Para conferir as ferramentas: `kubectl version --client`, `curl --version` e `openssl version`. Em uma estação Ubuntu 24.04 nova, instale as utilidades ausentes com `sudo apt-get update` e `sudo apt-get install -y curl openssl tar coreutils ca-certificates`. Registre as versões; o apt verifica a autenticidade dos pacotes pelo repositório assinado.

Todos os comandos são **LOCAL**, salvo indicação contrária. Esta prática não cria balanceador público nem exige domínio pago: os nomes `.test` são atendidos pelo Host/SNI informado no cliente. Serão instalados um controller, RBAC e APIs de Gateway no cluster de laboratório.

## O que você vai conseguir fazer

- Diferenciar falha de DNS, conectividade entre Pods, Service e proxy HTTP por testes separados.
- Instalar a combinação de versões fornecida e localizar seus objetos e permissões.
- Encaminhar a mesma aplicação por Ingress e HTTPRoute, interpretando o status da reconciliação.
- Configurar TLS nos dois modelos e validar confiança e hostname com o cliente.
- Recuperar uma rota sem backends e devolver o laboratório a um estado conhecido.

## Separe as camadas para conseguir diagnosticar

O CNI atribui/configura a conectividade dos Pods. No laboratório, o Calico usa VXLAN entre nós. O dataplane de Service mantém o acesso a um conjunto de endpoints; no kubeadm desta trilha, kube-proxy implementa esse caminho. CoreDNS oferece descoberta por nome. Traefik implementa o roteamento HTTP/TLS declarado em APIs de entrada. Nenhum desses componentes substitui todos os demais.

O Service seleciona Pods por labels, não por nome do Deployment. O endereço ClusterIP permanece estável durante a substituição de Pods. `port` é a porta oferecida pelo Service; `targetPort` identifica a porta do backend. EndpointSlices registram os backends descobertos e sua prontidão. No Service do curso, `port: 80` aponta para `targetPort: http`; o container declara a porta de nome `http` como 8080.

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

No namespace `curso`, o nome curto `web` pode ser expandido pela busca DNS para `web.curso.svc.cluster.local`. De outro namespace, use `web.curso` ou o FQDN. `cluster.local` é o domínio padrão desta instalação, não um nome mágico universal. O `/etc/resolv.conf` do Pod mostra nameserver, search e ndots realmente utilizados. `search` lista sufixos tentados e `ndots` influencia quando a busca tenta esses sufixos antes do nome absoluto; por isso, uma resolução pode gerar mais de uma consulta.

Escolha o IP de um Pod web da saída anterior e teste `kubectl exec -n curso diagnostico -- wget -T 5 -qO- http://IP_REAL:8080/healthz`, substituindo `IP_REAL`. Compare também `http://CLUSTER_IP_REAL:80/healthz`. Se backend direto funciona mas ClusterIP falha, a suspeita muda para Service/endpoints/dataplane. Se ClusterIP funciona e o nome falha, investigue DNS. Se ambos falham apenas entre nós, investigue CNI, MTU e firewall.

Para afirmar conectividade **entre nós**, o diagnóstico e o backend precisam estar em nós distintos. Caso estejam juntos, vamos usar uma restrição pequena e explícita: `nodeSelector` exige uma label no Node. A label `kubernetes.io/hostname` identifica o hostname anunciado pelo nó; seu valor pode diferir do nome do objeto. Esse Pod é temporário, não tem volume persistente e pode ser recriado sem perda de dados.

```bash
kubectl get pods -n curso -l app=web -o wide
read -r -p 'Nome de um Pod web pronto: ' WEB_POD
WEB_NODE=$(kubectl get pod "$WEB_POD" -n curso -o jsonpath='{.spec.nodeName}')
WEB_IP=$(kubectl get pod "$WEB_POD" -n curso -o jsonpath='{.status.podIP}')
kubectl get nodes -L kubernetes.io/hostname
read -r -p 'Nome de OUTRO worker Ready para o diagnóstico: ' DIAG_NODE
test -n "$DIAG_NODE" && test "$DIAG_NODE" != "$WEB_NODE" || exit 1
DIAG_HOSTNAME=$(kubectl get node "$DIAG_NODE" -o go-template='{{ index .metadata.labels "kubernetes.io/hostname" }}')
kubectl delete pod diagnostico -n curso
kubectl patch --local -f laboratorios/03-rede/diagnostico.yaml --type=merge -p "{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"$DIAG_HOSTNAME\"}}}" -o yaml | kubectl apply -f -
kubectl wait -n curso --for=condition=Ready pod/diagnostico --timeout=120s
kubectl exec -n curso diagnostico -- wget -T 5 -qO- "http://$WEB_IP:8080/healthz"
kubectl exec -n curso diagnostico -- wget -T 5 -qO- http://web/healthz
kubectl get pods -n curso -o wide
```

Guarde os dois nós e respostas `ok`. Se o Pod diagnóstico ficar Pending, confirme a label e a capacidade do nó escolhido com `kubectl describe pod diagnostico -n curso`. Para desfazer a restrição, apague somente `pod/diagnostico` e reaplique o arquivo original. No módulo 05 estudaremos as demais decisões do scheduler.

## 2. Preparar Helm e instalar Traefik

Traefik é o proxy reverso e controller de entrada escolhido para este laboratório: ele recebe requisições HTTP/TLS e as encaminha aos backends conforme regras declaradas. Seus providers Kubernetes observam objetos da API e atualizam a configuração de roteamento quando esses objetos mudam. Você aprenderá sua instalação e operação nesta aula; não é necessário ter usado Traefik antes. Usaremos Ingress nativo e Gateway API, sem precisar escrever recursos das APIs específicas do Traefik. Gateway API é distribuída por CRDs, mantidas pelo projeto Kubernetes SIG Network; usá-las é diferente de desenvolver seu próprio Operator.

Helm combina arquivos de um **chart** com seus **values** e gerencia o conjunto instalado como uma **release**. `helm template` apenas renderiza os objetos; `helm upgrade --install` envia-os à API. Nesta aula a release se chama `traefik`. Se você já usa Helm, registre `helm version --short`; para reproduzir exatamente o roteiro, use **Helm 4.2.3**. A instalação abaixo verifica seu checksum publicado e escolhe a arquitetura do computador LOCAL, que pode diferir da dos servidores.

```bash
HELM_DIR=$(mktemp -d)
case "$(uname -m)" in
  x86_64) HELM_ARCH=amd64; HELM_SHA=e9b88b4ee95b18c706839c28d3a0220e5bc470e9cd9262410c90793c45ff8b7c ;;
  aarch64|arm64) HELM_ARCH=arm64; HELM_SHA=21abd9354d39b2cd79a8d76be6912cd137a983cbf997193503fb8a6a6e2f2785 ;;
  *) printf 'Este roteiro de instalação suporta Linux amd64 ou arm64.\n'; exit 1 ;;
esac
curl -fL "https://get.helm.sh/helm-v4.2.3-linux-${HELM_ARCH}.tar.gz" -o "$HELM_DIR/helm.tar.gz"
printf '%s  %s\n' "$HELM_SHA" "$HELM_DIR/helm.tar.gz" | sha256sum --check - || exit 1
tar -xzf "$HELM_DIR/helm.tar.gz" -C "$HELM_DIR"
sudo install -m 0755 "$HELM_DIR/linux-$HELM_ARCH/helm" /usr/local/bin/helm
helm version --short
```

Interrompa em caso de checksum incorreto; só extraia/instale após resultado `OK`. O comando instala em `/usr/local/bin/helm`; se já houver uma versão necessária para seu trabalho, preserve-a e use o binário extraído pelo caminho completo nesta aula. Não substitua ferramentas de uma estação de produção sem planejar esse impacto.

O conjunto deste laboratório é **chart Traefik 41.5.0 → Traefik v3.7.13 → Gateway API Standard v1.6.1**. A versão do chart e a da aplicação não são o mesmo número. Os comandos fixam essa combinação, e `helm show chart` permite conferir `version`, `appVersion` e `kubeVersion`. O bundle Standard registra as APIs estáveis/beta necessárias; não instale o bundle Experimental para esta aula. Imagens do controller e da aplicação devem incluir a arquitetura dos workers; erro `exec format error` indica uma investigação de arquitetura, não de HTTP.

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

O values fornecido cria duas réplicas, Service ClusterIP, IngressClass/GatewayClass `traefik`, e mantém o dashboard desabilitado. Na saída renderizada, localize esses cinco elementos e a imagem `v3.7.13`: essa é a revisão necessária, não a leitura de todo o projeto. RBAC concede ao ServiceAccount do Traefik leitura dos recursos de rota e atualização de status. A existência das CRDs apenas registra os tipos; controller saudável e permissões corretas são necessários para reconciliar seus objetos. Espere duas réplicas disponíveis e ambas as classes listadas.

## 3. Publicar por Ingress

```bash
kubectl apply -f laboratorios/03-rede/ingress.yaml
kubectl describe ingress web -n curso
kubectl port-forward -n traefik svc/traefik 8088:80 8443:443
# Outro terminal LOCAL; manter port-forward aberto
curl --fail -H 'Host: web.curso.test' http://127.0.0.1:8088/
```

O caminho testado é cliente → túnel da API → Pod Traefik → backend web. O recurso Ingress referencia o **Service porta 80**, não a porta 8080 diretamente. Traefik pode usar os endpoints do Service diretamente, dependendo de seu modo de balanceamento; ter uma referência a Service não implica que todo proxy sempre encaminhe para seu ClusterIP.

Ingress define host/path/TLS e `ingressClassName` escolhe a implementação. `pathType: Prefix` aceita a raiz e os caminhos abaixo dela. O campo `ADDRESS` vazio neste laboratório privado com ClusterIP não significa, sozinho, falha de roteamento. Faça o teste HTTP e consulte `kubectl logs -n traefik deployment/traefik --tail=50` se a rota não aparecer. Ingress continua existindo; sua API está congelada e novas capacidades de entrada são desenvolvidas em Gateway API.

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

As rotas deste Gateway estão limitadas ao mesmo namespace por `allowedRoutes.namespaces.from: Same`. `ResolvedRefs=False` significa que uma referência, como Service/porta, não pôde ser resolvida; `Accepted=False` indica rejeição da ligação/regra. Observe também o campo `reason`, que especifica a causa. Como exercício curto, altere o parentRef para um nome inexistente, observe a ausência de aceitação para esse parent e reaplique `httproute.yaml`. Referências entre namespaces exigem permissões adicionais, inclusive `ReferenceGrant` para backends; isso fica fora desta prática, que usa um único namespace.

## 5. TLS local, sem depender de ACME público

A base de TLS e certificados faz parte dos pré-requisitos da trilha; aqui o objetivo é localizar sua responsabilidade no cluster. O Secret TLS pertence ao namespace do Ingress. Crie um certificado efêmero de laboratório fora do repositório e confie explicitamente nele para este teste. Não use `curl -k`: precisamos provar nome e confiança, não só criptografia.

```bash
TLS_DIR=$(mktemp -d)
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 2 -keyout "$TLS_DIR/tls.key" -out "$TLS_DIR/tls.crt" -subj '/CN=web.curso.test' -addext 'subjectAltName=DNS:web.curso.test'
kubectl create secret tls web-tls -n curso --cert="$TLS_DIR/tls.crt" --key="$TLS_DIR/tls.key" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f laboratorios/03-rede/extras/ingress-tls.yaml
curl --fail --cacert "$TLS_DIR/tls.crt" --resolve web.curso.test:8443:127.0.0.1 https://web.curso.test:8443/healthz
```

O arquivo extra atualiza o mesmo Ingress `web` para o entrypoint HTTPS. A rota Gateway HTTP continua independente em `gateway.curso.test`. O certificado expira em dois dias: para repetir, gere outro e atualize o Secret. Em produção, automatize emissão/renovação e valide o método ACME/PKI apropriado; o módulo de entrega aprofundará a gestão de dependências.

Agora faça o mesmo pela Gateway API. O certificado do Ingress não cobre o segundo hostname, então criaremos `gateway-tls` com SAN próprio. Abra [extras/gateway-tls.yaml](../laboratorios/03-rede/extras/gateway-tls.yaml): ele preserva o listener HTTP `web`, adiciona `websecure` HTTPS na porta interna 8443 e referencia esse Secret em `tls.certificateRefs`. `mode: Terminate` significa que Traefik encerra TLS; o backend segue HTTP. A HTTPRoute passa a se ligar aos dois listeners explicitamente.

```bash
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 2 -keyout "$TLS_DIR/gateway.key" -out "$TLS_DIR/gateway.crt" -subj '/CN=gateway.curso.test' -addext 'subjectAltName=DNS:gateway.curso.test'
kubectl create secret tls gateway-tls -n curso --cert="$TLS_DIR/gateway.crt" --key="$TLS_DIR/gateway.key" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f laboratorios/03-rede/extras/gateway-tls.yaml
kubectl describe gateway web-gateway -n curso
kubectl get httproute web -n curso -o yaml
curl --fail --cacert "$TLS_DIR/gateway.crt" --resolve gateway.curso.test:8443:127.0.0.1 https://gateway.curso.test:8443/healthz
```

Espere `ok`, listener aceito e referências resolvidas. Um SAN errado produz falha de hostname no cliente; Secret inexistente produz erro no status/listener. Para recuperar um certificado errado, gere o SAN correto e reaplique **somente** o Secret correspondente. Os certificados desta prática duram dois dias; automação de renovação e TLS entre proxy/backend são extensões de produção, não resultados reivindicados por esta aula.

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

**Tempo: 90–120 minutos.** Publique uma segunda aplicação no mesmo Traefik com hostname diferente. Pode ser outra instância do servidor HTTP fornecido no módulo 02, com nomes de recursos e labels próprios e conteúdo que permita distinguir sua resposta. Forneça uma rota Ingress e outra HTTPRoute, faça um teste que deve ser aceito e outro que deve ser rejeitado por hostname/path. Faça um backendRef incorreto produzir diagnóstico pelo status e recupere. Explique como o tráfego chegaria ao Traefik sem port-forward numa implantação AWS.

## Fechamento

Você percorreu descoberta DNS, transporte, seleção de backend e entrada HTTP/TLS separadamente. Explique sem consultar a aula: por que resolver o DNS não prova que existe backend? Qual porta a HTTPRoute referencia? Por que a criação de um Gateway pode ser aceita pela API, mas não pelo controller? O que `curl --cacert` e `--resolve` verificam juntos?

**Rubrica, 10 pontos:** 2 para isolar DNS/CNI/Service/proxy; 2 para endpoints e tráfego comprovado entre nós; 2 para Ingress e Gateway funcionais; 2 para TLS com nome/confiança validados nos dois modelos; 2 para recuperar falha e apresentar evidências. Avance com 8/10, sem reivindicar um teste entre nós ainda não executado.

Para deixar o ambiente previsível, volte às rotas HTTP com `kubectl apply -f laboratorios/03-rede/ingress.yaml`, `kubectl apply -f laboratorios/03-rede/gateway.yaml` e `kubectl apply -f laboratorios/03-rede/httproute.yaml`. Teste ambas as rotas antes de remover somente os Secrets efêmeros: `kubectl delete secret web-tls gateway-tls -n curso`. Apague o Pod temporário com `kubectl delete pod diagnostico -n curso` e encerre o port-forward com Ctrl+C. Os diretórios impressos em `TLS_DIR`/`HELM_DIR` ficam fora do Git; remova suas chaves efêmeras pelo gerenciador de arquivos quando não forem mais necessárias.

Preserve Traefik, suas classes e as CRDs para as próximas aulas. Desinstalar o controller com `helm uninstall traefik -n traefik` só faz sentido quando encerrar todo o uso dele; remover CRDs apagaria objetos dessa API no cluster inteiro. NetworkPolicy será estudada no módulo 06. Próximo: [04 — Storage e persistência](04-storage.md).

## Referências opcionais

Fontes verificadas nesta edição em **12/09/2026**; nenhuma leitura abaixo é necessária para completar a prática.

- [Services](https://kubernetes.io/docs/concepts/services-networking/service/) e [EndpointSlices](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/) aprofundam tipos, descoberta e distribuição dos backends.
- [DNS de Pods e Services](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/) detalha nomes, search domains e registros headless.
- [Helm 4.2.3](https://github.com/helm/helm/releases/tag/v4.2.3) documenta a procedência dos binários e seus checksums.
- [Chart Traefik 41.5.0](https://github.com/traefik/traefik-helm-chart/blob/v41.5.0/traefik/Chart.yaml) e [provider Gateway](https://doc.traefik.io/traefik/reference/install-configuration/providers/kubernetes/kubernetes-gateway/) aprofundam versões e opções da implementação.
- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) cobre regras e limites dessa API.
- [HTTPRoute](https://gateway-api.sigs.k8s.io/api-types/httproute/) e [TLS em Gateway API](https://gateway-api.sigs.k8s.io/guides/tls/) explicam condições, referências e outros modos de TLS.
