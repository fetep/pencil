#!/usr/bin/env ruby

require "rubygems"
require "namespace"

#require "json"
require "config"
require "erb"
require "helpers"
require "models"
require "rack"
require "sinatra/base"

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
      # redirect to /dash
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
      "List of dashboards for #{params[:cluster]}"
    end

    get '/dash' do
      "List of dashboards"
    end

    get '/host/:cluster/:host' do
      @cluster = params[:cluster]
      @host = Host.find_by_name_and_cluster(params[:host], params[:cluster])
      raise "Unknown host: #{params[:host]} in #{params[:cluster]}" unless @host

      @title = "host :: #{@host.name}"

      erb :host
    end
  end # Dash::App
end # Dash
