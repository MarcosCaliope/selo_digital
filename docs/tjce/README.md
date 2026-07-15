# WSDL/XSD do serviço MovimentarAtos (TJCE Selo Digital)

Baixado direto do TJCE em 2026-07-15 (mTLS, certificado de produção), via:

```bash
curl -k --cert certs/<cert>.crt --key certs/<cert>.key \
  "https://selodigital.tjce.jus.br/wsselodigital/MovimentarAtos?wsdl" \
  -o docs/tjce/MovimentarAtosService.wsdl

curl -k --cert certs/<cert>.crt --key certs/<cert>.key \
  "https://selodigital.tjce.jus.br/wsselodigital/MovimentarAtos?wsdl=MovimentarAtosService.wsdl" \
  -o docs/tjce/MovimentarAtosService.types.wsdl
```

`MovimentarAtosService.wsdl` é o WSDL raiz (binding/operações); `MovimentarAtosService.types.wsdl`
é o WSDL importado com os `xsd:complexType` de verdade (`Ato`, `AtoSelado`, `CGenerica`, etc.) —
é o segundo arquivo que interessa pra entender os campos aceitos por `movimentarAtos`.

Isso existe porque `app/services/selo_digital/client.rb#ato_xml` foi construído por
engenharia reversa do PHP legado e só foi corrigido de fato lendo os erros de validação
que o próprio TJCE devolveu em produção (ver histórico de commits). Ter o XSD real evita
depender de tentativa e erro contra produção de novo.

## Achados relevantes

- O tipo usado hoje (`CGenerica`) é `Ato` → `AtoSelado` (+ `selo`) → `CGenerica`
  (+ `observacoes`, `partePessoa`).
- `Ato` tem um campo `sqAtoRetificado` (`xs:long`, opcional) — é assim que se retifica um
  ato já enviado: reenviar o mesmo `CGenerica`, preenchendo esse campo com o `sqAto` que o
  TJCE atribuiu ao ato original. Não é um tipo/endpoint separado. Ainda não implementado
  em `ato_xml`/`Lote.enviar_atos!` — ver colunas `retificacao`, `sqAto_idOriginal`,
  `sqAto_tj_retificacao` em `sd_atosPraticados`, que já existem mas não são lidas/escritas
  por este app.
- O mesmo serviço também expõe `consultaMovimentacao(idLote, idAto?)` — consulta status de
  um lote/ato direto no TJCE. Não usado ainda.
- Campos obrigatórios (`minOccurs` ausente, i.e. default 1) em `Ato`: `dataAtoSolicitacao`,
  `valorEmolumento`, `valorFermoju`, `valorEmolumentoLivre`, `numeroAtendimento` (string —
  preenchido com `numeroTalao`, não existe coluna `numeroAtendimento`), `tipoCobranca`,
  `tipoMovimentacao`, `responsavel`, `codigoAto`. `partePessoa` é obrigatório em `CGenerica`
  (`maxOccurs="unbounded"` sem `minOccurs="0"` — precisa de pelo meno um).

Esses WSDLs valem pra produção; homologação é um sistema TJCE separado (ver CLAUDE.md) e
pode ter uma versão diferente — não foi verificado.
