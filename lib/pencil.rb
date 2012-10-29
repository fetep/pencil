require 'sinatra/base'
require 'sinatra/cookies'

require 'pencil/version'
require 'pencil/config'
require 'pencil/helpers'
require 'pencil/models'

require 'chronic'
require 'chronic_duration'
require 'json'

module Pencil
  class App < Sinatra::Base
    helpers Sinatra::Cookies
    set :static, true
    set :views, File.join(File.expand_path(File.dirname(__FILE__)), '..', 'views')

    set :config, Pencil::Config.new
    set :port, settings.config.port
    set :erb, :trim => '-'
    use Rack::Logger
    set :logging, true
    set :config_lock, Mutex.new
    set :numthreads, 0

    include Pencil::Models
    helpers Pencil::Helpers

    # fixme don't rely on rubygems
    if Sinatra.const_defined?('VERSION') && Gem::Version.new(Sinatra::VERSION) >= Gem::Version.new('1.3.0')
      set :public_folder, File.join(File.expand_path(File.dirname(__FILE__)), '..', 'static')
    else
      set :public, File.join(File.expand_path(File.dirname(__FILE__)), '..', 'static')
    end

    before do
      @request_time = Time.now
      settings.config_lock.lock
      settings.numthreads += 1
      settings.config_lock.unlock

      @compatibility = true if params[:start]

      @refresh_rate = settings.config[:refresh_rate] * 1000 # s -> ms
      @views = settings.config[:views].dup

      @overrides = {:timezone => cookies['tz']}
      @overrides[:width] = cookies['mw'] if cookies['mw']

      if @compatibility
        from = Chronic.parse(params[:start]) || Time.now
        from = from.strftime('%s')
        @overrides[:from] = from

        if params[:duration]
          duration = ChronicDuration.parse(params[:duration]) || 3600
          @overrides[:until] = "#{from.to_i + duration}"
        else
          @overrides[:until] = Time.now.strftime('%s')
        end
      elsif params[:from] =~ /^\d+/ && params[:until] =~ /^\d+/
        # calendar view
        @overrides[:from] = params[:from]
        @overrides[:until] = params[:until]
      else
        # we'll do it live!
        view = settings.config[:views].find {|x| x.from == params[:from]}
        if params[:from] && !view
          # fixme do error checking for this, and report in ui when it fails
          @views << settings.config.gen_view(params[:from])
        end
        view ||= settings.config[:views].find {|x| x.is_default}
        @overrides[:from] = view.from
        @overrides[:until] = 'now'
      end


      @dashboards = settings.config.dashboards
      @graphs = settings.config.graphs
      @fakeglobal = Cluster.new(nil, nil, nil, true) #fixme move to config
      @clusters = settings.config.clusters
      @multi = @clusters.size > 1
      @hosts = settings.config.hosts
    end

    after do
      settings.config_lock.lock
      settings.numthreads -= 1
      settings.config_lock.unlock
    end

    # FIXME the redirecting when there is a single or no cluster is shoddy
    get %r[^/(dash/?)?$] do
      if @clusters.size == 1
        redirect append_query_string("/dash/#{@clusters.first}")
      else
        redirect append_query_string('/dash/global')
      end
    end

    get '/dash/:cluster/?' do
      cluster = params[:cluster]
      @title = 'Overview'
      if cluster == 'global' && @multi
        @cluster = @fakeglobal
      elsif cluster == 'global' && @clusters.size == 1
        @cluster = @clusters.first
      else
        @cluster = @clusters.find {|x| x.name == cluster}
        @title = "cluster :: #{cluster}"
      end
      erb :global
    end

    get '/dash/:cluster/:dashboard/?' do
      cluster = params[:cluster]
      @dash = @dashboards[params[:dashboard]]
      raise "dashboard #{params[:dashboard]} not found" unless @dash

      @title = "dashboard :: #{@cluster} :: #{@dash.title}"

      if cluster == 'global'
        @cluster = @fakeglobal
        @target = @clusters
        @method = :render_global
      else
        @cluster = @clusters.find {|x| x.name == cluster}
        @target = [@cluster]
        @method = :render_cluster
      end
      erb :dashboard
    end

    get '/dash/:cluster/:dashboard/:zoom/?' do
      cluster = params[:cluster]
      @dash = @dashboards[params[:dashboard]]
      raise "Unknown dashboard: #{params[:dashboard].inspect}" unless @dash

      @zoom = @graphs[params[:zoom]]
      raise "Unknown zoom parameter: #{params[:zoom]}" unless @zoom

      @title = "dashboard :: #{cluster} :: #{@dash.title} :: #{params[:zoom]}"

      if cluster == 'global'
        @cluster = @fakeglobal
        erb !@multi ? :'cluster-zoom' : :'global-zoom'
      else
        @cluster = @clusters.find {|x| x.name == cluster}
        erb :'cluster-zoom'
      end
    end

    get '/host/:cluster/:host/?' do
      cluster = params[:cluster] == 'global' ? nil : params[:cluster]
      @host = @hosts[Host.get_name(params[:host], cluster)]
      raise "Unknown host: #{params[:host]} in #{params[:cluster]}" unless @host

      @cluster = @cluster = @clusters.find {|x| x.name == cluster} || @fakeglobal

      @title = "#{@host.cluster} :: host :: #{@host.name}"

      erb :host
    end

    get '/manifest.webapp' do
      content_type 'application/x-web-app-manifest+json'
      if settings.config[:webapp]
        settings.config[:webapp][:manifest].to_json
      else
        {}.to_json
      end
    end

    get '/reload' do
      settings.config_lock.lock
      if settings.numthreads == 1
        # block other threads until reload is done, for now
        settings.config.load_verify_stage
        settings.config_lock.unlock
        new_route = '/'
      else
        settings.config_lock.unlock
        new_route = '/reload'
        sleep 5
      end
      redirect new_route
    end
  end # Pencil::App
end # Pencil
