# coffeelint: disable=no_unnecessary_double_quotes
class App.Utils

  # textCleand = App.Utils.textCleanup(rawText)
  @textCleanup: (ascii) ->
    $.trim( ascii )
      .replace(/(\r\n|\n\r)/g, "\n")  # cleanup
      .replace(/\r/g, "\n")           # cleanup
      .replace(/[ ]\n/g, "\n")        # remove tailing spaces
      .replace(/\n{3,20}/g, "\n\n")   # remove multiple empty lines

  # htmlEscapedAndLinkified = App.Utils.text2html(rawText)
  @text2html: (ascii) ->
    ascii = @textCleanup(ascii)
    #ascii = @htmlEscape(ascii)
    ascii = @linkify(ascii)
    ascii = '<div>' + ascii.replace(/\n/g, '</div><div>') + '</div>'
    ascii.replace(/<div><\/div>/g, '<div><br></div>')

  # rawText = App.Utils.html2text(html, no_trim)
  @html2text: (html, no_trim) ->
    return html if !html

    if no_trim
      html = html
        .replace(/([A-z])\n([A-z])/gm, '$1 $2')
        .replace(/\n|\r/g, '')
        .replace(/<(br|hr)>/g, "\n")
        .replace(/<(br|hr)\/>/g, "\n")
        .replace(/<\/(div|p|blockquote|form|textarea|address|tr)>/g, "\n")
      return $('<div>' + html + '</div>').text()

    # remove not needed new lines
    html = html.replace(/([A-z])\n([A-z])/gm, '$1 $2')
      .replace(/>\n/g, '>')
      .replace(/\n|\r/g, '')

    # trim and cleanup
    html = html
      .replace(/<(br|hr)>/g, "\n")
      .replace(/<(br|hr)\/>/g, "\n")
      .replace(/<(div)(|.+?)>/g, "")
      .replace(/<(p|blockquote|form|textarea|address|tr)(|.+?)>/g, "\n")
      .replace(/<\/(div|p|blockquote|form|textarea|address|tr)>/g, "\n")
    $('<div>' + html + '</div>').text().trim()
      .replace(/\n{3,20}/g, "\n\n")   # remove multiple empty lines

  # htmlEscapedAndLinkified = App.Utils.linkify(rawText)
  @linkify: (ascii) ->
    window.linkify(ascii)

  # wrappedText = App.Utils.wrap(rawText, maxLineLength)
  @wrap: (ascii, max = 82) ->
    result        = ''
    counter_lines = 0
    lines         = ascii.split(/\n/)
    for line in lines
      counter_lines += 1
      counter_parts  = 0
      part_length    = 0
      result_part    = ''
      parts          = line.split(/\s/)
      for part in parts
        counter_parts += 1

        # put overflow of parts to result and start new line
        if (part_length + part.length) > max
          part_length = 0
          result_part = result_part.trim()
          result_part += "\n"
          result     += result_part
          result_part = ''

        part_length += part.length
        result_part += part

        # add spacer at the end
        if counter_parts isnt parts.length
          part_length += 1
          result_part += ' '

      # put parts to result
      result     += result_part
      result_part = ''

      # add new line
      if counter_lines isnt lines.length
        result += "\n"
    result

  # quotedText = App.Utils.quote(rawText)
  @quote: (ascii, max = 82) ->
    ascii = @textCleanup(ascii)
    ascii = @wrap(ascii, max)
    $.trim(ascii)
      .replace /^(.*)$/mg, (match) ->
        if match
          '> ' + match
        else
          '>'

  # htmlEscaped = App.Utils.htmlEscape(rawText)
  @htmlEscape: (ascii) ->
    return ascii if !ascii
    return ascii if !ascii.replace
    ascii.replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;')

  # App.Utils.htmlStrip(element)
  @htmlStrip: (element) ->
    loop
      el = element.get(0)
      break if !el
      child = el.firstChild
      break if !child
      break if child.nodeType isnt 1 || child.tagName isnt 'BR'
      child.remove()

    loop
      el = element.get(0)
      break if !el
      child = el.lastChild
      break if !child
      break if child.nodeType isnt 1 || child.tagName isnt 'BR'
      child.remove()

  # true|false = App.Utils.htmlLastLineEmpty(element)
  @htmlLastLineEmpty: (element) ->
    el = element.get(0)
    return false if !el
    child = el.lastChild
    return false if !child
    return false if child.nodeType isnt 1 || child.tagName isnt 'BR'
    true

  # textWithoutTags = App.Utils.htmlRemoveTags(html)
  @htmlRemoveTags: (html) ->
    html = @_checkTypeOf(html)

    # remove comments
    @_removeComments(html)

    # remove work markup
    @_removeWordMarkup(html)

    # remove tags, keep content
    html.find('div, span, p, li, ul, ol, a, b, u, i, label, small, strong, strike, pre, code, center, blockquote, form, fieldset, textarea, font, address, table, thead, tbody, tr, td, h1, h2, h3, h4, h5, h6').replaceWith( ->
      $(@).contents()
    )

    # remove tags & content
    html.find('div, span, p, li, ul, ol, a, b, u, i, label, small, strong, strike, pre, code, center, blockquote, form, fieldset, textarea, font, table, thead, tbody, tr, td, h1, h2, h3, h4, h5, h6, br, hr, img, svg, input, select, button, style, applet, embed, noframes, canvas, script, frame, iframe, meta, link, title, head').remove()

    html

  # htmlOnlyWithRichtext = App.Utils.htmlRemoveRichtext(html)
  @htmlRemoveRichtext: (html, parent = true) ->
    return html if !html
    html = @_checkTypeOf(html)

    # remove comments
    @_removeComments(html)

    # remove style and class
    if parent
      @_removeAttributes(html)

    # remove work markup
    @_removeWordMarkup(html)

    # remove tags, keep content
    html.find('li, ul, ol, a, b, u, i, label, small, strong, strike, pre, code, center, blockquote, form, fieldset, textarea, font, address, table, thead, tbody, tr, td, h1, h2, h3, h4, h5, h6').replaceWith( ->
      $(@).contents()
    )

    # remove tags & content
    html.find('li, ul, ol, a, b, u, i, label, small, strong, strike, pre, code, center, blockquote, form, fieldset, textarea, font, address, table, thead, tbody, tr, td, h1, h2, h3, h4, h5, h6, hr, img, svg, input, select, button, style, applet, embed, noframes, canvas, script, frame, iframe, meta, link, title, head').remove()

    html

  # cleanHtmlWithRichText = App.Utils.htmlCleanup(html)
  @htmlCleanup: (html) ->
    return html if !html
    html = @_checkTypeOf(html)

    # remove comments
    @_removeComments(html)

    # remove style and class
    @_removeAttributes(html)

    # remove work markup
    @_removeWordMarkup(html)

    # remove tags, keep content
    html.find('a, font, small, time, form, label').replaceWith( ->
      $(@).contents()
    )

    # replace tags with generic div
    # New type of the tag
    replacementTag = 'div';

    # Replace all x tags with the type of replacementTag
    html.find('textarea').each( ->
      outer = @outerHTML

      # Replace opening tag
      regex = new RegExp('<' + @tagName, 'i')
      newTag = outer.replace(regex, '<' + replacementTag)

      # Replace closing tag
      regex = new RegExp('</' + @tagName, 'i')
      newTag = newTag.replace(regex, '</' + replacementTag)

      $(@).replaceWith(newTag)
    )

    # remove tags & content
    html.find('font, img, svg, input, select, button, style, applet, embed, noframes, canvas, script, frame, iframe, meta, link, title, head, fieldset').remove()

    html

  @_checkTypeOf: (item) ->
    return item if typeof item isnt 'string'

    try
      result = $(item)

      # if we have more then on element at first level
      if result.length > 1
        return $("<div>#{item}</div>")

      # if we have just a text string without html markup
      if !result || !result.get(0)
        return $("<div>#{item}</div>")

      return result
    catch err
      return $("<div>#{item}</div>")

  @_removeAttributes: (html, parent = true) ->
    if parent
      html.find('*')
        .removeAttr('style')
        .removeAttr('class')
        .removeAttr('title')
        .removeAttr('lang')
        .removeAttr('type')
        .removeAttr('id')
        .removeAttr('wrap')
        .removeAttrs(/data-/)
    html
      .removeAttr('style')
      .removeAttr('class')
      .removeAttr('title')
      .removeAttr('lang')
      .removeAttr('type')
      .removeAttr('id')
      .removeAttr('wrap')
      .removeAttrs(/data-/)
    html

  @_removeComments: (html) ->
    html.contents().each( ->
      if @nodeType == 8
        $(@).remove()
    )
    html

  @_removeWordMarkup: (html) ->
    return html if !html.get(0)
    match = false
    htmlTmp = html.get(0).outerHTML
    regex = new RegExp('<(/w|w)\:[A-Za-z]')
    if htmlTmp.match(regex)
      match = true
      htmlTmp = htmlTmp.replace(regex, '')
    regex = new RegExp('<(/o|o)\:[A-Za-z]')
    if htmlTmp.match(regex)
      match = true
      htmlTmp = htmlTmp.replace(regex, '')
    if match
      return window.word_filter(html)
    html

  # signatureNeeded = App.Utils.signatureCheck(message, signature)
  @signatureCheck: (message, signature) ->
    messageText   = $('<div>' + message + '</div>').text().trim()
    messageText   = messageText.replace(/(\n|\r|\t)/g, '')
    signatureText = $('<div>' + signature + '</div>').text().trim()
    signatureText = signatureText.replace(/(\n|\r|\t)/g, '')

    quote = (str) ->
      (str + '').replace(/[.?*+^$[\]\\(){}|-]/g, "\\$&")

    #console.log('SC', messageText, signatureText, quote(signatureText))
    regex = new RegExp(quote(signatureText), 'mi')
    if messageText.match(regex)
      false
    else
      true

  # messageWithMarker = App.Utils.signatureIdentify(message, false)
  @signatureIdentify: (message, test = false, internal = false) ->
    textToSearch = @html2text(message)

    # if we do have less then 10 lines and less then 300 chars ignore this
    textToSearchInLines = textToSearch.split("\n")
    return message if !test && (textToSearchInLines.length < 10 && textToSearch.length < 300)

    quote = (str) ->
      (str + '').replace(/[.?*+^$[\]\\(){}|-]/g, "\\$&")

    cleanup = (str) ->
      if str.match(/(<|>|&)/)
        str = str.replace(/(.+?)(<|>|&).+?$/, "$1").trim()
      str

    # search for signature separator "--\n"
    markers = []
    searchForSeparator = (textToSearchInLines, markers) ->
      lineCount = 0
      for line in textToSearchInLines
        lineCount += 1
        if line && line.match( /^\s{0,10}--\s{0,10}$/ )
          marker =
            line:      line
            lineCount: lineCount
            type:      'separator'
          markers.push marker
          return
    searchForSeparator(textToSearchInLines, markers)

    # search for Thunderbird
    searchForThunderbird = (textToSearchInLines, markers) ->
      lineCount = 0
      for line in textToSearchInLines
        lineCount += 1

        # Am 04.03.2015 um 12:47 schrieb Alf Aardvark:
        if line && line.match( /^(Am)\s.{6,20}\s(um)\s.{3,10}\s(schrieb)\s.{1,250}:/ )
          marker =
            line:      cleanup(line)
            lineCount: lineCount
            type:      'thunderbird'
          markers.push marker
          return

        # Thunderbird default - http://kb.mozillazine.org/Reply_header_settings
        # On 01-01-2007 11:00 AM, Alf Aardvark wrote:
        if line && line.match( /^(On)\s.{6,20}\s.{3,10},\s.{1,250}(wrote):/ )
          marker =
            line:      cleanup(line)
            lineCount: lineCount
            type:      'thunderbird'
          markers.push marker
          return

        # http://kb.mozillazine.org/Reply_header_settings
        # Alf Aardvark wrote, on 01-01-2007 11:00 AM:
        if line && line.match( /^.{1,250}\s(wrote),\son\s.{3,20}:/ )
          marker =
            line:      cleanup(line)
            lineCount: lineCount
            type:      'thunderbird'
          markers.push marker
          return
    searchForThunderbird(textToSearchInLines, markers)

    # search for Apple Mail
    searchForAppleMail = (textToSearchInLines, markers) ->
      lineCount = 0
      for line in textToSearchInLines
        lineCount += 1

        # On 01/04/15 10:55, Bob Smith wrote:
        if line && line.match( /^(On)\s.{6,20}\s.{3,10}\s.{1,250}\s(wrote):/ )
          marker =
            line:      cleanup(line)
            lineCount: lineCount
            type:      'apple'
          markers.push marker
          return

        # Am 03.04.2015 um 20:58 schrieb Martin Edenhofer <me@znuny.ink>:
        if line && line.match( /^(Am)\s.{6,20}\s(um)\s.{3,10}\s(schrieb)\s.{1,250}:/ )
          marker =
            line:      cleanup(line)
            lineCount: lineCount
            type:      'apple'
          markers.push marker
          return
    searchForAppleMail(textToSearchInLines, markers)

    # search for otrs
    # 25.02.2015 10:26 - edv hotline wrote:
    # 25.02.2015 10:26 - edv hotline schrieb:
    searchForOtrs = (textToSearchInLines, markers) ->
      lineCount = 0
      for line in textToSearchInLines
        lineCount += 1
        if line && line.match( /^.{6,10}\s.{3,10}\s-\s.{1,250}\s(wrote|schrieb|a écrit|escribió):/ )
          marker =
            line:      cleanup(line)
            lineCount: lineCount
            type:      'Otrs'
          markers.push marker
          return
    searchForOtrs(textToSearchInLines, markers)

    # search for Ms
    # From: Martin Edenhofer via Znuny Support [mailto:support@znuny.inc]
    # Send: Donnerstag, 2. April 2015 10:00
    # To/Cc/Bcc: xxx
    # Subject: xxx
    # - or -
    # From: xxx
    # To/Cc/Bcc: xxx
    # Date: 01.04.2015 12:41
    # Subject: xxx
    # - or -
    # De : xxx
    # À/?/?: xxx
    # Envoyé : mercredi 29 avril 2015 17:31
    # Objet : xxx
    searchForMs = (textToSearchInLines, markers) ->
      lineCount          = 0
      fromFound          = undefined
      foundInLines       = 0
      subjectWithinLines = 5
      for line in textToSearchInLines
        lineCount += 1

        # find Sent
        if fromFound
          if line && line.match( /^(Subject|Betreff|Objet)(\s|):\s.+?/) # en/de/fr | sometimes ms adds a space to "xx : value"
            marker =
              line:      fromFound
              lineCount: lineCount
              type:      'Ms'
            markers.push marker
            return
          if lineCount > ( foundInLines + subjectWithinLines )
            fromFound = undefined

        # find From
        else
          if line && line.match( /^(From|Von|De)(\s|):\s.+?/ ) # en/de/fr | sometimes ms adds a space to "xx : value"
            fromFound    = line.replace(/\s{0,5}(\[|<).+?(\]|>)/g, '')
            foundInLines = lineCount
    searchForMs(textToSearchInLines, markers)

    # word 14
    # edv hotline wrote:
    # edv hotline schrieb:
    searchForWord14 = (textToSearchInLines, markers) ->
      lineCount = 0
      for line in textToSearchInLines
        lineCount += 1
        if line && line.match( /^.{1,250}\s(wrote|schrieb|a écrit|escribió):/ )
          marker =
            line:      cleanup(line)
            lineCount: lineCount
            type:      'Word14'
          markers.push marker
          return
    searchForWord14(textToSearchInLines, markers)

    # gmail
    # Am 24.10.2016 18:55 schrieb "xxx" <somebody@example.com>:
    searchForGmail = (textToSearchInLines, markers) ->
      lineCount = 0
      for line in textToSearchInLines
        lineCount += 1
        if line && line.match( /.{1,250}\s(wrote|schrieb|a écrit|escribió)\s.{1,250}:/ )
          marker =
            line:      cleanup(line)
            lineCount: lineCount
            type:      'gmail'
          markers.push marker
          return
    searchForGmail(textToSearchInLines, markers)

    # marker template
    markerTemplate = '<span class="js-signatureMarker"></span>'

    # search for zammad
    # <div data-signature="true" data-signature-id=".{1,5}">
    if !markers || !markers[0] || internal
      regex = new RegExp("(<div data-signature=\"true\" data-signature-id=\".{1,5}\">)")
      if message.match(regex)
        return message.replace(regex, "#{markerTemplate}\$1")
      regex = new RegExp("(<div data-signature-id=\".{1,5}\" data-signature=\"true\">)")
      if message.match(regex)
        return message.replace(regex, "#{markerTemplate}\$1")

    # search for <blockquote type="cite">
    # <blockquote type="cite">
    if !markers || !markers[0]
      regex = new RegExp("(<blockquote type=\"cite\">)")
      if message.match(regex)
        return message.replace(regex, "#{markerTemplate}\$1")

    # gmail
    # <div class="ecxgmail_quote">
    if !markers || !markers[0]
      regex = new RegExp("(<blockquote class=\"(ecxgmail_quote|gmail_quote)\">)")
      if message.match(regex)
        return message.replace(regex, "#{markerTemplate}\$1")

    # if no marker is found, return
    return message if !markers || !markers[0]

    # get first marker
    markers = _.sortBy(markers, 'lineCount')
    if markers[0].type is 'separator'
      regex = new RegExp("\>(\s{0,10}#{quote(App.Utils.htmlEscape(markers[0].line))})\s{0,10}\<")
      message.replace(regex, ">#{markerTemplate}\$1<")
    else
      regex = new RegExp("\>(\s{0,10}#{quote(App.Utils.htmlEscape(markers[0].line))})")
      message.replace(regex, ">#{markerTemplate}\$1")

  # textReplaced = App.Utils.replaceTags( template, { user: { firstname: 'Bob', lastname: 'Smith' } } )
  @replaceTags: (template, objects) ->
    template = template.replace( /#\{\s{0,2}(.+?)\s{0,2}\}/g, (index, key) ->
      levels  = key.split(/\./)
      dataRef = objects
      for level in levels
        if level of dataRef
          dataRef = dataRef[level]
        else
          dataRef = ''
          break
      if typeof dataRef is 'function'
        value = dataRef()
      else if dataRef isnt undefined && dataRef isnt null && dataRef.toString
        value = dataRef.toString()
      else
        value = ''
      #console.log( "tag replacement #{key}, #{value} env: ", objects)
      if value is ''
        value = '-'
      value
    )

  # string = App.Utils.removeEmptyLines(stringWithEmptyLines)
  @removeEmptyLines: (string) ->
    string.replace(/^\s*[\r\n]/gm, '')

  # cleanString = App.Utils.htmlAttributeCleanup(string)
  @htmlAttributeCleanup: (string) ->
    string.replace(/((?![-a-zA-Z0-9_]+).|\n|\r|\t)/gm, '')

  # diff = App.Utils.formDiff(dataNow, dataLast)
  @formDiff: (dataNowRaw, dataLastRaw) ->
    dataNow = clone(dataNowRaw)
    @_formDiffNormalizer(dataNow)
    dataLast = clone(dataLastRaw)
    @_formDiffNormalizer(dataLast)

    @_formDiffChanges(dataNow, dataLast)

  @_formDiffChanges: (dataNow, dataLast, changes = {}) ->
    for dataNowkey, dataNowValue of dataNow
      if dataNow[dataNowkey] isnt dataLast[dataNowkey]
        if _.isArray( dataNow[dataNowkey] ) && _.isArray( dataLast[dataNowkey] )
          diff = _.difference( dataNow[dataNowkey], dataLast[dataNowkey] )
          if !_.isEmpty( diff )
            changes[dataNowkey] = diff
        else if _.isObject( dataNow[dataNowkey] ) &&  _.isObject( dataLast[dataNowkey] )
          changes = @_formDiffChanges( dataNow[dataNowkey], dataLast[dataNowkey], changes )
        else
          changes[dataNowkey] = dataNow[dataNowkey]
    changes

  @_formDiffNormalizer: (data) ->
    return undefined if data is undefined

    if _.isArray(data)
      for i in [0...data.length]
        data[i] = @_formDiffNormalizer(data[i])
    else if _.isObject(data)
      for key, value of data
        if _.isArray(data[key])
          @_formDiffNormalizer(data[key])
        else if _.isObject( data[key] )
          @_formDiffNormalizer(data[key])
        else
          data[key] = @_formDiffNormalizerItem(key, data[key])
    else
      @_formDiffNormalizerItem('', data)

  @_formDiffNormalizerItem: (key, value) ->

    # handel owner/nobody behavior
    if key is 'owner_id' && value.toString() is '1'
      value = ''
    else if typeof value is 'number'
      value = value.toString()

    # handle null/undefined behavior - we just handle both as the same
    else if value is null
      value = undefined

    value

  # check if attachment is referenced in message
  @checkAttachmentReference: (message) ->
    return false if !message
    matchwords = ['Attachment', 'attachment', 'Attached', 'attached', 'Enclosed', 'enclosed', 'Enclosure', 'enclosure']
    for word in matchwords

      # en
      attachmentTranslatedRegExp = new RegExp("\\W#{word}\\W", 'i')
      return word if message.match(attachmentTranslatedRegExp)

      # user locale
      attachmentTranslated = App.i18n.translateContent(word)
      attachmentTranslatedRegExp = new RegExp("\\W#{attachmentTranslated}\\W", 'i')
      return attachmentTranslated if message.match(attachmentTranslatedRegExp)
    false

  # human readable file size
  @humanFileSize: (size) ->
    if size > ( 1024 * 1024 )
      size = Math.round( size / ( 1024 * 1024 ) ) + ' MB'
    else if size > 1024
      size = Math.round( size / 1024 ) + ' KB'
    else
      size = size + ' Bytes'
    size

  # format decimal
  @decimal: (data, positions = 2) ->

    # input validation
    return '' if data is undefined
    return '' if data is null

    if data.toString
      data = data.toString()

    return data if data is ''
    return data if data.match(/[A-z]/)

    format = ( num, digits ) ->
      while num.toString().length < digits
        num = num + '0'
      num

    result = data.match(/^(.+?)\.(.+?)$/)

    # add .00
    if !result || !result[2]
      return "#{data}.#{format(0, positions)}"
    length = result[2].length
    diff = positions - length

    # check length, add .00
    return "#{result[1]}.#{format(result[2], positions)}" if diff > 0

    # check length, remove longer positions
    "#{result[1]}.#{result[2].substr(0,positions)}"

  @sortByValue: (options, order = 'ASC') ->
    # sort by name
    byNames = []
    byNamesWithValue = {}
    for i, value of options
      valueTmp = value.toString().toLowerCase()
      byNames.push valueTmp
      byNamesWithValue[valueTmp] = [i, value]
    byNames = byNames.sort()

    # do a reverse, if needed
    if order == 'DESC'
      byNames = byNames.reverse()

    optionsNew = {}
    for i in byNames
      ref = byNamesWithValue[i]
      optionsNew[ref[0]] = ref[1]
    optionsNew

  @sortByKey: (options, order = 'ASC') ->
    # sort by name
    byKeys = []
    for i, value of options
      if i.toString
        iTmp = i.toString().toLowerCase()
      else
        iTmp = i
      byKeys.push iTmp
    byKeys = byKeys.sort()

    # do a reverse, if needed
    if order == 'DESC'
      byKeys = byKeys.reverse()

    optionsNew = {}
    for i in byKeys
      optionsNew[i] = options[i]
    optionsNew

  @formatTime: (num, digits) ->

    # input validation
    return '' if num is undefined
    return '' if num is null

    if num.toString
      num = num.toString()

    while num.length < digits
      num = '0' + num
    num

  @icon: (name, className = '') ->
    #
    # reverse regex
    # =============
    #
    # search: <svg class="icon icon-([^\s]+)\s([^"]*).*<\/svg>
    # replace: <%- @Icon('$1', '$2') %>
    #
    path = if window.svgPolyfill then '' else 'assets/images/icons.svg'
    "<svg class=\"icon icon-#{name} #{className}\"><use xlink:href=\"#{path}#icon-#{name}\" /></svg>"

  @getScrollBarWidth: ->
    $outer = $('<div>').css(
      visibility: 'hidden'
      width: 100
      overflow: 'scroll'
    ).appendTo('body')

    widthWithScroll = $('<div>').css(
      width: '100%'
    ).appendTo($outer).outerWidth()

    $outer.remove()

    return 100 - widthWithScroll

  @diffPositionAdd: (a, b) ->
    applyOrder = []
    newOrderMethod = (a, b, applyOrder) ->
      for position of b
        if a[position] isnt b[position]
          positionInt = parseInt(position)

          # changes to complex, whole rerender
          if _.contains(a, b[position])
            return false

          # insert new item and try next
          a.splice(positionInt, 0, b[position])
          positionNew = 0
          for positionA of a
            if b[positionA] is b[position]
              positionNew = parseInt(positionA)
              break
          apply =
            position: positionNew
            id: b[position]
          applyOrder.push apply
          newOrderMethod(a, b, applyOrder)
      true

    result = newOrderMethod(a, b, applyOrder)
    return false if !result
    applyOrder
