class AtoPraticado < ApplicationRecord
  self.table_name = "sd_atosPraticados"

  # Dados de partePessoa editados manualmente pra retificação (nome,
  # documento, endereço) — ver RetificacaoParte e #parte_pessoa_dados abaixo.
  # Tabela própria deste app, não faz parte do schema legado de
  # sd_atosPraticados.
  has_one :retificacao_parte, inverse_of: :ato_praticado

  # Última rejeição do TJCE em movimentar_atos, se houver — ver AtoFalha e
  # #rejeitados abaixo. Também tabela própria deste app.
  has_one :ato_falha, inverse_of: :ato_praticado

  # tipoDocumento numérico que o TJCE espera em <partePessoa><pessoa><documento>.
  TIPO_DOCUMENTO_CNPJ = 1
  TIPO_DOCUMENTO_CPF = 2

  # Mapa de tipo_doc (cbl_tit/cbl_dev) pro tipoDocumento numérico acima. Só CGC
  # e CPF têm mapeamento — outros valores (PF, CI, GC — raros no legado) caem
  # no placeholder genérico em parte_pessoa_titulo.
  TIPO_DOCUMENTO_POR_TIPO_DOC = { "CGC" => TIPO_DOCUMENTO_CNPJ, "CPF" => TIPO_DOCUMENTO_CPF }.freeze

  # Pra campos legados que guardam CPF ou CNPJ juntos sem uma coluna de tipo
  # separada (tblcontcertidoes.scpfcnpj, bd_escr.cpfcgc_n): tipo inferido pela
  # contagem de dígitos — 11 = CPF, 14 = CNPJ, convenção padrão nesse caso.
  TIPO_DOCUMENTO_POR_QTD_DIGITOS = { 11 => TIPO_DOCUMENTO_CPF, 14 => TIPO_DOCUMENTO_CNPJ }.freeze

  scope :pendentes_de_envio, -> {
    where(status: "N", lote: 0).where.not(tipo_selo: 99).order(:id).limit(50)
  }

  # Atos já confirmados pelo TJCE (status "E") com sqAto_tj real, candidatos a
  # retificação — ver #marcar_para_retificacao!. A maioria das linhas com
  # status "E" no legado é histórica, de antes de sqAto_tj/data_retorno_tj
  # existirem (sem os dois preenchidos, não há sqAto pra referenciar em
  # <sqAtoRetificado>) — por isso o filtro. NULLS LAST porque o Postgres
  # ordena NULL primeiro em DESC por padrão, o que colocaria essas linhas
  # históricas na frente das enviadas de verdade por este app. Uma vez
  # marcado, o ato volta a status "N" e some desta lista até ser reenviado
  # (voltando pra "E"/"F"). Painel mostra só os 10 mais recentes por padrão;
  # `busca:` filtra pelo número do selo (ver #selo) antes de aplicar o limite,
  # pra achar um enviado mais antigo sem precisar aumentar o limite. numero_selo
  # e validador são colunas de largura fixa no legado (cheias de espaço à
  # direita) — TRIM nos dois lados do ILIKE cobre buscar com ou sem o "-".
  scope :enviados, ->(busca: nil) {
    relation = where(status: "E").where.not(sqAto_tj: [ nil, "" ])
    if busca.present?
      relation = relation.where(
        "TRIM(numero_selo) || '-' || TRIM(validador) ILIKE ?", "%#{busca.strip}%"
      )
    end
    relation.order(Arel.sql("data_retorno_tj DESC NULLS LAST")).limit(10)
  }

  # Atos rejeitados pelo TJCE em movimentar_atos (status "F", ver
  # Lote.enviar_atos!) — o join com ato_falhas garante que só aparecem aqui
  # atos rejeitados por *este app* (a tabela só é escrita ali), não qualquer
  # uso histórico de "F" que porventura exista no legado. Saem desta lista
  # assim que reenviados (status volta a "N" em #reenviar!, ver abaixo) —
  # nada aqui apaga o histórico em ato_falhas, só o registro mais recente é
  # exibido.
  scope :rejeitados, -> {
    joins(:ato_falha).where(status: "F")
      .order(Arel.sql("ato_falhas.ocorrida_em DESC"))
      .limit(50)
  }

  def selo
    "#{numero_selo&.strip}-#{validador&.strip}"
  end

  # retificacao é "1" (nunca outro valor além de nil hoje) quando este ato
  # corrige um ato já enviado ao TJCE; sqAto_idOriginal guarda o sqAto (não
  # o id local) do ato original, no formato que o TJCE espera de volta em
  # <sqAtoRetificado>.
  def retificacao?
    retificacao == 1
  end

  # Marca este ato (já confirmado pelo TJCE, status "E") como uma retificação
  # a ser reenviada: aplica os campos corrigidos, referencia o sqAto original
  # (o mais recente conhecido — sqAto_tj_retificacao se este já for uma
  # correção de uma correção anterior, senão sqAto_tj) em sqAto_idOriginal, e
  # devolve o ato pra fila normal de envio (status "N", lote 0) — dali em
  # diante segue o fluxo comum de pendentes_de_envio/Lote.enviar_atos!, que já
  # sabe gravar o retorno do TJ nas colunas *_retificacao em vez de sobrescrever
  # sqAto_tj/statusAtoTJ originais (ver Lote.enviar_atos!).
  def marcar_para_retificacao!(campos)
    assign_attributes(campos)
    self.retificacao = 1
    self.sqAto_idOriginal = sqAto_tj_retificacao.presence || sqAto_tj
    self.status = "N"
    self.lote = 0
    save!
  end

  # Devolve um ato rejeitado (status "F", ver .rejeitados) pra fila normal de
  # envio, sem tocar em mais nada — se era uma retificação, continua sendo
  # (retificacao/sqAto_idOriginal preservados), então o próximo envio ainda
  # referencia o sqAto certo em <sqAtoRetificado>. O histórico em ato_falha
  # não é apagado aqui; Lote.enviar_atos! atualiza (nova rejeição) ou remove
  # (sucesso) no próximo envio.
  def reenviar!
    update!(status: "N", lote: 0)
  end

  # nomePessoa/documento/endereço para <partePessoa> (ver client.rb#ato_xml).
  # Prioridade: 1) retificacao_parte preenchida manualmente pelo usuário na
  # tela de retificação (sobrepõe tudo, é intencional); 2) dados reais
  # automáticos quando stiposelagem indica que este ato não é um ato de
  # cartório comum e tem uma parte real identificável fora de
  # sd_atosPraticados — hoje "D" (título de protesto), "C" (certidão), "E"
  # (escritura) e "T" (testamento); 3) nil, e client.rb usa o placeholder
  # genérico de sempre (stiposelagem em branco ou sem tratamento aqui).
  def parte_pessoa_dados
    return retificacao_parte.parte_pessoa_dados if retificacao_parte&.preenchida?

    case stiposelagem
    when "D" then parte_pessoa_titulo
    when "C" then parte_pessoa_certidao
    when "E" then parte_pessoa_escritura
    when "T" then parte_pessoa_testamento
    end
  end

  def minutos_pendente
    return nil unless data_registro

    ((Time.current - data_registro) / 60).round
  end

  private

  # stiposelagem "D": título de protesto (cbl_tit, protocolo = id_ato) — TJCE
  # espera o nome/documento reais do devedor, não o placeholder. cbl_tit não
  # guarda o nome do devedor diretamente; cbl_dev é a tabela mestre de
  # devedores, indexada por (tipo_doc, cpf_cgc).
  #
  # Retorna nil sempre que os dados reais não puderem ser montados com
  # confiança (título não encontrado, sem devedor correspondente, ou tipo_doc
  # sem mapeamento em TIPO_DOCUMENTO_POR_TIPO_DOC) — parte_pessoa_dados cai no
  # placeholder genérico nesses casos em vez de falhar o envio.
  def parte_pessoa_titulo
    titulo = CblTit.find_by(protocolo: id_ato.to_i.to_s)
    return nil unless titulo

    tipo_documento = TIPO_DOCUMENTO_POR_TIPO_DOC[titulo.tipo_doc]
    return nil unless tipo_documento

    devedor = CblDev.find_by(tipo_doc: titulo.tipo_doc, cpf_cgc: titulo.cpf_cgc)
    return nil unless devedor

    { nome: devedor.nome, tipo_documento: tipo_documento, numero_documento: titulo.cpf_cgc }
  end

  # stiposelagem "C": certidão (tblcontcertidoes, icodigo = id_ato) — nome vem
  # de snome, documento de scpfcnpj (formato sujo mas já geralmente só
  # dígitos, ex.: "Não Apresentou" quando ausente). Ver
  # tipo_e_numero_documento_por_digitos abaixo pra como o tipo é inferido.
  def parte_pessoa_certidao
    certidao = TblContCertidoes.find_by(icodigo: id_ato.to_i)
    return nil unless certidao

    documento = tipo_e_numero_documento_por_digitos(certidao.scpfcnpj)
    return nil unless documento

    { nome: certidao.snome }.merge(documento)
  end

  # stiposelagem "E": escritura (bd_escr, id = id_ato) — nome vem de gant1
  # ("outorgante"), documento de cpfcgc_n. Formatado com pontuação
  # (".", "-", "/") ao contrário de tblcontcertidoes.scpfcnpj, mas
  # tipo_e_numero_documento_por_digitos já limpa isso.
  def parte_pessoa_escritura
    escritura = BdEscr.find_by(id: id_ato.to_i)
    return nil unless escritura

    documento = tipo_e_numero_documento_por_digitos(escritura.cpfcgc_n)
    return nil unless documento

    { nome: escritura.gant1 }.merge(documento)
  end

  # stiposelagem "T": testamento (bd_test, id = id_ato) — nome vem de
  # testador, documento de qualifica1. Ao contrário de "C"/"E", só mapeia CPF
  # (não reusa tipo_e_numero_documento_por_digitos, que também aceita 14
  # dígitos como CNPJ): testador é sempre pessoa física, CNPJ não faz sentido
  # aqui. qualifica1 é campo de "qualificação" livre no legado — a maioria é
  # CPF formatado, mas várias linhas antigas têm RG em vez de CPF (ex.: "RG Nº
  # 330.559-SSP-CE") ou estão em branco/sujas ("***"); qualquer coisa que não
  # resulte em exatamente 11 dígitos cai no placeholder.
  def parte_pessoa_testamento
    testamento = BdTest.find_by(id: id_ato.to_i)
    return nil unless testamento

    numero_documento = testamento.qualifica1.to_s.gsub(/\D/, "")
    return nil unless numero_documento.length == 11

    { nome: testamento.testador, tipo_documento: TIPO_DOCUMENTO_CPF, numero_documento: numero_documento }
  end

  # Campos legados tipo scpfcnpj/cpfcgc_n guardam CPF ou CNPJ no mesmo campo,
  # às vezes formatado (pontos/traço/barra), às vezes sujo (texto livre tipo
  # "Não Apresentou", ou dois documentos concatenados pra titularidade
  # conjunta). Só confia no valor quando, depois de tirar tudo que não é
  # dígito, sobra exatamente 11 (CPF) ou 14 (CNPJ) dígitos — qualquer outra
  # contagem retorna nil em vez de arriscar mandar um tipoDocumento errado.
  def tipo_e_numero_documento_por_digitos(documento_bruto)
    numero_documento = documento_bruto.to_s.gsub(/\D/, "")
    tipo_documento = TIPO_DOCUMENTO_POR_QTD_DIGITOS[numero_documento.length]
    return nil unless tipo_documento

    { tipo_documento: tipo_documento, numero_documento: numero_documento }
  end
end
