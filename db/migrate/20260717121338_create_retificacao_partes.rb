class CreateRetificacaoPartes < ActiveRecord::Migration[8.0]
  def change
    # Tabela nova, própria deste app — não altera sd_atosPraticados (schema
    # legado, gerenciado pelo Delphi/PHP, ver CLAUDE.md). ato_praticado_id
    # aponta pro id de sd_atosPraticados sem FK de banco (tabela legada, fora
    # do controle de migrations deste app).
    create_table :retificacao_partes do |t|
      t.bigint :ato_praticado_id, null: false
      t.string :nome_pessoa
      t.integer :tipo_documento
      t.string :numero_documento
      t.string :descricao_documento
      t.string :orgao_emissor
      t.date :data_emissao_documento
      t.string :descricao_logradouro
      t.string :numero_endereco
      t.string :bairro
      t.string :complemento
      t.integer :cidade
      t.string :uf
      t.string :cep

      t.timestamps
    end
    add_index :retificacao_partes, :ato_praticado_id, unique: true
  end
end
