class AtoPraticado < ApplicationRecord
  self.table_name = "sd_atosPraticados"

  scope :pendentes_de_envio, -> {
    where(status: "N", lote: 0).where.not(tipo_selo: 99).order(:id).limit(50)
  }

  def selo
    "#{numero_selo&.strip}-#{validador&.strip}"
  end

  def minutos_pendente
    return nil unless data_registro

    ((Time.current - data_registro) / 60).round
  end
end
