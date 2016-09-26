require 'rest-client'
require 'sinatra'
require 'json'
require 'chunky_png'
require_relative './face-detection'

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
        fetch_and_compose_image(file, event.channel) unless already_processing?(file.timestamp)
      end
    end

    if event.text && event.text.match(/^<@#{@team.bot["bot_user_id"]}>/)
      arr = FaceDetection::Emotions.values.select do |emotion|
        event.text.include?(":#{emotion}:")
      end

      find_image_with_emotion(arr, event.channel) if arr
    end
  end

  return 200
end

def fetch_and_compose_image(file, channel)
  p "file_and_compose_image"

  filename = file.timestamp

  if file.filetype == "jpg"
    File.open("./tmp/#{filename}", 'wb') do |f|
      f << fetch_image(file.url_private)
    end

    fd = FaceDetection.new("./tmp/#{filename}", "./tmp/composed/#{filename}")
    file_id = upload(file, channel) if fd.process_image
    add_reactions(file_id, fd)
  end
end

def fetch_image(url)
  p "fetch_image"
  res = RestClient.get(url, {"Authorization" => "Bearer #{@team.access_token}" })
  if res.code == 200
    return res.body
  else
    raise 'Download failed'
  end
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

  JSON.parse(res.body)["file"]["id"]
end

def add_reactions(file_id, face_detection)
  p "add reactions"

  face_detection.emotions.uniq.each do |emotion|
    options = {
      token: @team.bot["bot_access_token"],
      file: file_id,
      name: emotion
    }

    res = RestClient.post 'https://slack.com/api/reactions.add', options, content_type: :json
  end
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

def find_image_with_emotion(array_of_emoji, channel)
  bot_id = @team.bot["bot_user_id"]
  options = {
    token: @team.access_token,
    channel: channel,
    user: bot_id,
    types: "images"
  }

  res = RestClient.post 'https://slack.com/api/files.list', options, content_type: :json
  body = JSON.parse(res.body)

  found_files = []

  body["files"].each do |file|
    if file["reactions"]
      bot_reacted = file["reactions"].any? do |reaction|
        reaction["users"].include?(bot_id) && array_of_emoji.include?(reaction["name"])
      end

      found_files << file if bot_reacted
    end
  end

  rand_file = found_files.sample
  if rand_file
    options = {
      token: @team.bot["bot_access_token"],
      channel: channel,
      text: rand_file['url_private'],
      as_user: true
    }

    res = RestClient.post 'https://slack.com/api/chat.postMessage', options, content_type: :json
    p res.body
  end
end
