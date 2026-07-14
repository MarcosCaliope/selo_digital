class Lote < ApplicationRecord
  self.table_name = "sd_lotes"

  scope :emitidos_hoje, -> { where("date(data_emissao) = date(now())").order(id: :desc) }

  # Submete os atos informados ao TJCE (movimentarAtos), consumindo o selo já
  # reservado localmente em cada um. Cria o lote, reserva os atos nele, envia,
  # e atualiza cada ato + o próprio lote conforme a resposta do TJCE.
  def self.enviar_atos!(empresa, atos)
    return if atos.empty?

    lote = create!(data_emissao: Time.current)
    AtoPraticado.where(id: atos.map(&:id)).update_all(lote: lote.id)

    itens = empresa.selo_digital_client.movimentar_atos(atos: atos)

    confirmados = 0
    itens.each do |item|
      ato = atos.find { |a| a.id == item[:id_ato] }
      next unless ato

      ato.update!(
        data_retorno_tj: Time.current,
        status: "E",
        data_atualizacao_tj: Time.current,
        sqAto_tj: item[:sq_ato_tj],
        statusAtoTJ: item[:status_ato_tj]
      )
      confirmados += 1
    end

    lote.update!(
      tipo_selo: atos.first&.tipo_selo,
      qte_titulos: confirmados,
      titulos: atos.map(&:id).join(","),
      data_resposta: Time.current,
      resposta: confirmados.to_s,
      observacoes: "Qte titulos retornados #{confirmados}"
    )

    lote
  end
end
