using Toybox.Lang;
using Toybox.Test;

//! Unit tests for PressureFormatter. Excluded from non --unit-test builds.
//!
//! Reference value throughout is one standard atmosphere: 101325 Pa,
//! 1013.25 hPa, 29.9213 inHg, 760.0 mmHg.

(:test)
function testUnitIdsAreContiguous(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqual(PressureFormatter.UNIT_HPA, 0);
    Test.assertEqual(PressureFormatter.UNIT_INHG, 1);
    Test.assertEqual(PressureFormatter.UNIT_MMHG, 2);
    Test.assertEqual(PressureFormatter.UNIT_COUNT, 3);
    return true;
}

(:test)
function testIsValidUnit(logger as Test.Logger) as Lang.Boolean {
    for (var u = 0; u < PressureFormatter.UNIT_COUNT; u++) {
        Test.assertMessage(PressureFormatter.isValidUnit(u), "unit " + u + " rejected");
    }
    Test.assertMessage(!PressureFormatter.isValidUnit(-1), "negative unit accepted");
    Test.assertMessage(!PressureFormatter.isValidUnit(3), "out of range unit accepted");
    Test.assertMessage(!PressureFormatter.isValidUnit(99), "out of range unit accepted");
    return true;
}

(:test)
function testConvertStandardAtmosphere(logger as Test.Logger) as Lang.Boolean {
    var pa = 101325.0;

    var hpa = PressureFormatter.convert(pa, PressureFormatter.UNIT_HPA);
    Test.assertMessage((hpa - 1013.25).abs() < 0.01, "hPa was " + hpa);

    var inhg = PressureFormatter.convert(pa, PressureFormatter.UNIT_INHG);
    Test.assertMessage((inhg - 29.9213).abs() < 0.001, "inHg was " + inhg);

    var mmhg = PressureFormatter.convert(pa, PressureFormatter.UNIT_MMHG);
    Test.assertMessage((mmhg - 760.0).abs() < 0.01, "mmHg was " + mmhg);

    return true;
}

//! A unit id from a newer build of the settings must not produce nonsense.
(:test)
function testConvertUnknownUnitFallsBackToHpa(logger as Test.Logger) as Lang.Boolean {
    var pa = 101325.0;
    var expected = PressureFormatter.convert(pa, PressureFormatter.UNIT_HPA);

    Test.assertEqual(PressureFormatter.convert(pa, 99), expected);
    Test.assertEqual(PressureFormatter.convert(pa, -1), expected);
    Test.assertEqual(PressureFormatter.getUnitLabel(99), "hPa");

    return true;
}

//! Integer Pascals must convert as readily as Floats — SensorHistory hands out
//! either depending on the device.
(:test)
function testConvertAcceptsIntegerPascals(logger as Test.Logger) as Lang.Boolean {
    var hpa = PressureFormatter.convert(101325, PressureFormatter.UNIT_HPA);
    Test.assertMessage(hpa instanceof Lang.Float, "conversion did not produce a Float");
    Test.assertMessage((hpa - 1013.25).abs() < 0.01, "hPa was " + hpa);
    return true;
}

//! inHg needs two decimals to be readable at all; the others get one.
(:test)
function testFormatPrecision(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqual(PressureFormatter.format(101300.0, PressureFormatter.UNIT_HPA), "1013.0");
    Test.assertEqual(PressureFormatter.format(101325.0, PressureFormatter.UNIT_INHG), "29.92");
    Test.assertEqual(PressureFormatter.format(101325.0, PressureFormatter.UNIT_MMHG), "760.0");
    return true;
}

//! No reading yet must render as a placeholder, never as "0.0".
(:test)
function testFormatNull(logger as Test.Logger) as Lang.Boolean {
    for (var u = 0; u < PressureFormatter.UNIT_COUNT; u++) {
        Test.assertEqual(PressureFormatter.format(null, u), PressureFormatter.PLACEHOLDER);
        Test.assertEqual(PressureFormatter.formatWithUnit(null, u),
            PressureFormatter.PLACEHOLDER + " " + PressureFormatter.getUnitLabel(u));
    }
    return true;
}

(:test)
function testUnitLabels(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqual(PressureFormatter.getUnitLabel(PressureFormatter.UNIT_HPA), "hPa");
    Test.assertEqual(PressureFormatter.getUnitLabel(PressureFormatter.UNIT_INHG), "inHg");
    Test.assertEqual(PressureFormatter.getUnitLabel(PressureFormatter.UNIT_MMHG), "mmHg");
    return true;
}

(:test)
function testFormatWithUnit(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqual(PressureFormatter.formatWithUnit(101300.0, PressureFormatter.UNIT_HPA),
        "1013.0 hPa");
    Test.assertEqual(PressureFormatter.formatWithUnit(101325.0, PressureFormatter.UNIT_INHG),
        "29.92 inHg");
    Test.assertEqual(PressureFormatter.formatWithUnit(101325.0, PressureFormatter.UNIT_MMHG),
        "760.0 mmHg");
    return true;
}

//! The whole plausible range of the sensor must format without losing digits
//! or overflowing the field the view lays out for it.
(:test)
function testFormatSensorRange(logger as Test.Logger) as Lang.Boolean {
    // 30000 Pa is roughly 9000 m, 110000 Pa a deep low at sea level — the same
    // window PressureBuffer accepts.
    var lows = [30000.0, 110000.0];
    for (var i = 0; i < lows.size(); i++) {
        for (var u = 0; u < PressureFormatter.UNIT_COUNT; u++) {
            var text = PressureFormatter.formatWithUnit(lows[i], u);
            Test.assertMessage(text.length() > 0, "empty rendering for " + lows[i]);
            Test.assertMessage(text.length() <= 11,
                "rendering '" + text + "' is too wide for the pressure row");
        }
    }
    return true;
}

//! The pressure the view actually draws comes straight out of the buffer.
(:test)
function testFormatFromPressureBuffer(logger as Test.Logger) as Lang.Boolean {
    var b = new PressureBuffer(24, 900);
    Test.assertEqual(
        PressureFormatter.formatWithUnit(b.getLastPressure(), PressureFormatter.UNIT_HPA),
        "-- hPa");

    b.addSample(1700000000, 100000.0);
    Test.assertEqual(
        PressureFormatter.formatWithUnit(b.getLastPressure(), PressureFormatter.UNIT_HPA),
        "1000.0 hPa");

    return true;
}
