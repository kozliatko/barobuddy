using Toybox.Activity;
using Toybox.ActivityMonitor;
using Toybox.Application.Storage;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.SensorHistory;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;

//! Main watch face view: reads the barometer, keeps the rolling pressure
//! buffer, persists it and draws the whole face.
//!
//! Nothing is drawn from fixed pixel coordinates. The display is round, so a
//! layout laid out for a 240x240 rectangle puts its corners off screen; the
//! positions below are stacked in onLayout() from the real font metrics and
//! kept inside the circle.
class BaroBuddyView extends WatchUi.WatchFace {

    //! 24 samples at least 15 minutes apart span the intended 6 hours.
    private const BUFFER_CAPACITY = 24;
    private const BUFFER_MIN_INTERVAL_S = 900;

    //! No forecast is shown until the buffer covers at least this much time.
    //! Extrapolating a 6 hour tendency from a few minutes of data is noise.
    private const MIN_FORECAST_SPAN_S = 3600;

    //! Storm alert. The window is three hours because that is the span over
    //! which a "rapid fall" is conventionally defined, and because at one
    //! sample per 15 minutes a 30 minute window holds three readings at best.
    //! See StormMonitor for why the trigger is half the drop it detects.
    private const STORM_WINDOW_S = 10800;
    private const STORM_MIN_SAMPLES = 5;
    private const STORM_TRIGGER_HPA = 1.5;
    private const STORM_CLEAR_HPA = 1.0;
    private const STORM_REARM_S = 10800;

    //! Readings older than this say nothing about the weather right now, so
    //! they neither restore from storage nor feed the storm alert.
    private const MAX_DATA_AGE_S = 21600;
    private const MAX_ALERT_DATA_AGE_S = 3600;

    //! Upper bound on the one-off walk through the barometer history in
    //! _primeFromHistory(). The FR935 keeps 200 samples; the limit is a stop
    //! against a device that reports more than the buffer could ever use.
    private const HISTORY_SCAN_LIMIT = 400;

    //! Persistence. Writing on every retained sample would mean a flash write
    //! every 15 minutes for the life of the device; every fourth sample is
    //! roughly hourly and loses at most 45 minutes of history on a hard reset.
    private const STORAGE_KEY_SAMPLES = "PressureSamples";
    private const SAVE_EVERY_SAMPLES = 4;

    //! Palette. All values exist in the 64 colour MIP palette of the FR935.
    private const COLOR_DATE = 0x555555;
    private const COLOR_PRESSURE = 0xAAAAAA;
    private const COLOR_GRAPH = 0x555555;
    private const COLOR_SECONDS = 0xAAAAAA;
    private const COLOR_STATUS = Graphics.COLOR_WHITE;
    private const COLOR_HEART = Graphics.COLOR_RED;
    private const COLOR_BATTERY_LOW = Graphics.COLOR_RED;
    private const COLOR_STORM = Graphics.COLOR_RED;

    //! Battery level below which the icon turns red.
    private const BATTERY_LOW_PCT = 15;

    //! Space between a status icon and its value.
    private const STATUS_GAP = 2;

    private const FONT_TIME = Graphics.FONT_NUMBER_THAI_HOT;
    private const FONT_DATE = Graphics.FONT_XTINY;
    private const FONT_PRESSURE = Graphics.FONT_TINY;
    private const FONT_SECONDS = Graphics.FONT_TINY;
    private const FONT_STATUS = Graphics.FONT_XTINY;

    private var _buffer as PressureBuffer;
    private var _settings as AppSettings;
    private var _storm as StormMonitor;

    private var _forecast as WeatherPredictor.Forecast;
    private var _hasForecast as Lang.Boolean;
    private var _lowPower as Lang.Boolean;
    private var _partialUpdatesAllowed as Lang.Boolean;
    private var _unsavedSamples as Lang.Number;
    private var _primed as Lang.Boolean;
    private var _stormBanner as Lang.String?;

    // Cached settings, refreshed by _applySettings().
    private var _showSeconds as Lang.Boolean;
    private var _showGraph as Lang.Boolean;
    private var _showHeartRate as Lang.Boolean;
    private var _stormAlertEnabled as Lang.Boolean;
    private var _pressureUnit as Lang.Number;

    // Layout, all computed in onLayout().
    private var _centerX as Lang.Number;
    private var _iconX as Lang.Number;
    private var _iconY as Lang.Number;
    private var _iconSize as Lang.Number;
    private var _timeX as Lang.Number;
    private var _timeY as Lang.Number;
    private var _timeW as Lang.Number;
    private var _secondsX as Lang.Number;
    private var _secondsY as Lang.Number;
    private var _secondsW as Lang.Number;
    private var _secondsH as Lang.Number;
    private var _dateY as Lang.Number;
    private var _pressureY as Lang.Number;
    private var _arrowSize as Lang.Number;
    private var _graphX as Lang.Number;
    private var _graphY as Lang.Number;
    private var _graphW as Lang.Number;
    private var _graphH as Lang.Number;
    private var _graphPoints as Lang.Number;
    private var _bannerY as Lang.Number;
    private var _statusY as Lang.Number;
    private var _statusW as Lang.Number;
    private var _statusH as Lang.Number;
    private var _statusIconSize as Lang.Number;

    public function initialize() {
        WatchFace.initialize();

        _buffer = new PressureBuffer(BUFFER_CAPACITY, BUFFER_MIN_INTERVAL_S);
        _settings = new AppSettings();
        _storm = new StormMonitor(STORM_TRIGGER_HPA, STORM_CLEAR_HPA, STORM_REARM_S);

        _forecast = WeatherPredictor.FORECAST_STEADY;
        _hasForecast = false;
        _lowPower = false;
        // Devices without partial update support simply never call it; asking
        // up front lets the seconds be hidden instead of frozen there.
        _partialUpdatesAllowed = (WatchUi.WatchFace has :onPartialUpdate);
        _unsavedSamples = 0;
        _primed = false;
        _stormBanner = null;

        _showSeconds = _settings.getShowSeconds();
        _showGraph = _settings.getShowGraph();
        _showHeartRate = _settings.getShowHeartRate();
        _stormAlertEnabled = _settings.getStormAlert();
        _pressureUnit = _settings.getPressureUnit();

        _centerX = 0;
        _iconX = 0;
        _iconY = 0;
        _iconSize = 0;
        _timeX = 0;
        _timeY = 0;
        _timeW = 0;
        _secondsX = 0;
        _secondsY = 0;
        _secondsW = 0;
        _secondsH = 0;
        _dateY = 0;
        _pressureY = 0;
        _arrowSize = 0;
        _graphX = 0;
        _graphY = 0;
        _graphW = 0;
        _graphH = 0;
        _graphPoints = 0;
        _bannerY = 0;
        _statusY = 0;
        _statusW = 0;
        _statusH = 0;
        _statusIconSize = 0;

        _restoreBuffer();
    }

    //! Stacks the layout from the measured font heights so it adapts to any
    //! screen size rather than hard coding 240x240 offsets.
    //!
    //! The stack is built bottom up. On a round screen the vertical position of
    //! the three column status row is dictated by how wide that row has to be,
    //! so it is placed first and everything else is piled on top of it.
    public function onLayout(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var centerY = h / 2;
        // Two pixels in from the bezel so no glyph is clipped by the round edge.
        var radius = (w < h ? w : h) / 2 - 2;

        var timeH = Graphics.getFontHeight(FONT_TIME);
        var dateH = Graphics.getFontHeight(FONT_DATE);
        var pressureH = Graphics.getFontHeight(FONT_PRESSURE);

        _centerX = w / 2;

        _statusH = Graphics.getFontHeight(FONT_STATUS);
        // 78% is the widest this row can be before the chord pushes it up
        // into the graph and squeezes the weather icon off the top. It is also
        // about the narrowest that fits a four digit step count, which is why
        // _formatSteps() and _fit() shorten rather than assume.
        _statusW = w * 78 / 100;
        _statusIconSize = _statusH * 50 / 100;
        _statusY = centerY + _chordOffset(radius, _statusW / 2) - _statusH;

        _graphH = h * 16 / 240;
        if (_graphH < 8) {
            _graphH = 8;
        }
        _graphW = w * 130 / 240;
        _graphX = _centerX - (_graphW / 2);
        _graphY = _statusY - 4 - _graphH;
        // One point per ~5 px keeps the polyline smooth without oversampling
        // a buffer that only holds BUFFER_CAPACITY readings.
        _graphPoints = _graphW / 5;

        // The banner replaces the graph, but it is text and therefore taller,
        // so it is centred on the graph band rather than aligned to it.
        _bannerY = _graphY + (_graphH / 2) - (dateH / 2);

        _pressureY = _graphY - 2 - pressureH;
        _arrowSize = pressureH / 2;

        _dateY = _pressureY - 2 - dateH;

        _timeY = _dateY - timeH;
        if (_timeY < 0) {
            _timeY = 0;
        }

        _iconSize = h * 28 / 240;
        _iconX = _centerX - (_iconSize / 2);
        _iconY = (_timeY - _iconSize) / 2;
        if (_iconY < 2) {
            _iconY = 2;
        }

        // Both widths are measured whether or not seconds are enabled, so that
        // toggling the setting later does not need another Dc.
        _timeW = dc.getTextWidthInPixels("00:00", FONT_TIME);
        _secondsW = dc.getTextWidthInPixels(":00", FONT_SECONDS);
        _secondsH = Graphics.getFontHeight(FONT_SECONDS);
        // Seconds sit on the baseline of the big time block.
        _secondsY = _timeY + timeH - _secondsH;

        _applySettings();
        _logLayout(dc, w, h);
    }

    public function onShow() as Void {
    }

    //! Last chance to persist before the face is torn down.
    public function onHide() as Void {
        saveBuffer();
    }

    //! Full redraw. Runs once per minute in low-power mode and once per second
    //! for the first few seconds after a gesture.
    public function onUpdate(dc as Graphics.Dc) as Void {
        _primeFromHistory();
        _readPressure();
        _updateForecast();
        _checkStormAlert();
        _logState();

        // Clears whatever clip onPartialUpdate() left behind before it can
        // truncate the full redraw.
        dc.clearClip();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        _drawWeatherIcon(dc);
        _drawTime(dc);
        if (_secondsVisible()) {
            _drawSeconds(dc);
        }
        _drawDate(dc);
        _drawPressure(dc);

        // The banner takes the graph's row: during a storm the warning matters
        // more than the trace that led to it.
        if (_stormAlertEnabled && _storm.isActive()) {
            _drawStormBanner(dc);
        } else if (_showGraph && !_lowPower) {
            // The graph is dropped in low power, matching the AOD design.
            _drawGraph(dc);
        }

        _drawStatusRow(dc);
    }

    //! Per-second update in low-power mode. Only the seconds are touched, and
    //! only inside a clip region — the rest of the screen keeps its pixels.
    //!
    //! Must stay under the power budget: no sensor reads, no forecast work, one
    //! string allocation.
    public function onPartialUpdate(dc as Graphics.Dc) as Void {
        if (!_showSeconds || !_partialUpdatesAllowed) {
            return;
        }

        dc.setClip(_secondsX, _secondsY, _secondsW + 2, _secondsH);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        _drawSeconds(dc);
        dc.clearClip();
    }

    public function onEnterSleep() as Void {
        _lowPower = true;
        WatchUi.requestUpdate();
    }

    public function onExitSleep() as Void {
        _lowPower = false;
        WatchUi.requestUpdate();
    }

    public function isLowPower() as Lang.Boolean {
        return _lowPower;
    }

    //! Called by the delegate when onPartialUpdate() overran its power budget.
    //! Seconds are given up rather than risk the face being disabled.
    public function onPowerBudgetExceeded() as Void {
        _partialUpdatesAllowed = false;
        WatchUi.requestUpdate();
    }

    //! Called by the app when settings change in Garmin Connect Mobile.
    public function onSettingsChanged() as Void {
        _applySettings();
    }

    // --- Data ---------------------------------------------------------------

    //! Offers the newest barometer reading to the buffer. The buffer discards
    //! anything that arrives inside its minimum interval, so calling this every
    //! minute is cheap.
    private function _readPressure() as Void {
        if (!(Toybox has :SensorHistory)) {
            return;
        }
        if (!(SensorHistory has :getPressureHistory)) {
            return;
        }

        // getPressureHistory() is declared non-nullable; the two has-checks
        // above are what guards a device without a barometer.
        var iterator = SensorHistory.getPressureHistory({});
        var sample = iterator.next();
        if (sample == null || sample.data == null || sample.when == null) {
            return;
        }

        // The sample carries its own timestamp; "now" would be wrong for a
        // reading the device recorded a minute ago.
        if (!_buffer.addSample(sample.when.value(), sample.data)) {
            return;
        }

        _unsavedSamples++;
        if (_unsavedSamples >= SAVE_EVERY_SAMPLES) {
            saveBuffer();
        }
    }

    //! Fills the buffer from the barometer history the watch has been logging
    //! all along.
    //!
    //! Without this the face collects its own samples one minimum interval at a
    //! time and stays blank for the first six hours after install, even though
    //! the device already knows what the pressure has been doing. The FR935
    //! keeps 200 pressure samples at 72 second spacing, just under four hours,
    //! which is past MIN_FORECAST_SPAN_S and enough to draw a forecast on the
    //! very first frame.
    //!
    //! Runs once, on the first draw rather than in initialize(): the history is
    //! not readable yet while the view is being constructed, and asking there
    //! returns an empty iterator. A buffer that survived a restart still keeps
    //! precedence, because addSample() rejects anything older than what it
    //! already holds.
    private function _primeFromHistory() as Void {
        if (_primed) {
            return;
        }
        _primed = true;

        if (!(Toybox has :SensorHistory)) {
            return;
        }
        if (!(SensorHistory has :getPressureHistory)) {
            return;
        }
        // Already have enough to forecast from; walking the history would cost
        // a few hundred iterations to change nothing.
        if (_buffer.getSpanSeconds() >= MIN_FORECAST_SPAN_S) {
            return;
        }

        // addSample() only accepts increasing timestamps, so the history has to
        // be walked forwards. Thinning it to the buffer's own spacing is left
        // to the buffer: its minimum interval drops the samples in between and
        // its capacity keeps the newest.
        var iterator = SensorHistory.getPressureHistory({
            :order => SensorHistory.ORDER_OLDEST_FIRST
        });

        // Whatever was restored is thin by the check above, but its newest
        // sample alone sits ahead of the entire history and addSample() would
        // reject every one of them behind it. Set it aside, fill from history,
        // then offer it back: samples newer than the history still land, the
        // rest are dropped as duplicates of what the history already gave.
        var carried = _buffer.toArray();
        _buffer.clear();

        var sample = iterator.next();
        var scanned = 0;
        var kept = 0;
        while (sample != null && scanned < HISTORY_SCAN_LIMIT) {
            if (sample.data != null && sample.when != null) {
                if (_buffer.addSample(sample.when.value(), sample.data)) {
                    kept++;
                }
            }
            sample = iterator.next();
            scanned++;
        }

        // fromArray() would clear() first and throw the history away, so the
        // carried samples go back in through the same gate as the history.
        for (var i = 0; i + 1 < carried.size(); i += 2) {
            _buffer.addSample(carried[i].toNumber(), carried[i + 1]);
        }

        _logPrime(scanned, kept);
    }

    (:debug)
    private function _logPrime(scanned as Lang.Number, kept as Lang.Number) as Void {
        System.println("prime scanned=" + scanned + " kept=" + kept
            + " size=" + _buffer.size()
            + " span=" + _buffer.getSpanSeconds() + "s");
    }

    (:release)
    private function _logPrime(scanned as Lang.Number, kept as Lang.Number) as Void {
    }

    private function _updateForecast() as Void {
        if (_buffer.getSpanSeconds() >= MIN_FORECAST_SPAN_S) {
            _forecast = WeatherPredictor.classify(_buffer.getTrendHpa6h());
            _hasForecast = true;
        } else {
            _hasForecast = false;
        }
    }

    //! Feeds the storm monitor and surfaces the banner when it latches a new
    //! warning.
    //!
    //! The plan called for a vibration here. Connect IQ does not allow it: a
    //! watch face is refused Toybox.Attention outright, and the refusal is a
    //! thrown permission error rather than a missing symbol, so `Toybox has
    //! :Attention` passes and the face dies on the next line. The warning is
    //! therefore visual only.
    private function _checkStormAlert() as Void {
        var last = _buffer.getLastTimestamp();
        if (last == null) {
            return;
        }

        var now = Time.now().value();
        // Stale history — the watch was off, or the barometer stopped
        // reporting. Whatever it says is about the past, not about now.
        if (now - last > MAX_ALERT_DATA_AGE_S) {
            return;
        }

        var drop = _buffer.getDropHpa(STORM_WINDOW_S, STORM_MIN_SAMPLES);
        if (_storm.update(drop, now) && _stormAlertEnabled) {
            // A storm can latch during a partial update, when only the seconds
            // are being redrawn. Ask for a full pass so the banner appears now
            // rather than at the next minute boundary.
            WatchUi.requestUpdate();
        }
    }

    // --- Persistence --------------------------------------------------------

    //! Writes the buffer to Application.Storage. Public so the app can flush on
    //! shutdown.
    public function saveBuffer() as Void {
        if (_buffer.size() == 0) {
            return;
        }
        try {
            Storage.setValue(STORAGE_KEY_SAMPLES,
                _buffer.toArray() as Lang.Array<Storage.ValueType>);
            _unsavedSamples = 0;
        } catch (e) {
            // A full or unavailable storage is not worth crashing the face
            // over; the buffer keeps working in RAM.
            _unsavedSamples = 0;
        }
    }

    //! Reloads the buffer saved by a previous run so a restart does not throw
    //! away six hours of history. PressureBuffer.fromArray() re-validates every
    //! sample, so a corrupt blob degrades to an empty buffer.
    private function _restoreBuffer() as Void {
        var data = null;
        try {
            data = Storage.getValue(STORAGE_KEY_SAMPLES);
        } catch (e) {
            return;
        }

        if (!(data instanceof Lang.Array)) {
            return;
        }

        _buffer.fromArray(data as Lang.Array);

        var last = _buffer.getLastTimestamp();
        if (last == null) {
            return;
        }

        var now = Time.now().value();
        // Too old to describe the current weather, or stamped in the future by
        // a clock that has since been corrected.
        if (now - last > MAX_DATA_AGE_S || last > now) {
            _buffer.clear();
        }
    }

    // --- Drawing ------------------------------------------------------------

    //! Seconds are only drawn when they can actually keep ticking: in high
    //! power every redraw refreshes them, in low power only onPartialUpdate()
    //! can, and a frozen "42" is worse than no seconds at all.
    private function _secondsVisible() as Lang.Boolean {
        if (!_showSeconds) {
            return false;
        }
        return !_lowPower || _partialUpdatesAllowed;
    }

    private function _drawTime(dc as Graphics.Dc) as Void {
        var clock = System.getClockTime();
        var hour = clock.hour;

        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }

        var timeStr = Lang.format("$1$:$2$", [
            hour.format("%02d"),
            clock.min.format("%02d")
        ]);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_timeX, _timeY, FONT_TIME, timeStr, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function _drawSeconds(dc as Graphics.Dc) as Void {
        var seconds = System.getClockTime().sec;
        dc.setColor(COLOR_SECONDS, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_secondsX, _secondsY, FONT_SECONDS, ":" + seconds.format("%02d"),
            Graphics.TEXT_JUSTIFY_LEFT);
    }

    private function _drawDate(dc as Graphics.Dc) as Void {
        // Gregorian.info returns names already localised for the device
        // language. System.getClockTime() carries no date at all.
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = Lang.format("$1$ $2$ $3$", [info.day_of_week, info.day, info.month]);

        dc.setColor(COLOR_DATE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, _dateY, FONT_DATE, dateStr, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Trend arrow plus the current reading, centred as one group.
    private function _drawPressure(dc as Graphics.Dc) as Void {
        var text = PressureFormatter.formatWithUnit(_buffer.getLastPressure(), _pressureUnit);

        var textW = dc.getTextWidthInPixels(text, FONT_PRESSURE);
        var arrowW = _hasForecast ? _arrowSize + 6 : 0;
        var startX = _centerX - ((textW + arrowW) / 2);

        if (_hasForecast) {
            var pressureH = Graphics.getFontHeight(FONT_PRESSURE);
            _drawArrow(
                dc,
                startX + (_arrowSize / 2),
                _pressureY + (pressureH / 2),
                WeatherPredictor.getArrowDirection(_forecast)
            );
        }

        dc.setColor(COLOR_PRESSURE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX + arrowW, _pressureY, FONT_PRESSURE, text, Graphics.TEXT_JUSTIFY_LEFT);
    }

    //! Storm warning, drawn where the graph would otherwise go.
    private function _drawStormBanner(dc as Graphics.Dc) as Void {
        if (_stormBanner == null) {
            _stormBanner = WatchUi.loadResource(Rez.Strings.StormBanner) as Lang.String;
        }

        dc.setColor(COLOR_STORM, Graphics.COLOR_TRANSPARENT);

        var textW = dc.getTextWidthInPixels(_stormBanner, FONT_DATE);
        var markSize = _statusH * 70 / 100;
        var startX = _centerX - ((textW + markSize + 6) / 2);

        _drawWarningMark(dc, startX + (markSize / 2), _bannerY + (_statusH / 2), markSize);
        dc.drawText(startX + markSize + 6, _bannerY, FONT_DATE, _stormBanner,
            Graphics.TEXT_JUSTIFY_LEFT);
    }

    //! Warning triangle with a punched-out exclamation mark.
    private function _drawWarningMark(dc as Graphics.Dc, cx as Lang.Number, cy as Lang.Number,
                                      size as Lang.Number) as Void {
        var half = size / 2;
        dc.fillPolygon([
            [cx, cy - half],
            [cx - half, cy + half],
            [cx + half, cy + half]
        ]);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        var barW = size / 6;
        if (barW < 1) {
            barW = 1;
        }
        dc.fillRectangle(cx - (barW / 2), cy - (half / 4), barW, half);
        dc.setColor(COLOR_STORM, Graphics.COLOR_TRANSPARENT);
    }

    //! Trend arrow drawn from polygons. Unicode arrows are not guaranteed to
    //! exist in the device fonts.
    private function _drawArrow(dc as Graphics.Dc, cx as Lang.Number, cy as Lang.Number,
                                direction as Lang.Number) as Void {
        var halfW = _arrowSize / 2;
        var halfH = _arrowSize / 2;

        if (direction > 0) {
            dc.setColor(Graphics.COLOR_DK_GREEN, Graphics.COLOR_TRANSPARENT);
        } else if (direction < 0) {
            dc.setColor(Graphics.COLOR_DK_RED, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(COLOR_PRESSURE, Graphics.COLOR_TRANSPARENT);
        }

        if (direction == 0) {
            // Steady: a right pointing triangle.
            dc.fillPolygon([
                [cx + halfW, cy],
                [cx - halfW, cy - halfH],
                [cx - halfW, cy + halfH]
            ]);
            return;
        }

        var up = direction > 0;
        var fast = direction.abs() > 1;

        if (!fast) {
            _fillTriangle(dc, cx, cy, halfW, halfH, up);
            return;
        }

        // Rising / falling fast: two stacked chevrons.
        var step = (halfH / 2) + 1;
        _fillTriangle(dc, cx, cy - step, halfW, halfH - 1, up);
        _fillTriangle(dc, cx, cy + step, halfW, halfH - 1, up);
    }

    private function _fillTriangle(dc as Graphics.Dc, cx as Lang.Number, cy as Lang.Number,
                                   halfW as Lang.Number, halfH as Lang.Number,
                                   up as Lang.Boolean) as Void {
        var tipY = up ? cy - halfH : cy + halfH;
        var baseY = up ? cy + halfH : cy - halfH;
        dc.fillPolygon([
            [cx, tipY],
            [cx - halfW, baseY],
            [cx + halfW, baseY]
        ]);
    }

    //! Pressure history polyline.
    private function _drawGraph(dc as Graphics.Dc) as Void {
        var points = _buffer.getNormalizedSamples(_graphPoints);
        if (points.size() < 2) {
            return;
        }

        dc.setColor(COLOR_GRAPH, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);

        var last = points.size() - 1;
        var stepX = _graphW.toFloat() / last;
        var prevX = _graphX;
        var prevY = _graphY + _graphH - (points[0] * _graphH).toNumber();

        for (var i = 1; i <= last; i++) {
            var x = _graphX + (i * stepX).toNumber();
            var y = _graphY + _graphH - (points[i] * _graphH).toNumber();
            dc.drawLine(prevX, prevY, x, y);
            prevX = x;
            prevY = y;
        }

        dc.setPenWidth(1);
    }

    // --- Status row ---------------------------------------------------------

    //! Heart rate, steps and battery across the bottom.
    //!
    //! The cells are laid out over _statusW rather than over the full screen
    //! width: at this height a round display is only about two thirds as wide
    //! as it is at the centre, and thirds of 240 px would fall off the glass.
    private function _drawStatusRow(dc as Graphics.Dc) as Void {
        var cells = _showHeartRate ? 3 : 2;
        var cellW = _statusW / cells;
        var left = _centerX - (_statusW / 2);
        var index = 0;

        // What is left for the value once the icon and its gap are taken out.
        var textW = cellW - _statusIconSize - STATUS_GAP;

        if (_showHeartRate) {
            _drawStatusCell(dc, left + (cellW / 2), COLOR_HEART, COLOR_STATUS,
                :heart, _readHeartRate());
            index++;
        }

        _drawStatusCell(dc, left + (cellW / 2) + (index * cellW), COLOR_STATUS, COLOR_STATUS,
            :steps, _formatSteps(dc, textW));
        index++;

        var battery = System.getSystemStats().battery.toNumber();
        var batteryColor = battery <= BATTERY_LOW_PCT ? COLOR_BATTERY_LOW : COLOR_STATUS;
        _drawStatusCell(dc, left + (cellW / 2) + (index * cellW), batteryColor, COLOR_STATUS,
            :battery, _fit(dc, battery.format("%d") + "%", battery.format("%d"), textW));
    }

    //! Returns `preferred` when it fits `maxW`, otherwise `fallback`.
    //!
    //! The row is measured rather than assumed: the same font is a different
    //! width on every device in the product list, and a step count grows by a
    //! digit halfway through the day.
    private function _fit(dc as Graphics.Dc, preferred as Lang.String,
                          fallback as Lang.String, maxW as Lang.Number) as Lang.String {
        if (dc.getTextWidthInPixels(preferred, FONT_STATUS) <= maxW) {
            return preferred;
        }
        return fallback;
    }

    //! One icon plus value, centred as a group on cellCx.
    private function _drawStatusCell(dc as Graphics.Dc, cellCx as Lang.Number,
                                     iconColor as Lang.Number, textColor as Lang.Number,
                                     icon as Lang.Symbol, text as Lang.String) as Void {
        var textW = dc.getTextWidthInPixels(text, FONT_STATUS);
        var startX = cellCx - ((_statusIconSize + STATUS_GAP + textW) / 2);
        var iconCx = startX + (_statusIconSize / 2);
        var iconCy = _statusY + (_statusH / 2);

        dc.setColor(iconColor, Graphics.COLOR_TRANSPARENT);
        if (icon == :heart) {
            _drawHeartIcon(dc, iconCx, iconCy, _statusIconSize);
        } else if (icon == :steps) {
            _drawStepsIcon(dc, iconCx, iconCy, _statusIconSize);
        } else {
            _drawBatteryIcon(dc, iconCx, iconCy, _statusIconSize);
        }

        dc.setColor(textColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX + _statusIconSize + STATUS_GAP, _statusY, FONT_STATUS, text,
            Graphics.TEXT_JUSTIFY_LEFT);
    }

    //! Current heart rate, or "--" when the optical sensor has nothing.
    private function _readHeartRate() as Lang.String {
        if (Toybox has :Activity) {
            var info = Activity.getActivityInfo();
            if (info != null) {
                var live = info.currentHeartRate;
                if (live != null) {
                    return live.format("%d");
                }
            }
        }

        // Off-wrist or between measurements the live value is null, so fall
        // back to the last logged sample.
        if ((Toybox has :ActivityMonitor) && (ActivityMonitor has :getHeartRateHistory)) {
            var sample = ActivityMonitor.getHeartRateHistory(1, true).next();
            if (sample != null) {
                var logged = sample.heartRate;
                if (logged != null && logged != ActivityMonitor.INVALID_HR_SAMPLE) {
                    return logged.format("%d");
                }
            }
        }

        return "--";
    }

    //! Step count, abbreviated only when the exact figure will not fit.
    //!
    //! The exact number is what people actually want; "8.4k" is the fallback
    //! for the part of the day when five digits are too wide for the cell.
    private function _formatSteps(dc as Graphics.Dc, maxW as Lang.Number) as Lang.String {
        if (!(Toybox has :ActivityMonitor)) {
            return "--";
        }
        // getInfo() is declared non-nullable; the has-check above is what
        // guards a device without an activity monitor.
        var steps = ActivityMonitor.getInfo().steps;
        if (steps == null) {
            return "--";
        }

        var exact = steps.format("%d");
        if (steps < 1000) {
            return exact;
        }

        // Above ten thousand even one decimal is more width than it is worth.
        var short = steps >= 10000
            ? (steps / 1000).format("%d") + "k"
            : (steps / 1000.0).format("%.1f") + "k";

        return _fit(dc, exact, short, maxW);
    }

    //! Two lobes and a point. Drawn rather than loaded so the status row costs
    //! no bitmap memory.
    private function _drawHeartIcon(dc as Graphics.Dc, cx as Lang.Number, cy as Lang.Number,
                                    size as Lang.Number) as Void {
        var half = size / 2;
        var lobeR = size / 4;
        if (lobeR < 1) {
            lobeR = 1;
        }
        var lobeY = cy - (size / 6);

        dc.fillCircle(cx - lobeR, lobeY, lobeR);
        dc.fillCircle(cx + lobeR, lobeY, lobeR);
        dc.fillPolygon([
            [cx - half, lobeY],
            [cx + half, lobeY],
            [cx, cy + half]
        ]);
    }

    //! A footprint: rounded sole with a separate heel.
    private function _drawStepsIcon(dc as Graphics.Dc, cx as Lang.Number, cy as Lang.Number,
                                    size as Lang.Number) as Void {
        var soleW = size * 6 / 10;
        if (soleW < 3) {
            soleW = 3;
        }
        var soleH = size * 6 / 10;
        var heelR = size / 5;
        if (heelR < 1) {
            heelR = 1;
        }

        dc.fillRoundedRectangle(cx - (soleW / 2), cy - (size / 2), soleW, soleH, soleW / 2);
        dc.fillCircle(cx, cy + (size * 3 / 10), heelR);
    }

    //! Battery outline with a fill proportional to the charge.
    private function _drawBatteryIcon(dc as Graphics.Dc, cx as Lang.Number, cy as Lang.Number,
                                      size as Lang.Number) as Void {
        var bodyW = size - 2;
        var bodyH = size * 6 / 10;
        if (bodyH < 4) {
            bodyH = 4;
        }
        var x = cx - (size / 2);
        var y = cy - (bodyH / 2);

        dc.drawRectangle(x, y, bodyW, bodyH);
        // Terminal nub on the right hand end.
        dc.fillRectangle(x + bodyW, y + (bodyH / 4), 2, bodyH / 2);

        var level = System.getSystemStats().battery.toNumber();
        if (level < 0) {
            level = 0;
        } else if (level > 100) {
            level = 100;
        }
        var fillW = (bodyW - 2) * level / 100;
        if (fillW > 0) {
            dc.fillRectangle(x + 1, y + 1, fillW, bodyH - 2);
        }
    }

    // --- Weather icon -------------------------------------------------------

    //! Weather icon, drawn from primitives so it costs no bitmap memory and
    //! scales with the screen.
    private function _drawWeatherIcon(dc as Graphics.Dc) as Void {
        var cx = _iconX + (_iconSize / 2);
        var cy = _iconY + (_iconSize / 2);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        if (!_hasForecast) {
            _drawCollectingIcon(dc, cx, cy);
            return;
        }

        switch (_forecast) {
            case WeatherPredictor.FORECAST_RISING_FAST:
                _drawSun(dc, cx + (_iconSize / 5), cy, _iconSize * 22 / 100, true);
                _drawWind(dc, cx, cy);
                break;
            case WeatherPredictor.FORECAST_RISING:
                _drawSun(dc, cx, cy, _iconSize * 26 / 100, true);
                break;
            case WeatherPredictor.FORECAST_STEADY:
                _drawSun(dc, cx + (_iconSize / 5), cy - (_iconSize / 5), _iconSize * 18 / 100, true);
                _drawCloud(dc, cx, cy + (_iconSize / 8));
                break;
            case WeatherPredictor.FORECAST_FALLING:
                _drawCloud(dc, cx, cy - (_iconSize / 8));
                _drawRain(dc, cx, cy + (_iconSize * 3 / 10));
                break;
            default:
                _drawCloud(dc, cx, cy - (_iconSize / 8));
                _drawBolt(dc, cx, cy + (_iconSize * 3 / 10));
                break;
        }
    }

    //! Shown while the buffer is still filling: three dots.
    private function _drawCollectingIcon(dc as Graphics.Dc, cx as Lang.Number,
                                         cy as Lang.Number) as Void {
        dc.setColor(COLOR_DATE, Graphics.COLOR_TRANSPARENT);
        var gap = _iconSize / 4;
        var r = _iconSize / 12;
        if (r < 1) {
            r = 1;
        }
        dc.fillCircle(cx - gap, cy, r);
        dc.fillCircle(cx, cy, r);
        dc.fillCircle(cx + gap, cy, r);
    }

    private function _drawSun(dc as Graphics.Dc, cx as Lang.Number, cy as Lang.Number,
                              r as Lang.Number, rays as Lang.Boolean) as Void {
        if (r < 2) {
            r = 2;
        }
        dc.fillCircle(cx, cy, r);

        if (!rays) {
            return;
        }

        dc.setPenWidth(2);
        var inner = r + 2;
        var outer = r + 2 + (_iconSize / 7);
        // Eight rays at 45 degree steps, using exact unit vectors so no
        // trigonometry is needed on every redraw.
        var dirs = [[10, 0], [-10, 0], [0, 10], [0, -10],
                    [7, 7], [7, -7], [-7, 7], [-7, -7]];
        for (var i = 0; i < dirs.size(); i++) {
            var dx = dirs[i][0];
            var dy = dirs[i][1];
            dc.drawLine(
                cx + (dx * inner / 10), cy + (dy * inner / 10),
                cx + (dx * outer / 10), cy + (dy * outer / 10)
            );
        }
        dc.setPenWidth(1);
    }

    private function _drawCloud(dc as Graphics.Dc, cx as Lang.Number, cy as Lang.Number) as Void {
        var s = _iconSize;
        dc.fillCircle(cx - (s * 24 / 100), cy, s * 20 / 100);
        dc.fillCircle(cx + (s * 2 / 100), cy - (s * 12 / 100), s * 26 / 100);
        dc.fillCircle(cx + (s * 26 / 100), cy + (s * 2 / 100), s * 18 / 100);
        dc.fillRectangle(cx - (s * 30 / 100), cy, s * 62 / 100, s * 20 / 100);
    }

    private function _drawRain(dc as Graphics.Dc, cx as Lang.Number, cy as Lang.Number) as Void {
        var s = _iconSize;
        var len = s * 16 / 100;
        dc.setPenWidth(2);
        for (var i = -1; i <= 1; i++) {
            var x = cx + (i * s * 20 / 100);
            dc.drawLine(x + (len / 2), cy, x - (len / 2), cy + len);
        }
        dc.setPenWidth(1);
    }

    private function _drawBolt(dc as Graphics.Dc, cx as Lang.Number, cy as Lang.Number) as Void {
        var s = _iconSize;
        dc.fillPolygon([
            [cx + (s * 10 / 100), cy - (s * 12 / 100)],
            [cx - (s * 10 / 100), cy + (s * 4 / 100)],
            [cx - (s * 1 / 100), cy + (s * 4 / 100)],
            [cx - (s * 8 / 100), cy + (s * 20 / 100)],
            [cx + (s * 12 / 100), cy - (s * 2 / 100)],
            [cx + (s * 2 / 100), cy - (s * 2 / 100)]
        ]);
    }

    private function _drawWind(dc as Graphics.Dc, cx as Lang.Number, cy as Lang.Number) as Void {
        var s = _iconSize;
        dc.setPenWidth(2);
        for (var i = 0; i < 3; i++) {
            var y = cy - (s * 10 / 100) + (i * s * 14 / 100);
            var len = (i == 1) ? s * 44 / 100 : s * 32 / 100;
            dc.drawLine(cx - (s * 34 / 100), y, cx - (s * 34 / 100) + len, y);
        }
        dc.setPenWidth(1);
    }

    // --- Layout helpers -----------------------------------------------------

    //! Copies the settings into the cached fields and repositions the time
    //! group, which shifts left to make room when seconds are enabled.
    private function _applySettings() as Void {
        _settings.load();
        _showSeconds = _settings.getShowSeconds();
        _showGraph = _settings.getShowGraph();
        _showHeartRate = _settings.getShowHeartRate();
        _stormAlertEnabled = _settings.getStormAlert();
        _pressureUnit = _settings.getPressureUnit();

        var groupW = _showSeconds ? _timeW + _secondsW : _timeW;
        var left = _centerX - (groupW / 2);
        _timeX = left + (_timeW / 2);
        _secondsX = left + _timeW;
    }

    //! Vertical distance from the screen centre at which a horizontal run of
    //! 2 * halfWidth pixels still fits inside a circle of the given radius.
    private function _chordOffset(radius as Lang.Number, halfWidth as Lang.Number) as Lang.Number {
        if (halfWidth >= radius) {
            return 0;
        }
        return Math.sqrt((radius * radius) - (halfWidth * halfWidth)).toNumber();
    }

    //! Layout dump. This face has no fixed coordinates, so the only way to
    //! check the stack on a device whose fonts are taller than expected is to
    //! read the numbers back out.
    (:debug)
    private function _logLayout(dc as Graphics.Dc, w as Lang.Number, h as Lang.Number) as Void {
        System.println("layout " + w + "x" + h
            + " icon=" + _iconY + "+" + _iconSize
            + " time=" + _timeY + "+" + Graphics.getFontHeight(FONT_TIME)
            + " timeX=" + _timeX + " timeW=" + _timeW
            + " sec=" + _secondsX + "," + _secondsY + "+" + _secondsW + "x" + _secondsH
            + " date=" + _dateY + "+" + Graphics.getFontHeight(FONT_DATE)
            + " pressure=" + _pressureY + "+" + Graphics.getFontHeight(FONT_PRESSURE)
            + " graph=" + _graphY + "+" + _graphH + " points=" + _graphPoints
            + " status=" + _statusY + "+" + _statusH + " w=" + _statusW);

        if (_iconY + _iconSize > _timeY) {
            System.println("layout WARNING: icon overlaps time");
        }
        if (_graphY + _graphH > _statusY) {
            System.println("layout WARNING: graph overlaps status row");
        }
        if (_statusY + _statusH > h) {
            System.println("layout WARNING: status row off screen");
        }

        // Worst case the status row has to hold once the adaptive fallbacks in
        // _formatSteps() and _drawStatusRow() have kicked in: a three digit
        // heart rate, an abbreviated step count and a bare battery percentage.
        var cellW = _statusW / (_showHeartRate ? 3 : 2);
        var hrW = dc.getTextWidthInPixels("188", FONT_STATUS);
        var stepsW = dc.getTextWidthInPixels("12k", FONT_STATUS);
        var battW = dc.getTextWidthInPixels("100", FONT_STATUS);
        var widest = hrW;
        if (stepsW > widest) { widest = stepsW; }
        if (battW > widest) { widest = battW; }
        widest += _statusIconSize + STATUS_GAP;

        System.println("layout status cell=" + cellW + " widest=" + widest
            + " icon=" + _statusIconSize + " hr=" + hrW + " steps=" + stepsW
            + " batt=" + battW
            + " exactSteps=" + dc.getTextWidthInPixels("88888", FONT_STATUS)
            + " exactBatt=" + dc.getTextWidthInPixels("100%", FONT_STATUS));
        if (widest > cellW) {
            System.println("layout WARNING: status cells overflow by " + (widest - cellW));
        }

        // The pressure row is the widest single string on the face.
        var pressureW = dc.getTextWidthInPixels("1013.2 hPa", FONT_PRESSURE) + _arrowSize + 6;
        System.println("layout pressure width=" + pressureW);
        if (pressureW > w) {
            System.println("layout WARNING: pressure row wider than the screen");
        }
    }

    (:release)
    private function _logLayout(dc as Graphics.Dc, w as Lang.Number, h as Lang.Number) as Void {
    }

    //! Buffer dump, printed once per full redraw. Says whether a forecast on
    //! screen is backed by enough history or is an artefact of the simulator's
    //! generated sensor data.
    (:debug)
    private function _logState() as Void {
        System.println("state n=" + _buffer.size()
            + " span=" + _buffer.getSpanSeconds() + "s"
            + " last=" + _buffer.getLastTimestamp()
            + " pa=" + _buffer.getLastPressure()
            + " trend6h=" + _buffer.getTrendHpa6h()
            + " forecast=" + (_hasForecast ? _forecast : -1)
            + " drop3h=" + _buffer.getDropHpa(STORM_WINDOW_S, STORM_MIN_SAMPLES)
            + " storm=" + _storm.isActive()
            + " unsaved=" + _unsavedSamples);
    }

    (:release)
    private function _logState() as Void {
    }
}
