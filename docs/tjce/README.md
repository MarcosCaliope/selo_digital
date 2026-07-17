# WSDL/XSD dos serviços TJCE Selo Digital

Baixados direto do TJCE (mTLS, certificado de produção), via:

```bash
curl -k --cert certs/<cert>.crt --key certs/<cert>.key \
  "https://selodigital.tjce.jus.br/wsselodigital/<Servico>?wsdl" \
  -o docs/tjce/<Servico>Service.wsdl

curl -k --cert certs/<cert>.crt --key certs/<cert>.key \
  "https://selodigital.tjce.jus.br/wsselodigital/<Servico>?wsdl=<Servico>Service.wsdl" \
  -o docs/tjce/<Servico>Service.types.wsdl
```

Em cada par, o arquivo sem `.types` é o WSDL raiz (binding/operações); `*.types.wsdl` é o WSDL
importado com os `xsd:complexType` de verdade — é o segundo arquivo que interessa pra entender
os campos aceitos/retornados.

Isso existe porque `app/services/selo_digital/client.rb` foi construído por engenharia reversa
do PHP legado, sem WSDL em mãos — e mais de um bug real (ver histórico de commits) só foi
corrigido depois de ler os erros que o próprio TJCE devolveu em produção, ou o schema real.
Ter os XSDs reais evita depender de tentativa e erro contra produção de novo.

## MovimentarAtosService (baixado 2026-07-15)

- O tipo usado hoje (`CGenerica`) é `Ato` → `AtoSelado` (+ `selo`) → `CGenerica`
  (+ `observacoes`, `partePessoa`).
- `Ato` tem um campo `sqAtoRetificado` (`xs:long`, opcional) — é assim que se retifica um
  ato já enviado: reenviar o mesmo `CGenerica`, preenchendo esse campo com o `sqAto` que o
  TJCE atribuiu ao ato original. Não é um tipo/endpoint separado. **Implementado** em
  `ato_xml`/`Lote.enviar_atos!` e no dashboard de movimentação (marcar ato para retificação,
  editar campos, reenviar) — ver colunas `retificacao`, `sqAto_idOriginal`,
  `sqAto_tj_retificacao` em `sd_atosPraticados` e a seção de retificação em CLAUDE.md.
  **Testado contra produção em 2026-07-17** (com correção do bug de `idAto` duplicado —
  ver CLAUDE.md).
- O mesmo serviço também expõe `consultaMovimentacao(idLote, idAto?)` — consulta status de
  um lote/ato direto no TJCE. Não usado ainda.
- Campos obrigatórios (`minOccurs` ausente, i.e. default 1) em `Ato`: `dataAtoSolicitacao`,
  `valorEmolumento`, `valorFermoju`, `valorEmolumentoLivre`, `numeroAtendimento` (string —
  preenchido com `numeroTalao`, não existe coluna `numeroAtendimento`), `tipoCobranca`,
  `tipoMovimentacao`, `responsavel`, `codigoAto`. `partePessoa` é obrigatório em `CGenerica`
  (`maxOccurs="unbounded"` sem `minOccurs="0"` — precisa de pelo meno um).

## SolicitacaoSeloService / ReceberSelosService (baixados 2026-07-17)

Baixados pra revisar `client.rb#solicita_selos`/`#receber_selos` — nenhum dos dois tinha sido
disparado de verdade contra o TJCE ainda (ver Known Technical Debt no CLAUDE.md), então foram
escritos só por engenharia reversa do PHP legado, sem confirmação nenhuma. A revisão contra o
schema real achou um bug real e corrigiu (ver CLAUDE.md pra detalhes):

- **`parse_receber_selos` estava quebrado**: procurava `<seloRecebimento>` como filho direto
  de `<return>`, mas o schema real (`TSolicitacaoSeloProcessada`) aninha três níveis mais
  fundo (`return > itens > itemSolicitacao > seloRecebimento`). `selos` sempre vinha vazio —
  o botão "Receber" nunca teria funcionado, mesmo numa resposta de sucesso de verdade.
  Corrigido.
- Nem `parse_solicita_selos` nem `parse_receber_selos` detectavam `<Fault>` do SOAP (diferente
  de `parse_movimentar_atos`) — um erro estrutural (mesma classe do que already levou várias
  rodadas de tentativa e erro pra achar em `movimentar_atos`) virava uma mensagem genérica em
  vez do `faultstring` real. Corrigido nos dois.
- `TSolicitacaoSelo` (request de `solicitaSelos`) confere campo a campo e na mesma ordem com o
  que `client.rb` já enviava — nenhum problema de schema encontrado ali, só na resposta.
- `TSelo` (cada item de uma solicitação de recebimento) tem um `status` (`TRetorno`:
  código/status/mensagem) próprio por `sequencial`, permitindo rejeição parcial (ex: um tipo de
  selo sem estoque, outro ok) — não é usado ainda em `parse_receber_selos`, que só lê o
  `codigoRetorno` global. Ainda não implementado.

Ainda **não disparados de verdade contra produção** — só corrigidos contra o schema e testados
com respostas XML sintéticas moldadas no formato real.

Esses WSDLs valem pra produção; homologação é um sistema TJCE separado (ver CLAUDE.md) e
pode ter uma versão diferente — não foi verificado.
