


> direct message hubot

![demo](https://raw.githubusercontent.com/bearyinnovative/hubot-grafana/master/assets/demo.jpeg)



## Hubot Grafana

- install latest version of grafana 
- setup your data source 
- setup dashboard and graphs
- setup your hubot robot for your BearyChat Team
- create S3 bucket, Qiniu uploader is coming soon
- configure run.sh 
- voila , `chmod +x run.sh && ./run.sh`  or you can deploy it to Heroku



## deploy to Heroku 
- create Heroku account if you dont have already

- `heroku login`

- download source code of hubot-grafana

- `cd hubot-grafana`

- `heroku create`

- `heroku addons:create rediscloud`

- setup environment variables
```
  heroku config:set HUBOT_GRAFANA_HOST=http://example.com
  heroku config:set HUBOT_GRAFANA_API_KEY=YOUR_GRAFANA_API_KEY

  heroku config:set HUBOT_GRAFANA_S3_BUCKET=YOUR_S3_BUCKET
  heroku config:set HUBOT_GRAFANA_S3_ACCESS_KEY=YOUR_S3_ACCESS_KEY
  heroku config:set HUBOT_GRAFANA_S3_SECRET_KEY=YOUR_S3_SECRET_KEY
  heroku config:set HUBOT_GRAFANA_S3_REGION=YOUR_S3_REGION
  heroku config:set HUBOT_BEARYCHAT_TOKENS=YOUR_BEARYCHAT_TOKEN

  heroku HUBOT_BEARYCHAT_MODE=http
```

- `git push heroku  master`

- `heroku open`  and copy URL of newly opened page  and set it up as hubot weebhook URL in your BearyChat team settings.
