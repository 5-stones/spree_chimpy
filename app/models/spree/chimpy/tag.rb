class Spree::Chimpy::Tag < ActiveRecord::Base
      self.table_name = "spree_chimpy_tags"

      validates_uniqueness_of :name

    # NOTE: For development purposes, tags are synonymous with segments

    # id
    # name
    attr_readonly :external_id
        # the external_id is the MailChimp ID for the tag. This cannot change once it's been set

    after_commit :update_mailchimp, on: :update

    def update_mailchimp
      begin
        Spree::Chimpy.list.api_list_call.segments(self.external_id).update(body: { name: self.name })
      rescue Gibbon::MailChimpError => e
        Rails.logger.error({ scope: 'spree_chimpy', process: 'TagsController.update', message: "Error saving #{@chimpy_tag.name} tag. Remote record was not updated.", status_code: 500 })
      end
    end

end
