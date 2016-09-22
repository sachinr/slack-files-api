require 'rest-client'
require 'sinatra'
require 'json'
require 'chunky_png'


before do
  @teams ||= load_data

  begin
    request.body.rewind
    data = JSON.parse request.body.read
    if data["team_id"]
      @team = find_team(@teams, data["team_id"], data["event"]["user"])
    end
  rescue JSON::ParserError
    p "No JSON in body"
  end

end

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
    save(JSON.parse(res))

    @teams.to_s
  end
end

post '/events' do

  request.body.rewind
  data = JSON.parse(request.body.read, object_class: OpenStruct)

  case data.type
  when "url_verification"
    content_type :json
    return {challenge: data["challenge"]}.to_json

  when "event_callback"
    event = data.event
    if event.subtype && event.subtype == "file_share"
      if @team && event.user != @team.bot["bot_user_id"]
        file = event.file
        unless already_processing?(file.timestamp)
          fetch_and_compose_png(file)
          upload(file, event.channel) if file.filetype == "png"
        end
      end
    end
  end

  return 200
end

def fetch_and_compose_png(file)
  p "file_and_compose_png"
  File.open("./tmp/#{file.timestamp}", 'wb') do |f|
    f << fetch_png(file.url_private)
  end

  compose_png(file.timestamp)
end

def fetch_png(url)
  p "fetch_png"
  res = RestClient.get(url, {"Authorization" => "Bearer #{@team.access_token}" })
  if res.code == 200
    return res.body
  else
    raise 'Download failed'
  end
end

def compose_png(filename)
  p "compose_png"
  avatar = ChunkyPNG::Image.from_file("./tmp/#{filename}")
  badge  = ChunkyPNG::Image.from_file('./files/overlay.png')
  avatar.compose!(badge, 100, 100)
  avatar.save("./tmp/composed/#{filename}", :fast_rgba) # Force the fast saving routine.
end

def upload(file, channel)
  p "upload"
  options = {
    token: @team.bot["bot_access_token"],
    file: File.new("./tmp/composed/#{file.timestamp}", 'rb'),
    filename: "composed_" + file.name,
      title: "Composed " + file.title,
      channels: channel
  }

  res = RestClient.post 'https://slack.com/api/files.upload', options, content_type: :json
  p res.body
end

def already_processing?(filename)
  return true if FileTest.exist?("./tmp/#{filename}")
  File.open("./tmp/#{filename}", "w") {}

  false
end

def save(team)
  @teams << team

  File.open("store.json","w") do |file|
    file.write @teams.to_json
  end
end

def load_data
  if FileTest.exist?("store.json")
    JSON.parse(File.read('store.json'))
  else
    []
  end
end

def find_team(teams, team_id, user_id)
  all_matching_auths = teams.select {|t| t["team_id"] == team_id }
  user_auth = all_matching_auths.detect {|t| t["user_id"] == user_id }
  team = user_auth || all_matching_auths.first

  team ? OpenStruct.new(team) : nil
end
