# encoding: utf-8
require 'test_helper'
require 'rexml/document'

class TelegramControllerTest < ActionDispatch::IntegrationTest
  setup do
    @headers = { 'ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' }

    # configure telegram channel
    token = '291607826:AAH2dDv66JHL4D-Y_i7Q-mEvJmJ-5Rk7cgA'
    group_id = Group.find_by(name: 'Users').id
    #bot = Telegram.check_token(token)
    #Setting.set('http_type', 'http')
    Setting.set('http_type', 'https')
    Setting.set('fqdn', 'me.zammad.com')
    Channel.where(area: 'Telegram::Bot').destroy_all
    @channel = Telegram.create_or_update_channel(token, { group_id: group_id, welcome: 'hi!' })

    groups = Group.where(name: 'Users')
    roles  = Role.where(name: %w(Agent))
    agent  = User.create_or_update(
      login: 'telegram-agent@example.com',
      firstname: 'E',
      lastname: 'S',
      email: 'telegram-agent@example.com',
      password: 'agentpw',
      active: true,
      roles: roles,
      groups: groups,
      updated_by_id: 1,
      created_by_id: 1,
    )

  end

  test 'basic call' do
    Ticket.destroy_all

    # start communication #1
    post '/api/v1/channels/telegram_webhook', read_messaage('personal1_message_start'), @headers
    assert_response(404)
    result = JSON.parse(@response.body)

    post '/api/v1/channels/telegram_webhook/not_existing', read_messaage('personal1_message_start'), @headers
    assert_response(422)
    result = JSON.parse(@response.body)
    assert_equal('bot param missing', result['error'])

    callback_url = "/api/v1/channels/telegram_webhook/not_existing?bid=#{@channel.options[:bot][:id]}"
    post callback_url, read_messaage('personal1_message_start'), @headers
    assert_response(422)
    result = JSON.parse(@response.body)
    assert_equal('invalid callback token', result['error'])

    #url = 'api.telegram.org'
    #WebMock.stub_request(:any, url).to_return(
    #  body:    { data: [] }.to_json,
    #  headers: { 'Content-Type' => 'application/json' }
    #)

    callback_url = "/api/v1/channels/telegram_webhook/#{@channel.options[:callback_token]}?bid=#{@channel.options[:bot][:id]}"
    post callback_url, read_messaage('personal1_message_start'), @headers
    assert_response(200)

    # send message1
    post callback_url, read_messaage('personal1_message_content1'), @headers
    assert_response(200)
    assert_equal(1, Ticket.count)
    ticket = Ticket.last
    assert_equal('Hello, I need your Help', ticket.title)
    assert_equal('new', ticket.state.name)
    assert_equal(1, ticket.articles.count)
    assert_equal('Hello, I need your Help', ticket.articles.first.body)
    assert_equal('text/plain', ticket.articles.first.content_type)

    # send same message again, ignore it
    post callback_url, read_messaage('personal1_message_content1'), @headers
    assert_response(200)
    ticket = Ticket.last
    assert_equal('Hello, I need your Help', ticket.title)
    assert_equal('new', ticket.state.name)
    assert_equal(1, ticket.articles.count)
    assert_equal('Hello, I need your Help', ticket.articles.first.body)
    assert_equal('text/plain', ticket.articles.first.content_type)

    # send message2
    post callback_url, read_messaage('personal1_message_content2'), @headers
    assert_response(200)
    ticket = Ticket.last
    assert_equal('Hello, I need your Help', ticket.title)
    assert_equal('new', ticket.state.name)
    assert_equal(2, ticket.articles.count)
    assert_equal('Hello, I need your Help 2', ticket.articles.last.body)
    assert_equal('text/plain', ticket.articles.last.content_type)

    # send end message
    post callback_url, read_messaage('personal1_message_end'), @headers
    assert_response(200)
    ticket = Ticket.last
    assert_equal('Hello, I need your Help', ticket.title)
    assert_equal('closed', ticket.state.name)
    assert_equal(2, ticket.articles.count)
    assert_equal('Hello, I need your Help 2', ticket.articles.last.body)
    assert_equal('text/plain', ticket.articles.last.content_type)

    # start communication #2
    post callback_url, read_messaage('personal2_message_start'), @headers
    assert_response(200)

    # send message1
    post callback_url, read_messaage('personal2_message_content1'), @headers
    assert_response(200)
    assert_equal(2, Ticket.count)
    ticket = Ticket.last
    assert_equal('Can you help me with my feature?', ticket.title)
    assert_equal('new', ticket.state.name)
    assert_equal(1, ticket.articles.count)
    assert_equal('Can you help me with my feature?', ticket.articles.first.body)
    assert_equal('text/plain', ticket.articles.first.content_type)

    # send message2
    post callback_url, read_messaage('personal2_message_content2'), @headers
    assert_response(200)
    assert_equal(2, Ticket.count)
    ticket = Ticket.last
    assert_equal('Can you help me with my feature?', ticket.title)
    assert_equal('new', ticket.state.name)
    assert_equal(2, ticket.articles.count)
    assert_equal('Yes of course! <b>lalal</b>', ticket.articles.last.body)
    assert_equal('text/plain', ticket.articles.last.content_type)

    # start communication #3
    post callback_url, read_messaage('personal3_message_start'), @headers
    assert_response(200)

    # send message1
    post callback_url, read_messaage('personal3_message_content1'), @headers
    assert_response(200)
    assert_equal(3, Ticket.count)
    ticket = Ticket.last
    assert_equal('Can you help me with my feature?', ticket.title)
    assert_equal('new', ticket.state.name)
    assert_equal(1, ticket.articles.count)
    assert_equal('Can you help me with my feature?', ticket.articles.last.body)
    assert_equal('text/plain', ticket.articles.last.content_type)

    # send message2
    post callback_url, read_messaage('personal3_message_content2'), @headers
    assert_response(200)
    assert_equal(3, Ticket.count)
    ticket = Ticket.last
    assert_equal('Can you help me with my feature?', ticket.title)
    assert_equal('new', ticket.state.name)
    assert_equal(2, ticket.articles.count)
    assert_match(/<img style="width:360px;height:327px;"/i, ticket.articles.last.body)
    assert_equal('text/html', ticket.articles.last.content_type)

    # send message3
    post callback_url, read_messaage('personal3_message_content3'), @headers
    assert_response(200)
    assert_equal(3, Ticket.count)
    ticket = Ticket.last
    assert_equal('Can you help me with my feature?', ticket.title)
    assert_equal('new', ticket.state.name)
    assert_equal(3, ticket.articles.count)
    assert_match(/<img style="width:200px;height:200px;"/i, ticket.articles.last.body)
    assert_equal('text/html', ticket.articles.last.content_type)
    assert_equal(1, ticket.articles.last.attachments.count)

  end

  def read_messaage(file)
    #message = JSON.parse(File.read("test/fixtures/telegram/#{file}.json"))
    File.read("test/fixtures/telegram/#{file}.json")
  end
end
