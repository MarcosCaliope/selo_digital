class RetificacaoParte < ApplicationRecord
  belongs_to :ato_praticado, inverse_of: :retificacao_parte

  # nome_pessoa é o único campo obrigatório pra essa retificação contar como
  # "preenchida" e sobrepor o fluxo automático/placeholder de
  # AtoPraticado#parte_pessoa_dados — os demais (documento, endereço) têm
  # equivalente minOccurs="0" no XSD, ver client.rb#ato_xml pros defaults
  # quando ficam em branco.
  def preenchida?
    nome_pessoa.present?
  end

  # Mesmo formato de hash que AtoPraticado#parte_pessoa_titulo/certidao/etc
  # retornam, só que com as chaves extras (documento/endereço) que os
  # branches automáticos nunca preenchem — client.rb#ato_xml trata chaves
  # ausentes/em branco com o mesmo placeholder de sempre.
  def parte_pessoa_dados
    {
      nome: nome_pessoa,
      tipo_documento: tipo_documento,
      numero_documento: numero_documento,
      descricao_documento: descricao_documento,
      orgao_emissor: orgao_emissor,
      data_emissao_documento: data_emissao_documento,
      descricao_logradouro: descricao_logradouro,
      numero_endereco: numero_endereco,
      bairro: bairro,
      complemento: complemento,
      cidade: cidade,
      uf: uf,
      cep: cep
    }
  end
end
