class TipoSelo < ApplicationRecord
  self.table_name = "sd_tipos_selos"

  # "valid" colide com ActiveRecord::Validations#valid? — não usamos essa coluna.
  self.ignored_columns = [ "valid" ]

  # Estoque local = selos já recebidos do TJCE (status 'D' = disponível) e ainda não usados.
  # Diferente do saldo remoto mostrado em /selos, que vem direto do webservice do TJCE.
  def self.com_estoque_local
    find_by_sql(<<~SQL.squish)
      SELECT sd_tipos_selos.*,
             (SELECT COUNT(*) FROM sd_selos
              WHERE sd_selos.status = 'D'
                AND sd_selos.tipo_selo = CAST(sd_tipos_selos.codigo_tipo AS integer)) AS estoque_atual
      FROM sd_tipos_selos
      ORDER BY codigo_tipo
    SQL
  end

  # Quantidade de selos deste tipo já baixados do TJCE e ainda não usados.
  # Usa o valor já carregado por com_estoque_local quando disponível; caso
  # contrário (ex: registro carregado por find_by! fora do dashboard), calcula
  # na hora — abaixo_do_minimo?/solicitar! precisam funcionar nos dois casos.
  def estoque_local
    return estoque_atual.to_i if has_attribute?(:estoque_atual)

    Selo.where(status: "D", tipo_selo: codigo_tipo.to_i).count
  end

  def abaixo_do_minimo?
    estoque_local < estoque_min.to_i
  end

  # Solicita ao TJCE a quantidade configurada (qte_pedido) deste tipo de selo.
  # Grava a solicitação localmente com a chave retornada; receber_selos! (em
  # Solicitacao) é o próximo passo para efetivamente baixar os números de série.
  #
  # Só permite solicitar quando o estoque local está abaixo do mínimo configurado
  # — não é pra pedir selo "à toa", só quando realmente falta.
  def solicitar!(empresa)
    unless abaixo_do_minimo?
      raise SeloDigital::Error, "Estoque local do Tipo #{codigo_tipo} (#{estoque_local}) não está abaixo do mínimo (#{estoque_min})."
    end

    id_solicitacao = (Solicitacao.maximum(:id) || 0) + 1

    resposta = empresa.selo_digital_client.solicita_selos(
      codigo_tipo_selo: codigo_tipo,
      quantidade: qte_pedido,
      id_solicitacao: id_solicitacao
    )

    if resposta[:chave].blank?
      raise SeloDigital::Error, resposta[:mensagem].presence || "TJCE não retornou uma chave de solicitação"
    end

    Solicitacao.create!(
      data: Date.current,
      quantidade: qte_pedido,
      chave: resposta[:chave],
      recebido: false,
      codigo_tipo: codigo_tipo,
      estado: 0
    )
  end
end
