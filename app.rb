require 'rest-client'
require 'sinatra'
require 'json'
require 'chunky_png'

get '/' do
  erb :index
end

get '/oauth' do
  if params['code']

    options = {
      client_id: ENV['SLACK_CLIENT_ID'],
      client_secret: ENV['SLACK_CLIENT_SECRET'],
      code: params['code']
    }

    res = RestClient.post 'https://slack.com/api/oauth.access', options, content_type: :json

    p res
  end
end

post '/events' do
  data = JSON.parse(request.body.read, object_class: OpenStruct)

  case data.type
  when "url_verification"
    content_type :json
    return {challenge: data["challenge"]}.to_json

  when "event_callback"
    event = data.event
    if event.subtype && event.subtype == "file_share"
      file = event.file
      upload(file, fetch_and_compose_png(file)) if file.filetype == "png"
    end
  end
end

def fetch_and_compose_png(file)
  filename = fetch_png(file.url_private)
  compose_png(filename)

  filename
end

def fetch_png(url)
  res = RestClient.get(url, {"Authorization" => "Bearer #{ENV['BOT_ACCESS_TOKEN']}" })
  filename = "#{(Time.now.to_f * 1000).to_i}.png"
  if res.code == 200
    File.open("./tmp/#{filename}", 'wb'){ |file| file << res.body }
  end

  return filename
end

def compose_png(filename)
  avatar = ChunkyPNG::Image.from_file("./tmp/#{filename}")
  badge  = ChunkyPNG::Image.from_file('./files/overlay.png')
  avatar.compose!(badge, 100, 100)
  avatar.save("./tmp/composed/#{filename}", :fast_rgba) # Force the fast saving routine.
end

def upload(file, new_filename)
  options = {
    token: ENV['BOT_ACCESS_TOKEN'],
    file: File.new("./tmp/composed/#{new_filename}", 'rb'),
    filename: file.name + "_composed",
    title: file.title + "_composed"
  }

  res = RestClient.post 'https://slack.com/api/files.upload', options, content_type: :json
end
