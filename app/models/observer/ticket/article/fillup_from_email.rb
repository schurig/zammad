# Copyright (C) 2012-2016 Zammad Foundation, http://zammad-foundation.org/

class Observer::Ticket::Article::FillupFromEmail < ActiveRecord::Observer
  observe 'ticket::_article'

  def before_create(record)

    # return if we run import mode
    return if Setting.get('import_mode')

    # only do fill of email from if article got created via application_server (e. g. not
    # if article and sender type is set via *.postmaster)
    return if ApplicationHandleInfo.current.split('.')[1] == 'postmaster'

    # if sender is customer, do not change anything
    return if !record.sender_id
    sender = Ticket::Article::Sender.lookup(id: record.sender_id)
    return if sender.nil?
    return if sender['name'] == 'Customer'

    # set email attributes
    return if !record.type_id
    type = Ticket::Article::Type.lookup(id: record.type_id)
    return if type['name'] != 'email'

    # set subject if empty
    ticket = Ticket.lookup(id: record.ticket_id)
    if !record.subject || record.subject == ''
      record.subject = ticket.title
    end

    # clean subject
    record.subject = ticket.subject_clean(record.subject)

    # generate message id, force it in prodution, in test allow to set it for testing reasons
    if !record.message_id || Rails.env.production?
      fqdn = Setting.get('fqdn')
      record.message_id = "<#{DateTime.current.to_s(:number)}.#{record.ticket_id}.#{rand(999_999)}@#{fqdn}>"
    end

    # generate message_id_md5
    record.check_message_id_md5

    # set sender
    email_address = ticket.group.email_address
    if !email_address
      raise "No email address found for group '#{ticket.group.name}'"
    end
    if record.created_by_id != 1 && Setting.get('ticket_define_email_from') == 'AgentNameSystemAddressName'
      separator   = Setting.get('ticket_define_email_from_separator')
      sender      = User.find(record.created_by_id)
      realname    = "#{sender.firstname} #{sender.lastname} #{separator} #{email_address.realname}"
      record.from = Channel::EmailBuild.recipient_line(realname, email_address.email)
    else
      record.from = Channel::EmailBuild.recipient_line(email_address.realname, email_address.email)
    end
  end
end
