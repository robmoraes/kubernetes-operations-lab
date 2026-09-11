# Avaliações práticas

Os simulados são autorais. Não reproduzem questões reais nem todos os objetivos em uma única sessão. Execute somente no cluster de laboratório, com contexto confirmado e sem cargas reais.

| Avaliação | Quando | Duração | Correção |
|---|---|---|---|
| [A — recursos e diagnóstico](simulado-a.md) | Depois do módulo 09 | 120 min | [Gabarito A](gabaritos/simulado-a.md) |
| [B — administração e recuperação](simulado-b.md) | Depois do módulo 10 | 120 min, infraestrutura preparada antes | [Gabarito B](gabaritos/simulado-b.md) |
| [Complemento CKAD](ckad-complementar.md) | Depois de A | 3 sessões de 60 min | Critérios no próprio enunciado |
| [Projeto final](../curso/12-sre.md) | Depois do módulo 11 | 20–30 h, conforme escopo | Rubrica do módulo 12 |

Comece pelo enunciado. Leia o gabarito apenas depois da tentativa. Dê pontos pelo **estado final e comprovação**, não pela coincidência de comandos com a solução. Guarde as respostas em `evidencias/` sem segredos.

O A usa um namespace descartável e uma CRD identificada. O B precisa de acesso SSH e um cluster kubeadm descartável de um control plane. Não rode recuperação do etcd em um cluster HA por adaptação improvisada do B.

Antes do relógio: confira capacidade, CNI, DNS, provisionador de storage escolhido, versões dos clientes e cache de imagens. Tempo de download não deve virar teste de memorização. Em nova tentativa, use novo estado e variações de nomes/portas, sem afetar namespaces de outras aulas.

Um observador pode ler os critérios e avaliar suas evidências. Sozinho, espere até o dia seguinte para repetir itens que acabou de corrigir. Use a [matriz de certificações](certificacoes.md) para revisar temas que não caíram nos simulados.
