class Empresa < ApplicationRecord
  self.table_name = "tblempresa"

  encrypts :certificado_digital
  encrypts :senha_certificado_digital

  attr_accessor :certificado_digital_upload

  before_validation :ler_certificado_digital_upload

  validates :snomeempresa, presence: true

  private

  def ler_certificado_digital_upload
    return if certificado_digital_upload.blank?

    self.certificado_digital = Base64.strict_encode64(certificado_digital_upload.read)
  end
end
