# Connect IQ Store assets

The Store listing is edited by hand at [apps.garmin.com](https://apps.garmin.com),
so these files are kept here to be uploaded rather than referenced from
anywhere in the app.

| File | Device | Size |
| --- | --- | --- |
| `fr935.png` | Forerunner 935 | 240×240 |
| `fenix7x.png` | fēnix 7X family | 280×280 |
| `fenix5s.png` | fēnix 5S | 218×218 |
| `fr965.png` | Forerunner 965 | 454×454 |
| `fr965-always-on.png` | Forerunner 965, always-on screen | 454×454 |
| `fenix8-43mm.png` | fēnix 8 43mm | 416×416 |
| `vivoactive3.png` | vívoactive 3 | 240×240 |

That is one file per screen size the app ships for, which is what the listing
needs: the Store picks the screenshot whose resolution matches the watch the
visitor is browsing from.

Each one is the watch display at its native resolution, cropped out of a
simulator screenshot with `tools/crop_screenshot.py` and not resized, so the
Store shows exactly what the watch draws.

To replace the listing's screenshots: sign in at apps.garmin.com, open the app,
**Edit App** → **Images**, remove the old screenshots and upload these. The
change applies to the listing on its own; it does not need a new `.iq` upload.

Regenerate them after a layout change by capturing a screenshot per device in
the simulator — see the header of `tools/crop_screenshot.py` for the
calibration step the cropper needs.
