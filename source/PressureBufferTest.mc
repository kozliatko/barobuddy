using Toybox.Lang;
using Toybox.Test;

// Unit tests for PressureBuffer.
//
// (:test) functions are only compiled into a --unit-test build, so this file
// costs nothing in the shipped watch face.
//
// Run:  monkeyc -f monkey.jungle -d fr935 -o bin/test.prg -y <key> --unit-test
//       monkeydo bin/test.prg fr935 -t

(:test)
function testEmptyBuffer(logger as Test.Logger) as Lang.Boolean {
    var b = new PressureBuffer(24, 900);
    Test.assertEqual(b.size(), 0);
    Test.assertMessage(b.getLastPressure() == null, "empty buffer returned a pressure");
    Test.assertMessage(b.getLastTimestamp() == null, "empty buffer returned a timestamp");
    Test.assertEqual(b.getSpanSeconds(), 0);
    Test.assertEqual(b.getTrend(), 0.0);
    Test.assertEqual(b.getNormalizedSamples(20).size(), 0);
    return true;
}

(:test)
function testAddSampleRejectsBadInput(logger as Test.Logger) as Lang.Boolean {
    var b = new PressureBuffer(24, 900);

    Test.assertMessage(!b.addSample(null, 101300.0), "null timestamp accepted");
    Test.assertMessage(!b.addSample(1000, null), "null pressure accepted");
    Test.assertMessage(!b.addSample(1000, 5000.0), "absurdly low pressure accepted");
    Test.assertMessage(!b.addSample(1000, 200000.0), "absurdly high pressure accepted");
    Test.assertEqual(b.size(), 0);

    Test.assertMessage(b.addSample(1000, 101300.0), "valid sample rejected");
    Test.assertEqual(b.size(), 1);

    // Same timestamp, and a timestamp going backwards (clock change).
    Test.assertMessage(!b.addSample(1000, 101400.0), "duplicate timestamp accepted");
    Test.assertMessage(!b.addSample(500, 101400.0), "backwards timestamp accepted");
    Test.assertEqual(b.size(), 1);

    return true;
}

(:test)
function testMinIntervalGate(logger as Test.Logger) as Lang.Boolean {
    var b = new PressureBuffer(24, 900);

    Test.assertMessage(b.addSample(10000, 101300.0), "first sample rejected");
    // 60 s later — this is what onUpdate() offers every minute.
    Test.assertMessage(!b.addSample(10060, 101300.0), "sample inside min interval kept");
    Test.assertMessage(!b.addSample(10899, 101300.0), "sample 1 s early kept");
    Test.assertMessage(b.addSample(10900, 101300.0), "sample at min interval rejected");
    Test.assertEqual(b.size(), 2);

    return true;
}

// The plan's slice(size - capacity, capacity) would drop the newest sample.
(:test)
function testCapacityKeepsNewest(logger as Test.Logger) as Lang.Boolean {
    var cap = 5;
    var b = new PressureBuffer(cap, 900);

    // 10 samples, pressure rises 100 Pa per step.
    for (var i = 0; i < 10; i++) {
        Test.assertMessage(b.addSample(1000 + i * 900, 100000.0 + i * 100), "sample " + i + " rejected");
    }

    Test.assertEqual(b.size(), cap);
    // Newest sample is i == 9.
    Test.assertEqual(b.getLastTimestamp() as Lang.Number, 1000 + 9 * 900);
    Test.assertEqual(b.getLastPressure() as Lang.Float, 100900.0);
    // Oldest retained is i == 5, so the span is 4 intervals.
    Test.assertEqual(b.getSpanSeconds(), 4 * 900);

    return true;
}

(:test)
function testTrendFalling(logger as Test.Logger) as Lang.Boolean {
    // 24 samples, 15 min apart, falling exactly 3 hPa over the 6 h span.
    // The regression slope must come back as -3 hPa/6h.
    var b = new PressureBuffer(24, 900);
    var start = 1700000000;
    for (var i = 0; i < 24; i++) {
        var p = 101300.0 - (300.0 * i / 23.0); // 300 Pa total drop
        Test.assertMessage(b.addSample(start + i * 900, p), "sample " + i + " rejected");
    }

    var t = b.getTrendHpa6h();
    // Span is 23*900 = 20700 s, not a full 21600, so the 6 h extrapolation is
    // slightly steeper than the raw 3 hPa drop.
    var expected = -3.0 * 21600.0 / 20700.0;
    Test.assertMessage((t - expected).abs() < 0.01,
        "trend " + t + " expected " + expected);

    return true;
}

(:test)
function testTrendSteadyAndRising(logger as Test.Logger) as Lang.Boolean {
    var flat = new PressureBuffer(24, 900);
    for (var i = 0; i < 10; i++) {
        flat.addSample(1700000000 + i * 900, 101300.0);
    }
    Test.assertMessage(flat.getTrendHpa6h().abs() < 0.001,
        "flat series should have no trend, got " + flat.getTrendHpa6h());

    var rising = new PressureBuffer(24, 900);
    for (var i = 0; i < 10; i++) {
        rising.addSample(1700000000 + i * 900, 101300.0 + i * 10.0);
    }
    Test.assertMessage(rising.getTrendHpa6h() > 0.0,
        "rising series should have a positive trend");

    // 10 Pa per 900 s = 0.0111 Pa/s -> 2.4 hPa/6h
    var expected = 10.0 / 900.0 * 21600.0 / 100.0;
    Test.assertMessage((rising.getTrendHpa6h() - expected).abs() < 0.01,
        "trend " + rising.getTrendHpa6h() + " expected " + expected);

    return true;
}

// The trend must survive real epoch timestamps in 32-bit floats.
(:test)
function testTrendPrecisionWithEpochTimestamps(logger as Test.Logger) as Lang.Boolean {
    var b = new PressureBuffer(24, 900);
    var start = 1893456000; // 2030-01-01
    for (var i = 0; i < 24; i++) {
        b.addSample(start + i * 900, 101300.0 - i * 10.0);
    }
    var expected = -10.0 / 900.0 * 21600.0 / 100.0;
    Test.assertMessage((b.getTrendHpa6h() - expected).abs() < 0.01,
        "trend " + b.getTrendHpa6h() + " expected " + expected);
    return true;
}

(:test)
function testTrendCacheInvalidation(logger as Test.Logger) as Lang.Boolean {
    var b = new PressureBuffer(24, 900);
    for (var i = 0; i < 5; i++) {
        b.addSample(1700000000 + i * 900, 101300.0);
    }
    Test.assertMessage(b.getTrendHpa6h().abs() < 0.001, "expected flat trend");

    // Adding a falling sample must invalidate the cached value.
    b.addSample(1700000000 + 5 * 900, 101000.0);
    Test.assertMessage(b.getTrendHpa6h() < -1.0,
        "cached trend was not invalidated, got " + b.getTrendHpa6h());

    return true;
}

(:test)
function testNormalizedSamples(logger as Test.Logger) as Lang.Boolean {
    var b = new PressureBuffer(24, 900);
    for (var i = 0; i < 24; i++) {
        b.addSample(1700000000 + i * 900, 101000.0 + i * 10.0);
    }

    var g = b.getNormalizedSamples(20);
    Test.assertEqual(g.size(), 20);

    // Must be Floats spanning the full 0..1 range, not truncated Numbers.
    Test.assertMessage(g[0] instanceof Lang.Float, "graph point is not a Float");
    Test.assertMessage(g[0] == 0.0, "first point should be 0.0, got " + g[0]);
    Test.assertMessage(g[19] == 1.0, "last point should be 1.0, got " + g[19]);

    var mid = g[10];
    Test.assertMessage(mid > 0.2 && mid < 0.8,
        "midpoint collapsed to " + mid + " (Number truncation?)");

    // Monotonic rise for a monotonic series.
    for (var i = 1; i < g.size(); i++) {
        Test.assertMessage(g[i] >= g[i - 1], "graph not monotonic at " + i);
    }

    // A perfectly flat series must not divide by zero.
    var flat = new PressureBuffer(24, 900);
    for (var i = 0; i < 5; i++) {
        flat.addSample(1700000000 + i * 900, 101300.0);
    }
    var fg = flat.getNormalizedSamples(20);
    Test.assertEqual(fg.size(), 20);
    Test.assertEqual(fg[0], 0.0);

    // Degenerate widths.
    Test.assertEqual(b.getNormalizedSamples(1).size(), 0);
    Test.assertEqual(b.getNormalizedSamples(0).size(), 0);

    return true;
}

(:test)
function testGetDropHpa(logger as Test.Logger) as Lang.Boolean {
    var b = new PressureBuffer(24, 900);
    var start = 1700000000;

    // Not enough samples yet.
    b.addSample(start, 101300.0);
    Test.assertMessage(b.getDropHpa(1800, 3) == null, "drop reported with too few samples");

    // Steady 101300 Pa, then a 400 Pa dive on the last reading.
    b.addSample(start + 900, 101300.0);
    b.addSample(start + 1800, 101300.0);
    b.addSample(start + 2700, 100900.0);

    // Window covers t-1800..t -> samples at +900, +1800, +2700.
    var drop = b.getDropHpa(1800, 3) as Lang.Float;
    Test.assertMessage(drop != null, "expected a drop value");
    // mean = (101300 + 101300 + 100900)/3 = 101166.67 ; current = 100900
    var expected = (101166.667 - 100900.0) / 100.0;
    Test.assertMessage((drop - expected).abs() < 0.01,
        "drop " + drop + " expected " + expected);

    // Steady pressure means no drop.
    var steady = new PressureBuffer(24, 900);
    for (var i = 0; i < 5; i++) {
        steady.addSample(start + i * 900, 101300.0);
    }
    Test.assertMessage((steady.getDropHpa(1800, 3) as Lang.Float).abs() < 0.001,
        "steady pressure reported a drop");

    return true;
}

(:test)
function testStoragePersistenceRoundTrip(logger as Test.Logger) as Lang.Boolean {
    var b = new PressureBuffer(24, 900);
    var start = 1700000000;
    for (var i = 0; i < 24; i++) {
        b.addSample(start + i * 900, 101300.0 - i * 5.0);
    }

    var blob = b.toArray();
    Test.assertEqual(blob.size(), 48);

    var restored = new PressureBuffer(24, 900);
    restored.fromArray(blob as Lang.Array);

    Test.assertEqual(restored.size(), b.size());
    Test.assertEqual(restored.getLastTimestamp() as Lang.Number,
        b.getLastTimestamp() as Lang.Number);
    Test.assertEqual(restored.getLastPressure() as Lang.Float,
        b.getLastPressure() as Lang.Float);
    Test.assertEqual(restored.getSpanSeconds(), b.getSpanSeconds());
    Test.assertMessage((restored.getTrendHpa6h() - b.getTrendHpa6h()).abs() < 0.001,
        "trend changed across a storage round trip");

    // A missing or corrupt blob must leave an empty, usable buffer.
    var empty = new PressureBuffer(24, 900);
    empty.fromArray(null);
    Test.assertEqual(empty.size(), 0);

    empty.fromArray([start, 101300.0, start + 900]); // odd length
    Test.assertEqual(empty.size(), 1);

    empty.fromArray([start, 999999.0, start + 900, 101300.0]); // bad pressure
    Test.assertEqual(empty.size(), 1);
    Test.assertEqual(empty.getLastPressure() as Lang.Float, 101300.0);

    return true;
}

(:test)
function testClear(logger as Test.Logger) as Lang.Boolean {
    var b = new PressureBuffer(24, 900);
    for (var i = 0; i < 5; i++) {
        b.addSample(1700000000 + i * 900, 101300.0 - i * 20.0);
    }
    Test.assertMessage(b.getTrendHpa6h() < 0.0, "expected a falling trend");

    b.clear();
    Test.assertEqual(b.size(), 0);
    Test.assertEqual(b.getTrend(), 0.0);
    Test.assertMessage(b.getLastPressure() == null, "cleared buffer returned a pressure");

    return true;
}
