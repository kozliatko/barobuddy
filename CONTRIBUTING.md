# Contributing to BaroBuddy

Thanks for taking an interest. This is a small project with a narrow purpose —
a barometric watch face that works well on a Forerunner 935 — so the bar for
new features is deliberately high, while fixes, device support and test
coverage are always welcome.

## Before you start

Open an issue first for anything larger than a bug fix. It saves you writing
code that turns out to be a poor fit for a watch that redraws once a minute on
a strict power budget.

## Setting up

You need the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/)
(the project targets API 3.0.0) and a developer key. Both are covered in the
[README](README.md#building-from-source).

## Every change must

1. **Build clean at `-l 3`, with `-w`, on all six devices, in debug and
   release.** No errors, no warnings. The strictest type checker is not
   optional here; it is what catches the nullable returns that would otherwise
   only fail on a watch you do not own.

   ```bash
   for d in fr935 fenix5 fenix5s fenix5x fenixchronos d2charlie; do
       monkeyc -f monkey.jungle -d $d -o /tmp/$d.prg \
               -y ~/.garmin/developer_key.der -w -l 3 || echo "FAILED: $d"
   done
   ```

2. **Pass the full test suite.**

   ```bash
   monkeyc -f monkey.jungle -d fr935 -o bin/BaroBuddyTest.prg \
           -y ~/.garmin/developer_key.der --unit-test -w -l 3
   monkeydo bin/BaroBuddyTest.prg fr935 -t
   ```

3. **Come with tests** if it changes behaviour. Logic belongs in a testable
   module rather than in a drawing routine, which is why `PressureBuffer`,
   `WeatherPredictor`, `StormMonitor`, `PressureFormatter` and `AppSettings`
   exist as separate units. If a change can only be verified by looking at the
   screen, it is usually a sign the logic wants extracting.

## Code style

Garmin's own conventions, which the existing source follows throughout:

- `PascalCase` for classes and modules, `camelCase` for functions and
  variables, `UPPER_SNAKE_CASE` for constants.
- A leading underscore on private members: `_buffer`, `_readPressure()`.
- `private`, not the deprecated `hidden`.
- Four spaces, no tabs.
- Full `(:type)` annotations on every parameter, return and member. This is
  what makes `-l 3` possible.
- `//!` for documentation comments, `//` for inline explanation.

Comments explain *why*, not *what*. The interesting facts in this codebase are
platform constraints — that watch faces are refused `Toybox.Attention`, that
flash writes have a lifetime cost, that sensor history is unreadable during
view construction — and those are worth a sentence where they bite. A comment
restating the line below it is not.

Documentation and comments are in English.

## Testing conventions

- `(:test)` functions are auto-registered as test cases and called with a
  `Test.Logger`. A shared helper must therefore live inside a `(:test) module`,
  not as a free function, or the runner will call it as a test with the wrong
  arguments.
- Tests that write to `Application.Storage` or the property store must restore
  what they changed in a `finally` block, so the suite can run in any order.
- Prefer `Test.assertMessage` over bare `Test.assert`, with a message that
  includes the offending value.

## Adding a device

Add an `<iq:product>` entry to `manifest.xml`, check that the launcher icon
resolves for its screen size (see `resources-round-218x218/` for how a second
size is handled), generate the icon with `tools/make_launcher_icon.py`, and
confirm a clean `-l 3` build. Since the layout is computed from font metrics
rather than fixed coordinates, a new round device of a supported screen size
usually needs nothing else — but do load it in the simulator and check that
nothing collides at the top and bottom of the circle.

## Reporting bugs

Please include your watch model, its firmware version, the Connect IQ version,
and what the face was showing versus what you expected. A photograph of the
watch is worth more than a description.
