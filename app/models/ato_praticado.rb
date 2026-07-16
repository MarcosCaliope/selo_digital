class AtoPraticado < ApplicationRecord
  self.table_name = "sd_atosPraticados"

  # tipoDocumento numérico que o TJCE espera em <partePessoa><pessoa><documento>,
  # por tipo_doc de cbl_tit/cbl_dev. Só CGC e CPF têm mapeamento — outros valores
  # (PF, CI, GC — raros no legado) caem no placeholder genérico em parte_pessoa_titulo.
  TIPO_DOCUMENTO_POR_TIPO_DOC = { "CGC" => 1, "CPF" => 2 }.freeze

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

  # Quando stiposelagem = "D" o ato é de um título de protesto (cbl_tit,
  # protocolo = id_ato) em vez de um ato de cartório comum, e o TJCE espera o
  # nome/documento reais do devedor em <partePessoa> — não o placeholder
  # genérico usado para os demais atos (ver client.rb#ato_xml). cbl_tit não
  # guarda o nome do devedor diretamente; cbl_dev é a tabela mestre de
  # devedores, indexada por (tipo_doc, cpf_cgc).
  #
  # Retorna nil sempre que os dados reais não puderem ser montados com
  # confiança (não é um título "D", título não encontrado, sem devedor
  # correspondente, ou tipo_doc sem mapeamento em TIPO_DOCUMENTO_POR_TIPO_DOC)
  # — client.rb cai no placeholder genérico nesses casos em vez de falhar o envio.
  def parte_pessoa_titulo
    return nil unless stiposelagem == "D"

    titulo = CblTit.find_by(protocolo: id_ato.to_i.to_s)
    return nil unless titulo

    tipo_documento = TIPO_DOCUMENTO_POR_TIPO_DOC[titulo.tipo_doc]
    return nil unless tipo_documento

    devedor = CblDev.find_by(tipo_doc: titulo.tipo_doc, cpf_cgc: titulo.cpf_cgc)
    return nil unless devedor

    { nome: devedor.nome, tipo_documento: tipo_documento, numero_documento: titulo.cpf_cgc }
  end

  def minutos_pendente
    return nil unless data_registro

    ((Time.current - data_registro) / 60).round
  end
end
