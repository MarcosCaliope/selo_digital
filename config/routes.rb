Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  get "selos", to: "selos#index"
  get "movimentacao", to: "movimentacao#index"
  post "movimentacao/solicitar_selos", to: "movimentacao#solicitar_selos", as: :solicitar_selos_movimentacao
  post "movimentacao/receber_selos/:id", to: "movimentacao#receber_selos", as: :receber_selos_movimentacao
  post "movimentacao/enviar_atos", to: "movimentacao#enviar_atos", as: :enviar_atos_movimentacao
  get "movimentacao/atos/:id/retificar", to: "movimentacao#editar_retificacao", as: :editar_retificacao_movimentacao
  patch "movimentacao/atos/:id/retificar", to: "movimentacao#retificar", as: :retificar_movimentacao
  post "movimentacao/atos/:id/reenviar", to: "movimentacao#reenviar_rejeitado", as: :reenviar_rejeitado_movimentacao
  resources :empresas
  root "selos#index"
end
