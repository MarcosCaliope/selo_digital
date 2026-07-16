class AtoPraticado < ApplicationRecord
  self.table_name = "sd_atosPraticados"

  # tipoDocumento numérico que o TJCE espera em <partePessoa><pessoa><documento>.
  TIPO_DOCUMENTO_CNPJ = 1
  TIPO_DOCUMENTO_CPF = 2

  # Mapa de tipo_doc (cbl_tit/cbl_dev) pro tipoDocumento numérico acima. Só CGC
  # e CPF têm mapeamento — outros valores (PF, CI, GC — raros no legado) caem
  # no placeholder genérico em parte_pessoa_titulo.
  TIPO_DOCUMENTO_POR_TIPO_DOC = { "CGC" => TIPO_DOCUMENTO_CNPJ, "CPF" => TIPO_DOCUMENTO_CPF }.freeze

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
  # (título de protesto) e "C" (certidão). Nos demais casos (stiposelagem em
  # branco, ou qualquer valor sem tratamento aqui) retorna nil e client.rb usa
  # o placeholder genérico de sempre.
  def parte_pessoa_dados
    case stiposelagem
    when "D" then parte_pessoa_titulo
    when "C" then parte_pessoa_certidao
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
  # de snome, documento de scpfcnpj. Diferente de cbl_tit/cbl_dev,
  # tblcontcertidoes não tem uma coluna de tipo de documento separada (scpfcnpj
  # guarda CPF ou CNPJ no mesmo campo), então o tipo é inferido pela contagem
  # de dígitos (CPF tem 11, CNPJ tem 14 — regra padrão pra esse tipo de campo
  # combinado no Brasil). scpfcnpj tem valores sujos no legado (ex.: "Não
  # Apresentou", ou números sem zeros à esquerda) — nesses casos, ou em
  # qualquer contagem de dígitos que não seja 11 nem 14, retorna nil em vez de
  # arriscar mandar um tipoDocumento errado.
  def parte_pessoa_certidao
    certidao = TblContCertidoes.find_by(icodigo: id_ato.to_i)
    return nil unless certidao

    documento = certidao.scpfcnpj.to_s
    return nil unless documento.match?(/\A\d+\z/)

    tipo_documento = { 11 => TIPO_DOCUMENTO_CPF, 14 => TIPO_DOCUMENTO_CNPJ }[documento.length]
    return nil unless tipo_documento

    { nome: certidao.snome, tipo_documento: tipo_documento, numero_documento: documento }
  end
end
