# Pencil

Pencil is a monitoring frontend for graphite. It runs a web server that dishes
out pretty [Graphite](http://graphite.wikidot.com/) URLs in hopefully
interesting and intuitive fashion.

Some features are:

* LOTS of views and navigation UI for bouncing around them

  Dashboard groupings, global, cluster, dashboard, and host views. Single and
  no-cluster support for smaller sites as well.
  
  Snazzy [Twitter Bootstrap](http://twitter.github.com/bootstrap/) with responsive UI.

* Easy configuration

  Pretty much anything you'd want to do with the graphite can be done using the
  [Graphite DSL](https://github.com/ripienaar/graphite-graph-dsl/) and a bit of
  YAML.

* Implicit collection of host and cluster data

  Pencil picks these up from graphite without you having to explicitly define
  them, and gives you the ability to look at all the graphs for a particular
  host or cluster. You need only supply the metrics in your graph definitions;
  see <a href="#setup"/> for configuration details.

* Live and Calendar views with relative and absolute timespecs

  Timeslices are measured in terms of a (possibly relative) starting time and a
  duration. You can also use Pencil in "tail-mode" (i.e. constant refresh,
  looking at last couple hours of data) or to view a particular timeslice in
  the past with calendar views.

* permalinks

  Turn a relative timeslice (such as the last 8 hours) into an absolute one for
  placing in bug reports and all sorts of other useful things.

* popover graph descriptions

  If you've ever looked at a graph and thought to yourself "what is this?", you can
  now annotate each graph with a description, or by default the target data
  that's being sent to graphite.

* Client-side state using the [HTML5 History API](https://developer.mozilla.org/en-US/docs/DOM/Manipulating_the_browser_history) (when present)

* Timezone support via [detect_timezone.js](http://www.pageloom.com/automatic-timezone-detection-with-javascript).

## INSTALL

gem install pencil

Dependencies:

* rack
* sinatra
* sinatra-contrib
* json
* chronic
* chronic_duration
* graphite_graph

Pencil should work with Ruby 1.8.7 or higher, and probably non-MRI interpreters
too.

## <a name="setup"/>SETUP

You should have a working graphite installation. Your metrics need to be
composed of two or three pieces:

* "%m", _METRIC_ (the common part of each graphite path)
* "%c", _CLUSTER_ (cluster name, varies with query, must not contain periods)
* "%h", _HOST_ (host name, varies with query, must not contain periods)

The :metric_format string is specified in the configuration file (see below), and
defaults to %m.%c.%h". It should contain only one %m, but is otherwise mostly
unrestricted.

Example metric and corresponding formats:

system.load.hostname                          # %m.%h
system.load.dc.hostname                       # %m.%c.%h
dc.hostname.system.load                       # %c.%h.%m
hostname.dc.system.load                       # %h.%c.%m
prefix_for_all_metrics.system.load.hostname   # prefix_for_all_metrics.%m.%h

Pencil will recognize all these graphite metrics as "system.load" for the
host "hostname", and, where applicable, cluster "dc".

### pencil.yml, the configuration file

You need to set up a YAML configuration file in order for pencil to work. Pencil
searches the current directory (or, with -f FILE, FILE) for a file to load.

The most important keys are:

:graphite_url: (URL of your graphite instance)
:metric_format: (see above)
:templates_dir: where your graph and dashboard definitions reside

See examples/ for an example configuration directory. Here's
an example pencil.yml, which contains general configuration options:

    :graphite_url URL # graphite URL
    :metric_format: "%m.%c.%h" #%m metric, %c cluster, %h host
    :templates_dir: "./conf"
    :refresh_rate: 60 # refresh rate for images in seconds
    
    :default_url_opts:
      :width: 1400
      :height: 400
      :fontsize: 15
    
    :webapp: true
    :default_views:
      - default:
          -1h: "past hour"
      - -8h
      - -24h: "past 24 hours"

For a full description of all these options see docs/pencil_options.md.

With all this in place you should begin to populate your configuration directory
with dashboards and graphs.

Template Directory Layout?
--------------------------

The directory layout is such that you can have many groupings of dashboards
each with many dashboards underneath it, an example layout of your templates
dir would be:

        dashboard_templates
        `-- svc1
            |-- dash1.yml
            |-- dash2.yml
        `-- svc2
            |-- dash3.yml
            |-- dash4.yml


Here we have a two dashboard groups: svc1 and svc2 with dashboards underneath.
You can create as many groups as you want each with many dashboards inside.

But where are the graphs? Graphs are loaded irrespective of their location
within the template directory, so you can have them in a separate directory
(with no YAML files in it) or logically grouped with the dashboards they belong
with. My convention is to do as mentioned, but graphs such as load average that
are reported by all hosts are put in the "global" subdirectory of the templates
directory. See the example for details.

What exactly goes inside graph and dashboard files?
---------------------------------------------------

Here is an example dashboard definition:

    ---
    title: LDAP masters
    description: LDAP masters dashboard
    graphs:
    - ldap_ops
    - load_average
    - cpu_usage:
      hosts: other*
    - network_traffic
    hosts:
    - master*
    - foo*

Graphs are the graphs that comprise this dashboard (since they need not be
stored in the same directory as the dashboard itself). The name is the basename
of the graph, not its title.

Hosts are the hosts that this dashboard applies to. Simple wildcards are
supported. This can be overridden per-graph as seen above for the cpu_usage
graph.

And graph files?
----------------

An example cpu_usage.graph:

    title 'cpu usage'
    area :stacked
    description 'this gets put in a popover if supplied'

    field :system_cpu_system,
            :alias => "CPU/system",
            :color => 'yellow',
            :data => "system.cpu.system"
    
    field :system_cpu_wio,
            :alias => "CPU/wio",
            :color => 'red',
            :data => "system.cpu.wio"

See the [Graphite DSL](https://github.com/ripienaar/graphite-graph-dsl/) for
details. The only differences in how Pencil handles metrics from how the DSL
normally works is that the "data" attribute should NOT be fully qualified in
the graph file. So, if host FOO reports its load average like:

system.load.FOO

the .FOO should be omitted, as above. Pencil picks these values up when it
scrapes Graphite on start.

In addition, an "aggregator" key (default "sumSeries") can be set to
"averageSeries" for graphs where it is appropriate to aggregate at the global
or cluster-wide level using an average instead of a sum.

## RUNNING THE SERVER
Once you've set up the configuration, you should be able to just run

pencil

and get something up on localhost:9292

From there you should be able to click around and see various interesting
collections of graphs.

With no options, pencil looks in the current directory for YAML files and loads
them.

You can bind to a specific port with -p PORT and specify a configuration
file with -f FILE. Other rack-related options may be added at some point
in the future.

### Reloading configuration
Accessing

localhost:9292/reload

Or adding the &reload parameter to a URL cause pencil to manually reload its
configuration file and all graphite data. In the future reloading on changes
in the configuration directory will be supported. After a change is detected a
reload is scheduled, staged, and verified before being loaded into the running
pencil instance. See
[this](http://jim-mcbeath.blogspot.com/2010/01/reload-that-config-file.html)
for the general idea.
