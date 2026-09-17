# 00 — Como estudar e demonstrar competência

Este curso ensina a construir, operar, recuperar e explicar uma plataforma Kubernetes a partir de fundamentos de Linux, containers, redes, DNS e TLS. O percurso desenvolve conhecimento da API, dos controllers e das extensões do cluster, além da capacidade de resolver tarefas práticas sob tempo. Concluir leituras ou instalar um chart não comprova, sozinho, essas capacidades.

**Carga de referência:** 240–320 horas, aproximadamente 14–18 semanas com 18–22 horas semanais. Os módulos são etapas, não semanas rígidas. Troubleshooting, restauração e projeto final merecem repetição; avance pela evidência de domínio, não pelo calendário.

## Antes de começar

Reserve 2–3 horas para esta preparação. Você precisa saber operar Linux, containers, redes, DNS e TLS; não precisa conhecer Kubernetes, outro orquestrador ou ter um cluster instalado. Tenha este repositório aberto e um editor. Você produzirá um inventário inicial usando o cenário fornecido nesta aula ou uma aplicação própria containerizada, sem dados de clientes ou credenciais. Nesta aula você apenas organiza o estudo e planeja o laboratório: não cria recursos pagos nem executa comandos de Kubernetes.

O curso assume uma estação Linux com Bash e, a partir do módulo 01, três servidores Ubuntu 24.04 AMD64 novos, separados da produção. A estação pode ser AMD64 ou ARM64; sua arquitetura não precisa ser igual à dos servidores. Se usa outro sistema na estação, uma VM Ubuntu com acesso à rede privada permite seguir o mesmo roteiro. Instalações de ferramentas específicas aparecem antes de seu primeiro uso.

## O que você vai conseguir fazer

- Distinguir preparação, leitura, prática e comprovação de domínio.
- Planejar um laboratório isolado e reconhecer onde cada comando será executado.
- Produzir um inventário inicial da aplicação e uma evidência útil, sem segredos.
- Saber exatamente quando encerrar uma aula e quando uma referência é apenas aprofundamento.

## O contrato de leitura do curso

Cada capítulo declara seus pré-requisitos e objetivos, desenvolve a explicação, conduz a prática e termina com uma verificação de aprendizagem. O conhecimento obrigatório para seus objetivos está na própria aula ou em um módulo anterior declarado. Não é necessário abrir referências externas para conseguir concluí-la.

As referências ficam na última seção, chamada **Referências opcionais**. Abra-as depois, se quiser aprofundar o assunto indicado; você não precisa ler a página inteira nem seguir seus outros links. Encerrar a aula sem abrir essas referências é uma forma normal de estudar, não uma leitura incompleta.

Há duas exceções que não são tarefas escondidas de leitura: arquivos locais do laboratório, que são o material do exercício, e endereços usados por comandos para baixar pacotes ou testar serviços. Quando uma prática ensinar consulta técnica, haverá uma pergunta e um ponto de parada. Por exemplo: descobrir o efeito de um campo com `kubectl explain`, registrar a resposta e voltar ao exercício. Não será preciso explorar toda a documentação.

## O resultado que você vai construir

O fio condutor é implantar e operar uma aplicação em Kubernetes, comprovando seu comportamento a cada etapa. Os laboratórios fornecem uma aplicação web mínima e componentes para praticar rede, persistência e observabilidade. Você pode completar toda a trilha evoluindo esses materiais ou aplicar os desafios a um projeto próprio containerizado. O repositório deverá terminar com manifests, automação revisável, decisões de arquitetura, runbooks, incidentes investigados e um projeto final demonstrável.

Se escolher uma aplicação própria com vários serviços, comece pelo inventário de um único componente stateless e suas dependências. A plataforma completa pode entrar nas etapas posteriores. Ela pode vir de Compose, Docker ou outro ambiente; não precisa passar por uma migração intermediária nem já estar publicada na Internet.

O ambiente inicial tem um control plane, responsável pela API e pelas decisões do cluster, e dois workers, que executarão suas aplicações. O percurso acrescenta rede, armazenamento, segurança, manutenção, entrega, alta disponibilidade, EKS e práticas SRE. Prometheus será usado no módulo final para responder a perguntas operacionais; Loki não é necessário nesta trilha. Nenhum deles é pré-requisito para o primeiro control plane.

## O que o Kubernetes acrescenta aos containers

Uma aplicação containerizada precisa de decisões sobre execução, acesso de rede, configuração e persistência. No Kubernetes, essas responsabilidades são descritas por objetos enviados à API do cluster. Ao longo das aulas, você aprenderá quais objetos representam cada necessidade e como observar se o resultado foi alcançado. Não precisa memorizar uma lista de recursos antes de começar.

O Kubernetes trabalha de forma **declarativa**: você registra o resultado pretendido, como duas réplicas de uma aplicação. Esse é o **estado desejado**. O **estado observado** descreve o que existe naquele momento, por exemplo, apenas uma réplica saudável. **Reconciliar** é comparar continuamente essa intenção com a realidade e agir para aproximá-las. Um **controller** é o processo que executa esse ciclo para determinados objetos; ele pode solicitar a criação da réplica que falta. Se faltarem recursos ou houver uma configuração inválida, o resultado pode continuar diferente do desejado, e será necessário investigar. No módulo 01 veremos quais componentes assumem cada responsabilidade.

## Uma sessão de estudo útil

1. **Recordar, 10 minutos:** explique o conceito anterior sem consultar notas.
2. **Formular uma hipótese, 10 minutos:** escreva o que espera que aconteça no laboratório.
3. **Executar, 60–90 minutos:** observe objetos, eventos, logs e o resultado para o cliente.
4. **Provocar uma falha, 20–40 minutos:** altere uma variável e registre sintoma, hipótese, teste e causa.
5. **Concluir, 15 minutos:** restaure, prove o resultado e escreva o que faria diferente em produção.

Durante a primeira execução, consulte a aula e os manifests livremente. Na segunda, feche a solução e use o enunciado, suas notas de decisões e a ajuda pontual das ferramentas. Se faltar uma explicação, retorne à seção correspondente; não transforme a dúvida em uma obrigação de ler um site inteiro. Na terceira, use cronômetro e guarde a solução antes de olhar o gabarito. Uma resposta decorada perde valor quando o namespace, a porta ou o contexto muda.

Nos dias úteis, faça blocos curtos de teoria e tarefas de 20–40 minutos. Reserve os finais de semana para instalação, upgrades, restauração e exercícios de arquitetura. Deixe tempo para desprovisionar os recursos pagos depois de confirmar o que ainda será necessário.

## Onde cada comando roda

- **LOCAL:** seu computador com o clone deste repositório, acesso administrativo ao laboratório e, a partir do módulo 01, kubeconfig exclusivo do curso. Na AWS, o acesso privado será feito por túnel, sem exigir rota direta da sua LAN até a VPC.
- **HOST CP:** sessão SSH no control plane; comandos com sudo alteram essa máquina.
- **HOST WORKER:** sessão SSH em um worker identificado pelo nome.
- **TODOS OS HOSTS:** repetir em CP e workers novos, exclusivamente nas máquinas dedicadas ao laboratório.

Os exemplos assumem Bash e comandos LOCAL executados na raiz do repositório. Um **contexto** escolhe o cluster, a identidade e o namespace usados pelo cliente. Um **namespace** organiza uma parte dos objetos dentro do cluster, sem ser por si só uma barreira completa de segurança. O **kubeconfig** é o arquivo de configuração de acesso; ele pode conter credenciais. O módulo 01 ensina a instalar o cliente, criar um kubeconfig exclusivo e verificar o alvo antes de agir.

As credenciais de administração do laboratório devem ficar fora do Git; evidências públicas precisam estar sem tokens, certificados privados, Secrets e dados de clientes. Não execute uma instrução só porque ela contém a palavra LOCAL: confirme também que o contexto é do curso e não da produção.

## Preparação guiada: delimitar ambiente e custo

Crie um registro de preparação no seu editor. Use estas decisões como exemplo e substitua o que for específico da sua conta: “um CP e dois workers; Ubuntu 24.04 AMD64; mesma AZ; rede privada acessível pela estação; dados fictícios; nenhuma dependência da produção”. Anote nomes previstos, região/AZ, quem administra o acesso e como distinguir visualmente o terminal do curso.

Planeje três máquinas de 2 vCPU, 4 GiB de memória e disco root gp3 de 30 GiB cada. Esse é o tamanho didático do módulo 01, não uma regra universal de produção. `gp3` é um tipo de volume EBS: nesse início ele guarda o sistema e os arquivos do nó. Não é necessário criar discos de aplicação, banco ou PVC para estudar o primeiro control plane.

Defina também um teto de gasto na sua moeda, um responsável e uma revisão ao encerrar cada sessão. Instâncias ligadas, discos retidos, snapshots, NAT e balanceadores têm ciclos de cobrança próprios; parar uma EC2 não elimina todos os custos. Por enquanto, registre quais recursos pretende usar e quais ainda não serão criados. No módulo que introduzir um recurso pago, o exercício deverá incluir inventário e decisão de limpeza.

**Verificação:** você consegue apontar quais máquinas podem ser alteradas e quais não podem? Há uma maneira de acessar a rede privada sem expor a API administrativa à Internet? O teto de gasto e a data de revisão estão escritos? Se não, complete essas decisões antes de preparar hosts.

## Como produzir evidências

Crie um registro por laboratório. O [modelo de diário](../templates/diario.md) é um formulário local que você pode copiar; ele não é leitura conceitual adicional. Cada registro deve conter objetivo, data, versões, contexto, hipótese, comandos relevantes, resultado observado, diagnóstico e recuperação. Saídas pequenas e comentadas são mais úteis que uma transcrição de 500 linhas.

Exemplo de uma conclusão verificável: “Às 15:08, o Service tinha dois endpoints prontos. Ao remover a label esperada do seletor, os endpoints ficaram vazios e o cliente falhou. Restaurar o seletor recuperou o HTTP 200; os containers nunca reiniciaram.” Isso diferencia falha de descoberta de falha de processo.

Para cada módulo, produza também uma resposta de entrevista de dois minutos: problema, mecanismo, tradeoff e validação. Você deve conseguir defender por que escolheu uma solução e explicar uma situação em que escolheria outra.

## Regra de avanço e rubrica comum

Nos módulos práticos, cada item abaixo vale 0, 1 ou 2: não conseguiu; conseguiu consultando a solução; conseguiu com consulta pontual e explicação própria. A preparação deste módulo usa os critérios do exercício de entrada, pois ainda não há um cluster para recuperar.

| Dimensão    | O que demonstra 2 pontos                                       |
| ----------- | -------------------------------------------------------------- |
| Conceito    | Explica mecanismo e limites sem depender de analogia           |
| Execução    | Reconstrói o resultado e seleciona contexto/namespace corretos |
| Diagnóstico | Isola a causa por evidências e evita mudanças aleatórias       |
| Recuperação | Restaura o serviço e comprova comportamento do cliente         |
| Comunicação | Entrega manifest/runbook e explica riscos e alternativas       |

Avance com **8/10 ou mais**, sem zero em recuperação. Se falhar, repita apenas a dimensão fraca com uma variação do exercício. A meta de tempo só passa a contar depois da correção técnica.

## Falha de método e recuperação

O incidente de estudo mais comum é “rodei tudo, ficou verde, mas não sei repetir”. A recuperação é fechar o passo a passo, recriar o recurso em outro namespace e prever três resultados antes de executar: o controller responsável, o evento esperado e o teste do cliente. Compare previsão e realidade. Se só conseguir corrigir reinstalando, volte à árvore de diagnóstico do módulo.

Outra armadilha é adaptar a própria hipótese à saída. Preserve a previsão original no registro. Ao investigar profissionalmente, descartar uma hipótese com um teste pequeno já é progresso.

## Exercício autônomo de entrada

**Tempo: 45–60 minutos; sem cluster necessário.** Escolha um componente stateless da aplicação-base descrita abaixo ou de uma aplicação própria containerizada. Escreva: função, imagem/arquitetura, portas, dependências, configurações, secrets sem valores, volumes, réplicas, verificações de saúde, estratégia de atualização, forma de acesso pelo cliente, SLO e rollback. Separe fatos verificados, requisitos pretendidos e suposições. Para itens ausentes, registre “não se aplica” e a razão; para informações ainda desconhecidas, diga o que precisará verificar, sem inventar resultados.

Aqui, **stateless** significa que substituir uma instância não elimina estado exclusivo necessário ao serviço; o estado pode estar em um banco externo. **Probe** é uma verificação de saúde ou prontidão. Para o **SLO**, basta escrever uma meta de serviço percebida pelo usuário, como sucesso das requisições; seu cálculo formal será ensinado no módulo 12. **Rollback** é o caminho concreto para voltar à versão saudável. Descreva o comportamento e os mecanismos que conhece, sem precisar traduzi-los para objetos Kubernetes agora.

**Cenário fornecido para quem não tem aplicação própria:** um serviço HTTP serve uma página estática e os caminhos `/healthz` e `/readyz`. A implementação usa `httpd` da imagem `busybox:1.37.0`, na porta 8080, com duas réplicas previstas. A porta de acesso interno prevista é 80; o laboratório usará um acesso local antes de ensinar publicação com DNS e TLS. O conteúdo vem de arquivos de configuração versionados no repositório, montados somente para leitura. A aplicação não tem banco, autenticação nem API externa; usa `/tmp` apenas para arquivos descartáveis. A imagem escolhida no curso contempla AMD64 e ARM64; escolha a arquitetura do laboratório e registre que a execução ainda será comprovada. No módulo 02 você aprenderá a implantar essa base e verificar seu comportamento. Para este inventário, estas informações bastam; não é necessário interpretar os manifests nem instalar nada.

Usando esse cenário, formule com suas palavras a validação que um usuário faria e uma meta simples para ela. Descreva o que precisaria guardar para restaurar uma versão saudável após uma alteração na imagem ou no conteúdo. Como ainda não há implantação, registre esse rollback como plano a ensaiar no módulo 02. Quem usa uma aplicação própria também distingue mecanismos já testados de planos ainda não executados.

Exemplo de inventário: “frontend com duas réplicas, porta 8080, configuração não secreta, credencial para uma API externa, sem arquivos exclusivos no container; sucesso é obter a página e consultar a API; rollback usa a imagem anterior”. Isso identifica responsabilidades sem ainda decidir todos os objetos Kubernetes.

Se quiser, esboce quais objetos Kubernetes imagina que serão necessários, mas isso não é requisito de aprovação agora. Reavalie a proposta ao terminar os módulos 03, 06 e 09: o histórico da sua decisão será parte do portfólio.

**Aprovação:** nenhum segredo no documento, dados persistentes identificados ou sua ausência justificada, uma validação de sucesso percebida pelo usuário e um plano concreto de rollback. Não é necessário já ter executado esses testes para concluir esta preparação. “O pod ficou Running” não basta para provar que a aplicação funciona nas etapas práticas.

## Trabalho e certificação

Use a trilha principal para administração e CKA; os módulos de aplicação e entrega também apoiam CKAD, e segurança abre caminho para CKS. Não trate aprovação em prova como sinônimo de prontidão para qualquer produção. Trate o projeto final, os incidentes e os simulados como evidências complementares.

Regras, versões do ambiente e conteúdo dos exames mudam. Quando decidir agendar uma prova, será necessário conferir as condições atuais do exame contratado. Essa é uma etapa administrativa futura, não uma leitura obrigatória para começar o curso. Os simulados são autorais; não use questões vazadas.

## Fechamento

Você preparou um modo de estudar: observar o mecanismo, prever o resultado, praticar, recuperar e explicar. Ainda não aprendeu a instalar Kubernetes, e isso é esperado. Seu inventário descreve requisitos; a escolha e a operação dos objetos serão aprendidas nos próximos módulos.

Antes de avançar, responda sem abrir referências: qual é a diferença entre estado desejado e observado? Onde um comando HOST WORKER roda? Por que um kubeconfig e uma captura de terminal exigem cuidado? O que fará se entender a aula, mas não conseguir repetir o exercício?

Conclua este módulo quando tiver o inventário da aplicação, o plano isolado do laboratório, o teto de gasto e uma sessão de estudo agendada. Registre isso em [PROGRESSO.md](../PROGRESSO.md), sem marcar laboratórios ainda não executados. Próximo: [01 — Construir e compreender o control plane](01-control-plane.md).

## Critérios para avançar para o módulo 01

Marque apenas o que concluiu. Este checklist resume as entregas e verificações já descritas na aula.

- [x] Escolhi um componente stateless da aplicação-base ou de uma aplicação própria e registrei seu inventário: função, imagem/arquitetura, portas, dependências, configurações, secrets sem valores, volumes, réplicas, verificações de saúde, atualização e forma de acesso.
- [x] Separei fatos, requisitos e suposições, registrei o que ainda preciso verificar e identifiquei dados persistentes da aplicação e de suas dependências ou justifiquei sua ausência.
- [x] Defini uma meta simples de serviço (SLO), uma forma de verificar sucesso percebido pelo usuário e um plano concreto de rollback, distinguindo o que já foi testado do que ainda será ensaiado.
- [x] Registrei o plano do laboratório: máquinas e dimensionamento, região/AZ, isolamento da produção, acesso administrativo e identificação dos terminais.
- [x] Defini o teto de gasto, o responsável e quando revisar os recursos e custos.
- [x] Agendei uma sessão de estudo.
- [x] Respondi, com minhas palavras, às quatro perguntas da seção Fechamento.
- [x] Revisei a entrega para garantir que não contém credenciais reais, segredos ou dados de clientes.
- [x] Registrei a conclusão e a localização da entrega em [PROGRESSO.md](../PROGRESSO.md), sem marcar atividades ainda não executadas.

Com todos os itens concluídos, avance para o módulo 01. Não é necessário instalar Kubernetes, criar recursos pagos, definir os objetos Kubernetes da aplicação ou ler as referências opcionais para concluir esta etapa.

## Referências opcionais

Você pode encerrar a aula aqui. As fontes abaixo aprofundam pontos específicos e não são pré-requisitos do módulo 01. Base de fontes consultada em 10/09/2026.

- [Componentes do Kubernetes](https://kubernetes.io/docs/concepts/overview/components/) — visão mais ampla da arquitetura que será explicada e observada no próximo módulo.
- [Controllers](https://kubernetes.io/docs/concepts/architecture/controller/) — outros exemplos de reconciliação além de manter réplicas.
- [Organização do kubeconfig](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/) — configurações com múltiplos clusters e identidades, além do arquivo isolado usado no curso.
- [Currículos públicos da CNCF](https://github.com/cncf/curriculum) — consulta para comparar especializações e planejar certificações futuras.
- [Manual do candidato](https://docs.linuxfoundation.org/tc-docs/certification/lf-handbook2) — políticas administrativas a conferir quando for contratar uma prova; não acrescenta conteúdo exigido por esta aula.
