# Notes - Concepts

**stateless**:
Um serviço stateless (sem estado) é aquele que não armazena nenhuma
informação local ou histórico de interações de uma execução para a
seguinte; cada requisição traz todos os estados necessários para ser
processada.

- **Independência**: o container trata cada comando ou requisição como
  se fosse único e inédito;
- **Descartabilidade**: se um container falhar ou for encerrado, nenhum
  dado importante é perdido, pois nada de vital residia nele.
- **Armazenamento Externo**: Se o serviço precisar salvar dados (como
  cadastros de usuários ou arquivos), ele envia essas informações para
  fora do container - como para um banco de dados gerenciado ou
  armazenamento em nuvem.

`stateless service`, `independência`, `descartabilidade`,
`armazenamento externo`

---

o Kubernetes trabalha de **forma declarativa**:

Você registra o resultado pretendido, esse é o **estado desejado**;

O **estado observado** descreve o que existe naquele momento;

**Reconciliar** é comparar continuamente essa intenção com a realidade e
agir para aproximá-las.

Um **controller** é o processo que executa esse ciclo.

`forma declarativa`, `estado desejado`, `estado observado`,
`reconciliação`, `controller`

---

- `CRI`: interface entre `kubelet` e runtime;
- `containerd`: runtime;
- `CNI`: interface usada para integrar a rede de `Pods`;
- `Calico`: implementação;
- `CoreDNS`: responde consultas de nomes internos;
- `kube-proxy`: instalado por `kubadm`, programa o encaminhamento dos
  endereços virtuais do Services para seus backendds;

`CNI` e `kube-proxy` resolvem partes diferentes do caminho de rede.

- kubeadm: prepara o cluster e seus certificados;
- kubelet: agente de cada nó;
- kubectl: cliente da API;
