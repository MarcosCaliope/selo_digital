class Solicitacao < ApplicationRecord
  self.table_name = "sd_solicitacoes"

  scope :pendentes, -> { where(recebido: false).order(:id) }

  # Usa a chave desta solicitação para baixar do TJCE os números de série dos
  # selos, grava-os em sd_selos (status 'D' = disponível, data = hoje — mesmo
  # padrão das linhas legadas, que sempre preenchem data com a data do
  # recebimento) e marca como recebida. Retorna a quantidade de selos
  # efetivamente gravados.
  def receber!(empresa)
    resposta = empresa.selo_digital_client.receber_selos(chave: chave)

    if resposta[:selos].blank?
      raise SeloDigital::Error, resposta[:mensagem].presence || "TJCE não retornou selos para essa chave"
    end

    gravados = 0
    Selo.transaction do
      resposta[:selos].each do |s|
        next if Selo.exists?(numero_selo: s[:numero_serie], tipo_selo: s[:codigo_selo])

        Selo.create!(
          numero_selo: s[:numero_serie],
          id_sol: id,
          status: "D",
          validador: s[:validador],
          tipo_selo: s[:codigo_selo],
          data: Date.current
        )
        gravados += 1
      end
      update!(recebido: true)
    end

    gravados
  end
end
