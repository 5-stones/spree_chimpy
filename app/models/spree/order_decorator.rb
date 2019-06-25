Spree::Order.class_eval do
  has_one :source, class_name: 'Spree::Chimpy::OrderSource'

  around_save :handle_cancelation
  after_commit :notify_mail_chimp

  def notify_mail_chimp

    if (self.completed?)
      Rails.logger.info("Order is complete - pushing order")
      # Sync the Order in MailChimp if the order is complete
      Spree::Chimpy.enqueue(:order, self) if Spree::Chimpy.configured?
    else
      Rails.logger.info("Order is incomplete - pushing cart")
      # Sync the Cart entry in MailChimp if the order is in progress
      Spree::Chimpy.enqueue(:cart, self) if Spree::Chimpy.configured?
    end
  end

private
  def handle_cancelation
    canceled = state_changed? && canceled?
    yield
    notify_mail_chimp if canceled
  end
end
