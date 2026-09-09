# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Initial development. Nothing has been released yet.

### Added

- Barometric watch face for six Connect IQ devices: Forerunner 935, fēnix 5,
  5S and 5X, fēnix Chronos and D2 Charlie.
- Six-hour pressure trend from a 24-slot ring buffer with a 15-minute minimum
  sample spacing, fitted by least-squares regression and normalised to
  hPa per 6 hours.
- Five-state forecast with icon, coloured trend arrow and text label.
- Storm alert on a rapid three-hour pressure drop, with hysteresis between the
  trigger and clear thresholds and a three-hour re-arm window.
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
  fourth retained sample to limit flash wear, and discarded on restore if it is
  more than six hours old.
- Settings for units (hPa / inHg / mmHg), seconds, graph, the storm banner and
  the three status row cells, with validation of out-of-range values from the
  property store.
- 59 unit and render tests, including off-screen `BufferedBitmap` smoke tests
  covering every forecast state, every status field, the empty first-run
  buffer and a full sleep/wake cycle.
- Launcher icon generator for both required icon sizes.

### Notes

- The storm alert is visual only. The platform refuses `Toybox.Attention` to
  watch faces, and the refusal is a thrown permission error rather than a
  missing symbol, so it cannot be guarded with a `has` check.
