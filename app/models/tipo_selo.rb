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

  def abaixo_do_minimo?
    estoque_atual.to_i < estoque_min.to_i
  end
end
