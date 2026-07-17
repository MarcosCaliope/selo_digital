class CreateAtoFalhas < ActiveRecord::Migration[8.0]
  def change
    # Tabela nova, própria deste app — mesmo raciocínio de retificacao_partes
    # (ver 20260717121338): não altera sd_atosPraticados, sem FK de banco pro
    # id da tabela legada. Guarda a última rejeição do TJCE (movimentar_atos)
    # pra cada ato — hoje isso só existia em Rails.logger.warn e nos arquivos
    # crus em log/soap/, invisível no dashboard.
    create_table :ato_falhas do |t|
      t.bigint :ato_praticado_id, null: false
      t.string :codigo
      t.string :mensagem
      t.string :status_ato_tj
      t.datetime :ocorrida_em

      t.timestamps
    end
    add_index :ato_falhas, :ato_praticado_id, unique: true
  end
end
