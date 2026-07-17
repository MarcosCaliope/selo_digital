class AtoFalha < ApplicationRecord
  belongs_to :ato_praticado, inverse_of: :ato_falha
end
