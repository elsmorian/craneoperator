require 'oj'
require 'httparty'
require 'pry'
require 'erb'
require 'time'
require 'sinatra/base'
require 'sinatra/cross_origin'

class CraneOp < Sinatra::Base
  register Sinatra::CrossOrigin

  configure do
    enable :cross_origin
    mime_type :javascript, 'application/javascript'
    mime_type :javascript, 'text/javascript'
    set :logging, true
    set :static, true
    set :allow_origin, :any
    set :allow_methods, [:get, :post, :options]
    set :allow_credentials, true
    set :max_age, "1728000"
    set :expose_headers, ['Content-Type']
    set :json_encoder, :to_json
  end

  ## Setup ##

  def registry_host
    ENV['REGISTRY_HOST'] || 'localhost'
  end

  def registry_port
    ENV['REGISTRY_PORT'] || '5000'
  end

  def registry_proto
    ENV['REGISTRY_PROTO'] || 'https'
  end

  def registry_ssl_verify
    ENV['REGISTRY_SSL_VERIFY'] || 'true'
  end

  ## Authentication ##

  if ENV['USERNAME']
    use Rack::Auth::Basic, "Please Authenticate to View" do |username, password|
      username == ENV['USERNAME'] and password == ( ENV['PASSWORD'] || '' )
    end
  end

  ## Helpers ##

  def to_bool(str)
    str.downcase == 'true'
  end

  def html(view)
    File.read(File.join('public', "#{view.to_s}.html"))
  end

  def sort_versions(ary)
    valid_version_numbers = ary.select { |i| i if i.match(/(0-9|\.|\-)/)}
    non_valid_version_numbers = ary - valid_version_numbers
    (valid_version_numbers.sort_by {|v| Gem::Version.new( v ) } + non_valid_version_numbers)
  end

  ## Registry API Methods ##

  def containers
    response = HTTParty.get( "#{registry_proto}://#{registry_host}:#{registry_port}/v2/_catalog", verify: to_bool(registry_ssl_verify) )
    json = Oj.load response.body
    json['repositories']
  end

  def container_tags(repo)
    response = HTTParty.get( "#{registry_proto}://#{registry_host}:#{registry_port}/v2/#{repo}/tags/list", verify: to_bool(registry_ssl_verify) )
    json = Oj.load response.body
    tags = json['tags'] || []
    tags = sort_versions(tags).reverse
  end

  def container_info(repo, manifest)
    response = HTTParty.get( "#{registry_proto}://#{registry_host}:#{registry_port}/v2/#{repo}/manifests/#{manifest}", verify: to_bool(registry_ssl_verify) )
    json = Oj.load response.body

    # Add extra fields for easy display
    json['information'] = Oj.load(json['history'].first['v1Compatibility'])

    created_at = Time.parse(json['information']['created'])
    json['information']['created_formatted'] = created_at.to_s
    json['information']['created_millis']    = (created_at.to_f * 1000).to_i
    return json
  end

  ## Endpoints ##

  get '/' do
    html :index
  end

  get '/containers.json' do
    content_type :json

    containers.to_json
  end

  get '/container/*/tags.json' do |container|
    content_type :json

    tags = container_tags(container)
    halt 404 if tags.nil?
    tags.to_json
  end

  get /container\/(.*\/)(.*.json)/ do |container, tag|

    # This is here because we need to handle slashes in container names
    container.chop!
    tag.gsub!('.json', '')

    content_type :json

    info = container_info(container, tag)

    halt 404 if info['errors']
    halt 404 if info['fsLayers'].nil?

    info.to_json
  end

   get '/registryinfo' do
    content_type :json
    {
      host: registry_host,
      port: registry_port,
      protocol: registry_proto,
      ssl_verify: registry_ssl_verify
    }.to_json
  end

  # Error Handlers
  error do
    File.read(File.join('public', '500.html'))
  end

  not_found do
    status 404
    File.read(File.join('public', '404.html'))
  end

end
