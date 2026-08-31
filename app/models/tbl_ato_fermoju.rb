class TblAtoFermoju < ApplicationRecord
  self.table_name = "tblatosfermoju"

  # Sem coluna "id" (nem outra candidata a chave única óbvia) nesta tabela
  # legada — só usada aqui pra where/pluck (ver AtoPraticado#stiposelagem),
  # nunca find/save.
  self.primary_key = false
end
