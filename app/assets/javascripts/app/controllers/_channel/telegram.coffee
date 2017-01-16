class Index extends App.ControllerSubContent
  requiredPermission: 'admin.channel_telegram'
  events:
    'click .js-new':       'new'
    'click .js-edit':      'edit'
    'click .js-delete':    'delete'
    'click .js-disable':   'disable'
    'click .js-enable':    'enable'

  constructor: ->
    super

    #@interval(@load, 60000)
    @load()

  load: =>
    @startLoading()
    @ajax(
      id:   'telegram_index'
      type: 'GET'
      url:  "#{@apiPath}/channels/telegram_index"
      processData: true
      success: (data, status, xhr) =>
        @stopLoading()
        App.Collection.loadAssets(data.assets)
        @render(data)
    )

  render: (data) =>

    channels = []
    for channel_id in data.channel_ids
      channel = App.Channel.find(channel_id)
      if channel && channel.options
        displayName = '-'
        if channel.options.group_id
          group = App.Group.find(channel.options.group_id)
          displayName = group.displayName()
        channel.options.groupName = displayName
      channels.push channel
    @html App.view('telegram/index')(
      channels: channels
    )
      # accounts: accounts
      # showDescription: showDescription
      # description:     description

    if @channel_id
      @edit(undefined, @channel_id)
      @channel_id = undefined

  show: (params) =>
    for key, value of params
      if key isnt 'el' && key isnt 'shown' && key isnt 'match'
        @[key] = value

  new: (e) =>
    e.preventDefault()
    channel_id = $(e.target).closest('.action').data('id')
    new BotAdd(
      container: @el.parents('.content'),
      load: @load
    )

  edit: (e, id) =>
    if e
      e.preventDefault()
      id = $(e.target).closest('.action').data('id')
    channel = App.Channel.find(id)
    if !channel
      @navigate '#channels/telegram'
      return

    new BotEdit(
      channel: channel
      container: @el.parents('.content')
      load: @load
    )

  delete: (e) =>
    e.preventDefault()
    id   = $(e.target).closest('.action').data('id')
    item = App.Channel.find(id)
    new App.ControllerGenericDestroyConfirm(
      item:      item
      container: @el.closest('.content')
      callback:  @load
    )

  disable: (e) =>
    e.preventDefault()
    id   = $(e.target).closest('.action').data('id')
    item = App.Channel.find(id)
    item.active = false
    item.save(
      done: =>
        @load()
      fail: =>
        @load()
    )

  enable: (e) =>
    e.preventDefault()
    id   = $(e.target).closest('.action').data('id')
    item = App.Channel.find(id)
    item.active = true
    item.save(
      done: =>
        @load()
      fail: =>
        @load()
    )

  description: (e) =>
    new App.ControllerGenericDescription(
      description: App.Telegram.description
      container:   @el.closest('.content')
    )


class BotAdd extends App.ControllerModal
  head: 'Add Telegram Bot'
  shown: true
  button: 'Add'
  buttonCancel: true
  small: true

  content: ->
    @external_credential = App.ExternalCredential.findByAttribute('name', 'telegram')
    content = $(App.view('telegram/bot_add')(
      external_credential: @external_credential
    ))
    createGroupSelection = (selected_id, prefix) ->
      return App.UiElement.select.render(
        name: "#{prefix}::group_id"
        multiple: false
        limit: 100
        null: false
        relation: 'Group'
        nulloption: true
        value: selected_id
        class: 'form-control--small'
      )

    content.find('.js-select').on('click', (e) =>
      @selectAll(e)
    )
    content.find('.js-messagesGroup').replaceWith createGroupSelection(1, 'messages')
    content

  onClosed: =>
    return if !@isChanged
    @isChanged = false
    @load()

  onSubmit: (e) =>
    @formDisable(e)

    # verify app credentals
    @ajax(
      id:   'telegram_app_verify'
      type: 'POST'
      url:  "#{@apiPath}/channels/telegram_add"
      data: JSON.stringify(@formParams())
      processData: true
      success: (data, status, xhr) =>
        @isChanged = true
        @close()
      fail: =>
        @formEnable(e)
        @el.find('.alert').removeClass('hidden').text(data.error || 'Unable to save Bot.')
    )

class BotEdit extends App.ControllerModal
  head: 'Telegram Account'
  shown: true
  buttonCancel: true

  content: ->
    content = $( App.view('telegram/bot_edit')(channel: @channel) )

    createGroupSelection = (selected_id, prefix) ->
      return App.UiElement.select.render(
        name: "#{prefix}::group_id"
        multiple: false
        limit: 100
        null: false
        relation: 'Group'
        nulloption: true
        value: selected_id
        class: 'form-control--small'
      )


    content.find('.js-messagesGroup').replaceWith createGroupSelection(@channel.options.group_id, 'messages')
    content

  onClosed: =>
    return if !@isChanged
    @isChanged = false
    @load()

  onSubmit: (e) =>
    @formDisable(e)
    params = @formParams()
    search = []
    position = 0
    @channel.options = params
    @ajax(
      id:   'channel_telegram_update'
      type: 'POST'
      url:  "#{@apiPath}/channels/telegram_update/#{@channel.id}"
      data: JSON.stringify(@formParams())
      processData: true
      success: (data, status, xhr) =>
        @isChanged = true
        @close()
      fail: =>
        @formEnable(e)
        @el.find('.alert').removeClass('hidden').text(data.error || 'Unable to save changes.')
    )

App.Config.set('Telegram', { prio: 5100, name: 'Telegram', parent: '#channels', target: '#channels/telegram', controller: Index, permission: ['admin.channel_telegram'] }, 'NavBarAdmin')
