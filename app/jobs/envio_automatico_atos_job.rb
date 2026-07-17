# Dispara automaticamente a fila de atos pendentes ao TJCE (o mesmo que o
# botão "Enviar selecionados ao TJCE" faz), quando Empresa#envio_automatico?
# está ligado (tblempresa.intervalo_envio_minutos > 0 — 0 é o padrão e
# significa envio manual, comportamento inalterado). Agendado via
# config/recurring.yml de minuto em minuto; usa o Lote mais recente como
# marcador de "último envio" (manual ou automático, tanto faz) em vez de uma
# coluna própria — se o intervalo configurado ainda não passou desde esse
# último Lote, não faz nada.
class EnvioAutomaticoAtosJob < ApplicationJob
  queue_as :default

  def perform
    empresa = Empresa.first
    return unless empresa&.envio_automatico?

    intervalo = empresa.intervalo_envio_minutos.minutes
    ultimo_lote = Lote.where.not(data_emissao: nil).order(data_emissao: :desc).first
    return if ultimo_lote && ultimo_lote.data_emissao > intervalo.ago

    atos = AtoPraticado.pendentes_de_envio.to_a
    return if atos.empty?

    Lote.enviar_atos!(empresa, atos)
  rescue SeloDigital::Error, StandardError => e
    Rails.logger.error("[EnvioAutomaticoAtosJob] Erro no envio automático: #{e.message}")
  end
end
