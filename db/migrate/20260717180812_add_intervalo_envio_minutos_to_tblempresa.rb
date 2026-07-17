class AddIntervaloEnvioMinutosToTblempresa < ActiveRecord::Migration[8.0]
  def change
    # 0 (padrão) = envio manual, como sempre foi; >0 = minutos entre envios
    # automáticos de atos pendentes (ver EnvioAutomaticoAtosJob).
    add_column :tblempresa, :intervalo_envio_minutos, :integer, default: 0, null: false
  end
end
