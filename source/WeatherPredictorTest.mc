using Toybox.Lang;
using Toybox.Test;

//! Unit tests for WeatherPredictor. Excluded from non --unit-test builds.

(:test)
function testClassifyBands(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqual(WeatherPredictor.classify(10.0), WeatherPredictor.FORECAST_RISING_FAST);
    Test.assertEqual(WeatherPredictor.classify(3.5), WeatherPredictor.FORECAST_RISING_FAST);
    Test.assertEqual(WeatherPredictor.classify(1.5), WeatherPredictor.FORECAST_RISING);
    Test.assertEqual(WeatherPredictor.classify(0.0), WeatherPredictor.FORECAST_STEADY);
    Test.assertEqual(WeatherPredictor.classify(-0.2), WeatherPredictor.FORECAST_STEADY);
    Test.assertEqual(WeatherPredictor.classify(-1.5), WeatherPredictor.FORECAST_FALLING);
    Test.assertEqual(WeatherPredictor.classify(-5.0), WeatherPredictor.FORECAST_FALLING_FAST);
    return true;
}

//! Boundary values must land in the calmer of the two neighbouring states.
(:test)
function testClassifyBoundaries(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqual(WeatherPredictor.classify(3.0), WeatherPredictor.FORECAST_RISING);
    Test.assertEqual(WeatherPredictor.classify(0.5), WeatherPredictor.FORECAST_STEADY);
    Test.assertEqual(WeatherPredictor.classify(-0.5), WeatherPredictor.FORECAST_STEADY);
    Test.assertEqual(WeatherPredictor.classify(-3.0), WeatherPredictor.FORECAST_FALLING);

    // Just past each boundary.
    Test.assertEqual(WeatherPredictor.classify(3.001), WeatherPredictor.FORECAST_RISING_FAST);
    Test.assertEqual(WeatherPredictor.classify(0.501), WeatherPredictor.FORECAST_RISING);
    Test.assertEqual(WeatherPredictor.classify(-0.501), WeatherPredictor.FORECAST_FALLING);
    Test.assertEqual(WeatherPredictor.classify(-3.001), WeatherPredictor.FORECAST_FALLING_FAST);
    return true;
}

//! Enum values must stay contiguous from zero so they can index flat arrays.
(:test)
function testForecastValuesAreContiguous(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqual(WeatherPredictor.FORECAST_RISING_FAST, 0);
    Test.assertEqual(WeatherPredictor.FORECAST_RISING, 1);
    Test.assertEqual(WeatherPredictor.FORECAST_STEADY, 2);
    Test.assertEqual(WeatherPredictor.FORECAST_FALLING, 3);
    Test.assertEqual(WeatherPredictor.FORECAST_FALLING_FAST, 4);
    Test.assertEqual(WeatherPredictor.FORECAST_COUNT, 5);
    return true;
}

(:test)
function testArrowDirection(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqual(WeatherPredictor.getArrowDirection(WeatherPredictor.FORECAST_RISING_FAST), 2);
    Test.assertEqual(WeatherPredictor.getArrowDirection(WeatherPredictor.FORECAST_RISING), 1);
    Test.assertEqual(WeatherPredictor.getArrowDirection(WeatherPredictor.FORECAST_STEADY), 0);
    Test.assertEqual(WeatherPredictor.getArrowDirection(WeatherPredictor.FORECAST_FALLING), -1);
    Test.assertEqual(WeatherPredictor.getArrowDirection(WeatherPredictor.FORECAST_FALLING_FAST), -2);
    return true;
}

(:test)
function testSeverity(logger as Test.Logger) as Lang.Boolean {
    Test.assertMessage(WeatherPredictor.isSevere(WeatherPredictor.FORECAST_FALLING_FAST),
        "falling fast should be severe");
    for (var f = 0; f < WeatherPredictor.FORECAST_COUNT - 1; f++) {
        Test.assertMessage(!WeatherPredictor.isSevere(f as WeatherPredictor.Forecast),
            "state " + f + " should not be severe");
    }
    return true;
}

//! Every state must resolve to a distinct, non-empty label.
(:test)
function testLabelsResolve(logger as Test.Logger) as Lang.Boolean {
    var seen = [] as Lang.Array<Lang.String>;
    for (var f = 0; f < WeatherPredictor.FORECAST_COUNT; f++) {
        var label = WeatherPredictor.getLabel(f as WeatherPredictor.Forecast);
        Test.assertMessage(label instanceof Lang.String, "label " + f + " is not a String");
        Test.assertMessage(label.length() > 0, "label " + f + " is empty");
        Test.assertMessage(seen.indexOf(label) < 0, "label " + f + " duplicates '" + label + "'");
        seen.add(label);
    }
    return true;
}

//! End-to-end: a real PressureBuffer trend must classify as expected.
(:test)
function testClassifyFromPressureBuffer(logger as Test.Logger) as Lang.Boolean {
    var start = 1700000000;

    // ~2 hPa drop over 6 h -> "rain likely".
    var falling = new PressureBuffer(24, 900);
    for (var i = 0; i < 24; i++) {
        falling.addSample(start + i * 900, 101300.0 - (200.0 * i / 23.0));
    }
    Test.assertEqual(WeatherPredictor.classify(falling.getTrendHpa6h()),
        WeatherPredictor.FORECAST_FALLING);

    // ~6 hPa drop over 6 h -> storm.
    var storm = new PressureBuffer(24, 900);
    for (var i = 0; i < 24; i++) {
        storm.addSample(start + i * 900, 101300.0 - (600.0 * i / 23.0));
    }
    Test.assertEqual(WeatherPredictor.classify(storm.getTrendHpa6h()),
        WeatherPredictor.FORECAST_FALLING_FAST);

    // Dead flat -> steady.
    var flat = new PressureBuffer(24, 900);
    for (var i = 0; i < 24; i++) {
        flat.addSample(start + i * 900, 101300.0);
    }
    Test.assertEqual(WeatherPredictor.classify(flat.getTrendHpa6h()),
        WeatherPredictor.FORECAST_STEADY);

    // An empty buffer reports a zero trend, which must be a safe "steady".
    var empty = new PressureBuffer(24, 900);
    Test.assertEqual(WeatherPredictor.classify(empty.getTrendHpa6h()),
        WeatherPredictor.FORECAST_STEADY);

    return true;
}
