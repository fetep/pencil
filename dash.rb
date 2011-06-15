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
    use Rack::Session::Cookie, :expire_after => 126227700
    set :static, true
    set :public, File.join(File.dirname(__FILE__), "public")

    def initialize(settings={})
      super
    end

    before do
      @dashboards = Dashboard.all
      # fixme reload hosts after some expiry
    end

    get %r[^/(dash/?)?$] do
      redirect '/dash/global'
    end

    get '/dash/:cluster/:dashboard/:zoom' do
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
      @cluster = params[:cluster]
      if @cluster == "global"
        @title = "Overview"
        erb :global
      else
        @title = "cluster :: #{params[:cluster]}"
        erb :cluster
      end
    end

    get '/host/:cluster/:host' do
      @host = Host.new(params[:host], { 'cluster' => params[:cluster] })
      @cluster = params[:cluster]
      raise "Unknown host: #{params[:host]} in #{params[:cluster]}" unless @host

      @title = "#{@host.cluster} :: host :: #{@host.name}"

      erb :host
    end

    get '/saveprefs' do
      puts 'saving prefs'
      params.each do |k,v|
        session[k] = v unless v.empty?
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
