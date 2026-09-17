# Simulado B — administração e recuperação

Tempo: **120 minutos**, após preparar o ambiente. Pontuação: **100**. Use um **cluster kubeadm descartável com 1 CP e 2 workers**, independente do cluster HA do módulo 10. A recuperação altera o estado inteiro da API; não a execute no ambiente compartilhado dos outros módulos.

Pré-requisitos: módulos 01–10, SSH/sudo, `crictl` funcional, `etcdctl` e `etcdutl` compatíveis, CNI/DNS saudáveis, cliente compatível, Traefik e Gateway API da aula 03 instalados. O procedimento de restore do módulo 08 deve ter sido praticado antes da prova; aqui será executado autonomamente. O exame cobre parte da administração; complete upgrade real e HA nos laboratórios além desta avaliação.

## Preparação fora do relógio

Use a preparação do **cluster auxiliar** descrita no módulo 08, começando em Kubernetes 1.35 e com utilitários da versão efetiva do etcd. Se descartou aquele ambiente depois do upgrade, reconstrua o auxiliar antes do relógio; não substitua por restore no principal HA. Instale também o Traefik/Gateway API do módulo 03 nesse auxiliar. Escolha e registre endpoint/kubeconfig/contexto exclusivos para a avaliação.

Os nomes do runbook 08 são exemplos, não alvos universais. Neste simulado o marcador é `ConfigMap/prova-b/marcador`, não `curso-manutencao/prova`. Substitua as referências ao marcador, endpoint e kubeconfig pelos valores registrados da prova. Preserve os cuidados de snapshot, PKI, pausa dos componentes, diretório novo e validação; não execute o upgrade do módulo 08 durante estes 120 minutos.

Crie namespace `prova-b`, ConfigMap `marcador` com `fase=antes` e Deployment `web` com duas réplicas HTTP (pode adaptar o módulo 02), Service porta 80 e requests baixos. Confirme HTTP entre nós. Defina a variável `WORKER_TESTE` com o nome exato de um dos workers e anote o contexto. Garanta capacidade para as duas réplicas no worker restante e não crie PVC local para essa aplicação.

O diretório privado para backups fica **fora do Git**. Use nomes novos para o snapshot e cópias, sem sobrescrever os do treino. Registre IP/nome do membro etcd, paths de certificados, endpoints e mounts lidos do manifesto existente. Prepare uma cópia protegida da PKI e configuração da VM para recuperação. Disponibilidade externa não é necessária para esse simulado.

## Tarefas

| Item | Pontos | Resultado exigido |
|---|---|---|
| 1 — fotografia e backup | 15 | Registrar componentes/versões; snapshot consistente do etcd via API com hash/revisão/status verificáveis; copiar para armazenamento fora do CP e registrar checksum sem expor conteúdo |
| 2 — manutenção de worker | 10 | Cordon/drain de WORKER_TESTE, aplicações recuperadas no outro worker, inspeção do PDB/evictions, uncordon. Explicar dados descartados se usar emptyDir |
| 3 — runtime/nó | 15 | No worker de teste, parar kubelet por SSH, observar efeitos na API e nos containers por crictl, recuperar serviço e Ready. Registrar antes/depois. Não esperar que parar kubelet mate todos os containers |
| 4 — plano de upgrade | 10 | Selecionar minor seguinte e patches compatíveis, enumerar ordem kubeadm/control planes/kubelets/kubectl/workers, gates de backup/drain/add-ons e comandos de consulta. Não executar upgrade durante este simulado |
| 5 — Gateway API | 15 | Criar Gateway e HTTPRoute no namespace prova-b, usando GatewayClass Traefik existente; rotear prova-b.example.test para web:80, comprovar Accepted/ResolvedRefs/Programmed e resposta Host correta por port-forward do controller |
| 6 — certificados | 10 | Inspecionar expiração com kubeadm e certificado servidor com openssl, explicar CA vs folhas, quais static Pods reiniciar e como atualizar kubeconfig após renovação; sem renovar CA |
| 7 — restauração | 20 | Alterar marcador para fase=depois; restaurar snapshot do item 1 conforme módulo 08, mesmo CP isolado; API saudável e fase=antes; medir RTO e quantificar estado perdido pós-snapshot |
| 8 — defesa de arquitetura | 5 | Explicar por que 3 membros etcd toleram 1 falha, por que 2 não melhoram tolerância, e o que ocorre a um PVC EBS quando só há worker disponível em outra AZ |

Os itens 1 e 7 usam **o mesmo snapshot**. Depois do restore, objetos criados após o snapshot deixam de existir: guarde evidências do Gateway antes disso e reaplique a configuração desejada conscientemente após confirmar a recuperação.

O item 3 é uma interrupção intencional só no worker selecionado. Faça a recuperação mesmo se o tempo acabar. Se o diagnóstico levar mais tempo que o previsto, registre a lacuna e continue; não apague o nó ou resete o cluster para “consertar”.

## Entrega e critérios

Para cada item, metade dos pontos pelo procedimento correto/escopo e metade pela comprovação e explicação. Em tarefas só documentais (4/6/8), divida entre completude e correção. Expor credenciais, restaurar o cluster errado ou destruir dados invalida a avaliação de recuperação, mesmo que o estado final pareça saudável.

Arquive versões, comandos sanitizados, tempo, status final e uma linha do tempo do restore. Não arquive snapshot, kubeconfig ou chaves. Confira o [gabarito B](gabaritos/simulado-b.md) e registre a nota.
