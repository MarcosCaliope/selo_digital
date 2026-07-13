class AddCertificadoDigitalToTblempresa < ActiveRecord::Migration[8.0]
  def change
    add_column :tblempresa, :certificado_digital, :text
    add_column :tblempresa, :senha_certificado_digital, :text
  end
end
