# BaroBuddy

[![License: MIT](https://img.shields.io/github/license/kozliatko/barobuddy?color=blue)](LICENSE)
[![Platform: Connect IQ](https://img.shields.io/badge/platform-Connect%20IQ-007cc3)](https://developer.garmin.com/connect-iq/overview/)
[![API 3.0.0](https://img.shields.io/badge/API-3.0.0-007cc3)](https://developer.garmin.com/connect-iq/api-docs/)
[![Language: Monkey C](https://img.shields.io/badge/language-Monkey%20C-6f4e9c)](https://developer.garmin.com/connect-iq/monkey-c/)
[![Devices: 6](https://img.shields.io/badge/devices-6-informational)](#supported-devices)
[![Unit tests: 54](https://img.shields.io/badge/unit%20tests-54-brightgreen)](#running-the-tests)
[![Type check: strict](https://img.shields.io/badge/monkeyc%20--l%203-clean-brightgreen)](#building-from-source)

A barometric weather watch face for Garmin Connect IQ devices.

BaroBuddy forecasts the next few hours of weather the way a ship's barometer
does: not from the absolute pressure, but from **how fast and in which
direction it is changing**. It keeps six hours of pressure history on the
watch, fits a trend through it, and turns that trend into an icon, an arrow and
a plain-language outlook — with a separate alert for the rapid pressure drop
that precedes a storm.

No phone, no internet connection and no weather service are involved. The
forecast is computed entirely on the watch from its own barometer.

![BaroBuddy on a Forerunner 935](docs/screenshot.png)

*Simulator screenshot. The simulated barometer is a random walk, which is why
the storm banner appears next to a "clearing" icon and why the pressure reads
864 hPa — see [Notes on the reading](#notes-on-the-reading).*

## Features

- **Six-hour pressure trend** from the watch's own barometer, expressed in
  hPa per 6 hours and classified into five forecast states.
- **Storm alert** on a rapid three-hour pressure drop, with hysteresis so it
  does not flicker and a re-arm window so it does not nag.
- **History priming.** On first run the face fills its buffer from
  `SensorHistory`, so it is useful within minutes of installation instead of
  after six hours of wear.
- **Pressure graph** of the recent trace, drawn from the same buffer.
- **Bottom status row**: heart rate, step count and battery.
- **Configurable** from the Garmin Connect app: units (hPa / inHg / mmHg) and
  which rows to show.
- **Low-power aware.** In gesture-off mode only the seconds rectangle is
  redrawn, and the graph is dropped entirely.

## The layout

Nothing is drawn at fixed pixel coordinates. The display is round, so a layout
designed for a 240×240 rectangle would put its corners off screen. Every
position is stacked top to bottom in `onLayout()` from the real font metrics
and kept inside the circle, which is also what lets the same source render on
six devices with three different screen sizes.

| Row | Content |
| --- | --- |
| Icon | Forecast: sun / sun behind cloud / cloud / rain / lightning |
| Time | `FONT_NUMBER_THAI_HOT`, with smaller seconds tucked to its right |
| Date | `Fri 4 Sep` |
| Pressure | Trend arrow, coloured by direction, then the reading and its unit |
| Graph **or** storm | The recent pressure trace; during a storm a red banner takes its place |
| Status | Heart rate, steps, battery (the icon turns red below 15%) |

The banner replaces the graph deliberately: during a storm the warning matters
more than the curve that led to it.

## How the forecast works

Pressure is sampled once a minute and offered to a 24-slot ring buffer that
enforces a minimum spacing of 15 minutes between stored samples, so a full
buffer spans six hours in roughly 200 bytes. A least-squares regression over
the buffer gives the trend, normalised to hPa per six hours:

| Trend (hPa / 6 h) | State | Label |
| --- | --- | --- |
| above +3.0 | Rising fast | Windy / Clearing |
| +0.5 to +3.0 | Rising | Fair |
| −0.5 to +0.5 | Steady | Steady |
| −3.0 to −0.5 | Falling | Rain likely |
| below −3.0 | Falling fast | Storm warning |

No forecast is shown until the buffer covers at least one hour. Extrapolating a
six-hour tendency from a few minutes of data is noise, and showing it would be
worse than showing nothing.

The **storm alert is independent of the forecast**. It watches the drop of the
latest reading below the mean of the last three hours, over at least five
samples. It latches at 1.5 hPa and clears at 1.0 hPa — the gap is what stops it
flickering around the threshold — and will not re-latch for another three
hours. Because the drop is measured against the window mean rather than its
first sample, a 1.5 hPa trigger corresponds to a real fall of roughly 3 hPa
across the three hours.

The two measures can disagree: pressure that fell sharply and has begun
recovering will show a rising trend while the storm is still latched. That is
intended, not a bug — one describes where the pressure is going, the other what
it just did.

## Supported devices

| Device | Screen | Launcher icon |
| --- | --- | --- |
| Forerunner 935 | 240×240 | 40×40 |
| fēnix 5 | 240×240 | 40×40 |
| fēnix 5X | 240×240 | 40×40 |
| D2 Charlie | 240×240 | 40×40 |
| fēnix 5S | 218×218 | 36×36 |
| fēnix Chronos | 218×218 | 36×36 |

All are 64-colour MIP displays on Connect IQ API 3.0.0. The Forerunner 935 is
the reference device: where a trade-off has to be made, it is made in favour of
the FR935.

The only permission the app requests is `SensorHistory`.

## Installing

Download `BaroBuddy-<device>.prg` for your watch, connect the watch by USB, and
copy the file into the `GARMIN/APPS/` folder of the drive that appears. Eject
the drive and disconnect. The face then shows up under long-press `UP` →
*Watch Face*.

## Settings

Configurable from the Garmin Connect app under the watch face's settings:

| Setting | Default | Effect |
| --- | --- | --- |
| Show Seconds | on | Seconds beside the time, redrawn by the partial-update path |
| Show Pressure Graph | on | The pressure trace row |
| Show Heart Rate | on | The heart rate cell in the status row |
| Storm Warning Banner | on | The red storm banner |
| Pressure Unit | hPa | hPa, inHg or mmHg |

An unrecognised unit — from a newer settings page than the installed face —
is clamped back to hPa rather than passed on.

## Building from source

Requires the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) and
a developer key.

```bash
export PATH="/path/to/connectiq-sdk/bin:$PATH"

monkeyc -f monkey.jungle -d fr935 -o bin/BaroBuddy-fr935.prg \
        -y ~/.garmin/developer_key.der -w -l 3
```

- `-l 3` is the strictest type checker. The project builds clean at that level
  with no warnings, in both debug and release, on all six devices.
- `-r` produces a release build (about 24 kB per device).
- `-e` together with an `.iq` output produces a store-ready package for all
  devices at once.

To generate a developer key, if you do not have one:

```bash
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER \
              -in developer_key.pem -out developer_key.der -nocrypt
```

The launcher icons are generated rather than hand-drawn:

```bash
python3 tools/make_launcher_icon.py
```

## Running the tests

```bash
monkeyc -f monkey.jungle -d fr935 -o bin/BaroBuddyTest.prg \
        -y ~/.garmin/developer_key.der --unit-test -w -l 3

monkeydo bin/BaroBuddyTest.prg fr935 -t
```

54 tests covering the buffer arithmetic, the forecast thresholds and their
boundaries, the storm hysteresis and re-arm window, the unit conversions, the
`Application.Storage` round trip, and six render smoke tests that draw the full
face into an off-screen `BufferedBitmap`.

The render tests cannot say whether the face *looks* right, but they catch what
a static review does not: a null dereference in a branch that only runs during
a storm, a polygon built from a negative size, a resource id that no longer
resolves. Every state is exercised, including the empty first-run buffer and a
full sleep/wake cycle.

Run a single test with `monkeydo bin/BaroBuddyTest.prg fr935 -t <test_name>`.

## Running in the simulator

```bash
connectiq &                                     # start the simulator
monkeydo bin/BaroBuddy-fr935.prg fr935          # load the face into it
```

The simulator's barometer is a random walk rather than a plausible pressure
series, so the forecast it produces is not meaningful. What it is good for is
the layout, the settings, the sleep transitions and the storage behaviour.

Note that the simulator keys `Application.Storage` by the application name from
the manifest, and a `--unit-test` build gets a `Test` suffix — so the test
build and the app build have separate stores and cannot seed each other.

## Project layout

```
source/
  BaroBuddyApp.mc         AppBase: lifecycle, settings changes, save on exit
  BaroBuddyView.mc        The face: sampling, state, layout and all drawing
  BaroBuddyDelegate.mc    WatchFaceDelegate: the power budget callback
  PressureBuffer.mc       Ring buffer, regression trend, drop detection, serialisation
  WeatherPredictor.mc     Trend to forecast state, arrows, labels
  StormMonitor.mc         Latching storm alert with hysteresis and a re-arm window
  PressureFormatter.mc    hPa / inHg / mmHg conversion and formatting
  AppSettings.mc          Typed, validated access to the property store
  *Test.mc                Unit and render tests, excluded from shipping builds
resources/                Strings, settings, properties, 40x40 launcher icon
resources-round-218x218/  36x36 launcher icon for the smaller screens
tools/                    Launcher icon generator
```

## Design notes

A few decisions that are not obvious from the code:

**Watch faces cannot vibrate.** The platform refuses `Toybox.Attention` to
watch faces, and the refusal is a *thrown permission error*, not a missing
symbol — so `Toybox has :Attention` returns true and the face dies on the next
line. The storm alert is therefore visual only. This is the kind of bug the
render smoke tests exist to find.

**The buffer is written to flash about once an hour, not every sample.**
Persisting on every retained sample would mean a flash write every 15 minutes
for the life of the device. Writing every fourth sample costs at most 45
minutes of history after a hard reset.

**History older than six hours is discarded on restore**, and the storm alert
will not fire from data older than one hour. Readings from a previous life of
the device say nothing about the weather now.

**Priming runs on the first draw, not in `initialize()`.** The sensor history
is not readable while the view is being constructed; asking there returns an
empty iterator.

### Notes on the reading

The pressure shown is the **raw ambient reading, not corrected to sea level**.
That is why a watch at altitude — or the simulator — shows something well below
1013 hPa. It makes no difference to the forecast, which depends only on the
change over time, but it does mean the number will not match a weather report.

## License

MIT — see [LICENSE](LICENSE).
