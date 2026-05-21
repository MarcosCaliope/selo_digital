require "net/https"
require "openssl"

module SeloDigital
  class Client
    ENDPOINT_HOMOLOGACAO = "https://homologacao-selodigital.tjce.jus.br/wsselodigital-homologacao/SelosDisponiveis"
    ENDPOINT_PRODUCAO    = "https://selodigital.tjce.jus.br/wsselodigital/SelosDisponiveis"
    NAMESPACE_SD  = "http://service.selosdisponiveis.selodigital.tjce.jus.br/"
    NAMESPACE_ENV = "http://schemas.xmlsoap.org/soap/envelope/"

    # Aceita PFX (pfx_path + pfx_password) ou cert/key extraídos (cert_path + key_path)
    # ambiente: 1 = homologação, 2 = produção
    def initialize(codigo_serventia:, versao: "2", ambiente: 1,
                   pfx_path: nil, pfx_password: nil,
                   cert_path: nil, key_path: nil)
      @codigo_serventia  = codigo_serventia
      @versao            = versao
      @ambiente          = ambiente
      @endpoint          = ambiente == 2 ? ENDPOINT_PRODUCAO : ENDPOINT_HOMOLOGACAO
      @pfx_path          = pfx_path
      @pfx_password      = pfx_password
      @cert_path         = cert_path
      @key_path          = key_path
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
          xmlns:sd="#{NAMESPACE_SD}">
          <soapenv:Header/>
          <soapenv:Body>
            #{body.strip}
          </soapenv:Body>
        </soapenv:Envelope>
      XML
    end

    def post(xml)
      uri  = URI.parse(@endpoint)
      http = Net::HTTP.new(uri.host, uri.port)

      http.use_ssl     = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      if @pfx_path
        pkcs12 = OpenSSL::PKCS12.new(File.binread(@pfx_path), @pfx_password)
        http.cert = pkcs12.certificate
        http.key  = pkcs12.key
      else
        http.cert = OpenSSL::X509::Certificate.new(File.read(@cert_path))
        http.key  = OpenSSL::PKey::RSA.new(File.read(@key_path))
      end

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

  class Error < StandardError; end
end
