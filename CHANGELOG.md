# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Initial development. Nothing has been released yet.

### Added

- Barometric watch face for eleven Connect IQ devices: Forerunner 935 and 965,
  vívoactive 3, fēnix 5, 5S and 5X, fēnix Chronos, D2 Charlie, the fēnix 7X
  profile that also covers the Enduro 2, tactix 7 and quatix 7X Solar, and the
  fēnix 8 AMOLED in both 43mm and 47/51mm, the latter also covering the
  tactix 8 and quatix 8.
- Always-on screen for panels that report `requiresBurnInProtection`, which on
  the supported devices means the Forerunner 965 and the fēnix 8 AMOLED:
  partial updates are given up,
  the sleeping face is reduced to the time, the reading and any storm warning
  in grey, and the group is shifted a few pixels every minute so no pixel stays
  lit. It draws 1.2% of the panel's luminance against Garmin's 10% budget.
- Six-hour pressure trend from a 24-slot ring buffer with a 15-minute minimum
  sample spacing, fitted by least-squares regression and normalised to
  hPa per 6 hours.
- Five-state forecast with icon, coloured trend arrow and text label.
- Storm alert on a rapid three-hour pressure drop, with hysteresis between the
  trigger and clear thresholds and a three-hour re-arm window. Its threshold is
  configurable from 2 to 6 hPa of fall over three hours — the same scale the
  watch's built-in Storm Alert uses, so the two can be set to fire together.
- Priming of the pressure buffer from `SensorHistory` on first draw, so the
  face is useful within minutes of installation rather than after six hours of
  wear.
- Pressure graph of the recent trace, replaced by the storm banner while an
  alert is latched.
- Status row of three configurable cells, each one selectable between heart
  rate, steps, battery, calories, distance, floors climbed, notifications and
  off. Cells set to off are dropped and the rest spread over the whole row.
- Seconds redrawn through `onPartialUpdate()` with a clip region, so the
  low-power path stays inside the power budget.
- Persistence of the pressure buffer to `Application.Storage`, written every
  fourth retained sample to limit flash wear, skipped when nothing has changed
  since the last write, and discarded on restore if it is more than six hours
  old.
- Priming of the buffer from `SensorHistory`, on the first draw and again
  whenever the newest sample is more than half an hour old, which is what a
  sport activity leaves behind: the face does not run during the activity, the
  watch's barometer log does.
- Settings for units (hPa / inHg / mmHg), seconds, graph, the storm banner and
  the three status row cells, with validation of out-of-range values from the
  property store.
- 64 unit and render tests, including off-screen `BufferedBitmap` smoke tests
  covering every forecast state, every status field, the empty first-run
  buffer and a full sleep/wake cycle.
- Clock font chosen at layout time from the measured height of the candidates,
  so the stack keeps its proportions on screens whose fonts are scaled
  differently.
- English registered as its own language bucket in `monkey.jungle`, pointed at
  the base strings rather than a copy of them, so the settings labels resolve
  in Garmin Connect.
- Launcher icon generator for both required icon sizes.

### Notes

- The storm alert is visual only. The platform refuses `Toybox.Attention` to
  watch faces, and the refusal is a thrown permission error rather than a
  missing symbol, so it cannot be guarded with a `has` check.
