# Correção do simulado B

Avalie a execução em cluster descartável de um CP. Não há um comando universal de restore: nome do membro, endereço e mounts precisam corresponder à instalação. O [runbook do módulo 08](../../curso/08-manutencao.md) é a referência operacional deste curso.

O candidato deve distinguir o auxiliar de manutenção/avaliação do cluster principal HA, selecionar o kubeconfig correto e usar o marcador `prova-b/marcador` da prova. Copiar endpoint, caminhos de uma tentativa anterior ou o marcador `curso-manutencao/prova` sem verificar o inventário não comprova execução correta. O preparo das ferramentas e de Traefik/Gateway ocorre fora do relógio.

## 1 — Backup (15)

Deve haver leitura do static Pod etcd para identificar endpoints/certificados e snapshot por `etcdctl snapshot save`, sem copiar a quente o diretório de dados. Verifique `etcdutl snapshot status`, revisão, checksum e existência da cópia fora da máquina. O backup contém dados sensíveis da API. Ter um arquivo `.db` sem comprovar validade/cópia não atende à tarefa.

## 2 — Drain (10)

Mostre nó SchedulingDisabled durante manutenção, Pods reposicionados e uncordon depois. DaemonSets exigem tratamento apropriado; PDB pode impedir eviction, e `emptyDir` exige aceitação explícita da perda para a aplicação de teste. `--force` não é uma solução geral de disponibilidade. Drain usa eviction voluntária; desligamento inesperado não espera PDB.

## 3 — Kubelet (15)

A evidência deve distinguir kubelet de containerd. `systemctl stop kubelet` impede novas reconciliações/heartbeats, mas os containers já existentes podem continuar no runtime. O nó muda de condição após os tempos de detecção do cluster, não instantaneamente. Reiniciar kubelet, confirmar logs, Ready e aplicação é a recuperação esperada. Não há necessidade de alterar certificados ou apagar o objeto Node.

## 4 — Upgrade (10)

Um plano correto inclui compatibilidade de CNI/CSI/Gateway, versão de origem/destino, snapshot recuperável e `kubeadm upgrade plan`. Minor upgrades são sequenciais, sem pular versões. kubelet não deve ficar mais novo que API Server. O primeiro CP executa `kubeadm upgrade apply`; demais CP/workers usam o fluxo `kubeadm upgrade node` apropriado. Atualizar pacote kubeadm não atualiza todos os componentes sozinho.

Espera-se pesquisa de versões exatas APT, unhold/hold apenas durante a manutenção, drain e atualização de kubelet/kubectl na ordem documentada, daemon-reload/restart e validações. Downgrade improvisado de etcd não é rollback seguro. Esta tarefa vale pelo plano; a execução real é obrigatória no módulo 08.

## 5 — Gateway API (15)

Gateway referencia uma classe realmente implementada, listener na porta configurada para o Traefik e HTTPRoute aponta para Service web:80. Hostname deve coincidir com o cabeçalho enviado. Observe condições e eventos, não apenas existência dos objetos. `Accepted=True` sem backend resolvido/HTTP funcional vale só parte da tarefa. Ingress antigo funcionando não comprova HTTPRoute.

Port-forward é aceitável para testar roteamento de Host/listener; não comprova comportamento de um load balancer AWS ou NetworkPolicy entre nós.

## 6 — Certificados (10)

`kubeadm certs check-expiration` mostra certificados gerenciados e datas. Deve haver comparação com `openssl x509` sobre o certificado correto (não uma chave). Renovação de folhas mantém a CA existente. Static Pods precisam recarregar certificados, normalmente por recriação controlada; um backup de manifesto dentro de `/etc/kubernetes/manifests` pode ser interpretado como outro manifesto. Atualize a cópia de admin.conf se usar kubeconfig copiado e preserve permissões.

## 7 — Restore (20)

Aceite apenas restauração confirmada: marcador antes retorna, estado pós-snapshot desaparece, API Ready e controllers/nós voltam a reconciliar. O dado original deve ser preservado como opção de recuperação; restore vai para diretório novo, com processo etcd parado e mounts ajustados conforme o runbook. Para watches Kubernetes, avalie revision bump/mark-compacted na versão de etcdutl usada.

Use `etcdutl snapshot restore`, não uma instrução antiga de `etcdctl snapshot restore`. A restauração de um membro não é receita para reconciliar um cluster etcd HA. RTO vai do começo da indisponibilidade até o serviço verificado; RPO corresponde ao estado perdido desde o snapshot. Snapshot do etcd não contém o conteúdo de EBS/PVCs de aplicações.

## 8 — Arquitetura (5)

Quórum é maioria: 3 membros precisam de2, toleram 1; 2 precisam de2, toleram 0. Um EBS só anexa a EC2 da mesma AZ; sem worker elegível na zona, Pod fica pendente até recuperar capacidade ou executar um plano explícito de recuperação dos dados. Réplica de banco em outra AZ com volume próprio é mecanismo diferente de mover um único volume entre zonas.

Ao concluir, confira todos os workers uncordoned/Ready e registre a sessão em [PROGRESSO.md](../../PROGRESSO.md).
