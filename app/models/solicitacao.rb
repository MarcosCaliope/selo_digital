class Solicitacao < ApplicationRecord
  self.table_name = "sd_solicitacoes"

  scope :pendentes, -> { where(recebido: false).order(:id) }
end
