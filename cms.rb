require "sinatra"
require "sinatra/reloader"
require "sinatra/content_for"
require "tilt/erubis"
require "redcarpet"
require "fileutils"
require "yaml"
require "bcrypt"

# root = File.expand_path("..", __FILE__)

configure do
  enable :sessions
  set :session_secret, 'secret'
end

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def render_markdown(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(text)
end

def load_file_content(path)
  content = File.read(path)

  case File.extname(path)
  when ".txt"
    headers["Content-Type"] = "text/plain"
    content
  when '.md'
    erb render_markdown(content)
  end
end

def valid_filename?(name)
  name = name.strip
  name.length > 0 && (name.end_with?(".txt") || name.end_with?(".md")) 
end

def load_user_credentials
  credentials_path = if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/.users.yml", __FILE__)
  else
    File.expand_path("../.users.yml", __FILE__)
  end
  YAML.load_file(credentials_path)
end

def valid_user?(username, password)
  users = load_user_credentials
  if users.key?(username)
    bcrypt_password = BCrypt::Password.new(users[username])
    bcrypt_password == password
  else
    false
  end
end

def require_signed_in_user
  return if session[:user]
  session[:message] = "You must be signed in to do that."
  redirect "/"
end

def duplicate_file(filename)
  name_arr = filename.split('.')
  name_arr[-2] += "_copy"
  duplicate_filename = name_arr.join('.')

  file_path = File.join(data_path, filename)
  dup_file_path = File.join(data_path, duplicate_filename)
  FileUtils::cp(file_path, dup_file_path)
end

get "/" do
  pattern = File.join(data_path, '*')
  @files = Dir.glob(pattern).map do |path|
    File.basename(path)
  end

  erb :index
end

get "/new" do
  require_signed_in_user
  erb :new
end

get "/users/signin" do
  erb :signin
end

get "/:filename" do
  file_path = File.join(data_path, File.basename(params[:filename]))

  if File.exist?(file_path)
    load_file_content(file_path)
  else
    session[:message] = "#{params[:filename]} does not exist"
    redirect "/"
  end
end

get "/:filename/edit" do
  require_signed_in_user

  @filename = params[:filename]
  file_path = File.join(data_path, params[:filename])

  @content = File.read(file_path).strip

  erb :edit
end

post "/new" do
  require_signed_in_user

  @filename = params[:filename]

  if valid_filename?(@filename)
    file_path = File.join(data_path, @filename)

    File.write(file_path, "")
    session[:message] = "#{@filename} has been created."
    redirect "/"
  else
    session[:message] = "Please enter a valid filename ending with '.txt' or '.md'"
    status 422
    erb :new
  end
end

post "/users/signin" do
  username = params[:username]
  password = params[:password]

  if valid_user?(username, password)
    session[:user] = username
    session[:message] = "Welcome!"
    redirect "/"
  else
    session[:message] = "Invalid credentials"
    status 422
    erb :signin
  end
end

post "/users/signout" do
  session.delete(:user)
  session[:message] = "You have been signed out."
  redirect "/"
end

post "/:filename" do
  require_signed_in_user

  file_path = File.join(data_path, params[:filename])
  
  File.write(file_path, params[:content])

  session[:message] = "#{params[:filename]} has been updated."
  redirect "/"
end

post "/:filename/destroy" do
  require_signed_in_user

  file_path = File.join(data_path, params[:filename])

  File.delete(file_path)
  session[:message] = "#{params[:filename]} has been deleted."
  redirect "/"
end

post "/:filename/duplicate" do
  require_signed_in_user

  duplicate_file(params[:filename])
  session[:message] = "#{params[:filename]} has been duplicated!"
  redirect "/"
end

get "/users/signup" do
  erb :signup
end

post "/users/signup" do
  username = params[:username].strip
  password = params[:password].strip

  if username.length == 0 || password.length == 0
    session[:message] = "Please enter a valid username and password"
    status 422
    erb :signup
  else
    bcrypt_password = BCrypt::Password.create(password).to_s
   
    user_file = load_user_credentials
    user_file[username] = bcrypt_password 
    File.write("./.users.yml", user_file.to_yaml)
    
    session[:message] = "New user #{username} has been signed up, please sign in to access!"
    redirect "/"
  end
end