#!/usr/bin/env ruby

require "rubygems"
require "namespace"

require "config"
require "erb"
require "helpers"
require "models"
require "rack"
require "sinatra/base"
require "json"
require "open-uri"
require "yaml"
require "chronic"
require "chronic_duration"
require "optparse"
require "rubyfixes"

# fixme style.css isn't actually cached, you need to set something up with
# rack to cache static files

$:.unshift(File.dirname(__FILE__))

module Dash
  class App < Sinatra::Base
    include Dash::Models
    helpers Dash::Helpers
    config = Dash::Config.new
    set :config, config
    set :port, config.global_config[:port]
    set :run, true
    use Rack::Session::Cookie, :expire_after => 126227700 # 4 years
    set :root, File.dirname(__FILE__)
    set :static, true
    set :logging, true

    def initialize(settings={})
      super
    end

    before do
      session[:not] #fixme kludge is back
      @request_time = Time.now
      @dashboards = Dashboard.all
      @no_graphs = false
      # time stuff
      start = param_lookup("start")
      duration = param_lookup("duration")
      @stime = Chronic.parse(start)
      if @stime
        @stime -= @stime.sec unless @params["noq"]
      end
      if duration
        @duration = ChronicDuration.parse(duration)
      else
        @duration = @request_time.to_i - @stime.to_i
      end

      unless @params["noq"]
        @duration -= (@duration % settings.config.global_config[:quantum]||1)
      end

      if @stime
        @etime = Time.at(@stime + @duration)
        @etime = @request_time if @etime > @request_time
      else
        @etime = @request_time
      end

      params[:stime] = @stime.to_i.to_s
      params[:etime] = @etime.to_i.to_s
      # fixme reload hosts after some expiry
    end

    get %r[^/(dash/?)?$] do
      @no_graphs = true
      if settings.config.clusters.size == 1
        redirect "/dash/#{settings.config.clusters.first}"
      else
        redirect '/dash/global'
      end
    end

    get '/dash/:cluster/:dashboard/:zoom/?' do
      @cluster = params[:cluster]
      @dash = Dashboard.find(params[:dashboard])
      raise "Unknown dashboard: #{params[:dashboard].inspect}" unless @dash

      @zoom = nil
      @dash.graphs.each do |graph|
        @zoom = graph if graph.name == params[:zoom]
      end
      raise "Unknown zoom parameter: #{params[:zoom]}" unless @zoom

      @title = "dashboard :: #{@cluster} :: #{@dash['title']} :: #{params[:zoom]}"

      if @cluster == "global"
        erb :'dash-global-zoom'
      else
        erb :'dash-cluster-zoom'
      end
    end

    get '/dash/:cluster/:dashboard/?' do
      @cluster = params[:cluster]
      @dash = Dashboard.find(params[:dashboard])
      raise "Unknown dashboard: #{params[:dashboard].inspect}" unless @dash

      @title = "dashboard :: #{@cluster} :: #{@dash['title']}"

      if @cluster == "global"
        erb :'dash-global'
      else
        erb :'dash-cluster'
      end
    end

    get '/dash/:cluster/?' do
      @no_graphs = true
      @cluster = params[:cluster]
      if @cluster == "global"
        @title = "Overview"
        erb :global
      else
        @title = "cluster :: #{params[:cluster]}"
        erb :cluster
      end
    end

    get '/host/:cluster/:host/?' do
      @host = Host.find_by_name_and_cluster(params[:host], params[:cluster])
      @cluster = @host.cluster
      raise "Unknown host: #{params[:host]} in #{params[:cluster]}" unless @host

      @title = "#{@host.cluster} :: host :: #{@host.name}"

      erb :host
    end

    # fixme make sure not to save shitty values for :start, :duration
    # remove stime, etime
    # there is definitely something wrong here
    # disallow saving from, until
    get '/saveprefs' do
      puts 'saving prefs'
      params.each do |k,v|
        session[k] = v unless v.empty?
      end
      redirect URI.parse(request.referrer).path
    end

    get '/clear' do
      puts "clearing prefs"
      session.clear
      redirect URI.parse(request.referrer).path
    end
  end # Dash::App
end # Dash
