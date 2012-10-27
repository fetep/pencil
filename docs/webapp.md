Pencil has [Open Web App](https://developer.mozilla.org/en-US/docs/Apps)
support. To enable it add:

    :webapp: true

To your pencil configuration. If you'd like to specify a manifest instead of
the default (recommended), use something like this:

    :webapp:
      :manifest:
        {
          "name": "Pencil",
          "description": "Graphite Dashboard Frontend",
          "launch_path": "/",
          "icons": {
            "16": "/favicon.ico"
          },
          "developer": {
            "name": "whd@mozilla.com",
            "url": "https://github.com/fetep/pencil"
          },
          "default_locale": "en"
        }

See [here](https://developer.mozilla.org/en-US/docs/Apps/Manifest) for details
on app manifests. Bear in mind that if you use a different icon than the
stock it will need to be put somewhere in /static at the pencil root, otherwise
pencil won't serve it. This could be fixed by traversing the manifest
beforehand for a regular filesystem path and adding a route to serve it, but is
currently unsupported.

Also to note: pencil configuration is in yaml, while manifests are served as
json. Keep that in mind when writing your manifest (though the manifest above
is perfectly valid json as well).
