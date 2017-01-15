class App.TicketCreate extends App.Controller
  elements:
    '.tabsSidebar': 'sidebar'

  events:
    'click .type-tabs .tab': 'changeFormType'
    'submit form':           'submit'
    'click .js-cancel':      'cancel'

  constructor: (params) ->
    super

    # define default type
    @default_type = 'phone-in'

    # remember split info if exists
    @split = ''
    if @ticket_id && @article_id
      @split = "/#{@ticket_id}/#{@article_id}"

    load = (data) =>
      App.Collection.loadAssets(data.assets)
      @formMeta = data.form_meta
      @buildScreen(params)
    @bindId = App.TicketCreateCollection.one(load)

    # lisen if view need to be rerendered
    @bind 'ticket_create_rerender', (defaults) =>
      @log 'notice', 'error', defaults
      @render(defaults)

    # rerender view, e. g. on langauge change
    @bind 'ui:rerender', =>
      return if !@authenticateCheck()
      @render()

  release: =>
    App.TicketCreateCollection.unbindById(@bindId)

  currentChannel: =>
    if !type
      type = @$('.type-tabs .tab.active').data('type')
    if !type
      type = @default_type
    type

  changeFormType: (e) =>
    type = $(e.currentTarget).data('type')
    @setFormTypeInUi(type)

  setFormTypeInUi: (type) =>

    # detect current form type
    if !type
      type = @currentChannel()

    # reset all tabs
    tabs = @$('.type-tabs .tab')
    tabs.removeClass('active')
    tabIcons = @$('.type-tabs .tab .icon')
    tabIcons.addClass('gray')
    tabIcons.removeClass('white')

    # set active tab
    selectedTab = @$(".type-tabs .tab[data-type='#{type}']")
    selectedTab.addClass('active')

    # set form type attributes
    articleSenderTypeMap =
      'phone-in':
        sender:  'Customer'
        article: 'phone'
        title:   'Call Inbound'
        screen:  'create_phone_in'
      'phone-out':
        sender:  'Agent'
        article: 'phone'
        title:   'Call Outbound'
        screen:  'create_phone_out'
      'email-out':
        sender:  'Agent'
        article: 'email'
        title:   'Email'
        screen:  'create_email_out'
    @articleAttributes = articleSenderTypeMap[type]

    # update form
    @$('[name="formSenderType"]').val(type)

    # force changing signature
    @$('[name="group_id"]').trigger('change')

    # show cc
    if type is 'email-out'
      @$('[name="cc"]').closest('.form-group').removeClass('hide')
    else
      @$('[name="cc"]').closest('.form-group').addClass('hide')

  meta: =>
    text = ''
    if @articleAttributes
      text = App.i18n.translateInline(@articleAttributes['title'])
    title = @$('[name=title]').val()
    if title
      text = "#{text}: #{title}"
    meta =
      url:   @url()
      head:  text
      title: text
      id:    @id
      iconClass: 'pen'

  url: =>
    "#ticket/create/id/#{@id}"

  show: =>
    @navupdate "#ticket/create/id/#{@id}#{@split}", type: 'menu'
    @autosaveStart()

  hide: =>
    @autosaveStop()

  changed: =>
    formCurrent = @formParam( @$('.ticket-create') )
    diff = difference(@formDefault, formCurrent)
    return false if !diff || _.isEmpty(diff)
    return true

  autosaveStop: =>
    @clearDelay('ticket-create-form-update')
    @el.off('change.local blur.local keyup.local paste.local input.local')

  autosaveStart: =>
    if !@autosaveLast
      task = App.TaskManager.get(@task_key)
      if task && !task.state
        task.state = {}
      @autosaveLast = task.state || {}
    update = =>
      data = @formParam(@$('.ticket-create'))
      return if _.isEmpty(data)
      diff = difference(@autosaveLast, data)
      if _.isEmpty(@autosaveLast) || !_.isEmpty(diff)
        @autosaveLast = data
        @log 'debug', 'form hash changed', diff, data
        App.TaskManager.update(@task_key, { 'state': data })

        # check it task title in task need to be updated
        if @latestTitle isnt data.title
          @latestTitle = data.title
          App.TaskManager.touch(@task_key)

    @el.on('change.local blur.local keyup.local paste.local input.local', 'form, .js-textarea', (e) =>
      @delay(update, 250, 'ticket-create-form-update')
    )
    @delay(update, 800, 'ticket-create-form-update')

  # get data / in case also ticket data for split
  buildScreen: (params) =>

    if !params.ticket_id && !params.article_id
      if !_.isEmpty(params.customer_id)
        @render(options: { customer_id: params.customer_id })
        return
      @render()
      return

    # fetch split ticket data
    @ajax(
      id:    "ticket_split#{@task_key}"
      type:  'GET'
      url:   "#{@apiPath}/ticket_split"
      data:
        ticket_id: params.ticket_id
        article_id: params.article_id
      processData: true
      success: (data, status, xhr) =>

        # load assets
        App.Collection.loadAssets(data.assets)

        # prefill with split ticket
        t = App.Ticket.find(params.ticket_id).attributes()
        a = App.TicketArticle.find(params.article_id)

        # reset owner
        t.owner_id               = 0
        t.customer_id_completion = a.from
        t.subject                = a.subject || t.title

        # convert non text/html from text 2 html
        if a.content_type.match(/\/html/)
          t.body = a.body
        else
          t.body  = App.Utils.text2html(a.body)

        # render page
        @render(options: t)
    )

  render: (template = {}) ->

    # get params
    params = {}
    if template && !_.isEmpty(template.options)
      params = template.options
    else if App.TaskManager.get(@task_key) && !_.isEmpty(App.TaskManager.get(@task_key).state)
      params = App.TaskManager.get(@task_key).state

    if params['form_id']
      @form_id = params['form_id']
    else
      @form_id = App.ControllerForm.formId()

    @html App.view('agent_ticket_create')(
      head:    'New Ticket'
      agent:   @permissionCheck('ticket.agent')
      admin:   @permissionCheck('admin')
      form_id: @form_id
    )

    signatureChanges = (params, attribute, attributes, classname, form, ui) =>
      if attribute && attribute.name is 'group_id'
        signature = undefined
        if params['group_id']
          group = App.Group.find(params['group_id'])
          if group && group.signature_id
            signature = App.Signature.find(group.signature_id)

        # check if signature need to be added
        type = @$('[name="formSenderType"]').val()

        if signature isnt undefined &&  signature.body && type is 'email-out'
          signatureFinished = App.Utils.replaceTags(signature.body, { user: App.Session.get() })

          body = @$('[data-name=body]')
          if App.Utils.signatureCheck(body.html() || '', signatureFinished)

            # if signature has changed, in case remove old signature
            signature_id = @$('[data-signature=true]').data('signature-id')
            if signature_id && signature_id.toString() isnt signature.id.toString()

              @$('[data-signature="true"]').remove()

            if !App.Utils.htmlLastLineEmpty(body)
              body.append('<br><br>')
            signature = $("<div data-signature=\"true\" data-signature-id=\"#{signature.id}\">#{signatureFinished}</div>")
            App.Utils.htmlStrip(signature)
            body.append(signature)
            @$('[data-name=body]').replaceWith(body)

        # remove old signature
        else
          @$('[data-name="body"]').find('[data-signature=true]').remove()

    App.Ticket.configure_attributes.push {
      name: 'cc'
      display: 'Cc'
      tag: 'input'
      type: 'text'
      maxlength: 1000
      null: true
      screen: {
        create_top: {
          Agent: {
            null: true
          }
        }
        create_middle: {}
        edit: {}
      }
    }
    new App.ControllerForm(
      el:       @$('.ticket-form-top')
      form_id:  @form_id
      model:    App.Ticket
      screen:   'create_top'
      events:
        'change [name=customer_id]': @localUserInfo
      handlers: [
        @ticketFormChanges,
        signatureChanges,
      ]
      filter:    @formMeta.filter
      autofocus: true
      params:    params
    )

    new App.ControllerForm(
      el:      @$('.article-form-top')
      form_id: @form_id
      model:   App.TicketArticle
      screen:  'create_top'
      params:  params
    )
    new App.ControllerForm(
      el:      @$('.ticket-form-middle')
      form_id: @form_id
      model:   App.Ticket
      screen:  'create_middle'
      events:
        'change [name=customer_id]': @localUserInfo
      handlers: [
        @ticketFormChanges,
        signatureChanges,
      ]
      filter:     @formMeta.filter
      params:     params
      noFieldset: true
    )
    new App.ControllerForm(
      el:       @$('.ticket-form-bottom')
      form_id:  @form_id
      model:    App.Ticket
      screen:   'create_bottom'
      events:
        'change [name=customer_id]': @localUserInfo
      handlers: [
        @ticketFormChanges,
        signatureChanges,
      ]
      filter:   @formMeta.filter
      params:   params
    )
    App.Ticket.configure_attributes.pop()

    # set type selector
    @setFormTypeInUi( params['formSenderType'] )

    # remember form params of init load
    @formDefault = @formParam( @$('.ticket-create') )

    # show text module UI
    @textModule = new App.WidgetTextModule(
      el: @$('[data-name="body"]').parent()
    )

    new Sidebar(
      el:         @sidebar
      params:     @formDefault
      textModule: @textModule
    )

    $('#tags').tokenfield()

    # update taskbar with new meta data
    App.TaskManager.touch(@task_key)

  localUserInfo: (e) =>

    params = App.ControllerForm.params($(e.target).closest('form'))

    new Sidebar(
      el:         @sidebar
      params:     params
      textModule: @textModule
    )

  cancel: (e) ->
    e.preventDefault()
    @navigate '#'

  submit: (e) =>
    e.preventDefault()

    # get params
    params = @formParam(e.target)

    # fillup params
    if !params.title
      params.title = params.subject

    # create ticket
    ticket = new App.Ticket

    # find sender_id
    sender = App.TicketArticleSender.findByAttribute('name', @articleAttributes['sender'])
    type   = App.TicketArticleType.findByAttribute('name', @articleAttributes['article'])

    if params.group_id
      group  = App.Group.find(params.group_id)

    # add linked objects if ticket got splited
    if @ticket_id
      params['links'] =
        Ticket:
          child: [@ticket_id]

    # allow cc only on email tickets
    if @currentChannel() isnt 'email-out'
      delete params.cc

    # create article
    if sender.name is 'Customer'
      params['article'] = {
        to:           (group && group.name) || ''
        from:         params.customer_id_completion
        cc:           params.cc
        subject:      params.subject
        body:         params.body
        type_id:      type.id
        sender_id:    sender.id
        form_id:      @form_id
        content_type: 'text/html'
      }
    else
      params['article'] = {
        from:         (group && group.name) || ''
        to:           params.customer_id_completion
        cc:           params.cc
        subject:      params.subject
        body:         params.body
        type_id:      type.id
        sender_id:    sender.id
        form_id:      @form_id
        content_type: 'text/html'
      }

    ticket.load(params)

    ticketErrorsTop = ticket.validate(
      screen: 'create_top'
    )
    ticketErrorsMiddle = ticket.validate(
      screen: 'create_middle'
    )
    ticketErrorsBottom = ticket.validate(
      screen: 'create_bottom'
    )

    article = new App.TicketArticle
    article.load(params['article'])
    articleErrors = article.validate(
      screen: 'create_top'
    )

    # collect whole validation result
    errors = {}
    errors = _.extend(errors, ticketErrorsTop)
    errors = _.extend(errors, ticketErrorsMiddle)
    errors = _.extend(errors, ticketErrorsBottom)
    errors = _.extend(errors, articleErrors)

    # show errors in form
    if !_.isEmpty(errors)
      @log 'error', errors
      @formValidate(
        form:   e.target
        errors: errors
      )
      return

    # save ticket, create article
    # check attachment
    if article['body']
      if @$('.richtext .attachments .attachment').length < 1
        matchingWord = App.Utils.checkAttachmentReference(article['body'])
        if matchingWord
          if !confirm(App.i18n.translateContent('You use %s in text but no attachment is attached. Do you want to continue?', matchingWord))
            return

    # disable form
    @formDisable(e)
    ui = @
    ticket.save(
      done: ->

        # notify UI
        ui.notify
          type:    'success'
          msg:     App.i18n.translateInline('Ticket %s created!', @number)
          link:    "#ticket/zoom/#{@id}"
          timeout: 4000

        # close ticket create task
        App.TaskManager.remove(ui.task_key)

        # scroll to top
        ui.scrollTo()

        # access to group
        group_ids = _.map(App.Session.get('group_ids'), (id) -> id.toString())
        if group_ids && _.contains(group_ids, @group_id.toString())
          ui.navigate "#ticket/zoom/#{@id}"
          return

        # if not, show start screen
        ui.navigate '#'

      fail: (settings, details) ->
        ui.log 'errors', details
        ui.formEnable(e)
        ui.notify(
          type:    'error'
          msg:     App.i18n.translateContent(details.error_human || details.error || 'Unable to create object!')
          timeout: 6000
        )
    )

class Sidebar extends App.Controller
  constructor: ->
    super

    # load user
    if @params['customer_id']
      App.User.full(@params['customer_id'], @render)
      return

    # render ui
    @render()

  render: (user) =>

    items = []
    if user

      showCustomer = (el) =>
        # update text module UI
        if @textModule
          @textModule.reload(
            ticket:
              customer: user
            user: App.Session.get()
          )

        new App.WidgetUser(
          el:      el
          user_id: user.id
        )

      editCustomer = (e, el) =>
        new App.ControllerGenericEdit(
          id: @params.customer_id
          genericObject: 'User'
          screen: 'edit'
          pageData:
            title:   'Users'
            object:  'User'
            objects: 'Users'
          container: @el.closest('.content')
        )
      items.push {
        head: 'Customer'
        name: 'customer'
        icon: 'person'
        actions: [
          {
            title:    'Edit Customer'
            name:     'Edit Customer'
            class:    'glyphicon glyphicon-edit'
            callback: editCustomer
          },
        ]
        callback: showCustomer
      }

      if user.organization_id
        editOrganization = (e, el) =>
          new App.ControllerGenericEdit(
            id: user.organization_id
            genericObject: 'Organization'
            pageData:
              title:   'Organizations'
              object:  'Organization'
              objects: 'Organizations'
            container: @el.closest('.content')
          )
        showOrganization = (el) ->
          new App.WidgetOrganization(
            el:              el
            organization_id: user.organization_id
          )
        items.push {
          head: 'Organization'
          name: 'organization'
          icon: 'group'
          actions: [
            {
              title:    'Edit Organization'
              name:     'Edit Organization'
              class:    'glyphicon glyphicon-edit'
              callback: editOrganization
            },
          ]
          callback: showOrganization
        }

    showTemplates = (el) ->

      # show template UI
      new App.WidgetTemplate(
        el:          el
        #template_id: template['id']
      )

    items.push {
      head: 'Templates'
      name: 'template'
      icon: 'templates'
      callback: showTemplates
    }

    new App.Sidebar(
      el:    @el
      items: items
    )

class Router extends App.ControllerPermanent
  requiredPermission: 'ticket.agent'
  constructor: (params) ->
    super

    # create new uniq form id
    if !params['id']
      # remember split info if exists
      split = ''
      if params['ticket_id'] && params['article_id']
        split = "/#{params['ticket_id']}/#{params['article_id']}"

      if params.customer_id
        split = "/customer/#{params.customer_id}"

      id = Math.floor( Math.random() * 99999 )
      @navigate "#ticket/create/id/#{id}#{split}"
      return

    # cleanup params
    clean_params =
      ticket_id:   params.ticket_id
      article_id:  params.article_id
      type:        params.type
      customer_id: params.customer_id
      id:          params.id

    App.TaskManager.execute(
      key:        "TicketCreateScreen-#{params['id']}"
      controller: 'TicketCreate'
      params:     clean_params
      show:       true
    )

# create new ticket routes/controller
App.Config.set('ticket/create', Router, 'Routes')
App.Config.set('ticket/create/', Router, 'Routes')
App.Config.set('ticket/create/id/:id', Router, 'Routes')
App.Config.set('ticket/create/customer/:customer_id', Router, 'Routes')
App.Config.set('ticket/create/id/:id/customer/:customer_id', Router, 'Routes')

# split ticket
App.Config.set('ticket/create/:ticket_id/:article_id', Router, 'Routes')
App.Config.set('ticket/create/id/:id/:ticket_id/:article_id', Router, 'Routes')

# set new actions
App.Config.set('TicketCreate', { prio: 8003, parent: '#new', name: 'New Ticket', translate: true, target: '#ticket/create', permission: ['ticket.agent'], divider: true }, 'NavBarRight')
