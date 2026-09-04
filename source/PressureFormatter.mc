using Toybox.Lang;

//! Converts a barometric reading in Pascals into the unit the user selected.
//!
//! A module rather than a class: it is pure arithmetic, so there is nothing to
//! allocate and nothing to keep alive on the view.
module PressureFormatter {

    //! Unit ids. These are the raw values stored in the PressureUnit property,
    //! so they must stay in sync with resources/settings/settings.xml.
    const UNIT_HPA  = 0;
    const UNIT_INHG = 1;
    const UNIT_MMHG = 2;

    //! Number of selectable units.
    const UNIT_COUNT = 3;

    //! Drawn instead of a reading while the barometer has not produced one.
    const PLACEHOLDER = "--";

    // One Pascal expressed in each unit.
    const HPA_PER_PA  = 0.01;
    const INHG_PER_PA = 0.000295299830714;
    const MMHG_PER_PA = 0.00750061682704;

    //! True when `unit` is one of the UNIT_* ids. Settings arriving from a
    //! newer version of the app on the phone can carry a value we do not know.
    function isValidUnit(unit as Lang.Number) as Lang.Boolean {
        return unit >= 0 && unit < UNIT_COUNT;
    }

    //! Converts Pascals into `unit`. Unknown units fall back to hPa.
    function convert(pressurePa as Lang.Numeric, unit as Lang.Number) as Lang.Float {
        if (unit == UNIT_INHG) {
            return (pressurePa * INHG_PER_PA).toFloat();
        }
        if (unit == UNIT_MMHG) {
            return (pressurePa * MMHG_PER_PA).toFloat();
        }
        return (pressurePa * HPA_PER_PA).toFloat();
    }

    //! Numeric part of the reading, without the unit suffix.
    //!
    //! inHg gets two decimals because its whole range of interest spans barely
    //! two units (roughly 28.5 to 31.0); hPa and mmHg get one, which is already
    //! finer than the sensor is honest about.
    function format(pressurePa as Lang.Numeric?, unit as Lang.Number) as Lang.String {
        if (pressurePa == null) {
            return PLACEHOLDER;
        }
        var value = convert(pressurePa, unit);
        if (unit == UNIT_INHG) {
            return value.format("%.2f");
        }
        return value.format("%.1f");
    }

    //! Unit suffix. Deliberately a literal and not a resource: these are
    //! international symbols, not prose, and loading three resources on every
    //! redraw would cost more than it buys.
    function getUnitLabel(unit as Lang.Number) as Lang.String {
        if (unit == UNIT_INHG) {
            return "inHg";
        }
        if (unit == UNIT_MMHG) {
            return "mmHg";
        }
        return "hPa";
    }

    //! Reading and unit as one string, e.g. "1013.2 hPa".
    function formatWithUnit(pressurePa as Lang.Numeric?, unit as Lang.Number) as Lang.String {
        return format(pressurePa, unit) + " " + getUnitLabel(unit);
    }
}
