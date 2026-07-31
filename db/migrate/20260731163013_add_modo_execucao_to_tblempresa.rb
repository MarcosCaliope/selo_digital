class AddModoExecucaoToTblempresa < ActiveRecord::Migration[8.0]
  def change
    # "web" (padrão) = processada pela instância no Render; "local" = por uma
    # instância rodando na rede do próprio cartório (ver
    # Empresa.para_esta_instancia / variável de ambiente APP_MODO_EXECUCAO).
    add_column :tblempresa, :modo_execucao, :string, default: "web", null: false
  end
end
