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
    private const KEY_STORM_ALERT = "StormAlert";
    private const KEY_STORM_THRESHOLD = "StormThresholdHpa";
    private const KEY_PRESSURE_UNIT = "PressureUnit";

    //! One key per cell of the status row, left to right. Indexed by slot, so
    //! the order here is the order on screen.
    private const KEYS_STATUS_FIELD = [
        "StatusFieldLeft", "StatusFieldMiddle", "StatusFieldRight"
    ];

    // Defaults, used when a key is missing or holds a value of the wrong type.
    // They match resources/settings/properties.xml.
    private const DEFAULT_SHOW_SECONDS = true;
    private const DEFAULT_SHOW_GRAPH = true;
    private const DEFAULT_STORM_ALERT = true;

    //! Storm threshold in hPa of fall over three hours. Three is the classic
    //! "pressure fell 3 hPa in 3 hours" criterion and matches the middle of
    //! the range the watch's own Storm Alert offers, so the two can be set to
    //! agree. The bounds cover that range with a little room either side; a
    //! value outside them is a corrupt property, not a user choice.
    private const DEFAULT_STORM_THRESHOLD = 3;
    private const MIN_STORM_THRESHOLD = 1;
    private const MAX_STORM_THRESHOLD = 9;

    //! Heart rate, steps and battery — the row the face shipped with before
    //! the cells became configurable.
    private const DEFAULT_STATUS_FIELDS = [
        StatusField.FIELD_HEART_RATE,
        StatusField.FIELD_STEPS,
        StatusField.FIELD_BATTERY
    ];

    private var _showSeconds as Lang.Boolean;
    private var _showGraph as Lang.Boolean;
    private var _stormAlert as Lang.Boolean;
    private var _stormThreshold as Lang.Number;
    private var _pressureUnit as Lang.Number;
    private var _statusFields as Lang.Array<Lang.Number>;

    function initialize() {
        _showSeconds = DEFAULT_SHOW_SECONDS;
        _showGraph = DEFAULT_SHOW_GRAPH;
        _stormAlert = DEFAULT_STORM_ALERT;
        _stormThreshold = DEFAULT_STORM_THRESHOLD;
        _pressureUnit = PressureFormatter.UNIT_HPA;
        _statusFields = new Lang.Array<Lang.Number>[StatusField.SLOT_COUNT];
        load();
    }

    //! Re-reads every property. Called once at start up and again from
    //! AppBase.onSettingsChanged().
    function load() as Void {
        _showSeconds = _readBoolean(KEY_SHOW_SECONDS, DEFAULT_SHOW_SECONDS);
        _showGraph = _readBoolean(KEY_SHOW_GRAPH, DEFAULT_SHOW_GRAPH);
        _stormAlert = _readBoolean(KEY_STORM_ALERT, DEFAULT_STORM_ALERT);

        var threshold = _readNumber(KEY_STORM_THRESHOLD, DEFAULT_STORM_THRESHOLD);
        if (threshold < MIN_STORM_THRESHOLD || threshold > MAX_STORM_THRESHOLD) {
            threshold = DEFAULT_STORM_THRESHOLD;
        }
        _stormThreshold = threshold;

        var unit = _readNumber(KEY_PRESSURE_UNIT, PressureFormatter.UNIT_HPA);
        if (!PressureFormatter.isValidUnit(unit)) {
            unit = PressureFormatter.UNIT_HPA;
        }
        _pressureUnit = unit;

        for (var slot = 0; slot < StatusField.SLOT_COUNT; slot++) {
            var fallback = DEFAULT_STATUS_FIELDS[slot];
            var field = _readNumber(KEYS_STATUS_FIELD[slot], fallback);
            if (!StatusField.isValid(field)) {
                field = fallback;
            }
            _statusFields[slot] = field;
        }
    }

    function getShowSeconds() as Lang.Boolean {
        return _showSeconds;
    }

    function getShowGraph() as Lang.Boolean {
        return _showGraph;
    }

    function getStormAlert() as Lang.Boolean {
        return _stormAlert;
    }

    //! How far the pressure has to fall over three hours, in hPa, before the
    //! warning is raised. Always within the supported range.
    function getStormThresholdHpa() as Lang.Number {
        return _stormThreshold;
    }

    //! One of the PressureFormatter.UNIT_* ids, always valid.
    function getPressureUnit() as Lang.Number {
        return _pressureUnit;
    }

    //! What the status row cell in `slot` shows, left to right, as one of the
    //! StatusField.FIELD_* ids. Always valid. Out of range slots read as
    //! FIELD_NONE rather than throwing: this is called from the draw path.
    function getStatusField(slot as Lang.Number) as Lang.Number {
        if (slot < 0 || slot >= StatusField.SLOT_COUNT) {
            return StatusField.FIELD_NONE;
        }
        return _statusFields[slot];
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
