class EmpresasController < ApplicationController
  before_action :set_empresa, only: %i[show edit update destroy]

  def index
    @empresas = Empresa.order(:snomeempresa)
  end

  def show
  end

  def new
    @empresa = Empresa.new
  end

  def edit
  end

  def create
    @empresa = Empresa.new(empresa_params)

    if @empresa.save
      redirect_to @empresa, notice: "Empresa cadastrada com sucesso."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @empresa.update(empresa_params)
      redirect_to @empresa, notice: "Empresa atualizada com sucesso."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @empresa.destroy
    redirect_to empresas_path, notice: "Empresa removida com sucesso."
  end

  private

  def set_empresa
    @empresa = Empresa.find(params[:id])
  end

  def empresa_params
    permitted = params.require(:empresa).permit(
      :snomeempresa, :sfantasia, :sendereco, :sbairro, :scidade, :sestado, :scep,
      :snocnpj, :snocgf, :sfone1, :sfone2, :semail,
      :snomeresponsavel, :snocpfresponsavel, :codigo_serventia, :homologacao,
      :certificado_digital_upload, :senha_certificado_digital, :intervalo_envio_minutos
    )
    # Campo de senha em branco significa "manter a senha atual" — não sobrescrever.
    permitted.delete(:senha_certificado_digital) if permitted[:senha_certificado_digital].blank?
    permitted
  end
end
