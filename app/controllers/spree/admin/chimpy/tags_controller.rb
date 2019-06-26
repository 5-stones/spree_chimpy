class Spree::Admin::Chimpy::TagsController < Spree::Admin::ResourceController
  respond_to :html, :json

  def create

    # NOTE: Creating tags is a little strange. The `external_id` attribute needs to be readonly
    # to prevent breaking updates to the record, which means we cannot chnge the value once the
    # spree record is created.
    #
    # In order to _have_ and external_id, we need to push the record to mailchimp successfully.
    # As such, the create method for this controller submits a MailChimp call to create the tag
    # an upon successful response, we create the linked Spree record
    #
    # This find_by call doubles down on the uniqueness validation for name to prevent making a
    # MailChimp call that we know will fail

    @chimpy_tag = Spree::Chimpy::Tag.new(name: tag_params[:name])

    if !(Spree::Chimpy::Tag.find_by(name: tag_params[:name]).blank?)
      flash[:errpr] = "That tag already exists. Please choose another name"
      render :new and return
    end

    begin
      response = Spree::Chimpy.list.api_list_call.segments.create(body: { name: tag_params[:name], static_segment: [] })

      if response
        @chimpy_tag = Spree::Chimpy::Tag.find_or_create_by(name: response.body['name'], external_id: response.body['id'])

        if @chimpy_tag.save
          flash[:notice] = 'Tag created!'

        else # The tag was created in MailChimp, but failed to save in Spree.
          Rails.logger.error({ scope: 'spree_chimpy', process: 'TagsController.create', message: "Error saving #{@chimpy_tag.name} tag. Deleting MailChimp record.", status_code: 500 })

          begin
            # Delete the MailChimp tag to prevent future errors
            Rails.logger.info({ scope: 'spree_chimpy', process: 'TagsController.create', message: "MailChimp tag #{@chimpy_tag.name} was created successfully, but there was an error saving the record in Spree. Deleting the remote tag.", status_code: 500 })

            Spree::Chimpy.list.api_list_call.segments(response.body['id']).delete

          rescue Gibbon::MailChimpError => e
            # An error occurred while trying to delete the MailChimp record. Log it for reference
            Rails.logger.error({ scope: 'spree_chimpy', process: 'TagsController.create', message: "Error creating #{@chimpy_tag.name} tag. MailChimp returned no response.", status_code: 500 })
          end

          flash[:error] = 'Failed to save tag. Please try again'
          render :new and return
        end
      else # MailChimp returned no response.
        Rails.logger.error({ scope: 'spree_chimpy', process: 'TagsController.create', message: "Error creating #{@chimpy_tag.name} tag. MailChimp returned no response.", status_code: 500 })

        flash[:error] = 'Failed to save tag. Please try again'
        render :new and return
      end

    rescue Gibbon::MailChimpError => e
      Rails.logger.error({ scope: 'spree_chimpy', process: 'TagsController.create', exception: e, message: e.detail,  backtrace: e.backtrace.join("\n"), status_code: e.status_code })

      flash[:error] = e.detail

      render :new and return
    end


    redirect_to edit_admin_chimpy_tag_path(@chimpy_tag)
  end

  def update
    @chimpy_tag = Spree::Chimpy::Tag.find(params[:id])

    @chimpy_tag.update_attributes(tag_params)

    redirect_to edit_admin_chimpy_tag_path(@chimpy_tag)
  end

  def location_after_save
    spree.edit_admin_chimpy_tag_path(@chimpy_tag)
  end

  private

    def tag_params
      return params.require(:chimpy_tag).permit(:id, :name)
    end
end
