class SelosController < ApplicationController
  def index
    empresa = Empresa.first
    raise SeloDigital::Error, "Nenhuma empresa cadastrada." if empresa.nil?

    @homologacao = empresa.homologacao

    raise SeloDigital::Error, "Certificado digital não cadastrado para #{empresa.snomeempresa}." if empresa.certificado_digital.blank?
    raise SeloDigital::Error, "Código da serventia não cadastrado para #{empresa.snomeempresa}." if empresa.codigo_serventia.blank?

    client = SeloDigital::Client.new(
      pfx_content:      Base64.decode64(empresa.certificado_digital),
      pfx_password:     empresa.senha_certificado_digital,
      codigo_serventia: empresa.codigo_serventia,
      homologacao:      empresa.homologacao,
      versao:           "1.12"
    )

    @resultado = client.consulta_selos_disponiveis
  rescue SeloDigital::Error, StandardError => e
    @erro = e.message
  end
end
