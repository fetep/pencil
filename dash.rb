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

# fixme style.css isn't actually cached, you need to set something up with
# rack to cache static files

$:.unshift(File.dirname(__FILE__))

module Dash
  class App < Sinatra::Base
    include Dash::Models
    helpers Dash::Helpers
    set :config, Dash::Config.new
    set :run, true
    set :sessions, true
    set :static, true
    set :public, File.join(File.dirname(__FILE__), "public")

    def initialize(settings={})
      super
    end

    before do
      @dashboards = Dashboard.all
    end

    get '/' do
      session[:not]
      redirect '/dash'
    end

    get '/dash/:cluster/:dashboard/:zoom' do
      session[:not] #fixme why are these neccesary?????
      @cluster = params[:cluster]
      @dash = Dashboard.find(params[:dashboard])
      raise "Unknown dashboard: #{params[:dashboard]}.inspect" unless @dash

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

    get '/dash/:cluster/:dashboard' do
      session[:not]
      @cluster = params[:cluster]
      @dash = Dashboard.find(params[:dashboard])
      raise "Unknown dashboard: #{params[:dashboard]}.inspect" unless @dash

      @title = "dashboard :: #{@cluster} :: #{@dash['title']}"

      if @cluster == "global"
        erb :'dash-global'
      else
        erb :'dash-cluster'
      end
    end

    get '/dash/:cluster' do
      session[:not]
      @cluster = params[:cluster]
      erb :dash
    end

    get '/dash' do
      redirect '/dash/global'
    end

    get '/host/:cluster/:host' do
      session[:not]
      @host = Host.new(params[:host], { 'cluster' => params[:cluster] })
      @cluster = params[:cluster]
      # FIXME without predefined hosts, it's more difficult to error out here, 
      # because many graphs like cpu_usage use "*" as their match.
      # (basically you would have to check the graphite results for a metric)
      # raise "Unknown host: #{params[:host]} in #{params[:cluster]}" unless @host

      @title = "host :: #{@host.name}"

      erb :host
    end

    get '/saveprefs' do
      puts 'saving prefs'
      params.each do |k,v|
        session[k] = v if !v.empty?
      end
      redirect URI.parse(request.referer).path
    end

    get '/clear' do
      puts 'clearing prefs'
      session.clear
      redirect URI.parse(request.referer).path
    end
  end # Dash::App
end # Dash
