class TipoSelo < ApplicationRecord
  self.table_name = "sd_tipos_selos"

  # "valid" colide com ActiveRecord::Validations#valid? — não usamos essa coluna.
  self.ignored_columns = [ "valid" ]

  # Estoque local = selos já recebidos do TJCE (status 'D' = disponível) e ainda não usados.
  # Diferente do saldo remoto mostrado em /selos, que vem direto do webservice do TJCE.
  def self.com_estoque_local
    find_by_sql(<<~SQL.squish)
      SELECT sd_tipos_selos.*,
             (SELECT COUNT(*) FROM sd_selos
              WHERE sd_selos.status = 'D'
                AND sd_selos.tipo_selo = CAST(sd_tipos_selos.codigo_tipo AS integer)) AS estoque_atual
      FROM sd_tipos_selos
      ORDER BY codigo_tipo
    SQL
  end

  # Quantidade de selos deste tipo já baixados do TJCE e ainda não usados.
  # Usa o valor já carregado por com_estoque_local quando disponível; caso
  # contrário (ex: registro carregado por find_by! fora do dashboard), calcula
  # na hora — abaixo_do_minimo?/solicitar! precisam funcionar nos dois casos.
  def estoque_local
    return estoque_atual.to_i if has_attribute?(:estoque_atual)

    Selo.where(status: "D", tipo_selo: codigo_tipo.to_i).count
  end

  def abaixo_do_minimo?
    estoque_local < estoque_min.to_i
  end

  # Solicita ao TJCE a quantidade configurada (qte_pedido) deste tipo de selo.
  #
  # Só permite solicitar quando o estoque local está abaixo do mínimo configurado
  # — não é pra pedir selo "à toa", só quando realmente falta. Ver
  # #solicitar_quantidade! pro pedido manual, sem esse guard.
  def solicitar!(empresa)
    unless abaixo_do_minimo?
      raise SeloDigital::Error, "Estoque local do Tipo #{codigo_tipo} (#{estoque_local}) não está abaixo do mínimo (#{estoque_min})."
    end

    solicitar_quantidade!(empresa, qte_pedido)
  end

  # Solicita ao TJCE uma quantidade escolhida manualmente pelo operador, sem o
  # guard de estoque mínimo de #solicitar! — usado pelo formulário de
  # solicitação manual no dashboard, pra quando o operador quer pedir selo por
  # antecipação, não só quando o estoque já caiu abaixo do mínimo configurado.
  # Grava a solicitação localmente com a chave retornada; receber_selos! (em
  # Solicitacao) é o próximo passo para efetivamente baixar os números de série.
  #
  # A Solicitacao é criada (sem chave) antes de chamar o TJCE para que o id
  # enviado como idSolicitacaoSelo seja o id real atribuído pelo Postgres —
  # calcular via Solicitacao.maximum(:id) + 1 diverge sempre que a sequence tiver
  # algum gap (rollback, insert falho, linha deletada), o que é comum em produção.
  def solicitar_quantidade!(empresa, quantidade)
    quantidade = quantidade.to_i
    raise SeloDigital::Error, "Quantidade precisa ser maior que zero." unless quantidade.positive?

    solicitacao = Solicitacao.create!(
      data: Date.current,
      quantidade: quantidade,
      recebido: false,
      codigo_tipo: codigo_tipo,
      estado: 0
    )

    resposta = empresa.selo_digital_client.solicita_selos(
      codigo_tipo_selo: codigo_tipo,
      quantidade: quantidade,
      id_solicitacao: solicitacao.id
    )

    if resposta[:chave].blank?
      solicitacao.destroy!
      raise SeloDigital::Error, resposta[:mensagem].presence || "TJCE não retornou uma chave de solicitação"
    end

    solicitacao.update!(chave: resposta[:chave])
    solicitacao
  end
end
