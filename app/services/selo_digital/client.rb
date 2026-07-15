require "net/https"
require "openssl"

module SeloDigital
  class Client
    ENDPOINT_HOMOLOGACAO = "https://homologacao-selodigital.tjce.jus.br/wsselodigital-homologacao/SelosDisponiveis"
    ENDPOINT_PRODUCAO    = "https://selodigital.tjce.jus.br/wsselodigital/SelosDisponiveis"

    ENDPOINT_SOLICITACAO_HOMOLOGACAO  = "https://homologacao-selodigital.tjce.jus.br/wsselodigital-homologacao/SolicitacaoSelo"
    ENDPOINT_SOLICITACAO_PRODUCAO     = "https://selodigital.tjce.jus.br/wsselodigital/SolicitacaoSelo"
    ENDPOINT_RECEBIMENTO_HOMOLOGACAO  = "https://homologacao-selodigital.tjce.jus.br/wsselodigital-homologacao/ReceberSelos"
    ENDPOINT_RECEBIMENTO_PRODUCAO     = "https://selodigital.tjce.jus.br/wsselodigital/ReceberSelos"
    ENDPOINT_MOVIMENTACAO_HOMOLOGACAO = "https://homologacao-selodigital.tjce.jus.br/wsselodigital-homologacao/MovimentarAtos"
    ENDPOINT_MOVIMENTACAO_PRODUCAO    = "https://selodigital.tjce.jus.br/wsselodigital/MovimentarAtos"

    NAMESPACE_SD           = "http://service.selosdisponiveis.selodigital.tjce.jus.br/"
    NAMESPACE_SOLICITACAO  = "http://service.solicitacao.selodigital.tjce.jus.br/"
    NAMESPACE_RECEBIMENTO  = "http://service.recebimento.selodigital.tjce.jus.br/"
    NAMESPACE_MOVIMENTACAO = "http://service.movimentacao.selodigital.tjce.jus.br/"
    NAMESPACE_ENV    = "http://schemas.xmlsoap.org/soap/envelope/"
    NAMESPACE_SCHEMA = "http://www.tjce.jus.br/selodigital/schemas"
    NAMESPACE_DS     = "http://www.w3.org/2000/09/xmldsig#"
    NAMESPACE_XSI    = "http://www.w3.org/2001/XMLSchema-instance"

    # Aceita PFX via caminho (pfx_path), conteúdo binário já em memória (pfx_content)
    # ou cert/key extraídos (cert_path + key_path).
    # homologacao: false = endpoint de produção (padrão), true = endpoint de homologação.
    # ambiente: valor enviado no cabeçalho SOAP (1 para produção e homologação do TJCE).
    #
    # informante_cpf/solicitante_*: usados apenas por solicita_selos e movimentar_atos
    # (não são necessários para consulta_selos_disponiveis nem receber_selos).
    def initialize(codigo_serventia:, versao: "1.12", ambiente: 1, homologacao: false,
                   pfx_path: nil, pfx_content: nil, pfx_password: nil,
                   cert_path: nil, key_path: nil,
                   informante_cpf: nil, solicitante_nome: nil,
                   solicitante_ddd: nil, solicitante_telefone: nil, solicitante_email: nil)
      @codigo_serventia = codigo_serventia
      @versao           = versao
      @ambiente         = ambiente
      @homologacao      = homologacao
      @endpoint         = homologacao ? ENDPOINT_HOMOLOGACAO : ENDPOINT_PRODUCAO

      @informante_cpf       = informante_cpf
      @solicitante_nome     = solicitante_nome
      @solicitante_ddd      = solicitante_ddd
      @solicitante_telefone = solicitante_telefone
      @solicitante_email    = solicitante_email

      if pfx_content
        pkcs12 = OpenSSL::PKCS12.new(pfx_content, pfx_password)
        @cert  = pkcs12.certificate
        @key   = pkcs12.key
      elsif pfx_path
        pkcs12 = OpenSSL::PKCS12.new(File.binread(pfx_path), pfx_password)
        @cert  = pkcs12.certificate
        @key   = pkcs12.key
      else
        @cert = OpenSSL::X509::Certificate.new(File.read(cert_path))
        @key  = OpenSSL::PKey::RSA.new(File.read(key_path))
      end
    end

    def consulta_selos_disponiveis
      xml = build_envelope(
        <<~XML
          <sd:consultaSelosDisponiveis>
            <arg0>
              <cabecalho>
                <versao>#{@versao}</versao>
                <dataHora>#{Time.current.strftime("%Y-%m-%dT%H:%M:%S")}</dataHora>
                <ambiente>#{@ambiente}</ambiente>
                <serventia>
                  <codigoServentia>#{@codigo_serventia}</codigoServentia>
                </serventia>
              </cabecalho>
            </arg0>
          </sd:consultaSelosDisponiveis>
        XML
      )
      response_xml = post(@endpoint, xml)
      parse_selos_disponiveis(response_xml)
    end

    # Solicita mais selos de um tipo ao TJCE. Retorna a "chave" usada depois em
    # receber_selos para efetivamente baixar os números de série.
    #
    # id_solicitacao: identificador local do pedido (ex: próximo id de sd_solicitacoes),
    # enviado ao TJCE como referência — não é o mesmo que a chave retornada por ele.
    def solicita_selos(codigo_tipo_selo:, quantidade:, id_solicitacao:)
      corpo = <<~XML
        <arg0>
          #{cabecalho}
          <solicitante>
            <nomePessoa>#{@solicitante_nome}</nomePessoa>
            <documento>
              <tipoDocumento>1</tipoDocumento>
              <numero>#{@informante_cpf}</numero>
              <descricao>CPF</descricao>
              <orgaoEmissor></orgaoEmissor>
              <dataEmissao>#{Date.current.iso8601}</dataEmissao>
            </documento>
            <telefone>
              <tipoTelefone>1</tipoTelefone>
              <ddd>#{@solicitante_ddd}</ddd>
              <numero>#{@solicitante_telefone}</numero>
            </telefone>
            <email>
              <tipoEmail>1</tipoEmail>
              <enderecoEmail>#{@solicitante_email}</enderecoEmail>
            </email>
          </solicitante>
          <idSolicitacaoSelo>#{id_solicitacao}</idSolicitacaoSelo>
          <itens>
            <itemSolicitacao>
              <sequencial>1</sequencial>
              <codigoSelo>
                <codigo>#{codigo_tipo_selo}</codigo>
              </codigoSelo>
              <quantidade>#{quantidade}</quantidade>
            </itemSolicitacao>
          </itens>
        </arg0>
      XML
      xml = envelope(NAMESPACE_SOLICITACAO, "solicitaSelos", corpo)
      endpoint = @homologacao ? ENDPOINT_SOLICITACAO_HOMOLOGACAO : ENDPOINT_SOLICITACAO_PRODUCAO
      parse_solicita_selos(post(endpoint, xml))
    end

    # Usa a "chave" de uma solicitação já aceita pelo TJCE para efetivamente baixar
    # os números de série dos selos. Retorna um array de
    # { numero_serie:, validador:, codigo_selo: }.
    def receber_selos(chave:)
      corpo = <<~XML
        <arg0>
          #{cabecalho}
          <chave>#{chave}</chave>
        </arg0>
      XML
      xml = envelope(NAMESPACE_RECEBIMENTO, "receberSelos", corpo)
      endpoint = @homologacao ? ENDPOINT_RECEBIMENTO_HOMOLOGACAO : ENDPOINT_RECEBIMENTO_PRODUCAO
      parse_receber_selos(post(endpoint, xml))
    end

    # Submete um lote de atos praticados ao TJCE, consumindo o selo já reservado
    # localmente para cada um. `atos` é uma lista de objetos respondendo a: id,
    # codigo_ato, tipo_selo, numero_selo, validador, valorSelo, tipoCobranca,
    # tipoMovimentacao, quantidadeExtra, valorDocumento, valorEmolumento,
    # valorFermoju, retificacao?, sqAto_idOriginal (AtoPraticado já responde a
    # tudo isso — os nomes camelCase vêm das colunas reais de sd_atosPraticados).
    #
    # Retorna um array de { id_ato:, falha:, sq_ato_tj:, status_ato_tj:, codigo_falha: }
    # na ordem de resposta do TJCE — id_ato corresponde ao `id` passado em cada ato.
    #
    # NOTA: o bloco <partePessoa> replica o placeholder genérico ("Generico"/dados
    # fictícios) que o PHP legado já envia em produção — não temos confirmação de que
    # o TJCE valida esse bloco de fato. Ver CLAUDE.md antes de usar isso em produção.
    def movimentar_atos(atos:)
      corpo = <<~XML
        <arg0>
          #{cabecalho}
          <informante>#{@informante_cpf}</informante>
          #{atos.map { |ato| ato_xml(ato) }.join}
        </arg0>
      XML
      xml = envelope(
        NAMESPACE_MOVIMENTACAO,
        "movimentarAtos",
        corpo,
        extra_xmlns: %( xmlns:xsi="#{NAMESPACE_XSI}" xmlns:ns3="#{NAMESPACE_SCHEMA}")
      )
      endpoint = @homologacao ? ENDPOINT_MOVIMENTACAO_HOMOLOGACAO : ENDPOINT_MOVIMENTACAO_PRODUCAO
      parse_movimentar_atos(post(endpoint, xml))
    end

    private

    def cabecalho
      <<~XML
        <cabecalho>
          <versao>#{@versao}</versao>
          <dataHora>#{Time.current.strftime("%Y-%m-%dT%H:%M:%S")}</dataHora>
          <ambiente>#{@ambiente}</ambiente>
          <serventia>
            <codigoServentia>#{@codigo_serventia}</codigoServentia>
          </serventia>
        </cabecalho>
      XML
    end

    # Combina a data (dataAtoPraticado/dataAtoSolicitacao, colunas date puras em
    # sd_atosPraticados) com o horário de tempo (a única coluna de horário do
    # ato) para formar o dateTime exigido pelo TJCE — em vez de usar o horário
    # do envio, que não reflete quando o ato foi de fato praticado/solicitado.
    def data_hora_ato(data, tempo)
      return Time.current.strftime("%Y-%m-%dT%H:%M:%S") if data.blank?

      hora = tempo.present? ? tempo.strftime("%H:%M:%S") : "00:00:00"
      "#{data.strftime("%Y-%m-%d")}T#{hora}"
    end

    # Ordem dos elementos e conjunto de campos aceitos confirmados batendo um
    # ato real contra o TJCE de produção: primeiro rejeitou "tipoGeracao" (não
    # existe no schema CGenerica), depois rejeitou a ordem por faltar
    # <numeroAtendimento> logo após valorFermoju — esse elemento recebe o
    # mesmo valor de numeroTalao (não existe coluna "numeroAtendimento" em
    # sd_atosPraticados; numeroTalao é o dado real por trás desse campo).
    # "registro" também é legal mas não tem coluna correspondente e foi omitido.
    #
    # <sqAtoRetificado> só é enviado quando ato.retificacao? — sua posição real
    # no XSD (docs/tjce/) é logo após codigoAto, então foi inserido ali; ver
    # AtoPraticado#retificacao? para de onde vem o valor.
    def ato_xml(ato)
      sq_ato_retificado = ato.retificacao? ? "<sqAtoRetificado>#{ato.sqAto_idOriginal}</sqAtoRetificado>\n  " : ""
      <<~XML
        <atos xsi:type="ns3:CGenerica">
          <valorEmolumento>#{ato.valorEmolumento}</valorEmolumento>
          <codigoAto>#{ato.codigo_ato}</codigoAto>
          #{sq_ato_retificado}<valorEmolumentoLivre>0</valorEmolumentoLivre>
          <dataAtoPraticado>#{data_hora_ato(ato.dataAtoPraticado, ato.tempo)}</dataAtoPraticado>
          <tipoMovimentacao>#{ato.tipoMovimentacao}</tipoMovimentacao>
          <dataAtoSolicitacao>#{data_hora_ato(ato.dataAtoSolicitacao, ato.tempo)}</dataAtoSolicitacao>
          <observacoes></observacoes>
          <selo>
            <codigoSelo>
              <codigo>#{ato.tipo_selo}</codigo>
            </codigoSelo>
            <numeroSerie>#{ato.numero_selo.to_s.strip}</numeroSerie>
            <validador>#{ato.validador.to_s.strip}</validador>
            <valor>#{ato.valorSelo}</valor>
          </selo>
          <valorDocumento>#{ato.valorDocumento}</valorDocumento>
          <valorFermoju>#{ato.valorFermoju}</valorFermoju>
          <numeroAtendimento>#{ato.numeroTalao}</numeroAtendimento>
          <tipoCobranca>#{ato.tipoCobranca}</tipoCobranca>
          <quantidadeExtra>#{ato.quantidadeExtra}</quantidadeExtra>
          <responsavel>#{@informante_cpf}</responsavel>
          <idAto>#{ato.id}</idAto>
          <partePessoa>
            <ordem>1</ordem>
            <tipoParte>1</tipoParte>
            <pessoa>
              <nomePessoa>Generico</nomePessoa>
              <endereco>
                <tipoEndereco>1</tipoEndereco>
                <descricaoLogradouro>rua</descricaoLogradouro>
                <numero>10</numero>
                <bairro>Todos</bairro>
                <cidade>2304400</cidade>
                <uf>23</uf>
                <cep>61522080</cep>
              </endereco>
              <documento>
                <tipoDocumento>1</tipoDocumento>
                <numero>0123456789</numero>
                <descricao>Doc Teste</descricao>
                <orgaoEmissor>SSP</orgaoEmissor>
                <dataEmissao>2017-01-01T10:00:00</dataEmissao>
              </documento>
            </pessoa>
          </partePessoa>
        </atos>
      XML
    end

    def build_envelope(body)
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <soapenv:Envelope xmlns:soapenv="#{NAMESPACE_ENV}"
          xmlns:sd="#{NAMESPACE_SD}"
          xmlns:xd="#{NAMESPACE_DS}">
          <soapenv:Header/>
          <soapenv:Body>
            #{body.strip}
          </soapenv:Body>
        </soapenv:Envelope>
      XML
    end

    # Igual a build_envelope, mas genérico para as operações com namespace "ser:"
    # próprio e (no caso de movimentarAtos) declarações xmlns extras no Envelope.
    def envelope(namespace, operation, body, extra_xmlns: nil)
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <soapenv:Envelope xmlns:soapenv="#{NAMESPACE_ENV}"
          xmlns:ser="#{namespace}"
          xmlns:xd="#{NAMESPACE_DS}"#{extra_xmlns}>
          <soapenv:Header/>
          <soapenv:Body>
            <ser:#{operation}>
              #{body.strip}
            </ser:#{operation}>
          </soapenv:Body>
        </soapenv:Envelope>
      XML
    end

    def post(url, xml)
      log_dir   = Rails.root.join("log/soap")
      FileUtils.mkdir_p(log_dir)
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      File.write(log_dir.join("request_#{timestamp}.xml"), xml)

      uri  = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl     = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      http.cert = @cert
      http.key  = @key

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "text/xml; charset=utf-8"
      request["SOAPAction"]   = '""'
      request.body = xml

      response = http.request(request)
      # Grava a resposta crua com o mesmo timestamp da requisição — sem isso,
      # respostas de erro (fault SOAP, payload inesperado) são indistinguíveis
      # de sucesso vazio depois do fato, já que só o parsing decide o que fazer
      # com elas e nada da resposta original fica disponível pra investigar.
      # binwrite (não write): o corpo pode vir em encoding diferente de UTF-8
      # (ex: ISO-8859-1) e write levantaria Encoding::UndefinedConversionError
      # ao tentar recodificar — aqui só queremos preservar os bytes originais.
      File.binwrite(log_dir.join("response_#{timestamp}.xml"), response.body.to_s)
      response.body
    end

    def parse_selos_disponiveis(xml)
      doc = Nokogiri::XML(xml)
      doc.remove_namespaces!

      ret = doc.at_xpath("//return")
      raise SeloDigital::Error, "Resposta vazia do servidor" unless ret

      retorno = ret.at_xpath("codigoRetorno")
      result  = {
        codigo:   retorno&.at_xpath("codigo")&.text,
        status:   retorno&.at_xpath("status")&.text&.to_i,
        mensagem: retorno&.at_xpath("mensagem")&.text,
        selos:    []
      }

      ret.xpath("selosDisponiveis").each do |s|
        result[:selos] << {
          codigo_selo: s.at_xpath("codigoSelo")&.text&.to_i,
          saldo:       s.at_xpath("saldo")&.text&.to_i,
          cota:        s.at_xpath("cota")&.text&.to_i
        }
      end

      result
    end

    def parse_solicita_selos(xml)
      raise SeloDigital::Error, "Resposta vazia do servidor" if xml.blank?

      doc = Nokogiri::XML(xml)
      doc.remove_namespaces!

      # A resposta do TJCE para essa operação não segue o mesmo formato
      # codigoRetorno > codigo/status/mensagem das outras — busca direta no
      # documento inteiro, replicando o que o PHP legado faz (AUTOsolicitar_selos.php).
      {
        codigo:    doc.at_xpath("//codigo")&.text,
        mensagem:  doc.at_xpath("//mensagem")&.text,
        chave:     doc.at_xpath("//chave")&.text,
        data_hora: doc.at_xpath("//dataHora")&.text
      }
    end

    def parse_receber_selos(xml)
      doc = Nokogiri::XML(xml)
      doc.remove_namespaces!

      ret = doc.at_xpath("//return")
      raise SeloDigital::Error, "Resposta vazia do servidor" unless ret

      retorno = ret.at_xpath("codigoRetorno")
      result  = {
        codigo:   retorno&.at_xpath("codigo")&.text,
        status:   retorno&.at_xpath("status")&.text&.to_i,
        mensagem: retorno&.at_xpath("mensagem")&.text,
        selos:    []
      }

      ret.xpath("seloRecebimento").each do |s|
        result[:selos] << {
          numero_serie: s.at_xpath("numeroSerie")&.text&.strip,
          validador:    s.at_xpath("validador")&.text&.strip,
          codigo_selo:  s.at_xpath("codigoSelo/codigo")&.text&.to_i
        }
      end

      result
    end

    def parse_movimentar_atos(xml)
      raise SeloDigital::Error, "Resposta vazia do servidor" if xml.blank?

      doc = Nokogiri::XML(xml)
      doc.remove_namespaces!

      fault = doc.at_xpath("//Fault")
      if fault
        raise SeloDigital::Error, fault.at_xpath("faultstring")&.text.presence || "Falha SOAP ao movimentar atos"
      end

      # Em erro de validação global (ex: XML fora do schema), o TJCE responde
      # no mesmo formato <return><codigoRetorno> usado por consulta_selos_disponiveis
      # e receber_selos, sem nenhum <itensLote> — mesmo com status "0" ali dentro,
      # que nessas outras operações significa sucesso. Presença de codigoRetorno
      # sem nenhum item processado só acontece nesse caso de erro global.
      codigo_retorno = doc.at_xpath("//codigoRetorno")
      if codigo_retorno && doc.xpath("//itensLote").empty?
        raise SeloDigital::Error, codigo_retorno.at_xpath("mensagem")&.text.presence || "Erro ao movimentar atos"
      end

      itens = []
      doc.xpath("//itensLote").each do |item|
        falha = item.at_xpath("statusFalha")
        if falha
          itens << {
            id_ato:        item.at_xpath("idAto")&.text&.to_i,
            falha:         true,
            sq_ato_tj:     nil,
            status_ato_tj: falha.at_xpath("status")&.text,
            codigo_falha:  falha.at_xpath("codigo")&.text
          }
        else
          itens << {
            id_ato:        item.at_xpath("idAto")&.text&.to_i,
            falha:         false,
            sq_ato_tj:     item.at_xpath("sqAto")&.text,
            status_ato_tj: item.at_xpath("statusAto")&.text
          }
        end
      end

      itens
    end
  end
end
