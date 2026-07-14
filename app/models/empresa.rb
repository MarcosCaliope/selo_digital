class Empresa < ApplicationRecord
  self.table_name = "tblempresa"

  encrypts :certificado_digital
  encrypts :senha_certificado_digital

  attr_accessor :certificado_digital_upload

  before_validation :ler_certificado_digital_upload

  validates :snomeempresa, presence: true

  # Monta o client SOAP configurado com o certificado, senha, código da serventia
  # e ambiente (homologação/produção) já cadastrados. O CPF/nome/telefone/e-mail do
  # responsável são usados como "informante"/"solicitante" nas operações de escrita
  # (solicita_selos, movimentar_atos) — não fazem diferença em consulta_selos_disponiveis
  # nem receber_selos.
  def selo_digital_client
    ddd, telefone = telefone_ddd_numero(sfone1)

    SeloDigital::Client.new(
      codigo_serventia: codigo_serventia,
      pfx_content: Base64.decode64(certificado_digital),
      pfx_password: senha_certificado_digital,
      homologacao: homologacao,
      informante_cpf: snocpfresponsavel,
      solicitante_nome: snomeresponsavel,
      solicitante_ddd: ddd,
      solicitante_telefone: telefone,
      solicitante_email: semail
    )
  end

  private

  def telefone_ddd_numero(telefone)
    digitos = telefone.to_s.gsub(/\D/, "")
    [ digitos[0, 2], digitos[2..] ]
  end

  def ler_certificado_digital_upload
    return if certificado_digital_upload.blank?

    self.certificado_digital = Base64.strict_encode64(certificado_digital_upload.read)
  end
end
