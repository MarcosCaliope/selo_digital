# Manual do Sistema — Selo Digital

## 1. O que é o sistema

O **Selo Digital** é a aplicação usada pelo cartório para se conectar ao webservice **Selo
Digital do TJCE** (Tribunal de Justiça do Ceará) — o sistema que controla, para cada
serventia, quantos selos digitais existem disponíveis, quais atos já foram registrados com
selo, e o pedido/recebimento de novos selos.

O sistema tem três telas principais:

- **Selos Disponíveis** (`/selos`) — consulta o saldo de selos que o TJCE ainda permite pedir.
- **Empresas** (`/empresas`) — cadastro do(s) cartório(s) e do certificado digital usado para
  autenticar no TJCE.
- **Movimentação** (`/movimentacao`) — o painel do dia a dia: envio de atos praticados,
  acompanhamento de lotes, retificação, estoque de selos e solicitação/recebimento de novos
  selos.

Por trás das telas, o sistema conversa com o TJCE por um protocolo chamado SOAP, usando um
certificado digital (arquivo `.pfx`) para provar que é realmente o cartório fazendo a
requisição — da mesma forma que um cadeado de segurança em um site, mas nos dois sentidos
(o TJCE também confirma a identidade do sistema, e o sistema confirma a do TJCE).

## 2. Tela: Selos Disponíveis (`/selos`)

Esta é a tela inicial do sistema. Assim que aberta, ela pergunta ao TJCE: "quantos selos de
cada tipo esta serventia ainda pode pedir?"

O que aparece na tela:

- **Tipo de Selo** — o código do tipo de selo (cada tipo de ato usa um tipo de selo diferente).
- **Saldo Disponível** — quantos selos desse tipo o TJCE ainda deixa o cartório solicitar.
- **Cota** — o limite total configurado pelo TJCE para esse tipo de selo.
- **Utilização** — uma barra mostrando o percentual já usado da cota (fica vermelha quando
  está baixa, sinal de que está perto de esgotar).

Se o cartório estiver configurado para o **ambiente de homologação** (ambiente de testes do
TJCE, não o de verdade), aparece um aviso amarelo no topo da tela lembrando disso.

Clicar em "Atualizar" refaz a consulta na hora.

**Importante:** este saldo é diferente do "estoque local" mostrado na tela de Movimentação —
ver seção 4.6.

## 3. Tela: Empresas (`/empresas`)

Cadastro do(s) cartório(s) que usam o sistema. Cada registro guarda os dados de identificação
do cartório e a configuração necessária para falar com o TJCE.

### 3.1 Listagem

Mostra todos os cartórios cadastrados, com uma visão rápida de: se já tem certificado digital
cadastrado, se está configurado para produção ou homologação, e se o envio automático de atos
está ligado (ver seção 4.7).

### 3.2 Cadastro / edição

Campos principais:

- **Dados de identificação** — razão social, nome fantasia, CNPJ, endereço, telefone, e-mail,
  responsável e CPF do responsável (esses últimos dois também são usados como identificação
  do "solicitante"/"informante" nas conversas com o TJCE).
- **Código da serventia (TJCE)** — o código que identifica esta serventia perante o TJCE.
- **Certificado digital (.pfx)** — o arquivo do certificado usado na conexão com o TJCE. Pode
  ser enviado (upload) diretamente pela tela; fica guardado de forma criptografada.
- **Senha do certificado** — a senha do arquivo `.pfx`. Também criptografada. Se deixada em
  branco na edição, a senha já cadastrada é mantida (não é apagada).
- **Usar ambiente de homologação do TJCE** — checkbox. Quando marcado, todas as consultas e
  operações desse cartório passam a usar o ambiente de testes do TJCE em vez do de produção.
  Atenção: homologação e produção são sistemas separados no TJCE, com cadastros de certificado
  independentes — um certificado que funciona em produção pode ser recusado em homologação até
  o TJCE cadastrá-lo lá também.
- **Envio automático de atos (minutos)** — ver seção 4.7.

## 4. Tela: Movimentação (`/movimentacao`)

O painel principal do dia a dia. Reúne seis blocos de informação/ação, descritos abaixo.

### 4.1 Atos aguardando envio

Lista os atos já praticados no cartório e ainda não enviados ao TJCE (até 50 por vez). Cada
linha mostra o selo, há quanto tempo está aguardando, o código do ato, o tipo de selo (com uma
etiqueta "Retificação" quando for o caso — ver seção 5) e o protocolo.

**Passo a passo para enviar:**

1. Marque a caixinha dos atos que deseja enviar (ou todos).
2. Clique em "Enviar selecionados ao TJCE".
3. Confirme o aviso — esta ação é real: consome selo de verdade e registra o ato de verdade
   junto ao TJCE, não é reversível.
4. O sistema cria um lote, envia todos os atos marcados numa única requisição, e atualiza cada
   ato individualmente conforme a resposta do TJCE: aceito (some desta lista, aparece em
   "Atos enviados") ou rejeitado (some desta lista, aparece em "Atos rejeitados").

Se um ato já estiver marcado como retificação (etiqueta "Retificação"), aparece também um link
"Editar retificação" para revisar os dados antes de enviar de novo.

### 4.2 Lotes emitidos hoje

Histórico simples dos lotes enviados no dia: quando foi emitido, quando o TJCE respondeu, a
resposta resumida (quantos títulos confirmados) e a quantidade de títulos no lote.

### 4.3 Atos enviados (confirmados pelo TJCE)

Lista os atos que o TJCE já confirmou (até os 10 mais recentes), com o número interno que o
TJCE atribuiu a cada um (`sqAto`) e a data de retorno.

Tem uma caixa de busca por **número do selo** no topo — útil quando o ato que você procura não
está entre os 10 mais recentes.

Cada linha tem um link **"Retificar"**, que abre o formulário de correção (seção 5).

### 4.4 Atos rejeitados pelo TJCE

Lista os atos que foram enviados mas que o TJCE recusou, mostrando o **código e a mensagem do
erro** que o TJCE devolveu — por exemplo, um dado inválido ou uma pendência.

Cada linha tem um botão **"Reenviar"**, que devolve o ato para a fila de "Atos aguardando
envio" (seção 4.1), pronto para corrigir (se for o caso, via retificação) e enviar de novo.

### 4.5 Estoque local de selos

Mostra, por tipo de selo, quantos selos já foram baixados do TJCE e ainda não foram usados
(diferente do saldo do TJCE mostrado em `/selos` — ver seção 2). Quando o estoque de um tipo
fica abaixo do mínimo configurado, o número aparece em vermelho.

Duas formas de pedir mais selo:

- **Botão "Solicitar N"** — só aparece quando o estoque está abaixo do mínimo. Pede a
  quantidade padrão já configurada para aquele tipo de selo.
- **Campo de quantidade + botão "Solicitar"** — sempre disponível, para qualquer tipo de selo,
  a qualquer momento, independente do estoque atual. Digite a quantidade desejada e confirme.

Em ambos os casos, o pedido é enviado ao TJCE na hora e vira uma "solicitação pendente"
(seção 4.6) até os selos serem efetivamente baixados.

### 4.6 Solicitações pendentes de recebimento

Lista os pedidos de selo já aceitos pelo TJCE mas cujos números de série ainda não foram
baixados para o sistema.

Clique em **"Receber"** para efetivamente baixar os selos dessa solicitação: se der certo, os
selos são gravados no estoque local (aumentando o número mostrado em 4.5) e a tela mostra
quantos selos foram recebidos; se der errado, aparece a mensagem de erro do TJCE.

## 5. Passo a passo: retificar um ato já enviado

Retificar significa corrigir um ato que o TJCE já confirmou, reenviando os dados corrigidos
referenciando o ato original.

1. Na lista "Atos enviados" (seção 4.3), clique em **"Retificar"** no ato desejado.
2. Abre um único formulário com duas partes:
   - **Dados do ato** — valores (emolumento, documento, FERMOJU, etc.), datas, tipo de
     cobrança/movimentação, número do talão.
   - **Dados da parte** (`partePessoa`) — nome, documento (tipo/número/descrição/órgão
     emissor/data de emissão) e endereço da pessoa envolvida no ato. Esses campos já vêm
     preenchidos automaticamente quando o sistema consegue identificar a parte real (alguns
     tipos de ato); pode editar livremente ou deixar como está.
3. Ajuste o que for necessário e clique em **"Marcar como retificação e devolver à fila"**,
   confirmando o aviso.
4. O ato volta para "Atos aguardando envio" (seção 4.1), marcado com a etiqueta
   "Retificação", pronto para ser enviado de verdade pelo botão "Enviar selecionados ao TJCE".
   **Nada é enviado ao TJCE neste passo** — só na hora de marcar a caixinha e enviar.

Se o ato ainda estiver na fila de pendentes (ainda não reenviado), é possível reabrir esse
mesmo formulário a qualquer momento pelo link "Editar retificação" (seção 4.1).

## 6. Passo a passo: solicitar e receber selos manualmente

1. Na tela de Movimentação, vá até "Estoque local de selos" (seção 4.5).
2. Escolha o tipo de selo desejado, digite a quantidade no campo ao lado, clique em
   "Solicitar" e confirme.
3. A solicitação aparece em "Solicitações pendentes de recebimento" (seção 4.6) assim que o
   TJCE aceita o pedido.
4. Clique em "Receber" nessa solicitação para baixar os números de série — eles passam a
   contar no estoque local (seção 4.5), disponíveis para uso nos atos.

## 7. Envio automático de atos

Além do envio manual (marcar e clicar em "Enviar selecionados ao TJCE"), o sistema pode
enviar a fila de atos pendentes sozinho, em intervalos regulares.

- Configurado por cartório, na tela de Empresas (seção 3.2), campo **"Envio automático de
  atos (minutos)"**.
- **0 (padrão) = desligado** — continua sendo preciso enviar manualmente.
- **Maior que 0** — o sistema verifica a fila periodicamente e, se já tiver passado esse
  número de minutos desde o último envio (manual ou automático), envia sozinho todos os atos
  que estiverem aguardando naquele momento.
- Quando ligado, aparece um aviso no topo da tela de Movimentação avisando que o envio
  automático está ativo e de quanto em quanto tempo ele roda, com um atalho para reconfigurar.
- Atos rejeitados pelo envio automático aparecem normalmente em "Atos rejeitados" (seção 4.4),
  do mesmo jeito que um envio manual rejeitado.

O envio automático de **solicitação e recebimento de selos** (seções 4.5 e 4.6) não existe —
essas duas ações continuam sempre manuais, por consumirem cota real de selo do TJCE sem
nenhuma forma de simulação prévia.

## 8. Produção x Homologação

O TJCE mantém dois ambientes completamente separados:

- **Produção** — o ambiente real, usado no dia a dia do cartório.
- **Homologação** — ambiente de testes do TJCE, para validar integrações sem afetar dados
  reais.

Cada cartório cadastrado escolhe um dos dois (checkbox "Usar ambiente de homologação",
seção 3.2). Um certificado digital precisa estar cadastrado separadamente em cada ambiente
pelo próprio TJCE — ter o certificado funcionando em produção não garante que funcione em
homologação, e vice-versa.

Sempre que o cartório estiver configurado para homologação, as telas de Selos Disponíveis e
Movimentação mostram um aviso visível disso, para não haver confusão sobre qual ambiente está
sendo usado.

## 9. Avisos gerais

- Ações de envio ao TJCE (enviar atos, solicitar selo, receber selo) **consomem recursos
  reais** — selo de verdade, atos registrados de verdade — e **não têm modo de simulação**.
  Uma vez confirmadas, não são reversíveis pelo sistema.
- O sistema guarda um registro técnico bruto de cada conversa com o TJCE (pergunta e resposta)
  para fins de suporte/depuração, mas isso não é visível nas telas — é uso interno da equipe
  técnica quando algo precisa ser investigado.
