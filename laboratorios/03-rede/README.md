# Rede, Traefik e Gateway API

Execute os arquivos individualmente na ordem da [aula 03](../../curso/03-rede.md). Primeiro, a [aplicação base](../02-workloads/) deve estar saudável.

| Arquivo | Consumidor | Requisito |
| --- | --- | --- |
| diagnostico.yaml | kubectl | Namespace curso |
| traefik-values.yaml | Helm | Chart 41.5.0, Gateway API Standard 1.6.1 instalada |
| ingress.yaml | kubectl | IngressClass traefik e Service web |
| gateway.yaml | kubectl | GatewayClass traefik |
| httproute.yaml | kubectl | Gateway web-gateway e Service web |
| extras/ingress-tls.yaml | kubectl | Secret web-tls criado pelo aluno |

`traefik-values.yaml` não é um manifesto Kubernetes; por isso, não aplique o diretório inteiro com kubectl. O chart cria a GatewayClass; o aluno cria Gateway e HTTPRoute para compreender a separação de responsabilidades.

Ingress usa host `web.curso.test`; HTTPRoute usa `gateway.curso.test`. São nomes reservados para teste, sem depender de domínio público. O exercício básico usa ClusterIP e port-forward local para Traefik; não cria load balancer pago nem abre NodePort. O teste de ClusterIP deve ser feito separadamente de dentro do pod diagnóstico.

Para repetir em outro dia, se `diagnostico` estiver Completed, remova somente esse Pod e reaplique seu arquivo. Ele dorme por 24 horas e não tem controller para recriá-lo.

Ao terminar o módulo, você pode remover somente o Pod de diagnóstico. Preserve os recursos de rota para os módulos seguintes. Não remova as CRDs de Gateway API para limpar um exercício: isso removeria instâncias da API em todo o cluster.
