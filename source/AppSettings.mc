using Toybox.Application;
using Toybox.Application.Properties;
using Toybox.Lang;

//! Cached view of the user settings from Garmin Connect Mobile.
//!
//! Every read is guarded. Properties.getValue() throws when a key is missing,
//! which happens whenever a build adds a setting that an already-paired phone
//! has not synced yet, and a watch face that throws out of onUpdate() is a
//! watch face that shows a blank screen.
//!
//! Values are cached rather than read per draw: onUpdate() runs every minute
//! for the life of the device, and each property read touches storage.
class AppSettings {

    private const KEY_SHOW_SECONDS = "ShowSeconds";
    private const KEY_SHOW_GRAPH = "ShowPressureGraph";
    private const KEY_SHOW_HEART_RATE = "ShowHeartRate";
    private const KEY_STORM_ALERT = "StormAlert";
    private const KEY_PRESSURE_UNIT = "PressureUnit";

    // Defaults, used when a key is missing or holds a value of the wrong type.
    // They match resources/settings/properties.xml.
    private const DEFAULT_SHOW_SECONDS = true;
    private const DEFAULT_SHOW_GRAPH = true;
    private const DEFAULT_SHOW_HEART_RATE = true;
    private const DEFAULT_STORM_ALERT = true;

    private var _showSeconds as Lang.Boolean;
    private var _showGraph as Lang.Boolean;
    private var _showHeartRate as Lang.Boolean;
    private var _stormAlert as Lang.Boolean;
    private var _pressureUnit as Lang.Number;

    function initialize() {
        _showSeconds = DEFAULT_SHOW_SECONDS;
        _showGraph = DEFAULT_SHOW_GRAPH;
        _showHeartRate = DEFAULT_SHOW_HEART_RATE;
        _stormAlert = DEFAULT_STORM_ALERT;
        _pressureUnit = PressureFormatter.UNIT_HPA;
        load();
    }

    //! Re-reads every property. Called once at start up and again from
    //! AppBase.onSettingsChanged().
    function load() as Void {
        _showSeconds = _readBoolean(KEY_SHOW_SECONDS, DEFAULT_SHOW_SECONDS);
        _showGraph = _readBoolean(KEY_SHOW_GRAPH, DEFAULT_SHOW_GRAPH);
        _showHeartRate = _readBoolean(KEY_SHOW_HEART_RATE, DEFAULT_SHOW_HEART_RATE);
        _stormAlert = _readBoolean(KEY_STORM_ALERT, DEFAULT_STORM_ALERT);

        var unit = _readNumber(KEY_PRESSURE_UNIT, PressureFormatter.UNIT_HPA);
        if (!PressureFormatter.isValidUnit(unit)) {
            unit = PressureFormatter.UNIT_HPA;
        }
        _pressureUnit = unit;
    }

    function getShowSeconds() as Lang.Boolean {
        return _showSeconds;
    }

    function getShowGraph() as Lang.Boolean {
        return _showGraph;
    }

    function getShowHeartRate() as Lang.Boolean {
        return _showHeartRate;
    }

    function getStormAlert() as Lang.Boolean {
        return _stormAlert;
    }

    //! One of the PressureFormatter.UNIT_* ids, always valid.
    function getPressureUnit() as Lang.Number {
        return _pressureUnit;
    }

    // --- Private -------------------------------------------------------------

    private function _readRaw(key as Lang.String) as Lang.Object? {
        try {
            return Properties.getValue(key);
        } catch (e) {
            return null;
        }
    }

    //! Boolean settings can come back as a Boolean or, from an older settings
    //! file that used <trueValue>1</trueValue>, as a Number.
    private function _readBoolean(key as Lang.String, fallback as Lang.Boolean) as Lang.Boolean {
        var value = _readRaw(key);
        if (value instanceof Lang.Boolean) {
            return value;
        }
        if (value instanceof Lang.Number) {
            return value != 0;
        }
        return fallback;
    }

    private function _readNumber(key as Lang.String, fallback as Lang.Number) as Lang.Number {
        var value = _readRaw(key);
        if (value instanceof Lang.Number) {
            return value;
        }
        // The settings list stores its entries as strings on some firmware.
        if (value instanceof Lang.String) {
            var parsed = value.toNumber();
            if (parsed != null) {
                return parsed;
            }
        }
        return fallback;
    }
}
