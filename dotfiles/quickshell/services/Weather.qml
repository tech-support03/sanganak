// services/Weather.qml — current conditions + 3-day / hourly forecast.
//
// Source: wttr.in's JSON (`?format=j1`), refreshed every 15 min. The location
// is the one line in ~/.config/rice/weather-location (a city, "lat,lon", or an
// airport code); empty or missing means wttr.in's IP geolocation. The weather
// panel writes that file; this singleton watches it and refetches.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: w

    property bool ready: false
    property bool failed: false
    property string location: ""          // configured query ("" = auto)
    property string city: "—"
    property string glyph: ""       // cloud until the first fetch lands
    property string condition: "—"
    property int    tempF: 0
    property int    feelsF: 0
    property int    humidity: 0
    property int    windMph: 0
    property string sunrise: ""
    property string sunset: ""
    // [{ date, label, glyph, hiF, loF, rainPct }]
    property var    days: []
    // [{ time: "3 PM", glyph, tempF, rainPct }] — next 8 three-hour slots
    property var    hours: []

    readonly property string locationFile: Quickshell.env("HOME") + "/.config/rice/weather-location"

    // wttr.in weatherCode → nerd-font glyph (day variants).
    function glyphFor(code) {
        var c = parseInt(code, 10)
        if (c === 113) return ""                                   // sunny
        if (c === 116) return ""                                   // partly cloudy
        if (c === 119 || c === 122) return ""                      // cloudy / overcast
        if ([143, 248, 260].indexOf(c) !== -1) return ""           // fog
        if ([200, 386, 389, 392, 395].indexOf(c) !== -1) return "" // thunder
        if ([179, 182, 185, 227, 230, 281, 284, 311, 314, 317, 320, 323, 326, 329, 332, 335, 338, 350, 362, 365, 368, 371, 374, 377].indexOf(c) !== -1)
            return ""                                              // snow / sleet
        return ""                                                  // rain / drizzle
    }

    function setLocation(q) {
        location = (q || "").trim()
        _save.command = ["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s\\n" "$2" > "$1"', "sh", locationFile, location]
        _save.running = true
    }
    function refresh() { if (!_fetch.running) _fetch.running = true }

    function _hourLabel(t) {
        var h = Math.floor(parseInt(t, 10) / 100)
        var ap = h >= 12 ? "PM" : "AM"
        var h12 = h % 12 === 0 ? 12 : h % 12
        return h12 + " " + ap
    }

    function _ingest(txt) {
        try {
            var j = JSON.parse(txt)
            var cur = j.current_condition[0]
            var area = j.nearest_area && j.nearest_area[0]
            city = area ? area.areaName[0].value : (location || "—")
            condition = cur.weatherDesc[0].value.trim()
            glyph = glyphFor(cur.weatherCode)
            tempF = parseInt(cur.temp_F, 10)
            feelsF = parseInt(cur.FeelsLikeF, 10)
            humidity = parseInt(cur.humidity, 10)
            windMph = parseInt(cur.windspeedMiles, 10)

            var names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            var ds = [], hs = []
            var nowH = new Date().getHours() * 100
            for (var i = 0; i < j.weather.length; i++) {
                var d = j.weather[i]
                var dt = new Date(d.date + "T12:00:00")
                var rain = 0
                d.hourly.forEach(function (h) { rain = Math.max(rain, parseInt(h.chanceofrain, 10) || 0) })
                ds.push({ date: d.date, label: i === 0 ? "Today" : names[dt.getDay()],
                          glyph: glyphFor(d.hourly[4] ? d.hourly[4].weatherCode : cur.weatherCode),
                          hiF: parseInt(d.maxtempF, 10), loF: parseInt(d.mintempF, 10), rainPct: rain })
                if (i === 0 && d.astronomy && d.astronomy[0]) {
                    sunrise = d.astronomy[0].sunrise
                    sunset = d.astronomy[0].sunset
                }
                d.hourly.forEach(function (h) {
                    if (hs.length >= 8) return
                    if (i === 0 && parseInt(h.time, 10) + 300 <= nowH) return
                    hs.push({ time: _hourLabel(h.time), glyph: glyphFor(h.weatherCode),
                              tempF: parseInt(h.tempF, 10), rainPct: parseInt(h.chanceofrain, 10) || 0 })
                })
            }
            days = ds
            hours = hs
            ready = true
            failed = false
        } catch (e) {
            failed = true
        }
    }

    property Process _fetch: Process {
        command: ["curl", "-fsS", "--max-time", "10",
                  "https://wttr.in/" + encodeURIComponent(w.location) + "?format=j1"]
        stdout: StdioCollector { onStreamFinished: if (text.length > 0) w._ingest(text) }
        onExited: function (code) { if (code !== 0) w.failed = true }
    }
    property Process _save: Process { onExited: w.refresh() }

    property FileView _locFile: FileView {
        path: w.locationFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { var q = text().trim(); if (q !== w.location) { w.location = q; w.refresh() } }
    }

    property Timer _tick: Timer {
        interval: 15 * 60 * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: w.refresh()
    }
}
