# Timespec

Pencil tries to support the 0.3.* and below style "start" and duration"
parameters, using the original [Chronic](http://chronic.rubyforge.org/) and
[Chronic-Duration](https://github.com/hpoydar/chronic_duration) method of
parsing. It automatically converts this style into a calendar view with "from"
and "until" parameters as UNIX timestamps. Bear in mind that the time
computation is done on the server in the server's timezone, and may be exactly
what you expect. In principle this could be fixed by using tzinfo and parsing
relative to a specific timezone, but since earlier pencils lacked timezone
support anyway it's not worth the implementation effort.
