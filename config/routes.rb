Rails.application.routes.draw do
  root "dashboard#show"

  get "auth/shopify", to: "shopify/oauth#install", as: :shopify_install
  get "auth/shopify/callback", to: "shopify/oauth#callback", as: :shopify_oauth_callback
  post "webhooks/shopify/app_uninstalled", to: "shopify/webhooks#app_uninstalled", as: :shopify_app_uninstalled_webhook
  get "dashboard", to: "dashboard#show", as: :dashboard
  post "dashboard/sync", to: "dashboard#sync", as: :dashboard_sync

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  get "health" => "health#show", as: :health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
