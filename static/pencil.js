// fixme when params are the same (multiple clicks to submit) don't push to history

// fixme possibly use this for query manipulation
// http://archive.plugins.jquery.com/project/query-object

// modified from
// http://stackoverflow.com/questions/1634748/how-can-i-delete-a-query-string-parameter-in-javascript
function removeParameter(url, parameter)
{
    var urlparts= url.split('?');

    if (urlparts.length>=2)
    {
        var urlBase=urlparts.shift(); //get first part, and remove from array
        var queryString=urlparts.join("?"); //join it back up

        var prefix = encodeURIComponent(parameter)+'=';
        var pars = queryString.split(/[&;]/g);
        for (var i= pars.length; i-->0;)               //reverse iteration as may be destructive
            if (pars[i].lastIndexOf(prefix, 0)!==-1)   //idiom for string.startsWith
                pars.splice(i, 1);
        if (pars.length === 0) {
            url = urlBase;
        } else {
            url = urlBase+'?'+pars.join('&');
        }
    }
    return url;
}

// this could be much better
function addParameter(url, parameterName, parameterValue){
    replaceDuplicates = true;
    var cl;

    if(url.indexOf('#') > 0){
        cl = url.indexOf('#');
        urlhash = url.substring(url.indexOf('#'),url.length);
    } else {
        urlhash = '';
        cl = url.length;
    }

    sourceUrl = url.substring(0,cl);

    var urlParts = sourceUrl.split("?");
    var newQueryString = "";
    var found = false;

    if (urlParts.length > 1)
    {
        var parameters = urlParts[1].split("&");
        for (var i=0; (i < parameters.length); i++)
        {
            var parameterParts = parameters[i].split("=");
            if (!(replaceDuplicates && parameterParts[0] == parameterName))
            {
                if (newQueryString === "")
                    newQueryString = "?";
                else
                    newQueryString += "&";
                newQueryString += parameterParts[0] + "=" + parameterParts[1];
            } else if (parameterParts[0] == parameterName) {
                found = true;
                if (newQueryString === "") {
                    newQueryString = "?";
                } else  {
                    newQueryString += "&";
                }
                newQueryString += parameterName + "=" + parameterValue;
            }
        }
    }
    if (newQueryString === "") {
        newQueryString = "?";
        newQueryString += parameterName + "=" + parameterValue;
    } else if (!found) {
        newQueryString += "&";
        newQueryString += parameterName + "=" + parameterValue;
    }

    return urlParts[0] + newQueryString + urlhash;
}

function reloadImg(obj, salt) {
    obj.src = addParameter(obj.src, '_salt', salt);
}

function calendarStart() {
    var day = moment($('#dp1 input').val() +
                     " " + $('#tp1 input').val(), "YYYY-MM-DD hh:mm:ss A");
    return day;
}

function calendarEnd() {
    var day = moment($('#dp2 input').val() +
                     " " + $('#tp2 input').val(), "YYYY-MM-DD hh:mm:ss A");
    return day;
}

function makeTimestamp() {
    if (liveTest()) {
        var offset = $('#tab1 li[class=active] a')[0].getAttribute("offset");
        var label = $('#tab1 li[class=active] a')[0].getAttribute("label");
        var d = Date.now();
        // fixme make flooring optional
        var b = moment(d).add('seconds', parseInt(offset, 10)).seconds(0);
        var format = b.format("dddd, MMMM Do YYYY, h:mm:ss a Z"); // "Sunday, February 14th 2010, 3:25:50 pm"
        $('#timestamp').text("timeslice: " + label + " (from " + format + ")");
    } else {
        $('#timestamp').text("calendar view: " +
                             calendarStart().format("dddd, MMMM Do YYYY, h:mm:ss a Z") +
                             " - " +
                             calendarEnd().format("dddd, MMMM Do YYYY, h:mm:ss a Z"));
    }
}

function liveTest () {
    return $('#tab1 li[class=active]').size() > 0;
}

function calendarSubmit() {
    var start = calendarStart().unix();
    var end = calendarEnd().unix();
    var url = window.location.toString();
    url = addParameter(url, 'from', start);
    url = addParameter(url, 'until', end);
    if (supportsHistoryApi()) {
        history.pushState({from: start, until: end}, '', url);
        changeState();
    } else {
        window.location.replace(url);
    }
    return false;
}

function liveSubmit(obj) {
    var url = window.location.toString();
    if ($(obj).parent()[0].getAttribute('default')) {
        url = removeParameter(url, 'from');
    } else {
        url = addParameter(url, 'from', obj.getAttribute('value'));
    }
    url = removeParameter(url, 'until');

    if (supportsHistoryApi()) {
        history.pushState({from: obj.getAttribute('value')}, '', url);
        changeState();
    } else {
        window.location.replace(url);
    }
}

function fixButtonLabels() {
    $('ul li a').each(
        function() {
            if (this.getAttribute('label') === '') {
                var d = moment.duration(parseInt(this.getAttribute('offset'), 10), "seconds").humanize(true);
                this.setAttribute('label', d);
                this.innerHTML = this.getAttribute('label');
            }
        }
    );
}

function updateImagesWithTimezone (timezone) {
    $('img').each(function() {
        this.src = addParameter(this.src, 'tz', timezone);
    });
}
function updateImagesWithWidth (width) {
    $('img').each(function() {
        this.src = addParameter(this.src, 'width', width);
    });
}

function reloadImages() {
    var salt =  new Date().getTime().toString();
    $('img').each(function() {
        reloadImg(this, salt);
    });
    makeTimestamp();
}

// http://stackoverflow.com/questions/901115/how-can-i-get-query-string-values
function getParameterByName(name)
{
    name = name.replace(/[\[]/, "\\[").replace(/[\]]/, "\\]");
    var regexS = "[\\?&]" + name + "=([^&#]*)";
    var regex = new RegExp(regexS);
    var results = regex.exec(window.location.search);
    if(results === null){
        return "";
    } else {
        return decodeURIComponent(results[1].replace(/\+/g, " "));
    }
}

function getParameterByName2(url, name)
{
    name = name.replace(/[\[]/, "\\[").replace(/[\]]/, "\\]");
    var regexS = "[\\?&]" + name + "=([^&#]*)";
    var regex = new RegExp(regexS);
    var results = regex.exec(url);
    if(results === null){
        return "";
    } else {
        return decodeURIComponent(results[1].replace(/\+/g, " "));
    }
}

function getState() {
    var result = {};
    var from = getParameterByName('from');
    var until = getParameterByName('until');
    if (from !== '') { result.from = from; }
    if (until !== '') { result.until = until; }
    return result;
}

// don't include anchors
function appendQueryStrings() {
    var q = window.location.toString();
    if (q.indexOf('#') != -1) {
        q = q.substring(0, q.indexOf('#'));
    }
    q = q.split('?');
    q.shift();
    q.unshift('');
    q = q.join('?');
    $("a[href^='/']").each(function() {
        var href = this.getAttribute('href');
        var base = href.split('?').shift();
        this.setAttribute('href', base + q);
    });
}

function highlightCurrent() {
    if (liveTest()) {
        $("#tabhead2").removeClass('active');
        $("#tabhead1").addClass('active');
    } else {
        $("#tabhead1").removeClass('active');
        $("#tabhead2").addClass('active');
    }
}

// we don't actually need the state object because the entirety of the state is
// controlled in query parameters
// todo keep old calendar dates when changing to live mode

// fixme spin on button click (so graphs with a changing view are easily
// distinguished) when url has changed
function changeState() {
    console.log('change state called');
    var now = moment();
    var from = getParameterByName('from');
    var until = getParameterByName('until');

    $('#tab1 li a').each(function() {
        $(this).parent().removeClass("active");
    });

    if (!from) {
        from = $('li[default=true] a')[0].getAttribute('value');
        $('li[default=true]').addClass('active');
    } else {
        $('li a[value=\"'+getParameterByName('from')+'\"]').parent().addClass('active');
    }
    if (liveTest()) {
        $("#tab1").addClass("active");
        $("#tab2").removeClass("active");
        // fixme check if active
        clearInterval(timer);
        if ($('img').size() > 0) {
            timer = setInterval(reloadImages, refresh);
        }
        $('img').each(function() {
            var url = this.src;
            url = addParameter(url, 'until', "now");
            url = addParameter(url, 'from', from);
            this.src = url;
            // $(this).spin();
        });
        $("#permd").show();
        $("#perm").parent().show();
        until = now.clone().hours(11).minutes(59).seconds(0);
        from = now.clone().subtract('days', 1).hours(12).minutes(1).seconds(0);
    } else {
        from = moment.unix(parseInt(from, 10));
        until = moment.unix(parseInt(until, 10));
        $("#tab1").removeClass("active");
        $('#tab1 li[class=active]').removeClass("active");
        $("#tab2").addClass("active");
        clearInterval(timer);
        $('img').each(function() {
            var url = this.src;
            url = addParameter(url, 'from', from.unix());
            url = addParameter(url, 'until', until.unix());
            this.src = url;
            // $(this).spin();
        });
        $("#permd").hide();
        $("#perm").parent().hide();
        // $(document).ready(function() {
        // $("img").loadNicely({
        //     onLoad: function (img) {
        //         $(img).fadeIn(200, function () {
        //             var spinner = $(this).parent().data("spinner");
        //             if (spinner)
        //                 spinner.stop();
        //         });
        //     }
        // });
        // });
    }

    // if ($("#dp1 input").val() === "") { }
    $("#dp1 input").val(from.format('YYYY-MM-DD'));
    $("#dp1").datepicker({ format: 'yyyy-mm-dd'});
    $("#dp2 input").val(until.format('YYYY-MM-DD'));
    $("#dp2").datepicker({ format: 'yyyy-mm-dd'});
    $('#tp1 input').timepicker({showSeconds: true, defaultTime: from.format('hh:mm:ss A')});
    $('#tp2 input').timepicker({showSeconds: true, defaultTime: until.format('hh:mm:ss A')});
    highlightCurrent();
    appendQueryStrings();
    makeTimestamp();
}

function initialize () {
    fixButtonLabels();
    $.cookie.defaults = {expires: 1460, path: '/'};
    // fixme this can cause three image loads on first use instead of two
    if (!$.cookie('tz')) {
        var timezone = jstz.determine().name();
        $.cookie('tz', timezone);
        updateImagesWithTimezone(timezone);
    }
    if ($('img').size() > 0) {
        var containerWidth = $('img').first().parent().parent().width();
        var imgWidth = parseInt(
            getParameterByName2($('img')[0].getAttribute('src'), 'width'), 10);
        if ((!$.cookie('mw') && imgWidth < containerWidth) ||
            ($.cookie('mw') && parseInt($.cookie('mw'),10) < containerWidth)) {
            $.cookie('mw', containerWidth);
            updateImagesWithWidth(containerWidth);
        }
    }
    if (supportsHistoryApi()) {
        window.addEventListener('popstate', function(event) {
            if (event.state !== null) {
                changeState();
            }
        });
        history.replaceState(getState(), '');
    }
    $('#perm').tooltip();
    $('div[class=graph] a').tooltip();
    $('footer a').tooltip();
    changeState();
}

function supportsHistoryApi() {
    return !!(window.history && history.pushState);
}

function permaLink() {
    if (liveTest()) {
        var offset = $('#tab1 li[class=active] a')[0].getAttribute("offset");
        var until = moment();
        var from = until.clone().add('seconds', parseInt(offset, 10)).seconds(0);
        var url = window.location.toString();
        url = addParameter(url, 'from', from.unix());
        url = addParameter(url, 'until', until.unix());
        if (supportsHistoryApi()) {
            history.pushState({from: from.unix(), until: until.unix()}, '', url);
            changeState();
        } else {
            window.location.replace(url);
        }
    } else {
        // calendar view is already essentially a permanent timeslice
        calendarSubmit();
    }
}

// relative web apps not supported yet, see
// https://bugzilla.mozilla.org/show_bug.cgi?id=745928
// fixme make error message more informative/evangelistic
function installWebApp () {
    if (navigator.mozApps) {
        var manifest = window.location.protocol + '//' + window.location.host + '/manifest.webapp';
        navigator.mozApps.install(manifest);
    } else {
        alert("Your browser doesn't support open web apps.");
    }
}
