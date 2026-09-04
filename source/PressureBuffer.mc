using Toybox.Lang;

// Rolling buffer of barometric pressure samples plus the linear-regression
// trend over that buffer.
//
// Storage layout: two parallel flat arrays instead of an Array<[t, p]>. On the
// FR935 (96 kB watch-face budget) 24 two-element sub-arrays cost roughly half a
// kilobyte in object headers alone, and the flat form is what Task 10 needs to
// hand to Application.Storage anyway.
//
// Timestamps are epoch seconds (Time.now().value()), NOT System.getTimer():
// getTimer() is milliseconds since boot and resets on every restart, which
// would corrupt the buffer as soon as it is restored from storage.
class PressureBuffer {

    // Sanity window for a barometric reading in Pascals. Roughly sea level +
    // 100 hPa down to ~9000 m altitude; anything outside is a sensor glitch.
    private const MIN_VALID_PA = 30000.0;
    private const MAX_VALID_PA = 110000.0;

    private var _times as Lang.Array<Lang.Number>;      // epoch seconds, ascending
    private var _pressures as Lang.Array<Lang.Float>;   // Pascals
    private var _capacity as Lang.Number;               // max retained samples
    private var _minInterval as Lang.Number;            // min seconds between samples
    private var _trend as Lang.Float;                   // cached trend, Pa/s
    private var _dirty as Lang.Boolean;                 // recompute flag

    // capacity      — how many samples to retain
    // minIntervalSec — samples arriving sooner than this after the last stored
    //                  one are discarded. onUpdate() fires once per minute, so
    //                  without this gate a 24-slot buffer would only ever span
    //                  24 minutes instead of the intended 6 hours.
    //                  24 slots x 900 s = 6 h.
    function initialize(capacity as Lang.Number, minIntervalSec as Lang.Number) {
        _times = [];
        _pressures = [];
        _capacity = capacity;
        _minInterval = minIntervalSec;
        _trend = 0.0;
        _dirty = false;
    }

    // Offers a sample to the buffer. Returns true if it was retained.
    // Rejects: implausible pressures, non-advancing timestamps (clock change or
    // a repeat of the same SensorHistory sample) and samples that arrive before
    // minInterval has elapsed.
    function addSample(timestamp as Lang.Number?, pressure as Lang.Numeric?) as Lang.Boolean {
        if (timestamp == null || pressure == null) {
            return false;
        }

        var pa = pressure.toFloat();
        if (pa < MIN_VALID_PA || pa > MAX_VALID_PA) {
            return false;
        }

        var n = _times.size();
        if (n > 0) {
            var last = _times[n - 1];
            if (timestamp <= last) {
                return false;
            }
            if (timestamp - last < _minInterval) {
                return false;
            }
        }

        _times.add(timestamp);
        _pressures.add(pa);

        if (_times.size() > _capacity) {
            var from = _times.size() - _capacity;
            // slice() takes (startIndex, endIndex); a null end means "to the
            // end of the array" and keeps the newest samples.
            _times = _times.slice(from, null);
            _pressures = _pressures.slice(from, null);
        }

        _dirty = true;
        return true;
    }

    // Trend in Pa/s (slope of the least-squares fit over the whole buffer).
    function getTrend() as Lang.Float {
        if (_dirty) {
            _computeTrend();
        }
        return _trend;
    }

    // Trend in hPa per 6 hours — the unit WeatherPredictor classifies on.
    function getTrendHpa6h() as Lang.Float {
        return getTrend() * 21600.0 / 100.0;
    }

    // Most recent pressure in Pa, or null if the buffer is empty.
    function getLastPressure() as Lang.Float? {
        var n = _pressures.size();
        if (n == 0) {
            return null;
        }
        return _pressures[n - 1];
    }

    // Timestamp of the most recent sample, or null.
    function getLastTimestamp() as Lang.Number? {
        var n = _times.size();
        if (n == 0) {
            return null;
        }
        return _times[n - 1];
    }

    // Seconds between the oldest and newest sample. The view uses this to
    // decide whether there is enough history to show a forecast at all.
    function getSpanSeconds() as Lang.Number {
        var n = _times.size();
        if (n < 2) {
            return 0;
        }
        return _times[n - 1] - _times[0];
    }

    // Pressure drop in hPa over the last windowSeconds, measured as
    // (mean over the window) - (current). Positive means falling pressure.
    // Returns null when the window holds fewer than minSamples readings.
    // Used by the storm alert in Task 7.
    function getDropHpa(windowSeconds as Lang.Number, minSamples as Lang.Number) as Lang.Float? {
        var n = _times.size();
        if (n < minSamples) {
            return null;
        }

        var cutoff = _times[n - 1] - windowSeconds;
        var sum = 0.0;
        var count = 0;

        for (var i = n - 1; i >= 0; i--) {
            if (_times[i] < cutoff) {
                break;
            }
            sum += _pressures[i];
            count++;
        }

        if (count < minSamples) {
            return null;
        }

        var mean = sum / count;
        return (mean - _pressures[n - 1]) / 100.0;
    }

    // Resamples the buffer to `width` points normalised to 0.0 .. 1.0 for the
    // mini graph. Returns an empty array when there is nothing to plot.
    function getNormalizedSamples(width as Lang.Number) as Lang.Array<Lang.Float> {
        var n = _pressures.size();
        if (n < 2 || width < 2) {
            return [];
        }

        var min = _pressures[0];
        var max = _pressures[0];
        for (var i = 1; i < n; i++) {
            var p = _pressures[i];
            if (p < min) { min = p; }
            if (p > max) { max = p; }
        }

        var range = max - min;
        if (range <= 0.0) {
            range = 1.0;
        }

        var result = new Lang.Array<Lang.Float>[width];
        // Map point i onto the sample range so that i == 0 -> oldest and
        // i == width-1 -> newest.
        var step = (n - 1).toFloat() / (width - 1);
        for (var i = 0; i < width; i++) {
            var idx = (i * step + 0.5).toNumber();
            if (idx >= n) { idx = n - 1; }
            // Stays a Float: the graph code multiplies this by the plot height.
            result[i] = (_pressures[idx] - min) / range;
        }

        return result;
    }

    function size() as Lang.Number {
        return _times.size();
    }

    function clear() as Void {
        _times = [];
        _pressures = [];
        _trend = 0.0;
        _dirty = false;
    }

    // --- Persistence (used by Task 10) ---------------------------------------

    // Flattens to [t0, p0, t1, p1, ...] for Application.Storage.
    function toArray() as Lang.Array<Lang.Numeric> {
        var n = _times.size();
        var out = new Lang.Array<Lang.Numeric>[n * 2];
        for (var i = 0; i < n; i++) {
            out[i * 2] = _times[i];
            out[i * 2 + 1] = _pressures[i];
        }
        return out;
    }

    // Restores from toArray(). Replaces any current contents. Samples still go
    // through addSample(), so a corrupt or stale blob cannot poison the buffer.
    function fromArray(data as Lang.Array?) as Void {
        clear();
        if (data == null) {
            return;
        }
        for (var i = 0; i + 1 < data.size(); i += 2) {
            // The blob comes back from storage untyped. addSample() re-checks
            // both values, so a wrong type here is rejected, not trusted.
            addSample(data[i] as Lang.Number?, data[i + 1] as Lang.Numeric?);
        }
    }

    // --- Private -------------------------------------------------------------

    private function _computeTrend() as Void {
        var n = _times.size();
        _dirty = false;

        if (n < 2) {
            _trend = 0.0;
            return;
        }

        // Times are reduced relative to the first sample before touching
        // floating point. Monkey C Floats are 32-bit, so a raw epoch second
        // (~1.8e9) has no usable precision left for the regression.
        var t0 = _times[0];

        var sumT = 0.0;
        var sumP = 0.0;
        for (var i = 0; i < n; i++) {
            sumT += (_times[i] - t0).toFloat();
            sumP += _pressures[i];
        }

        var meanT = sumT / n;
        var meanP = sumP / n;

        var num = 0.0;
        var den = 0.0;
        for (var i = 0; i < n; i++) {
            var dt = (_times[i] - t0).toFloat() - meanT;
            var dp = _pressures[i] - meanP;
            num += dt * dp;
            den += dt * dt;
        }

        if (den == 0.0) {
            _trend = 0.0;
        } else {
            _trend = num / den; // Pa/s
        }
    }
}
