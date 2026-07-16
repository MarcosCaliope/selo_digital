class AtoPraticado < ApplicationRecord
  self.table_name = "sd_atosPraticados"

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

  # nomePessoa/documento reais para <partePessoa> (ver client.rb#ato_xml), quando
  # stiposelagem indica que este ato não é um ato de cartório comum e por isso
  # tem uma parte real identificável fora de sd_atosPraticados — hoje "D"
  # (título de protesto), "C" (certidão), "E" (escritura) e "T" (testamento).
  # Nos demais casos (stiposelagem em branco, ou qualquer valor sem tratamento
  # aqui) retorna nil e client.rb usa o placeholder genérico de sempre.
  def parte_pessoa_dados
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
  #
  # cpfcgc_n guarda o documento da 1ª e 2ª pessoa (gant1/gant2, os
  # outorgantes — concatenados quando há dois, daí o caso de 22 dígitos
  # citado acima); cpfcgc_d guarda o documento da 3ª pessoa (gado1, o
  # outorgado). Só a 1ª pessoa (gant1/cpfcgc_n) é usada aqui hoje — o XSD do
  # TJCE só aceita uma <pessoa> por ato, então gant2/gado1/cpfcgc_d não têm
  # como ser enviados de qualquer forma.
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
