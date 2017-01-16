# Copyright (C) 2012-2015 Zammad Foundation, http://zammad-foundation.org/

class Telegram

  attr_accessor :client

  def user(message)
    {
      id:         message['from']['id'],
      username:   message['from']['username'],
      first_name: message['from']['first_name'],
      last_name:  message['from']['last_name']
    }
  end

  def to_user(telegram_update)
    message = telegram_update['message']

    Rails.logger.debug 'Create user from message...'
    Rails.logger.debug message.inspect

    # do message_user lookup
    message_user = user(message)

    auth = Authorization.find_by(uid: message_user[:id], provider: 'telegram')

    # create or update user
    user_data = {
      login: message_user[:username],
      firstname: message_user[:first_name],
      lastname: message_user[:last_name]
    }
    if auth
      user = User.find(auth.user_id)
      user.update_attributes(user_data)
    else
      user_data[:active]    = true
      user_data[:role_ids]  = Role.signup_role_ids

      user = User.create(user_data)
    end

    # create or update authorization
    auth_data = {
      uid:      message_user[:id],
      username: message_user[:username],
      user_id:  user.id,
      provider: 'telegram'
    }
    if auth
      auth.update_attributes(auth_data)
    else
      Authorization.create(auth_data)
    end

    user
  end

  def to_ticket(telegram_update, user, group_id, channel)
    message = telegram_update['message']

    UserInfo.current_user_id = user.id

    Rails.logger.debug 'Create ticket from message...'
    Rails.logger.debug message.inspect
    Rails.logger.debug user.inspect
    Rails.logger.debug group_id.inspect

    ticket = Ticket.find_by(
      create_article_type: Ticket::Article::Type.lookup(name: 'telegram personal-message'),
      customer_id:         user.id,
      state:               Ticket::State.where.not(
        state_type_id: Ticket::StateType.where(
          name: %w(closed merged removed),
        )
      )
    )
    return ticket if ticket

    # prepare title
    title = message['text']
    if title.length > 80
      title = "#{title[0, 80]}..."
    end

    state = get_state(channel, telegram_update)

    Ticket.create(
      customer_id: user.id,
      title:       title,
      group_id:    group_id,
      state:       state,
      priority:    Ticket::Priority.find_by(name: '2 normal'),
      preferences: {
        channel_id: channel.id,
        channel_username: channel.options['username'],
      },
    )
  end

  def to_article(telegram_update, user, ticket, channel)
    message = telegram_update['message']

    Rails.logger.debug 'Create article from message...'
    Rails.logger.debug message.inspect
    Rails.logger.debug user.inspect
    Rails.logger.debug ticket.inspect

    # import message
    to = nil
    from = nil
    article_type = nil
    in_reply_to = nil
    preferences = {}

    article_type = 'telegram personal-message'
    to = ''
    from = user(message)[:username]
    preferences = {
      created_at: message['date'],
      update_id: message['update_id'],
      sender_id: user(message)[:id],
      sender_username: user(message)[:username],
    }

    UserInfo.current_user_id = user.id

    # set ticket state to open if not new
    ticket_state = get_state(channel, telegram_update, ticket)
    if ticket_state.name != ticket.state.name
      ticket.state = ticket_state
      ticket.save!
    end

    Ticket::Article.create!(
      from:        from,
      to:          to,
      body:        message['text'],
      message_id:  message['message_id'],
      ticket_id:   ticket.id,
      in_reply_to: in_reply_to,
      type_id:     Ticket::Article::Type.find_by(name: article_type).id,
      sender_id:   Ticket::Article::Sender.find_by(name: 'Customer').id,
      internal:    false,
      preferences: {
        telegram: preferences
      }
    )
  end

  def to_group(telegram_update, group_id, channel)
    Rails.logger.debug 'import message'

    ticket = nil
    # use transaction

    Transaction.execute(reset_user_id: true) do

      # check if parent exists
      user = to_user(telegram_update)

      ticket = to_ticket(telegram_update, user, group_id, channel)
      to_article(telegram_update, user, ticket, channel)
    end

    ticket
  end

  def from_article(article)

    message = nil
    Rails.logger.debug "Create telegram personal message from article to '#{article[:to]}'..."

    message = {}
    # TODO: create telegram message here

    Rails.logger.debug message.inspect
    message
  end

  def get_state(channel, telegram_update, ticket = nil)
    message = telegram_update['message']
    message_user = user(message)

    # no changes in post is from page user it self
    if channel.options[:bot][:id].to_s == message_user[:id].to_s
      if !ticket
        return Ticket::State.find_by(name: 'closed') if !ticket
      end
      return ticket.state
    end

    state = Ticket::State.find_by(name: 'new')
    return state if !ticket
    return ticket.state if ticket.state.name == 'new'
    Ticket::State.find_by(name: 'open')
  end
end
