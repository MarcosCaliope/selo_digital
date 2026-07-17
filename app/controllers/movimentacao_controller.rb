class MovimentacaoController < ApplicationController
  def index
    @atos_pendentes = AtoPraticado.pendentes_de_envio.to_a
    @atos_enviados = AtoPraticado.enviados.to_a
    @atos_rejeitados = AtoPraticado.rejeitados.includes(:ato_falha).to_a
    @lotes = Lote.emitidos_hoje.to_a
    @tipos_selo = TipoSelo.com_estoque_local
    @solicitacoes = Solicitacao.pendentes.to_a
  end

  def solicitar_selos
    tipo = TipoSelo.find_by!(codigo_tipo: params[:codigo_tipo])
    tipo.solicitar!(empresa!)
    redirect_to movimentacao_path, notice: "Solicitação de #{tipo.qte_pedido} selo(s) do Tipo #{tipo.codigo_tipo} enviada ao TJCE."
  rescue SeloDigital::Error, StandardError => e
    redirect_to movimentacao_path, alert: "Erro ao solicitar selos: #{e.message}"
  end

  def receber_selos
    solicitacao = Solicitacao.find(params[:id])
    quantidade = solicitacao.receber!(empresa!)
    redirect_to movimentacao_path, notice: "#{quantidade} selo(s) recebido(s) com sucesso."
  rescue SeloDigital::Error, StandardError => e
    redirect_to movimentacao_path, alert: "Erro ao receber selos: #{e.message}"
  end

  def enviar_atos
    atos = AtoPraticado.where(id: Array(params[:ato_ids])).to_a
    raise SeloDigital::Error, "Nenhum ato selecionado." if atos.empty?

    Lote.enviar_atos!(empresa!, atos)
    redirect_to movimentacao_path, notice: "Lote com #{atos.size} ato(s) enviado ao TJCE."
  rescue SeloDigital::Error, StandardError => e
    redirect_to movimentacao_path, alert: "Erro ao enviar atos: #{e.message}"
  end

  # Formulário único de retificação: campos do CGenerica (valores, datas) e
  # de <partePessoa> (nome, documento, endereço) juntos — ver
  # AtoPraticado#parte_pessoa_dados pra prioridade entre esse override manual,
  # dados reais automáticos por stiposelagem e o placeholder genérico. Quando
  # ainda não há RetificacaoParte salva, pré-preenche com o que sairia
  # automaticamente (se houver) como ponto de partida, sem persistir nada até
  # o usuário salvar. Reaproveitado também pra reeditar um ato que já está
  # pendente de retificação (ver link "Editar retificação" no painel de
  # pendentes) — AtoPraticado.find não filtra por status.
  def editar_retificacao
    @ato = AtoPraticado.find(params[:id])
    @parte = @ato.retificacao_parte || @ato.build_retificacao_parte
    if @parte.new_record? && (automatico = @ato.parte_pessoa_dados)
      @parte.assign_attributes(
        nome_pessoa: automatico[:nome],
        tipo_documento: automatico[:tipo_documento],
        numero_documento: automatico[:numero_documento]
      )
    end
  end

  def retificar
    ato = AtoPraticado.find(params[:id])
    parte = ato.retificacao_parte || ato.build_retificacao_parte
    ActiveRecord::Base.transaction do
      ato.marcar_para_retificacao!(retificacao_params)
      parte.update!(retificacao_parte_params)
    end
    redirect_to movimentacao_path, notice: "Ato #{ato.id} marcado para retificação — revise e envie na fila de atos pendentes."
  rescue ActiveRecord::RecordInvalid, StandardError => e
    redirect_to movimentacao_path, alert: "Erro ao marcar retificação: #{e.message}"
  end

  # Devolve um ato rejeitado (ver AtoPraticado.rejeitados) pra fila normal de
  # envio, pra reenviar via "Enviar selecionados ao TJCE" como qualquer outro
  # ato pendente.
  def reenviar_rejeitado
    ato = AtoPraticado.find(params[:id])
    ato.reenviar!
    redirect_to movimentacao_path, notice: "Ato #{ato.id} devolvido à fila de envio."
  rescue ActiveRecord::RecordInvalid, StandardError => e
    redirect_to movimentacao_path, alert: "Erro ao devolver ato à fila: #{e.message}"
  end

  private

  def retificacao_params
    params.require(:ato_praticado).permit(
      :codigo_ato, :valorEmolumento, :valorDocumento, :valorFermoju, :valorEmolumentoLivre,
      :numeroTalao, :tipoCobranca, :tipoMovimentacao, :quantidadeExtra,
      :dataAtoPraticado, :dataAtoSolicitacao
    )
  end

  def retificacao_parte_params
    params.require(:retificacao_parte).permit(
      :nome_pessoa, :tipo_documento, :numero_documento, :descricao_documento,
      :orgao_emissor, :data_emissao_documento, :descricao_logradouro,
      :numero_endereco, :bairro, :complemento, :cidade, :uf, :cep
    )
  end

  def empresa!
    Empresa.first || raise(SeloDigital::Error, "Nenhuma empresa cadastrada.")
  end
end
