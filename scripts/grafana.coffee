#http://docs.grafana.org/reference/http_api/

crypto  = require 'crypto'
request = require 'request'
rp = require 'request-promise'
AWS = require 'aws-sdk'

module.exports = (robot) ->
  grafana_host = process.env.HUBOT_GRAFANA_HOST
  grafana_api_key = process.env.HUBOT_GRAFANA_API_KEY
  grafana_query_time_range = '24h'

  s3_bucket = process.env.HUBOT_GRAFANA_S3_BUCKET
  s3_access_key = process.env.HUBOT_GRAFANA_S3_ACCESS_KEY
  s3_secret_key = process.env.HUBOT_GRAFANA_S3_SECRET_KEY
  s3_region = process.env.HUBOT_GRAFANA_S3_REGION

  robot.respond /(?:grafana|graph|graf) db ([A-Za-z0-9\-\:_]+)(.*)?/i, (msg) ->
    slug = msg.match[1]
    remainder = msg.match[2]

    {envelope} = msg
    {user} = envelope
    {id, vchannel, id} = user

    msg.reply 'wait a sec, señor'
    timespan = {
      from: "now-#{grafana_query_time_range}"
      to: 'now'
    }

    variables = ''
    template_params = []
    visualPanelId = false
    apiPanelId = false
    pname = false

    # Parse out a specific panel
    if /\:/.test slug
      parts = slug.split(':')
      slug = parts[0]
      visualPanelId = parseInt parts[1], 10
      if isNaN visualPanelId
        visualPanelId = false
        pname = parts[1].toLowerCase()
      if /panel-[0-9]+/.test pname
        parts = pname.split('panel-')
        apiPanelId = parseInt parts[1], 10
        pname = false

    # Check if we have any extra fields
    if remainder
      # The order we apply non-variables in
      timeFields = ['from', 'to']

      for part in remainder.trim().split ' '
        # Check if it's a variable or part of the timespan
        if part.indexOf('=') >= 0
          variables = "#{variables}&var-#{part}"
          template_params.push { "name": part.split('=')[0], "value": part.split('=')[1] }

        # Only add to the timespan if we haven't already filled out from and to
        else if timeFields.length > 0
          timespan[timeFields.shift()] = part.trim()

    # Call the API to get information about this dashboard
    callGrafana("dashboards/db/#{slug}").then(
      (dashboard) ->
        if dashboard.dashboard
          data = dashboard.dashboard
          apiEndpoint = 'dashboard-solo'

        # Support for templated dashboards
        if data.templating.list
          template_map = []
          for template in data.templating.list
            continue unless template.current
            for _param in template_params
              if template.name == _param.name
                template_map['$' + template.name] = _param.value
              else
                template_map['$' + template.name] = template.current.text

        # Return dashboard rows
        panelNumber = 0
        for row in data.rows
          for panel in row.panels
            panelNumber += 1

            # Skip if visual panel ID was specified and didn't match
            if visualPanelId && visualPanelId != panelNumber
              continue

            # Skip if API panel ID was specified and didn't match
            if apiPanelId && apiPanelId != panel.id
              continue

            # Skip if panel name was specified any didn't match
            if pname && panel.title.toLowerCase().indexOf(pname) is -1
              continue

            # Build links for message sending
            title = formatTitleWithTemplate(panel.title, template_map)

            # Fork here for S3-based upload and non-S3
            if (s3_bucket && s3_access_key && s3_secret_key)
              imgURL = "#{grafana_host}/render/#{apiEndpoint}/db/#{slug}/?panelId=#{panel.id}&width=1000&height=500&from=#{timespan.from}&to=#{timespan.to}#{variables}"
              link = "#{grafana_host}/dashboard/db/#{slug}/?panelId=#{panel.id}&fullscreen&from=#{timespan.from}&to=#{timespan.to}#{variables}"
              processImage msg,title,vchannel,link,imgURL).catch(
      (err) ->
        sendError err.message, msg)

  processImage = (msg,title,vchannel,link,imgURL) ->
    postURL = getS3SignedPUTURL()
    S3ImgURL = postURL.substring(0,postURL.indexOf('?'))
    fetchAndUpload(imgURL,postURL).then(
      (response) ->
        sendBack msg,title,vchannel,S3ImgURL,link)

  fetchImage = (url) ->
    options =
      uri: url
      encoding: null
      headers:
        'Authorization': "Bearer #{grafana_api_key}"
    rp options

  getS3SignedPUTURL = () ->
    AWS.config.update {"accessKeyId" : s3_access_key, "secretAccessKey" : s3_secret_key}
    AWS.config.update {"region": s3_region}
    s3 = new AWS.S3 {params : {Bucket : s3_bucket}}

    # generate random filename
    filename = "#{crypto.randomBytes(20).toString('hex')}.png"
    imageData = {Key: filename, ACL: 'public-read', ContentType: 'image/png'}
    postURL = s3.getSignedUrl 'putObject', imageData;
    postURL

  uploadToS3 = (url,content) ->
    options =
      method: 'PUT'
      uri: url
      body: content
      headers:
        'Content-Type': 'image/png'
    rp options

  fetchAndUpload = (url,postURL) ->
    fetchImage(url).then(
      (response) ->
        return uploadToS3(postURL,response))

  sendBack = (response,text,vchannel,imgURL,dashboardURL) ->
    images = [{'url': imgURL}]
    markdownTitle = "[#{dashboardURL}](#{dashboardURL})"
    attachments = [{'title'  : text,'text' :'', 'color'  : 'green','images' : images}]
    opts = {markdown:true, attachments:attachments}
    response.send  markdownTitle, opts

  # Get a list of available dashboards
  robot.hear /(?:grafana|graph|graf) list\s?(.+)?/i, (msg) ->
    if msg.match[1]
      tag = msg.match[1].trim()
      console.log 'tag',tag
      callGrafana("search?tag=#{tag}").then(
        (dashboards) ->
          response = "Dashboards tagged `#{tag}`:\n"
          sendDashboardList dashboards, response, msg).catch(
        (err) ->
          sendError err.message, msg)
    else
      callGrafana('search').then(
        (dashboards) ->
          console.log dashboards
          response = "Available dashboards:\n"
          sendDashboardList dashboards, response, msg).catch(
        (err) ->
          sendError err.message, msg)

  # Search dashboards
  robot.hear /(?:grafana|graph|graf) search (.+)/i, (msg) ->
    query = msg.match[1].trim()
    callGrafana("search?query=#{query}").then(
      (dashboards) ->
        response = "Dashboards matching `#{query}`:\n"
        sendDashboardList dashboards, response, msg).catch(
      (err) ->
        sendError err.message, msg)

  # Send Dashboard list
  sendDashboardList = (dashboards, response, msg) ->
    # Handle refactor done for version 2.0.2+
    if dashboards.dashboards
      list = dashboards.dashboards
    else
      list = dashboards

    unless list.length > 0
      return

    for dashboard in list
      # Handle refactor done for version 2.0.2+
      if dashboard.uri
        slug = dashboard.uri.replace /^db\//, ''
      else
        slug = dashboard.slug
      response = response + "- #{slug}: #{dashboard.title}\n"

    # Remove trailing newline
    response.trim()
    msg.send response

  # Handle generic errors
  sendError = (message, msg) ->
    robot.logger.error message
    msg.send message

  # Format the title with template vars
  formatTitleWithTemplate = (title, template_map) ->
    title.replace /\$\w+/g, (match) ->
      if template_map[match]
        return template_map[match]
      else
        return match

  callGrafana = (query) ->
    url = "#{grafana_host}/api/#{query}"
    options =
      transform: (body, response, resolveWithFullResponse) ->
        if !body
          throw new Error('Transform failed!')
        if body and body.message
          throw new Error(body.message)
        if body and body.length == 0
          throw new Error('no result')
        return body
      uri: url
      method: 'GET'
      json: true
      headers:
        'Authorization': "Bearer #{grafana_api_key}"
    rp options
