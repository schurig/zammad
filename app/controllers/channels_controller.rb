# Copyright (C) 2012-2016 Zammad Foundation, http://zammad-foundation.org/

class ChannelsController < ApplicationController
  before_action :authentication_check

  require 'net/http'
  require 'telegramAPI'

=begin

Resource:
POST /api/v1/channels/group/{id}.json

Response:
{}

Test:
curl http://localhost/api/v1/group/channels.json -v -u #{login}:#{password} -H "Content-Type: application/json" -X POST '{group_id:123}'

=end

  def group_update
    permission_check('admin')
    check_access

    channel = Channel.find(params[:id])
    channel.group_id = params[:group_id]
    channel.save
    render json: {}
  end

=begin

Resource:
DELETE /api/v1/channels/{id}.json

Response:
{}

Test:
curl http://localhost/api/v1/channels.json -v -u #{login}:#{password} -H "Content-Type: application/json" -X DELETE

=end

  def destroy
    permission_check('admin')
    check_access
    model_destroy_render(Channel, params)
  end

  def twitter_index
    permission_check('admin.channel_twitter')
    assets = {}
    ExternalCredential.where(name: 'twitter').each { |external_credential|
      assets = external_credential.assets(assets)
    }
    channel_ids = []
    Channel.order(:id).each { |channel|
      next if channel.area != 'Twitter::Account'
      assets = channel.assets(assets)
      channel_ids.push channel.id
    }
    render json: {
      assets: assets,
      channel_ids: channel_ids,
      callback_url: ExternalCredential.callback_url('twitter'),
    }
  end

  def twitter_verify
    permission_check('admin.channel_twitter')
    model_update_render(Channel, params)
  end

  def facebook_index
    permission_check('admin.channel_facebook')
    assets = {}
    ExternalCredential.where(name: 'facebook').each { |external_credential|
      assets = external_credential.assets(assets)
    }
    channel_ids = []
    Channel.order(:id).each { |channel|
      next if channel.area != 'Facebook::Account'
      assets = channel.assets(assets)
      channel_ids.push channel.id
    }
    render json: {
      assets: assets,
      channel_ids: channel_ids,
      callback_url: ExternalCredential.callback_url('facebook'),
    }
  end

  def facebook_verify
    permission_check('admin.channel_facebook')
    model_update_render(Channel, params)
  end

  def telegram_index
    permission_check('admin.channel_telegram')
    assets = {}
    ExternalCredential.where(name: 'telegram').each { |external_credential|
      assets = external_credential.assets(assets)
    }
    channel_ids = []
    Channel.order(:id).each { |channel|
      next if channel.area != 'Telegram::Account'
      assets = channel.assets(assets)
      channel_ids.push channel.id
    }
    render json: {
      assets: assets,
      channel_ids: channel_ids
    }
  end

  def telegram_add
    permission_check('admin.channel_telegram')

    return if !params[:api_token]

    api_base = 'https://api.telegram.org/bot' + params[:api_token]
    result = Net::HTTP.get(URI.parse(api_base + '/getme'))
    bot = JSON.parse(result)

    return if !bot['ok']

    channel = Channel.create(
      area: 'Telegram::Account',
      options: {
        user_id: bot['result']['id'],
        username: bot['result']['username'],
        first_name: bot['result']['first_name'],
        api_token: params[:api_token],
      },
      group_id: params[:group_id],
      last_log_in: nil,
      last_log_out: nil,
      status_in: 'ok',
      status_out: 'ok',
      active: true,
    )
    channel.save

    # fetch telegram bot info (user_id, username, first_name)
    # check if user_id is already in database (duplication check)
      # send zammad webhook url to telegram api
      # save user_id, username, first_name to database
      # save destination group_id setting here
    # reject and return error (duplicated bot)

    render json: {
      ok: :ok
     }
  end

  def telegram_update
    permission_check('admin.channel_telegram')

    # save destination group_id setting here

    render json: {
      ok: :ok
    }
  end

  def email_index
    permission_check('admin.channel_email')
    system_online_service = Setting.get('system_online_service')
    account_channel_ids = []
    notification_channel_ids = []
    email_address_ids = []
    not_used_email_address_ids = []
    accounts_fixed = []
    assets = {}
    Channel.order(:id).each { |channel|
      if system_online_service && channel.preferences && channel.preferences['online_service_disable']
        email_addresses = EmailAddress.where(channel_id: channel.id)
        email_addresses.each { |email_address|
          accounts_fixed.push email_address
        }
        next
      end
      if channel.area == 'Email::Account'
        account_channel_ids.push channel.id
        assets = channel.assets(assets)
      elsif channel.area == 'Email::Notification' && channel.active
        notification_channel_ids.push channel.id
        assets = channel.assets(assets)
      end
    }
    EmailAddress.all.each { |email_address|
      next if system_online_service && email_address.preferences && email_address.preferences['online_service_disable']
      email_address_ids.push email_address.id
      assets = email_address.assets(assets)
      if !email_address.channel_id || !email_address.active || !Channel.find_by(id: email_address.channel_id)
        not_used_email_address_ids.push email_address.id
      end
    }
    render json: {
      accounts_fixed: accounts_fixed,
      assets: assets,
      account_channel_ids: account_channel_ids,
      notification_channel_ids: notification_channel_ids,
      email_address_ids: email_address_ids,
      not_used_email_address_ids: not_used_email_address_ids,
      channel_driver: {
        email: EmailHelper.available_driver,
      },
      config: {
        notification_sender: Setting.get('notification_sender'),
      }
    }
  end

  def email_probe

    # check admin permissions
    permission_check('admin.channel_email')

    # probe settings based on email and password
    result = EmailHelper::Probe.full(
      email: params[:email],
      password: params[:password],
      folder: params[:folder],
    )

    # verify if user+host already exists
    if result[:result] == 'ok'
      return if email_account_duplicate?(result)
    end

    render json: result
  end

  def email_outbound

    # check admin permissions
    permission_check('admin.channel_email')

    # verify access
    return if params[:channel_id] && !check_access(params[:channel_id])

    # connection test
    render json: EmailHelper::Probe.outbound(params, params[:email])
  end

  def email_inbound

    # check admin permissions
    permission_check('admin.channel_email')

    # verify access
    return if params[:channel_id] && !check_access(params[:channel_id])

    # connection test
    result = EmailHelper::Probe.inbound(params)

    # check account duplicate
    return if email_account_duplicate?({ setting: { inbound: params } }, params[:channel_id])

    render json: result
  end

  def email_verify

    # check admin permissions
    permission_check('admin.channel_email')

    email = params[:email] || params[:meta][:email]
    email = email.downcase
    channel_id = params[:channel_id]

    # verify access
    return if channel_id && !check_access(channel_id)

    # check account duplicate
    return if email_account_duplicate?({ setting: { inbound: params[:inbound] } }, channel_id)

    # check delivery for 30 sek.
    result = EmailHelper::Verify.email(
      outbound: params[:outbound],
      inbound: params[:inbound],
      sender: email,
      subject: params[:subject],
    )

    if result[:result] != 'ok'
      render json: result
      return
    end

    # fallback
    if !params[:group_id]
      params[:group_id] = Group.first.id
    end

    # update account
    if channel_id
      channel = Channel.find(channel_id)
      channel.update_attributes(
        options: {
          inbound: params[:inbound],
          outbound: params[:outbound],
        },
        group_id: params[:group_id],
        last_log_in: nil,
        last_log_out: nil,
        status_in: 'ok',
        status_out: 'ok',
      )
      render json: result
      return
    end

    # create new account
    channel = Channel.create(
      area: 'Email::Account',
      options: {
        inbound: params[:inbound],
        outbound: params[:outbound],
      },
      group_id: params[:group_id],
      last_log_in: nil,
      last_log_out: nil,
      status_in: 'ok',
      status_out: 'ok',
      active: true,
    )

    # remember address && set channel for email address
    address = EmailAddress.find_by(email: email)

    # if we are on initial setup, use already exisiting dummy email address
    if Channel.count == 1
      address = EmailAddress.first
    end

    if address
      address.update_attributes(
        realname: params[:meta][:realname],
        email: email,
        active: true,
        channel_id: channel.id,
      )
    else
      address = EmailAddress.create(
        realname: params[:meta][:realname],
        email: email,
        active: true,
        channel_id: channel.id,
      )
    end

    render json: result
  end

  def email_notification

    check_online_service

    # check admin permissions
    permission_check('admin.channel_email')

    adapter = params[:adapter].downcase

    email = Setting.get('notification_sender')

    # connection test
    result = EmailHelper::Probe.outbound(params, email)

    # save settings
    if result[:result] == 'ok'

      Channel.where(area: 'Email::Notification').each { |channel|
        active = false
        if adapter =~ /^#{channel.options[:outbound][:adapter]}$/i
          active = true
          channel.options = {
            outbound: {
              adapter: adapter,
              options: params[:options],
            },
          }
          channel.status_out   = 'ok'
          channel.last_log_out = nil
        end
        channel.active = active
        channel.save
      }
    end
    render json: result
  end

  private

  def email_account_duplicate?(result, channel_id = nil)
    Channel.where(area: 'Email::Account').each { |channel|
      next if !channel.options
      next if !channel.options[:inbound]
      next if !channel.options[:inbound][:adapter]
      next if channel.options[:inbound][:adapter] != result[:setting][:inbound][:adapter]
      next if channel.options[:inbound][:options][:host] != result[:setting][:inbound][:options][:host]
      next if channel.options[:inbound][:options][:user] != result[:setting][:inbound][:options][:user]
      next if channel.id.to_s == channel_id.to_s
      render json: {
        result: 'duplicate',
        message: 'Account already exists!',
      }
      return true
    }
    false
  end

  def check_online_service
    return true if !Setting.get('system_online_service')
    raise Exceptions::NotAuthorized
  end

  def check_access(id = nil)
    if !id
      id = params[:id]
    end
    return true if !Setting.get('system_online_service')

    channel = Channel.find(id)
    return true if channel.preferences && !channel.preferences[:online_service_disable]

    raise Exceptions::NotAuthorized
  end
end
