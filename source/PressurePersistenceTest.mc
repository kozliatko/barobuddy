using Toybox.Application.Storage;
using Toybox.Lang;
using Toybox.Test;

//! Unit tests for the Application.Storage round trip that keeps the pressure
//! history across a restart. Excluded from non --unit-test builds.
//!
//! PressureBufferTest already covers toArray()/fromArray() in isolation; what
//! is tested here is that the blob actually survives the storage layer, which
//! is the part a pure in-memory test cannot reach.

//! Same key the view uses, so a change on one side breaks this test.
(:test)
function testBufferSurvivesStorage(logger as Test.Logger) as Lang.Boolean {
    var key = "PressureSamplesTest";
    var start = 1700000000;

    var original = new PressureBuffer(24, 900);
    for (var i = 0; i < 24; i++) {
        original.addSample(start + i * 900, 101300.0 - i * 5.0);
    }

    try {
        Storage.setValue(key, original.toArray() as Lang.Array<Storage.ValueType>);

        var blob = Storage.getValue(key);
        Test.assertMessage(blob instanceof Lang.Array, "storage did not return an Array");

        var restored = new PressureBuffer(24, 900);
        restored.fromArray(blob as Lang.Array);

        Test.assertEqual(restored.size(), original.size());
        Test.assertEqual(restored.getLastTimestamp() as Lang.Number,
            original.getLastTimestamp() as Lang.Number);
        Test.assertEqual(restored.getLastPressure() as Lang.Float,
            original.getLastPressure() as Lang.Float);
        Test.assertEqual(restored.getSpanSeconds(), original.getSpanSeconds());
        Test.assertMessage((restored.getTrendHpa6h() - original.getTrendHpa6h()).abs() < 0.001,
            "trend changed across storage: " + restored.getTrendHpa6h()
            + " vs " + original.getTrendHpa6h());
    } finally {
        Storage.deleteValue(key);
    }

    return true;
}

//! A full buffer has to stay well inside the ~8 kB per-key storage limit.
(:test)
function testStoredBufferStaysSmall(logger as Test.Logger) as Lang.Boolean {
    var b = new PressureBuffer(24, 900);
    for (var i = 0; i < 40; i++) {
        b.addSample(1700000000 + i * 900, 101300.0 - i * 2.0);
    }

    // Capacity is 24 samples, two values each, however many were offered.
    Test.assertEqual(b.size(), 24);
    Test.assertEqual(b.toArray().size(), 48);

    return true;
}

//! A missing key is the normal first-run case and must not throw.
(:test)
function testMissingStorageKey(logger as Test.Logger) as Lang.Boolean {
    var key = "PressureSamplesAbsent";
    Storage.deleteValue(key);

    var value = Storage.getValue(key);
    Test.assertMessage(value == null, "absent key returned " + value);

    var b = new PressureBuffer(24, 900);
    b.fromArray(value as Lang.Array?);
    Test.assertEqual(b.size(), 0);

    return true;
}

//! Anything but an array of alternating numbers must degrade to an empty
//! buffer rather than poison the forecast.
(:test)
function testCorruptStorageBlob(logger as Test.Logger) as Lang.Boolean {
    var key = "PressureSamplesCorrupt";

    try {
        // Wrong shape entirely: the view's instanceof check is what stops this.
        Storage.setValue(key, "not an array");
        var blob = Storage.getValue(key);
        Test.assertMessage(!(blob instanceof Lang.Array), "a String passed as an Array");

        // Right shape, unusable contents.
        Storage.setValue(key, [1700000000, 999999.0, 1700000900, 101300.0]
            as Lang.Array<Storage.ValueType>);
        var b = new PressureBuffer(24, 900);
        b.fromArray(Storage.getValue(key) as Lang.Array);
        Test.assertEqual(b.size(), 1);
        Test.assertEqual(b.getLastPressure() as Lang.Float, 101300.0);
    } finally {
        Storage.deleteValue(key);
    }

    return true;
}
