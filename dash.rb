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
      redirect '/dash'
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
      erb :dash
    end

    get '/dash' do
      redirect '/dash/global'
    end

    get '/host/:cluster/:host' do
      @host = Host.new(params[:host], { 'cluster' => params[:cluster] })
      @cluster = params[:cluster]
      # FIXME without predefined hosts, it's more difficult to error out here, 
      # because many graphs like cpu_usage use "*" as their match.
      # (basically you would have to check the graphite results for a metric)
      # raise "Unknown host: #{params[:host]} in #{params[:cluster]}" unless @host

      @title = "host :: #{@host.name}"

      erb :host
    end
  end # Dash::App
end # Dash
