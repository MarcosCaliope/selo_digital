class Lote < ApplicationRecord
  self.table_name = "sd_lotes"

  scope :emitidos_hoje, -> { where("date(data_emissao) = date(now())").order(id: :desc) }

  # Submete os atos informados ao TJCE (movimentarAtos), consumindo o selo já
  # reservado localmente em cada um. Chama o TJCE primeiro e só então grava
  # qualquer coisa no banco: se movimentar_atos levantar (rede, timeout,
  # resposta inesperada), nenhum ato é tocado e continua disponível em
  # pendentes_de_envio para nova tentativa — em vez de ficar com lote setado
  # e status preso em "N", órfão e invisível na fila. Só entram no lote os
  # atos que de fato vieram na resposta do TJCE; os demais (se a resposta
  # vier incompleta) também continuam pendentes. Atos rejeitados pelo TJ
  # (statusFalha na resposta) recebem status "F" e não entram na contagem de
  # confirmados; sqAto_tj só é gravado para atos aceitos.
  def self.enviar_atos!(empresa, atos)
    return if atos.empty?

    itens = empresa.selo_digital_client.movimentar_atos(atos: atos)

    lote = create!(data_emissao: Time.current)

    confirmados = 0
    processados = []
    itens.each do |item|
      ato = atos.find { |a| a.id == item[:id_ato] }
      next unless ato

      if item[:falha]
        Rails.logger.warn("[SeloDigital] movimentarAtos falhou para ato #{ato.id}: status=#{item[:status_ato_tj]} codigo=#{item[:codigo_falha]}")
      end

      ato.update!(
        lote: lote.id,
        data_retorno_tj: Time.current,
        status: item[:falha] ? "F" : "E",
        data_atualizacao_tj: Time.current,
        sqAto_tj: item[:sq_ato_tj],
        statusAtoTJ: item[:status_ato_tj]
      )
      processados << ato
      confirmados += 1 unless item[:falha]
    end

    lote.update!(
      tipo_selo: processados.first&.tipo_selo,
      qte_titulos: confirmados,
      titulos: processados.map(&:id).join(","),
      data_resposta: Time.current,
      resposta: confirmados.to_s,
      observacoes: "Qte titulos retornados #{confirmados}"
    )

    lote
  end
end
