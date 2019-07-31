require 'digest'
require 'multi_json'

module Spree::Chimpy
  module Interface
    class List
      delegate :log, to: Spree::Chimpy

      def initialize(list_name, segment_name, double_opt_in, send_welcome_email, list_id)
        @list_id       = list_id
        @segment_name  = segment_name
        @double_opt_in = double_opt_in
        @send_welcome_email = send_welcome_email
        @list_name     = list_name
      end

      def api_call(list_id = nil)
        if list_id
          Spree::Chimpy.api.lists(list_id)
        else
          Spree::Chimpy.api.lists
        end
      end

      def subscribe(email, merge_vars, options = {})
        log "Subscribing #{email} to #{@list_name}"

        begin
          data = {
            email_address: email,
            status: "subscribed",
            email_type: 'html'
          }

          if merge_vars
            data[:merge_fields] = merge_vars
          end

          if options[:interests]
            data[:interests] = options[:interests]
          end

          api_member_call(email)
            .upsert(body: data) #, @double_opt_in, true, true, @send_welcome_email)

          # add to customer segment
          segment([email]) if options[:customer]
        rescue Gibbon::MailChimpError => ex
          log "Subscriber #{email} rejected for reason: [#{ex.raw_body}]"
          true
        end
      end

      def unsubscribe(email)
        log "Unsubscribing #{email} from #{@list_name}"

        begin
          api_member_call(email)
            .update(body: {
              email_address: email,
              status: "unsubscribed"
            })
        rescue Gibbon::MailChimpError => ex
          log "Subscriber unsubscribe for #{email} failed for reason: [#{ex.raw_body}]"
          true
        end
      end

      def email_for_id(mc_eid)
        log "Checking customer id for #{mc_eid} from #{@list_name}"
        begin
          response = api_list_call
            .members
            .retrieve(params: { "unique_email_id" => mc_eid, "fields" => "members.id,members.email_address" })
            .body

          member_data = response["members"].first
          member_data["email_address"] if member_data
        rescue Gibbon::MailChimpError => ex
          nil
        end
      end

      def info(email)
        log "Checking member info for #{email} from #{@list_name}"

        #maximum of 50 emails allowed to be passed in
        begin
          response = api_member_call(email)
            .retrieve(params: { "fields" => "email_address,merge_fields,status"})
            .body

          response = response.symbolize_keys
          response.merge(email: response[:email_address])
        rescue Gibbon::MailChimpError
          {}
        end

      end

      def merge_vars
        log "Finding merge vars for #{@list_name}"

        response = api_list_call
          .merge_fields
          .retrieve(params: { "fields" => "merge_fields.tag,merge_fields.name"})
          .body
        response["merge_fields"].map { |record| record['tag'] }
      end

      def add_merge_var(tag, description)
        log "Adding merge var #{tag} to #{@list_name}"

        api_list_call
          .merge_fields
          .create(body: {
            tag: tag,
            name: description,
            type: "text"
          })
      end

      def find_list_id(name)
        list = search_lists(name.downcase)

        if (list)
          return list["id"]
        else
          return nil
        end
      end

      def search_lists(list_name, page_size = 10, page_number = 1)
        # NOTE: MailChimp doesn't use a page number parameter -- calculate the offset instead
        offset = page_size * (page_number - 1)

        begin
          response = api_call
            .retrieve(params: {count: page_size, offset: offset, fields: "lists.id,lists.name"})
            .body

          lists = response["lists"]

          if (lists.size == 0)
            # No lists found, return nil
            return nil
          else
            list = lists.detect { |r| r["name"] == list_name }

            if (list)
              # Return the list if we found it
              return list
            elsif (lists.size == page_size)
              # We didn't find the list, but there may be more than one page -- try the next one
              return search_lists(list_name, page_size, page_number + 1)
              # NOTE: The response object returned from the API call does not have the `total_items` field mentioned in the
              # API documentation, so we don't know how many pages there are.
              #
              # If the returned list of audiences is equal to the passed page_size, but we do not find the audience
              # we're looking for, that is a good indication that there is a second page of results, so we'll try
              # fetching it.
              #
              # If the response comes back with zero items, we'll know we've reached the end
            else
              # We found nothing, and because lists.size != page_size, we know there are no more lists available.
              return nil
            end
          end

        rescue Gibbon::MailChimpError => e
          # Log the error to assist with debugging, but do not fail.
          Rails.logger.error({
            class: 'SpreeChimpy::Interface::List',
            scope: 'Retrieving Lists from MailChimp',
            params: { list_name: list_name, page_size: page_size, page_number: page_number, calculated_offset: offset },
            message: e.message,
            trace: e.backtrace.join("\n"),
            error: e.inspect
          })

          return nil
        end
      end

      def list_id
        @list_id ||= find_list_id(@list_name)
      end

      def segment(emails = [])
        log "Adding #{emails} to segment #{@segment_name} [#{segment_id}] in list [#{list_id}]"

        api_list_call.segments(segment_id.to_i).create(body: { members_to_add: Array(emails) })
      end

      def create_segment
        begin
          Rails.logger.info({
            class: 'SpreeChimpy::Interface::List',
            scope: 'Creating Segment from MailChimp',
            params: { segment_name: @segment_name, },
            message: "#{@segment_name} segment does not exist. Attempting to create it",
          })

          result = api_list_call.segments.create(body: { name: @segment_name, static_segment: []})
          @segment_id = result["id"]
        rescue Gibbon::MailChimpError => e
          # Log the error to assist with debugging, but do not fail.
          Rails.logger.error({
            class: 'SpreeChimpy::Interface::List',
            scope: 'Creating Segment from MailChimp',
            params: { segment_name: @segment_name, },
            message: e.message,
            trace: e.backtrace.join("\n"),
            error: e.inspect
          })

          return nil
        end
      end

      def find_segment_id
        segment = search_segments(@segment_name)

        return segment['id'] if segment
      end

      def search_segments(name, page_size = 10, page_number = 1)

        # NOTE: MailChimp doesn't use a page number parameter -- calculate the offset instead
        offset = page_size * (page_number - 1)

        begin
          response = api_list_call.segments
            .retrieve(params: {count: page_size, offset: offset, fields: "segments.id,segments.name"})
            .body

          segments = response["segments"]

          if (segments.size == 0)
            # No lists found, return nil
            return nil
          else
            segment = segments.detect { |segment| segment['name'].downcase == name.downcase }

            if (segment)
              # Return the list if we found it
              return segment
            elsif (segments.size == page_size)
              # We didn't find the list, but there may be more than one page -- try the next one
              return search_segments(name, page_size, page_number + 1)
              # NOTE: See the NOTE comment in search_lists as this has the same limitations
            else
              # We found nothing, and because segments.size != page_size, we know there are no more segments available.
              return nil
            end
          end

        rescue Gibbon::MailChimpError => e
          # Log the error to assist with debugging, but do not fail.
          Rails.logger.error({
            class: 'SpreeChimpy::Interface::List',
            scope: 'Retrieving Segments from MailChimp',
            params: { segment_name: name, page_size: page_size, page_number: page_number, calculated_offset: offset },
            message: e.message,
            trace: e.backtrace.join("\n"),
            error: e.inspect
          })

          return nil
        end

      end

      def segment_id
        @segment_id ||= find_segment_id
      end

      def api_list_call
        api_call(list_id)
      end

      def api_member_call(email)
        api_list_call.members(email_to_lower_md5(email))
      end

      private

      def email_to_lower_md5(email)
        Digest::MD5.hexdigest(email.downcase)
      end
    end
  end
end
