# Módulo 00 - Task 01 - Escolha do Serviço Stateless

**Serviço stateless candidato**

O Quick Quiz é um projeto de portfólio com vários serviços com
interoperabilidade, sua composição envolve APIs, SPAs e um Gerenciador;

O sistema roda com Docker Compose em uma instância EC2 na AWS.

Usa Traefik na borda que gerencia também os certificados usando
`Let's Encrypt` como resolver;

Foi escolhido o `SPA Dev` por ser totalmente stateless enquanto os
serviços mais completos são stateful. Vamos chamar o candidato apenas de
`SPA` nesse documento.

**Detalhes da Instância** onde o SPA roda

O serviço roda em uma instância EC2 standalone;

- amazon/al2023-ami-2023.12.20260608.0-kernel-6.1-x86_64
- 2 vCPUs
- EIP associado
- Registro DNS resolvendo para o servidor
- Traefik na borda resolvendo para o serviço
- Docker Compose gerenciando o serviço

**Detalhes do Compose** para o serviço SPA

Traefik é uma capacidade importante para os serviços; ele opera na borda
do servidor e gerencia os certificados com HTTP challenge usando Let’s Encrypt
como resolver;

Inventário do serviço **SPA**

| Item                 | Situação atual                         |
| -------------------- | -------------------------------------- |
| Função               | Interface web do QuickQuiz Dev         |
| Tipo                 | SPA estática                           |
| Hospedagem           | EC2 quickquiz-beta-ec2                 |
| Container            | quickquiz-spa-dev-1                    |
| Imagem               | robmoraes/quick-quiz-dev:v0.7.0        |
| Servidor web         | Nginx 1.27 Alpine                      |
| Arquitetura          | linux/amd64                            |
| Usuário              | nginx, sem root                        |
| Porta interna        | 8080/TCP                               |
| Acesso externo       | HTTPS                                  |
| Domínios             | dev.quickquiz.com.br, quickquiz.com.br |
| Proxy de entrada     | Traefik                                |
| Rede Docker          | quickquiz-web                          |
| Health check         | GET /healthz, a cada 30 segundos       |
| Política de reinício | unless-stopped                         |
| Filesystem           | Somente leitura                        |
| Área temporária      | /tmp, 32 MiB                           |
| Persistência         | Nenhuma                                |
| Segredos             | Nenhum                                 |
| Logs                 | stdout e stderr                        |
| Limites de recursos  | Não configurados                       |
| Consumo observado    | 6,32 MiB de RAM, CPU próxima de 0%     |
| Estado atual         | Saudável, sem reinícios                |

**Dependências, configurações e réplicas**

Atualmente o sistema roda em Docker Compose e apenas uma réplica. Como
meta futura o serviço deve rodar com 2 réplicas sendo uma em cada
worker para alta disponibilidade;

A SPA através do Nginx cria um proxy reverso para as APIs do quiz e ads.

O papel do serviço Manager é administrar os temas, questões e respostas
que serão usados pela API para fornecimento à SPA. O manager também
gerencia a publicidade através da ADS-API que por sua vez entrega os
produtos para exibição na SPA.

As APIs do Quiz e Ads são fechadas na rede interna e expostas apenas
no proxy reverso do Nginx da SPA que expõe apenas os métodos necessários
para seu próprio consumo.

A lista técnica de dependências do serviço atual para build e deploy é:

- Docker Engine
- Docker Compose
- Docker Hub
- Traefik
- Nginx
- DNS
- Let's Encrypt
- Quiz API
- Ads API
- Node.js
- npm

# SLO

O serviço SPA é o principal serviço entregue diretamente para o
usuário final e deve ter disponibilidade de 99.9% com exceção para uma
janela semanal de manutenção pois alguns serviços dependem de
reinicialização para atualização de novos pacotes de Quizzes.

O plano ainda não implementado para o serviço é: Todo sábado às
00:00 (-03), uma janela de manutenção de 30 minutos é aberta para
atualizações e o serviço SPA pode ficar desativado nesse período;

Então a meta é de 99.9% de disponibilidade de sábado às 00:30 (-03) até
sexta às 23:59:59 (-03);

Quando os demais serviços passarem por refatoração e forem classificados
como stateless e dispensar a necessidade de update para atualização de
pacotes de Quizzes, essa meta deve ser redefinida.

O sucesso pode ser medido com /healthz; Com estado saudável comprovado
deve ser feito teste automatizado de ponta a ponta para validar a
disponibilidade das APIs e ausência de logs de erro após requisições
contra a URL da SPA. A principal garantia de sucesso deve ser obtida
através de smoke teste manual com acesso a dev.quickquiz.com.br, escolha
de um tópico, resposta de todo quiz até a tela de resultado e
encerramento da sessão com sucesso.

# Rollback

A política de rollback é manual e consiste no seguinte:

Se houver alteração em arquivo .env com adição ou alteração de variáveis
e valores, um backup do .env deve ser realizado antes do processo de
deploy e o digest da imagem anterior deve ser anotado; Após execução do
deploy, se for necessário Rollback, o serviço deve ser atualizado com
o .env e imagem anteriores;

Se não houver alteração em variáveis de ambiente (.env) então o digest
da imagem deve ser anotado e em caso de falha do deploy, o serviço deve
ser restaurado para o digest anterior.

Atualmente o processo de atualização do serviço já contempla a política
de preservação do estado anterior para rollback, apesar de não ter sido
validado por teste e nem ter sido acionado ainda por falha no deploy.

O critério para acionamento do rollback é alguma falha que impeça a nova
versão do serviço de subir após o deploy, com o serviço docker falhando,
containers subindo e caindo imediatamente;

O critério de aceitação do deploy deve ser: após o deploy do novo serviço,
o container deve entrar em Running e se manter, e um teste manual feito
garantindo o comportamento mínimo de resposta de pelo menos um quiz até
a tela de resultado. Caso o critério não seja atendido, o rollback deve
ser acionado.

O procedimento é o seguinte:

- 1 Backup do .env e digest da imagem atual
- 2 Execução do deploy (compose update)
- 3 Checagem manual do estado dos containers
  - 3.1 Container Falhou
    - Rollback
      - Checagem manual do estado dos containers
        - Container Falhou
          - SPA em manutenção para análise forense
        - Container Running
          - Smoke teste de ponta a ponta de um quiz
            - Tela de resultado do quiz com sucesso
              - Rollback concluído, versão anterior restaurada
            - Erro na execução
              - SPA em manutenção para análise forense
  - 3.2 Containers Running
    - Smoke test
      - Tela de resultado do quiz com sucesso
        - Deploy concluído
      - Erro na execução
        - Rollback
          - Checagem manual do estado dos containers
            - Container Falhou
              - SPA em manutenção para análise forense
            - Container Running
              - Smoke teste de ponta a ponta de um quiz
                - Tela de resultado do quiz com sucesso
                  - Rollback concluído, versão anterior restaurada
                - Erro na execução
                  - SPA em manutenção para análise forense

# Plano para o laboratório

Para rodar a SPA será necessário rodar também os demais serviços que
atualmente são stateful; A SPA precisa de pouco processamento e pouca
memória e pode rodar em multireplica;

Atualmente todos serviços com exceção das SPAs operam com classificação
stateful e para continuar operando dessa forma no laboratório, eles
devem ser executados em apenas uma réplica e ancorados no worker de
nascimento.

O laboratório prevê arquitetura AMD64.

**Provisionamento**

- três EC2 Ubuntu 24.04 AMD64, 2 vCPUs, 4 GiB e 30 GiB gp3 cada;
- mesma AZ e rede isolada de produção;
- forma de acesso administrativo;

**Infra**

- Instâncias `c7i-flex.large`;
- Internet Gateway;
- IPv4 público temporário;
- acesso SSH pelo EC2 Instance Connect Endpoint;
- Security Group sem entrada administrativa direta da Internet;

Não serão usados os serviços: NAT Gateway, EIP e Load Balancer;

**Sobre o teto de gasto e rotina de desligamento/remoção**

O teto de gasto será de US$ 50 (dólares americanos);

Preparação:

Será criado um projeto Terraform pelo Codex para provisionamento de
toda a infraestrutura e bootstrap do Kubernetes nos nodes.

Primeira vez durante o Lab do módulo 01:

Criar a infraestrutura e realizar o bootstrap do Kubernetes manualmente sem
usar Terraform. Ao concluir o exercício do módulo, todos os
recursos devem ser destruídos para cessar cobrança.

A partir da segunda vez:

Aqui vou usar o Terraform para subir a infra para começar novos
exercícios em laboratório.

Primeiro aplico o Terraform à infraestrutura e aguardo o ambiente estar
saudável e faço a configuração manual até recuperar o estado para
começar o novo exercício. No fim do exercício, a infraestrutura deve ser
destruída usando Terraform.

O processo do Terraform consiste no seguinte: preparar os três
hosts, inicializar CP e Calico, deixar os workers preparados e
sem fornecer um token. O trabalho manual começa com a geração do
token e a realização dos joins nos workers.

**Região e AZ**

A região será Virgínia do Norte `us-east-1`, e a AZ será
escolhida conforme as opções disponíveis durante a criação das
instâncias;

**Acesso administrativo**

Via console AWS será usado o usuário `dslab`, que possui perfil
de provisionador via policy e grupo de usuários; as permissões
serão criadas conforme a necessidade.

Via CLI será usado o usuário administrativo já configurado no
AWS CLI local com acesso total a minha conta AWS.

O responsável pelo orçamento é o titular da conta AWS, e as
revisões de custos devem acontecer sempre antes de rodar
`terraform apply` pela primeira vez ao dia.

# Consumo atual

| Serviço                     | Memória   |
| --------------------------- | --------- |
| Manager FPM                 | 53,43 MiB |
| Manager Web                 | 4,47 MiB  |
| Quiz API                    | 8,63 MiB  |
| Ads API                     | 4,98 MiB  |
| SPA Dev                     | 6,32 MiB  |
| SPA DSLab                   | 4,38 MiB  |
| Traefik                     | 26,79 MiB |
| Total dos containers aprox. | 109 MiB   |

Na instância:

- Memória total: 916 MiB
- Usada pelo sistema: 402 MiB
- Disponível: 280 MiB
- Cache: 358 MiB
- Swap: inexistente
