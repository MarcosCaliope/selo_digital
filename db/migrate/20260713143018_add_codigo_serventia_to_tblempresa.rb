class AddCodigoServentiaToTblempresa < ActiveRecord::Migration[8.0]
  def change
    add_column :tblempresa, :codigo_serventia, :string
  end
end
