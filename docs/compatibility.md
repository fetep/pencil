# Migrating the configuration file format

Migrating to a single YAML configuration file from a previous Pencil version
should be pretty straightforward regarding application configuration (as
opposed to graph and dash configuration). See the example file provided as a
base, and migrate parameters from under the :config key to the top level of the
new config file. Some notes:

:url_opts is now :default_url_opts. *NOTE* this option has a slightly different
representation from before, because these are options passed to the
[Graphite DSL](https://github.com/ripienaar/graphite-graph-dsl/wiki) now. For
instance, fontSize in the old config should be translated to fontsize in the
new one. See the DSL for details. *NOTE* There may be unsupported options like
:thickness that don't have a DSL equivalent yet.

:quantum, :default_colors, and :now_threshold are no longer options.

:date_format is no longer an option, but will likely be reintroduced using
[moment.js](http://momentjs.com/docs) format strings.

In addition see the [new documentation](LINK) and example file for various new
options you may want to specify.

# Image Format

It used to be possible to tweak graphite image parameters from the UI, for two
reasons: 

1. Pencil didn't automatically resize the graph based on display size
2. Graphite's x-axis labeling can sometimes make that axis hard to read

(1) is mostly a nonissue now because Pencil automatically re-scales and resizes
graphite images based on display size, using the height given in the
configuration file as a lower limit.

For (2) see [this](./10hourview.png) as an example. This is still an issue with
no fix in the current version, and graphite in general.

# Timespec

Pencil tries to support the 0.3.* and below style "start" and duration"
parameters, using the original [Chronic](http://chronic.rubyforge.org/) and
[Chronic-Duration](https://github.com/hpoydar/chronic_duration) method of
parsing. It automatically converts this style into a calendar view with "from"
and "until" parameters as UNIX timestamps. Bear in mind that the time
computation is done on the server in the server's timezone, and may not be
exactly what you expect. In principle this could be fixed by using tzinfo and
parsing relative to a specific timezone, but since earlier pencils lacked
timezone support anyway this isn't much of an issue.
