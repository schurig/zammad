# Copyright (C) 2012-2016 Zammad Foundation, http://zammad-foundation.org/
class Ticket::TimeAccounting < ApplicationModel

  after_create :ticket_time_unit_update
  after_update :ticket_time_unit_update

  def ticket_time_unit_update
    exists = false
    time_units = 0
    Ticket::TimeAccounting.where(ticket_id: ticket_id).each { |record|
      time_units += record.time_unit
      exists = true
    }
    return false if exists == false
    ticket = Ticket.lookup(id: ticket_id)
    return false if !ticket
    return false if ticket.time_unit == time_units
    ticket.time_unit = time_units
    ticket.save!
    true
  end

end
