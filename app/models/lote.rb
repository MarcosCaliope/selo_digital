class Lote < ApplicationRecord
  self.table_name = "sd_lotes"

  scope :emitidos_hoje, -> { where("date(data_emissao) = date(now())").order(id: :desc) }

  # Submete os atos informados ao TJCE (movimentarAtos), consumindo o selo já
  # reservado localmente em cada um. O Lote precisa existir *antes* da chamada
  # porque seu id vai no envelope como <idLote> (obrigatório no XSD; replica o
  # que o PHP legado já fazia: insere o lote vazio, lê o id de volta, só então
  # monta e envia). <idLote> nunca era enviado aqui — o TJCE parece ter
  # tratado a ausência como um valor implícito fixo (0), que só aceita uma vez
  # por serventia; reenviar (mesmo lotes diferentes) batia em "O idLote já foi
  # enviado anteriormente por essa serventia" porque toda chamada repetia esse
  # mesmo valor implícito. Usar o id real do Lote garante um <idLote> novo a
  # cada tentativa.
  #
  # Se movimentar_atos levantar (rede, timeout, resposta inesperada, ou o
  # próprio erro de idLote duplicado), o Lote recém-criado é destruído e
  # nenhum ato é tocado — fica disponível em pendentes_de_envio para nova
  # tentativa, que vai criar outro Lote com outro id, em vez de ficar com lote
  # setado e status preso em "N", órfão e invisível na fila. Só entram no lote
  # os atos que de fato vieram na resposta do TJCE; os demais (se a resposta
  # vier incompleta) também continuam pendentes. Atos rejeitados pelo TJ
  # (statusFalha na resposta) recebem status "F" e não entram na contagem de
  # confirmados; sqAto_tj só é gravado para atos aceitos.
  def self.enviar_atos!(empresa, atos)
    return if atos.empty?

    lote = create!(data_emissao: Time.current)

    begin
      itens = empresa.selo_digital_client.movimentar_atos(atos: atos, id_lote: lote.id)
    rescue StandardError
      lote.destroy!
      raise
    end

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
