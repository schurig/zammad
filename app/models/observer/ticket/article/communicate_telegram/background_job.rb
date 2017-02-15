class Observer::Ticket::Article::CommunicateTelegram::BackgroundJob
  def initialize(id)
    @article_id = id
  end

  def perform
    article = Ticket::Article.find(@article_id)

    # set retry count
    if !article.preferences['delivery_retry']
      article.preferences['delivery_retry'] = 0
    end
    article.preferences['delivery_retry'] += 1

    ticket = Ticket.lookup(id: article.ticket_id)
    log_error(article, "Can't find ticket.preferences for Ticket.find(#{article.ticket_id})") if !ticket.preferences
    log_error(article, "Can't find ticket.preferences['telegram'] for Ticket.find(#{article.ticket_id})") if !ticket.preferences['telegram']
    log_error(article, "Can't find ticket.preferences['telegram']['chat_id'] for Ticket.find(#{article.ticket_id})") if !ticket.preferences['telegram']['chat_id']
    channel = Channel.lookup(id: ticket.preferences['channel_id'])
    log_error(article, "No such channel id #{ticket.preferences['channel_id']}") if !channel
    #log_error(article, "Channel.find(#{channel.id}) isn't a telegram channel!") if channel.options[:adapter] !~ /\Atelegram/i
    log_error(article, "Channel.find(#{channel.id}) has not telegram api token!") if channel.options[:api_token].blank?

    begin
      api = TelegramAPI.new(channel.options[:api_token])
      result = api.sendMessage(ticket.preferences[:telegram][:chat_id], article.body)
    rescue => e
      log_error(article, e.message)
      return
    end

    # fill article with message info
    article.from = "@#{result['from']['username']}"
    article.to = "@#{result['chat']['username']}"

    article.preferences['telegram'] = {
      date: result['date'],
      from_id: result['from']['id'],
      chat_id: result['chat']['id'],
      message_id: result['message_id']
    }

    # set delivery status
    article.preferences['delivery_status_message'] = nil
    article.preferences['delivery_status'] = 'success'
    article.preferences['delivery_status_date'] = Time.zone.now

    article.message_id = "telegram.#{result['message_id']}.#{result['chat']['id']}"

    article.save!

    Rails.logger.info "Send telegram message to: '#{article.to}' (from #{article.from})"

    article
  end

  def log_error(local_record, message)
    local_record.preferences['delivery_status'] = 'fail'
    local_record.preferences['delivery_status_message'] = message
    local_record.preferences['delivery_status_date'] = Time.zone.now
    local_record.save
    Rails.logger.error message

    if local_record.preferences['delivery_retry'] > 3
      Ticket::Article.create(
        ticket_id: local_record.ticket_id,
        content_type: 'text/plain',
        body: "Unable to send telegram message: #{message}",
        internal: true,
        sender: Ticket::Article::Sender.find_by(name: 'System'),
        type: Ticket::Article::Type.find_by(name: 'note'),
        preferences: {
          delivery_article_id_related: local_record.id,
          delivery_message: true,
        },
        updated_by_id: 1,
        created_by_id: 1,
      )
    end

    raise message
  end

  def max_attempts
    4
  end

  def reschedule_at(current_time, attempts)
    if Rails.env.production?
      return current_time + attempts * 120.seconds
    end
    current_time + 5.seconds
  end
end
