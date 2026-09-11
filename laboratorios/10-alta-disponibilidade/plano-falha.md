# Plano de falha de laboratório

- Contexto kubectl e conta AWS:
- Nós/AZs e IDs EC2 confirmados:
- Endpoint da API e load balancer:
- Data do backup e resultado do restore isolado:
- Responsável pela execução:
- Horário de início e limite da janela:
- Falha exata (somente um CP inicialmente):
- Hipótese de impacto na API:
- Hipótese de impacto no tráfego existente:
- Critério de abortar o experimento:
- Comando/ação de recuperação previamente preparado:
- Sondas antes, durante e depois:
- Tempo de detecção:
- Tempo de recuperação (RTO medido):
- Dados efetivamente perdidos / RPO medido:
- Resultado esperado versus observado:
- Riscos ainda não cobertos:

Uma indisponibilidade de API não equivale automaticamente a indisponibilidade dos pods
existentes. Também não prova que novos pods ou novos endpoints poderão ser reconciliados.
