class SelosController < ApplicationController
  def index
    creds = Rails.application.credentials.selo_digital!

    client = SeloDigital::Client.new(
      pfx_path:         Rails.root.join(creds[:pfx_path]).to_s,
      pfx_password:     creds[:pfx_password],
      codigo_serventia: creds[:codigo_serventia],
      versao:           "1.12"
    )

    @resultado = client.consulta_selos_disponiveis
  rescue SeloDigital::Error, StandardError => e
    @erro = e.message
  end
end
