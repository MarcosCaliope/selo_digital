class Lote < ApplicationRecord
  self.table_name = "sd_lotes"

  scope :emitidos_hoje, -> { where("date(data_emissao) = date(now())").order(id: :desc) }
end
