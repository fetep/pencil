# Pencil Options

## General Configuration

These are options for the main configuration file: pencil.yml.

* :graphite_url [no default]

  The url of your graphite instance.

* :default_url_opts [optional, no default]

  A map of default graph options, like width and height. See the
  [DSL](https://github.com/ripienaar/graphite-graph-dsl/wiki) for specific
  options. A sample configuration might would look like:

    :default_url_opts:
      :width: 1400
      :height: 400
      :fontsize: 15

* :refresh_rate [default 60]

  How often to refresh graph images, in seconds.

  In the future this option will be overridden under the :default_views: key
  per view, this value being the default.

* :host_sort [default "sensible"]

  One of "builtin", "numeric", or "sensible".

  Set to "builtin" to sort using ruby's builtin String sort.

  Set to "numeric" to sort hosts numerically (i.e. match secondarily on the
  first \d+).

  Set to "sensible" if you want to sort like this:

  http://www.bofh.org.uk/2007/12/16/comprehensible-sorting-in-ruby

* :metric_format [default "%m.%c.%h"]

  The format your graphite metrics are stored in. Pencil needs metrics to be
  composed of two or three distinct pieces, concatenated in some regular
  fashion. The format strings are:

  * %m metric
  * %c cluster
  * %h host

  The cluster "%c" portion is optional.

  Currently supported metric types are those that are qualified by at most a
  cluster and a short hostname, such as

  [METRIC].colo1.db1 # corresponding to db1.colo1.[rest of FQDN]
  
  or, with no cluster:

  [METRIC].db1 # corresponding to db1.[rest of FQDN]

  Example metric and corresponding formats:

  system.load.hostname                          # %m.%h
  system.load.dc.hostname                       # %m.%c.%h
  dc.hostname.system.load                       # %c.%h.%m
  hostname.dc.system.load                       # %h.%c.%m
  prefix_for_all_metrics.system.load.hostname   # prefix_for_all_metrics.%m.%h

  Pencil will recognize all these graphite metrics as "system.load" for the
  host "hostname", and, where applicable, cluster "dc".

* :port [default 9292]

   Port to bind to.

* :templates_dir [no default]

   Directory where graph and dashboard configuration is stored. Resolved
   relative to the location of the config file.

* :webapp [default false]

   Enable Open Web App support. See [here](./webapp.md) for details.

* :default_views:

  Pencil has two modes: live views and calendar views. For live monitoring of
  graphite data live views are used. This key species the default views
  available (though manually specifying "from=RELATIVE" in the URL works too).

  Default value:

    :default_views:
      - -1h: "one hour view"
      - default:
         -8h: "eight hour view"
      - -1day: "One day view"

 Each entry in this list should look like one of the following:

 TIMESPEC
 TIMESPEC: LABEL
 default: TIMESPEC
 default: TIMESPEC: LABEL

 TIMESPEC is a graphite at-style relative time from
 "now". [See the documentation](https://graphite.readthedocs.org/en/latest/render_api.html#from-until)
 for details.

 *NOTE* acceptable values for this key will expand in a later release to
 include arbitrary graphite-supported timespecs (not just references), an
 additional supported "until" value, and a "refresh" value as well. It will
 remain backwards compatible.
