# Copyright (C) 2012-2016 Zammad Foundation, http://zammad-foundation.org/
require 'exceptions'

class ApplicationController < ActionController::Base
  #  http_basic_authenticate_with :name => "test", :password => "ttt"

  helper_method :current_user,
                :authentication_check,
                :config_frontend,
                :http_log_config,
                :model_create_render,
                :model_update_render,
                :model_restory_render,
                :mode_show_rendeder,
                :model_index_render

  skip_before_action :verify_authenticity_token
  before_action :transaction_begin, :set_user, :session_update, :user_device_check, :cors_preflight_check
  after_action  :transaction_end, :http_log, :set_access_control_headers

  rescue_from StandardError, with: :server_error
  rescue_from ExecJS::RuntimeError, with: :server_error
  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActiveRecord::StatementInvalid, with: :unprocessable_entity
  rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity
  rescue_from ArgumentError, with: :unprocessable_entity
  rescue_from Exceptions::UnprocessableEntity, with: :unprocessable_entity
  rescue_from Exceptions::NotAuthorized, with: :unauthorized

  # For all responses in this controller, return the CORS access control headers.
  def set_access_control_headers
    headers['Access-Control-Allow-Origin']      = '*'
    headers['Access-Control-Allow-Methods']     = 'POST, GET, PUT, DELETE, OPTIONS'
    headers['Access-Control-Max-Age']           = '1728000'
    headers['Access-Control-Allow-Headers']     = 'Content-Type, Depth, User-Agent, X-File-Size, X-Requested-With, If-Modified-Since, X-File-Name, Cache-Control, Accept-Language'
    headers['Access-Control-Allow-Credentials'] = 'true'
  end

  # If this is a preflight OPTIONS request, then short-circuit the
  # request, return only the necessary headers and return an empty
  # text/plain.

  def cors_preflight_check

    return if request.method != 'OPTIONS'

    headers['Access-Control-Allow-Origin']      = '*'
    headers['Access-Control-Allow-Methods']     = 'POST, GET, PUT, DELETE, OPTIONS'
    headers['Access-Control-Allow-Headers']     = 'Content-Type, Depth, User-Agent, X-File-Size, X-Requested-With, If-Modified-Since, X-File-Name, Cache-Control, Accept-Language'
    headers['Access-Control-Max-Age']           = '1728000'
    headers['Access-Control-Allow-Credentials'] = 'true'
    render text: '', content_type: 'text/plain'

    false
  end

  def http_log_config(config)
    @http_log_support = config
  end

  private

  def transaction_begin
    ApplicationHandleInfo.current = 'application_server'
    PushMessages.init
  end

  def transaction_end
    Observer::Transaction.commit
    PushMessages.finish
    ActiveSupport::Dependencies::Reference.clear!
  end

  # Finds the User with the ID stored in the session with the key
  # :current_user_id This is a common way to handle user login in
  # a Rails application; logging in sets the session value and
  # logging out removes it.
  def current_user
    return @_current_user if @_current_user
    return if !session[:user_id]
    @_current_user = User.lookup(id: session[:user_id])
  end

  def current_user_set(user)
    session[:user_id] = user.id
    @_current_user = user
    set_user
  end

  # Sets the current user into a named Thread location so that it can be accessed
  # by models and observers
  def set_user
    if !current_user
      UserInfo.current_user_id = 1
      return
    end
    UserInfo.current_user_id = current_user.id
  end

  # update session updated_at
  def session_update
    #sleep 0.6

    session[:ping] = Time.zone.now.iso8601

    # check if remote ip need to be updated
    if !session[:remote_ip] || session[:remote_ip] != request.remote_ip
      session[:remote_ip]  = request.remote_ip
      session[:geo]        = Service::GeoIp.location(request.remote_ip)
    end

    # fill user agent
    return if session[:user_agent]

    session[:user_agent] = request.env['HTTP_USER_AGENT']
  end

  # log http access
  def http_log
    return if !@http_log_support

    # request
    request_data = {
      content: '',
      content_type: request.headers['Content-Type'],
      content_encoding: request.headers['Content-Encoding'],
      source: request.headers['User-Agent'] || request.headers['Server'],
    }
    request.headers.each { |key, value|
      next if key[0, 5] != 'HTTP_'
      request_data[:content] += if key == 'HTTP_COOKIE'
                                  "#{key}: xxxxx\n"
                                else
                                  "#{key}: #{value}\n"
                                end
    }
    body = request.body.read
    if body
      request_data[:content] += "\n" + body
    end
    request_data[:content] = request_data[:content].slice(0, 8000)

    # response
    response_data = {
      code: response.status = response.code,
      content: '',
      content_type: nil,
      content_encoding: nil,
      source: nil,
    }
    response.headers.each { |key, value|
      response_data[:content] += "#{key}: #{value}\n"
    }
    body = response.body
    if body
      response_data[:content] += "\n" + body
    end
    response_data[:content] = response_data[:content].slice(0, 8000)
    record = {
      direction: 'in',
      facility: @http_log_support[:facility],
      url: url_for(only_path: false, overwrite_params: {}),
      status: response.status,
      ip: request.remote_ip,
      request: request_data,
      response: response_data,
      method: request.method,
    }
    HttpLog.create(record)
  end

  def user_device_check
    return false if !user_device_log(current_user, 'session')
    true
  end

  def user_device_log(user, type)
    switched_from_user_id = ENV['SWITCHED_FROM_USER_ID'] || session[:switched_from_user_id]
    return true if params[:controller] == 'init' # do no device logging on static inital page
    return true if switched_from_user_id
    return true if !user
    return true if !user.permissions?('user_preferences.device')

    time_to_check = true
    user_device_updated_at = session[:user_device_updated_at]
    if ENV['USER_DEVICE_UPDATED_AT']
      user_device_updated_at = Time.zone.parse(ENV['USER_DEVICE_UPDATED_AT'])
    end

    if user_device_updated_at
      # check if entry exists / only if write action
      diff = Time.zone.now - 10.minutes
      method = request.method
      if method == 'GET' || method == 'OPTIONS' || method == 'HEAD'
        diff = Time.zone.now - 30.minutes
      end

      # only update if needed
      if user_device_updated_at > diff
        time_to_check = false
      end
    end

    # if ip has not changed and ttl in still valid
    remote_ip = ENV['TEST_REMOTE_IP'] || request.remote_ip
    return true if time_to_check == false && session[:user_device_remote_ip] == remote_ip
    session[:user_device_remote_ip] = remote_ip

    # for sessions we need the fingperprint
    if type == 'session'
      if !session[:user_device_updated_at] && !params[:fingerprint] && !session[:user_device_fingerprint]
        raise Exceptions::UnprocessableEntity, 'Need fingerprint param!'
      end
      if params[:fingerprint]
        session[:user_device_fingerprint] = params[:fingerprint]
      end
    end

    session[:user_device_updated_at] = Time.zone.now

    # add device if needed
    http_user_agent = ENV['HTTP_USER_AGENT'] || request.env['HTTP_USER_AGENT']
    Delayed::Job.enqueue(
      Observer::UserDeviceLogJob.new(
        http_user_agent,
        remote_ip,
        user.id,
        session[:user_device_fingerprint],
        type,
      )
    )
  end

  def authentication_check_only(auth_param)
    #logger.debug 'authentication_check'
    #logger.debug params.inspect
    #logger.debug session.inspect
    #logger.debug cookies.inspect

    # already logged in, early exit
    if session.id && session[:user_id]
      logger.debug 'session based auth check'
      user = User.lookup(id: session[:user_id])
      return authentication_check_prerequesits(user, 'session', auth_param) if user
    end

    # check sso based authentication
    sso_user = User.sso(params)
    if sso_user
      if authentication_check_prerequesits(sso_user, 'session', auth_param)
        session[:persistent] = true
        return sso_user
      end
    end

    # check http basic based authentication
    authenticate_with_http_basic do |username, password|
      request.session_options[:skip] = true # do not send a session cookie
      logger.debug "http basic auth check '#{username}'"
      if Setting.get('api_password_access') == false
        raise Exceptions::NotAuthorized, 'API password access disabled!'
      end
      user = User.authenticate(username, password)
      return authentication_check_prerequesits(user, 'basic_auth', auth_param) if user
    end

    # check http token based authentication
    authenticate_with_http_token do |token_string, _options|
      logger.debug "http token auth check '#{token_string}'"
      request.session_options[:skip] = true # do not send a session cookie
      if Setting.get('api_token_access') == false
        raise Exceptions::NotAuthorized, 'API token access disabled!'
      end
      user = Token.check(
        action: 'api',
        name: token_string,
        inactive_user: true,
      )
      if user && auth_param[:permission]
        user = Token.check(
          action: 'api',
          name: token_string,
          permission: auth_param[:permission],
          inactive_user: true,
        )
        raise Exceptions::NotAuthorized, 'Not authorized (token)!' if !user
      end

      if user
        token = Token.find_by(name: token_string)

        token.last_used_at = Time.zone.now
        token.save!

        if token.expires_at &&
           Time.zone.today >= token.expires_at
          raise Exceptions::NotAuthorized, 'Not authorized (token expired)!'
        end
      end

      @_token_auth = token_string # remember for permission_check
      return authentication_check_prerequesits(user, 'token_auth', auth_param) if user
    end

    # check oauth2 token based authentication
    token = Doorkeeper::OAuth::Token.from_bearer_authorization(request)
    if token
      request.session_options[:skip] = true # do not send a session cookie
      logger.debug "oauth2 token auth check '#{token}'"
      access_token = Doorkeeper::AccessToken.by_token(token)

      if !access_token
        raise Exceptions::NotAuthorized, 'Invalid token!'
      end

      # check expire
      if access_token.expires_in && (access_token.created_at + access_token.expires_in) < Time.zone.now
        raise Exceptions::NotAuthorized, 'OAuth2 token is expired!'
      end

      # if access_token.scopes.empty?
      #   raise Exceptions::NotAuthorized, 'OAuth2 scope missing for token!'
      # end

      user = User.find(access_token.resource_owner_id)
      return authentication_check_prerequesits(user, 'token_auth', auth_param) if user
    end

    false
  end

  def authentication_check_prerequesits(user, auth_type, auth_param)
    if check_maintenance_only(user)
      raise Exceptions::NotAuthorized, 'Maintenance mode enabled!'
    end

    if user.active == false
      raise Exceptions::NotAuthorized, 'User is inactive!'
    end

    # check scopes / permission check
    if auth_param[:permission] && !user.permissions?(auth_param[:permission])
      raise Exceptions::NotAuthorized, 'Not authorized (user)!'
    end

    current_user_set(user)
    user_device_log(user, auth_type)
    logger.debug "#{auth_type} for '#{user.login}'"
    true
  end

  def authentication_check(auth_param = {})
    user = authentication_check_only(auth_param)

    # check if basic_auth fallback is possible
    if auth_param[:basic_auth_promt] && !user
      return request_http_basic_authentication
    end

    # return auth not ok
    if !user
      raise Exceptions::NotAuthorized, 'authentication failed'
    end

    # return auth ok
    true
  end

  def ticket_permission(ticket)
    return true if ticket.permission(current_user: current_user)
    raise Exceptions::NotAuthorized
  end

  def article_permission(article)
    ticket = Ticket.lookup(id: article.ticket_id)
    return true if ticket.permission(current_user: current_user)
    raise Exceptions::NotAuthorized
  end

  def article_create(ticket, params)

    # create article if given
    form_id = params[:form_id]
    params.delete(:form_id)

    # check min. params
    raise Exceptions::UnprocessableEntity, 'Need at least article: { body: "some text" }' if !params[:body]

    # fill default values
    if params[:type_id].empty? && params[:type].empty?
      params[:type_id] = Ticket::Article::Type.lookup(name: 'note').id
    end
    if params[:sender_id].empty? && params[:sender].empty?
      sender = 'Customer'
      if current_user.permissions?('ticket.agent')
        sender = 'Agent'
      end
      params[:sender_id] = Ticket::Article::Sender.lookup(name: sender).id
    end

    # remember time accounting
    time_unit = params[:time_unit]

    clean_params = Ticket::Article.param_association_lookup(params)
    clean_params = Ticket::Article.param_cleanup(clean_params, true)

    # overwrite params
    if !current_user.permissions?('ticket.agent')
      clean_params[:sender_id] = Ticket::Article::Sender.lookup(name: 'Customer').id
      clean_params.delete(:sender)
      type = Ticket::Article::Type.lookup(id: clean_params[:type_id])
      if type.name !~ /^(note|web)$/
        clean_params[:type_id] = Ticket::Article::Type.lookup(name: 'note').id
      end
      clean_params.delete(:type)
      clean_params[:internal] = false
    end

    article = Ticket::Article.new(clean_params)
    article.ticket_id = ticket.id

    # store dataurl images to store
    if form_id && article.body && article.content_type =~ %r{text/html}i
      article.body.gsub!( %r{(<img\s.+?src=")(data:image/(jpeg|png);base64,.+?)">}i ) { |_item|
        file_attributes = StaticAssets.data_url_attributes($2)
        cid = "#{ticket.id}.#{form_id}.#{rand(999_999)}@#{Setting.get('fqdn')}"
        headers_store = {
          'Content-Type' => file_attributes[:mime_type],
          'Mime-Type' => file_attributes[:mime_type],
          'Content-ID' => cid,
          'Content-Disposition' => 'inline',
        }
        store = Store.add(
          object: 'UploadCache',
          o_id: form_id,
          data: file_attributes[:content],
          filename: cid,
          preferences: headers_store
        )
        "#{$1}cid:#{cid}\">"
      }
    end

    # find attachments in upload cache
    if form_id
      article.attachments = Store.list(
        object: 'UploadCache',
        o_id: form_id,
      )
    end
    article.save!

    # account time
    if time_unit.present?
      Ticket::TimeAccounting.create!(
        ticket_id: article.ticket_id,
        ticket_article_id: article.id,
        time_unit: time_unit
      )
    end

    # remove attachments from upload cache
    return article if !form_id

    Store.remove(
      object: 'UploadCache',
      o_id: form_id,
    )

    article
  end

  def permission_check(key)
    if @_token_auth
      user = Token.check(
        action: 'api',
        name: @_token_auth,
        permission: key,
      )
      return false if user
      raise Exceptions::NotAuthorized, 'Not authorized (token)!'
    end

    return false if current_user && current_user.permissions?(key)
    raise Exceptions::NotAuthorized, 'Not authorized (user)!'
  end

  def valid_session_with_user
    return true if current_user
    raise Exceptions::UnprocessableEntity, 'No session user!'
  end

  def response_access_deny
    raise Exceptions::NotAuthorized
  end

  def config_frontend

    # config
    config = {}
    Setting.select('name, preferences').where(frontend: true).each { |setting|
      next if setting.preferences[:authentication] == true && !current_user
      value = Setting.get(setting.name)
      next if !current_user && (value == false || value.nil?)
      config[setting.name] = value
    }

    # remember if we can to swich back to user
    if session[:switched_from_user_id]
      config['switch_back_to_possible'] = true
    end

    # remember session_id for websocket logon
    if current_user
      config['session_id'] = session.id
    end

    config
  end

  # model helper
  def model_create_render(object, params)

    clean_params = object.param_association_lookup(params)
    clean_params = object.param_cleanup(clean_params, true)

    # create object
    generic_object = object.new(clean_params)

    # save object
    generic_object.save!

    # set relations
    generic_object.param_set_associations(params)

    if params[:expand]
      render json: generic_object.attributes_with_relation_names, status: :created
      return
    end

    model_create_render_item(generic_object)
  end

  def model_create_render_item(generic_object)
    render json: generic_object.attributes_with_associations, status: :created
  end

  def model_update_render(object, params)

    # find object
    generic_object = object.find(params[:id])

    clean_params = object.param_association_lookup(params)
    clean_params = object.param_cleanup(clean_params, true)

    generic_object.with_lock do

      # set attributes
      generic_object.update_attributes!(clean_params)

      # set relations
      generic_object.param_set_associations(params)
    end

    if params[:expand]
      render json: generic_object.attributes_with_relation_names, status: :ok
      return
    end

    model_update_render_item(generic_object)
  end

  def model_update_render_item(generic_object)
    render json: generic_object.attributes_with_associations, status: :ok
  end

  def model_destroy_render(object, params)
    generic_object = object.find(params[:id])
    generic_object.destroy!
    model_destroy_render_item()
  end

  def model_destroy_render_item ()
    render json: {}, status: :ok
  end

  def model_show_render(object, params)

    if params[:expand]
      generic_object = object.find(params[:id])
      render json: generic_object.attributes_with_relation_names, status: :ok
      return
    end

    if params[:full]
      generic_object_full = object.full(params[:id])
      render json: generic_object_full, status: :ok
      return
    end

    generic_object = object.find(params[:id])
    model_show_render_item(generic_object)
  end

  def model_show_render_item(generic_object)
    render json: generic_object.attributes_with_associations, status: :ok
  end

  def model_index_render(object, params)
    offset = 0
    per_page = 500
    if params[:page] && params[:per_page]
      offset = (params[:page].to_i - 1) * params[:per_page].to_i
      limit = params[:per_page].to_i
    end

    if per_page > 500
      per_page = 500
    end

    generic_objects = if offset.positive?
                        object.limit(params[:per_page]).order(id: 'ASC').offset(offset).limit(limit)
                      else
                        object.all.order(id: 'ASC').offset(offset).limit(limit)
                      end

    if params[:expand]
      list = []
      generic_objects.each { |generic_object|
        list.push generic_object.attributes_with_relation_names
      }
      render json: list, status: :ok
      return
    end

    if params[:full]
      assets = {}
      item_ids = []
      generic_objects.each { |item|
        item_ids.push item.id
        assets = item.assets(assets)
      }
      render json: {
        record_ids: item_ids,
        assets: assets,
      }, status: :ok
      return
    end

    generic_objects_with_associations = []
    generic_objects.each { |item|
      generic_objects_with_associations.push item.attributes_with_associations
    }
    model_index_render_result(generic_objects_with_associations)
  end

  def model_index_render_result(generic_objects)
    render json: generic_objects, status: :ok
  end

  def model_match_error(error)
    data = {
      error: error
    }
    if error =~ /Validation failed: (.+?)(,|$)/i
      data[:error_human] = $1
    end
    if error =~ /(already exists|duplicate key|duplicate entry)/i
      data[:error_human] = 'Object already exists!'
    end
    if error =~ /null value in column "(.+?)" violates not-null constraint/i
      data[:error_human] = "Attribute '#{$1}' required!"
    end
    if error =~ /Field '(.+?)' doesn't have a default value/i
      data[:error_human] = "Attribute '#{$1}' required!"
    end

    if Rails.env.production? && !data[:error_human].empty?
      data[:error] = data[:error_human]
      data.delete('error_human')
    end
    data
  end

  def model_references_check(object, params)
    generic_object = object.find(params[:id])
    result = Models.references(object, generic_object.id)
    return false if result.empty?
    raise Exceptions::UnprocessableEntity, 'Can\'t delete, object has references.'
  rescue => e
    raise Exceptions::UnprocessableEntity, e
  end

  def not_found(e)
    logger.error e.message
    logger.error e.backtrace.inspect
    respond_to do |format|
      format.json { render json: model_match_error(e.message), status: :not_found }
      format.any {
        @exception = e
        @traceback = !Rails.env.production?
        file = File.open(Rails.root.join('public', '404.html'), 'r')
        render inline: file.read, status: :not_found
      }
    end
  end

  def unprocessable_entity(e)
    logger.error e.message
    logger.error e.backtrace.inspect
    respond_to do |format|
      format.json { render json: model_match_error(e.message), status: :unprocessable_entity }
      format.any {
        @exception = e
        @traceback = !Rails.env.production?
        file = File.open(Rails.root.join('public', '422.html'), 'r')
        render inline: file.read, status: :unprocessable_entity
      }
    end
  end

  def server_error(e)
    logger.error e.message
    logger.error e.backtrace.inspect
    respond_to do |format|
      format.json { render json: model_match_error(e.message), status: 500 }
      format.any {
        @exception = e
        @traceback = !Rails.env.production?
        file = File.open(Rails.root.join('public', '500.html'), 'r')
        render inline: file.read, status: 500
      }
    end
  end

  def unauthorized(e)
    message = e.message
    if message == 'Exceptions::NotAuthorized'
      message = 'Not authorized'
    end
    error = model_match_error(message)
    if error && error[:error]
      response.headers['X-Failure'] = error[:error_human] || error[:error]
    end
    respond_to do |format|
      format.json { render json: error, status: :unauthorized }
      format.any {
        @exception = e
        @traceback = !Rails.env.production?
        file = File.open(Rails.root.join('public', '401.html'), 'r')
        render inline: file.read, status: :unauthorized
      }
    end
  end

  # check maintenance mode
  def check_maintenance_only(user)
    return false if Setting.get('maintenance_mode') != true
    return false if user.permissions?('admin.maintenance')
    Rails.logger.info "Maintenance mode enabled, denied login for user #{user.login}, it's no admin user."
    true
  end

  def check_maintenance(user)
    return false if !check_maintenance_only(user)
    raise Exceptions::NotAuthorized, 'Maintenance mode enabled!'
  end

end
