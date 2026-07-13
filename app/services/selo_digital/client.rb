require "net/https"
require "openssl"

module SeloDigital
  class Client
    ENDPOINT_HOMOLOGACAO = "https://homologacao-selodigital.tjce.jus.br/wsselodigital-homologacao/SelosDisponiveis"
    ENDPOINT_PRODUCAO    = "https://selodigital.tjce.jus.br/wsselodigital/SelosDisponiveis"
    NAMESPACE_SD     = "http://service.selosdisponiveis.selodigital.tjce.jus.br/"
    NAMESPACE_ENV    = "http://schemas.xmlsoap.org/soap/envelope/"
    NAMESPACE_SCHEMA = "http://www.tjce.jus.br/selodigital/schemas"
    NAMESPACE_DS     = "http://www.w3.org/2000/09/xmldsig#"

    # Aceita PFX via caminho (pfx_path), conteúdo binário já em memória (pfx_content)
    # ou cert/key extraídos (cert_path + key_path).
    # homologacao: false = endpoint de produção (padrão), true = endpoint de homologação.
    # ambiente: valor enviado no cabeçalho SOAP (1 para produção e homologação do TJCE).
    def initialize(codigo_serventia:, versao: "1.12", ambiente: 1, homologacao: false,
                   pfx_path: nil, pfx_content: nil, pfx_password: nil,
                   cert_path: nil, key_path: nil)
      @codigo_serventia = codigo_serventia
      @versao           = versao
      @ambiente         = ambiente
      @endpoint         = homologacao ? ENDPOINT_HOMOLOGACAO : ENDPOINT_PRODUCAO

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
      response_xml = post(xml)
      parse_selos_disponiveis(response_xml)
    end

    private

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

    def post(xml)
      log_dir = Rails.root.join("log/soap")
      FileUtils.mkdir_p(log_dir)
      File.write(log_dir.join("request_#{Time.current.strftime("%Y%m%d_%H%M%S")}.xml"), xml)

      uri  = URI.parse(@endpoint)
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
  end
end
