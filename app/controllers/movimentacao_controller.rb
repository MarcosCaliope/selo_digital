class MovimentacaoController < ApplicationController
  def index
    @atos_pendentes = AtoPraticado.pendentes_de_envio.to_a
    @atos_enviados = AtoPraticado.enviados.to_a
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

  def editar_retificacao
    @ato = AtoPraticado.find(params[:id])
  end

  def retificar
    ato = AtoPraticado.find(params[:id])
    ato.marcar_para_retificacao!(retificacao_params)
    redirect_to movimentacao_path, notice: "Ato #{ato.id} marcado para retificação — revise e envie na fila de atos pendentes."
  rescue ActiveRecord::RecordInvalid, StandardError => e
    redirect_to movimentacao_path, alert: "Erro ao marcar retificação: #{e.message}"
  end

  private

  def retificacao_params
    params.require(:ato_praticado).permit(
      :codigo_ato, :valorEmolumento, :valorDocumento, :valorFermoju, :valorEmolumentoLivre,
      :numeroTalao, :tipoCobranca, :tipoMovimentacao, :quantidadeExtra,
      :dataAtoPraticado, :dataAtoSolicitacao
    )
  end

  def empresa!
    Empresa.first || raise(SeloDigital::Error, "Nenhuma empresa cadastrada.")
  end
end
