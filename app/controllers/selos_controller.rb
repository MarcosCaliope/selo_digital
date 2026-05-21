class SelosController < ApplicationController
  def index
    client = SeloDigital::Client.new(
      pfx_path:         Rails.root.join("certs/1010426078.pfx").to_s,
      pfx_password:     "CBL2026",
      codigo_serventia: Rails.application.credentials.dig(:selo_digital, :codigo_serventia) ||
                        ENV.fetch("SELO_DIGITAL_SERVENTIA", "000401"),
      versao:           "2",
      ambiente:         1
    )

    @resultado = client.consulta_selos_disponiveis
  rescue SeloDigital::Error, StandardError => e
    @erro = e.message
  end
end
