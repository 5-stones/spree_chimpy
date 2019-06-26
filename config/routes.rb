Spree::Core::Engine.add_routes do
  get 'admin/chimpy/orders/push', to: 'admin/orders#push_all_to_mail_chimp', as: 'mail_chimp_push_orders'
  get 'admin/chimpy/products/push', to: 'admin/products#push_all_to_mail_chimp', as: 'mail_chimp_push_products'

  namespace :chimpy, path: "" do
    resource :subscribers, only: [:create]
  end

  namespace :admin, path: Spree.admin_path do
    namespace :chimpy, path: 'mailchimp' do
      resources :tags
    end
  end
end
