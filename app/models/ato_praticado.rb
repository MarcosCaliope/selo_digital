class AtoPraticado < ApplicationRecord
  self.table_name = "sd_atosPraticados"

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

  def minutos_pendente
    return nil unless data_registro

    ((Time.current - data_registro) / 60).round
  end
end
