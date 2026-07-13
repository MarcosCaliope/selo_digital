class MovimentacaoController < ApplicationController
  def index
    @atos_pendentes = AtoPraticado.pendentes_de_envio.to_a
    @lotes = Lote.emitidos_hoje.to_a
    @tipos_selo = TipoSelo.com_estoque_local
    @solicitacoes = Solicitacao.pendentes.to_a
  end
end
