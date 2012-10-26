# Pencil rewrite

I (whd) am in the process of rewriting Pencil, due a few outstanding feature
requests and to leverage the excellent [graphite-dsl](https://github.com/ripienaar/graphite-graph-dsl/).

## Some features of the rewrite

* Single cluster and no cluster support, so the %c in metric format will be optional.

* Graph config format uses graphite-dsl. Goodbye messy hack-YAML graph configuration!

* Snazzy new twitter bootstrap UI and post-90s HTML/JS, including client-side
  state using the HTML5 history API (when present) and responsive UI.

* Timezone support via [detect_timezone.js](http://www.pageloom.com/automatic-timezone-detection-with-javascript).

* Dashboard groupings

## anti-features

* config file formats are incompatible, though migration scripts will be provided

* some features (quantum etc.) have been removed

# TODOS

* group view

* support for manual hacks (&height= &tz= and so forth)

* support for dashboards specific to a particular cluster

* update examples

* docs

* compatibility layer

* hosts associated with dashboards on cluster/global view

* arrows for navigation

* robust migration scripts

* automatic configuration reloading

  I implemented this imperfectly right before starting the rewrite. It's been
  gutted and needs to be redone.

* Be less dynamic 

  pencil can be a little slow at generating pages because practically everything
  is dynamic. Some of this stuff doesn't need to be, though this is largely
  mitigated by having image reloading/state changes done on the client side

* colo-specific dashboards again

* thread-safe graph url generation

* Refresh specific to view (use <unit> for ephemeral views)

* add ability to have an "all-time" view in live views

* HTML formatting (-%>)

* configurable format date (using moment.js, not strftime)

* time increments like graphite/possibly adopt graphite's style

* clear focus of form button on submit

## DONE

* [DONE] permalink

* [DONE] dynamically generate ephemeral entry in the live window when a from= is not in config

  This info could be stored in a session cookie, but a 'clear this view' button
  would need to be added to the ui to remove old entries.

* [DONE] make arbitrary default one hour between calendar views

* [DONE] update nav urls in addition to location bar

* [DONE] semi-dynamic resizing

* [DONE] append query parameters in js

* [DONE] when default, don't add parameter

* [DONE] move all class=active to js
  ...except where it's static per-page (nav)

* [DONE] history api / ie hack for window.replace

* [DONE] test single cluster 

* [DONE] test no cluster mode