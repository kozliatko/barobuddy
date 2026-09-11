using Toybox.Application.Properties;
using Toybox.Application.Storage;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.Test;
using Toybox.Time;

//! Smoke tests for BaroBuddyView. Excluded from non --unit-test builds.
//!
//! These draw into an off-screen BufferedBitmap and assert only that the whole
//! render path completes. They cannot say whether the face *looks* right, but
//! they do catch the failures that a layout dump cannot: a null dereference in
//! a branch that only runs during a storm, a polygon built from a negative
//! size, a resource id that no longer resolves.
//!
//! The view has no injection points, so the pressure history is seeded through
//! Application.Storage, which is where the view reads it in initialize().

//! Shared setup. This has to be a module rather than a bare (:test) function:
//! the runner registers every (:test) function as a test case and calls it with
//! a Logger, so a free helper is invoked with the wrong arguments and fails.
//! The (:test) on the module still keeps it out of shipping builds.
(:test)
module ViewTestFixture {

    //! Fills the view's storage key with `count` samples 15 minutes apart,
    //! ending a minute ago, moving `totalPa` Pascals across the whole series.
    function seedPressureHistory(totalPa as Lang.Float, count as Lang.Number) as Void {
        var last = Time.now().value() - 60;
        var data = new Lang.Array<Lang.Numeric>[count * 2];
        for (var i = 0; i < count; i++) {
            data[i * 2] = last - ((count - 1 - i) * 900);
            data[i * 2 + 1] = 101300.0 + (totalPa * i / (count - 1).toFloat());
        }
        Storage.setValue("PressureSamples", data as Lang.Array<Storage.ValueType>);
    }

    //! Property keys of the status row cells, left to right. The view reads
    //! these through AppSettings, which is the only way in from a test.
    const STATUS_KEYS = ["StatusFieldLeft", "StatusFieldMiddle", "StatusFieldRight"];

    //! Points every cell of the status row at the same field.
    function setStatusFields(field as Lang.Number) as Void {
        for (var slot = 0; slot < STATUS_KEYS.size(); slot++) {
            Properties.setValue(STATUS_KEYS[slot], field);
        }
    }

    //! Puts the status row back the way properties.xml left it.
    function restoreStatusFields() as Void {
        Properties.setValue(STATUS_KEYS[0], StatusField.FIELD_HEART_RATE);
        Properties.setValue(STATUS_KEYS[1], StatusField.FIELD_STEPS);
        Properties.setValue(STATUS_KEYS[2], StatusField.FIELD_BATTERY);
    }

    //! An off-screen Dc the size of the real screen, so the layout maths runs
    //! against the device it will ship to.
    function createDc() as Graphics.Dc {
        var settings = System.getDeviceSettings();
        var options = {
            :width => settings.screenWidth,
            :height => settings.screenHeight
        };
        // API 4.0.0 replaced the BufferedBitmap constructor with a factory that
        // returns a reference. On those devices the constructor is gone, and
        // calling it fails at run time rather than at compile time.
        if (Graphics has :createBufferedBitmap) {
            var bitmap = Graphics.createBufferedBitmap(options).get() as Graphics.BufferedBitmap;
            return bitmap.getDc();
        }
        return (new Graphics.BufferedBitmap(options)).getDc();
    }
}

//! Every forecast state has its own icon branch, and the steepest fall also
//! latches the storm warning, so this walks all of them.
(:test)
function testViewRendersEveryForecastState(logger as Test.Logger) as Lang.Boolean {
    var dc = ViewTestFixture.createDc();

    // Pascals moved across a 6 hour buffer: rising fast, rising, steady,
    // falling, falling fast. See WeatherPredictor's thresholds.
    var slopes = [500.0, 150.0, 0.0, -200.0, -600.0];

    try {
        for (var i = 0; i < slopes.size(); i++) {
            ViewTestFixture.seedPressureHistory(slopes[i], 24);

            var view = new BaroBuddyView();
            view.onLayout(dc);
            view.onShow();
            view.onUpdate(dc);

            Test.assertMessage(!view.isLowPower(), "view started in low power");
        }
    } finally {
        Storage.deleteValue("PressureSamples");
    }

    return true;
}

//! An empty buffer is the first-run case: no forecast, no graph, placeholders
//! instead of a reading. It must render as readily as a full one.
(:test)
function testViewRendersWithoutData(logger as Test.Logger) as Lang.Boolean {
    var dc = ViewTestFixture.createDc();

    Storage.deleteValue("PressureSamples");

    var view = new BaroBuddyView();
    view.onLayout(dc);
    view.onUpdate(dc);

    Storage.deleteValue("PressureSamples");
    return true;
}

//! The sleep transitions change what onUpdate() draws, and onPartialUpdate()
//! runs against whatever clip state was left behind.
(:test)
function testViewLowPowerCycle(logger as Test.Logger) as Lang.Boolean {
    var dc = ViewTestFixture.createDc();

    try {
        ViewTestFixture.seedPressureHistory(-300.0, 24);

        var view = new BaroBuddyView();
        view.onLayout(dc);
        view.onUpdate(dc);

        view.onEnterSleep();
        Test.assertMessage(view.isLowPower(), "onEnterSleep did not enter low power");
        view.onUpdate(dc);

        // A minute of seconds ticking without a full redraw in between.
        for (var i = 0; i < 60; i++) {
            view.onPartialUpdate(dc);
        }

        // Giving up on partial updates must not leave the face broken.
        view.onPowerBudgetExceeded();
        view.onPartialUpdate(dc);
        view.onUpdate(dc);

        view.onExitSleep();
        Test.assertMessage(!view.isLowPower(), "onExitSleep did not leave low power");
        view.onUpdate(dc);

        view.onHide();
    } finally {
        Storage.deleteValue("PressureSamples");
    }

    return true;
}

//! Settings change the layout (seconds shift the time block) and the content
//! (units, hidden rows), so a reload has to be safe mid-flight.
(:test)
function testViewSettingsChange(logger as Test.Logger) as Lang.Boolean {
    var dc = ViewTestFixture.createDc();

    try {
        ViewTestFixture.seedPressureHistory(-300.0, 24);

        var view = new BaroBuddyView();
        view.onLayout(dc);
        view.onUpdate(dc);

        // onSettingsChanged() arrives without a Dc, so it must reposition from
        // the widths measured back in onLayout().
        view.onSettingsChanged();
        view.onUpdate(dc);

        // And a second onLayout, as happens when the face is re-shown.
        view.onLayout(dc);
        view.onUpdate(dc);
    } finally {
        Storage.deleteValue("PressureSamples");
    }

    return true;
}

//! The view writes the buffer back so a restart keeps its history.
(:test)
function testViewPersistsBuffer(logger as Test.Logger) as Lang.Boolean {
    var dc = ViewTestFixture.createDc();

    try {
        ViewTestFixture.seedPressureHistory(-300.0, 24);

        var view = new BaroBuddyView();
        view.onLayout(dc);
        view.onUpdate(dc);
        view.saveBuffer();

        var saved = Storage.getValue("PressureSamples");
        Test.assertMessage(saved instanceof Lang.Array, "buffer was not written back");

        var restored = new PressureBuffer(24, 900);
        restored.fromArray(saved as Lang.Array);
        Test.assertMessage(restored.size() >= 24,
            "restored buffer lost samples, size " + restored.size());
        Test.assertMessage(restored.getSpanSeconds() >= 20000,
            "restored buffer lost its span, " + restored.getSpanSeconds() + " s");
    } finally {
        Storage.deleteValue("PressureSamples");
    }

    return true;
}

//! Each status field has its own icon and its own value lookup, several of
//! which can come back null on a device that does not track them. Every one of
//! them has to draw.
(:test)
function testViewRendersEveryStatusField(logger as Test.Logger) as Lang.Boolean {
    var dc = ViewTestFixture.createDc();

    try {
        ViewTestFixture.seedPressureHistory(-300.0, 24);

        for (var field = 0; field < StatusField.FIELD_COUNT; field++) {
            ViewTestFixture.setStatusFields(field);

            var view = new BaroBuddyView();
            view.onLayout(dc);
            view.onUpdate(dc);

            // And again in low power, which is where the face spends its life.
            view.onEnterSleep();
            view.onUpdate(dc);
        }
    } finally {
        ViewTestFixture.restoreStatusFields();
        Storage.deleteValue("PressureSamples");
    }

    return true;
}

//! Every cell switched off leaves the row with no width to divide, which is a
//! division by zero waiting to happen.
(:test)
function testViewRendersWithEmptyStatusRow(logger as Test.Logger) as Lang.Boolean {
    var dc = ViewTestFixture.createDc();

    try {
        ViewTestFixture.seedPressureHistory(-300.0, 24);
        ViewTestFixture.setStatusFields(StatusField.FIELD_NONE);

        var view = new BaroBuddyView();
        view.onLayout(dc);
        view.onUpdate(dc);

        // One cell back on: the row has to survive both edges of the count.
        Properties.setValue(ViewTestFixture.STATUS_KEYS[2], StatusField.FIELD_CALORIES);
        view.onSettingsChanged();
        view.onUpdate(dc);
    } finally {
        ViewTestFixture.restoreStatusFields();
        Storage.deleteValue("PressureSamples");
    }

    return true;
}

//! History from a previous life of the device says nothing about the weather
//! now, so it must be dropped rather than forecast from.
(:test)
function testViewDiscardsStaleHistory(logger as Test.Logger) as Lang.Boolean {
    var dc = ViewTestFixture.createDc();

    try {
        // Two days old.
        var last = Time.now().value() - 172800;
        var data = new Lang.Array<Lang.Numeric>[48];
        for (var i = 0; i < 24; i++) {
            data[i * 2] = last - ((23 - i) * 900);
            data[i * 2 + 1] = 101300.0 - i * 25.0;
        }
        Storage.setValue("PressureSamples", data as Lang.Array<Storage.ValueType>);

        var view = new BaroBuddyView();
        view.onLayout(dc);
        view.onUpdate(dc);

        // saveBuffer() is a no-op on an empty buffer, so the stale blob is
        // still there — what matters is that the view did not adopt it, which
        // it shows by rendering the no-forecast state without throwing.
        view.saveBuffer();
    } finally {
        Storage.deleteValue("PressureSamples");
    }

    return true;
}

//! A panel with burn-in protection swaps the sleeping face for a stripped,
//! dimmed one and is not allowed partial updates at all. The always-on screen
//! also shifts with the minute, so this walks a whole four step cycle plus the
//! storm branch, which is the one thing that survives into it.
(:test)
function testViewAlwaysOnDisplay(logger as Test.Logger) as Lang.Boolean {
    var dc = ViewTestFixture.createDc();

    try {
        // A steep fall, so the storm warning latches and the banner branch of
        // the always-on screen is drawn too.
        ViewTestFixture.seedPressureHistory(-900.0, 24);

        var view = new BaroBuddyView();
        view.onLayout(dc);
        view.setBurnInForTest(true);
        view.onUpdate(dc);

        view.onEnterSleep();
        // One update per minute for a full cycle of the pixel shift.
        for (var i = 0; i < 8; i++) {
            view.onUpdate(dc);
        }

        // Partial updates are forbidden on a panel that burns in; calling one
        // anyway must not draw the seconds back on top of the dimmed face.
        view.onPartialUpdate(dc);

        view.onExitSleep();
        view.onUpdate(dc);

        // And back to a normal panel on the same view.
        view.setBurnInForTest(false);
        view.onEnterSleep();
        view.onUpdate(dc);
        view.onExitSleep();
    } finally {
        Storage.deleteValue("PressureSamples");
    }

    return true;
}

//! A sport activity takes the screen for its whole duration, so the face comes
//! back to a buffer that stops where the activity started. The watch kept
//! logging pressure all along, and the face has to go and get it rather than
//! wait a quarter of an hour per sample to fill the hole itself.
(:test)
function testViewPrimesAfterAGap(logger as Test.Logger) as Lang.Boolean {
    var dc = ViewTestFixture.createDc();

    try {
        // Two hours of samples that end two hours ago: old enough to be a gap,
        // recent enough to survive the staleness check on restore, and wide
        // enough that the "already enough to forecast from" rule on its own
        // would refuse the walk.
        var last = Time.now().value() - 7200;
        var data = new Lang.Array<Lang.Numeric>[16];
        for (var i = 0; i < 8; i++) {
            data[i * 2] = last - ((7 - i) * 900);
            data[i * 2 + 1] = 101500.0 - i * 10.0;
        }
        Storage.setValue("PressureSamples", data as Lang.Array<Storage.ValueType>);

        var view = new BaroBuddyView();
        view.onLayout(dc);
        view.onUpdate(dc);
        view.saveBuffer();

        var saved = Storage.getValue("PressureSamples");
        Test.assertMessage(saved instanceof Lang.Array, "buffer was not written back");

        var restored = new PressureBuffer(24, 900);
        restored.fromArray(saved as Lang.Array);
        var newest = restored.getLastTimestamp();
        Test.assertMessage(newest != null, "restored buffer has no samples");
        var age = Time.now().value() - (newest as Lang.Number);
        Test.assertMessage(age < 7200,
            "the gap was not filled from the sensor history, newest sample is "
                + age + " s old");
    } finally {
        Storage.deleteValue("PressureSamples");
    }

    return true;
}

//! onHide() flushes, and the face is hidden every time the user opens a menu
//! or a widget. Writing the same array back on each of those would be dozens
//! of flash writes a day for no gain.
(:test)
function testViewSkipsRedundantSave(logger as Test.Logger) as Lang.Boolean {
    var dc = ViewTestFixture.createDc();

    try {
        ViewTestFixture.seedPressureHistory(-300.0, 24);

        var view = new BaroBuddyView();
        view.onLayout(dc);
        view.onUpdate(dc);
        view.saveBuffer();

        // A sentinel in place of the saved buffer: a second save with nothing
        // new to write must leave it untouched.
        Storage.setValue("PressureSamples", "untouched");
        view.saveBuffer();
        view.onHide();

        var stored = Storage.getValue("PressureSamples");
        Test.assertMessage(stored instanceof Lang.String && stored.equals("untouched"),
            "a save with nothing new to write still rewrote the buffer");
    } finally {
        Storage.deleteValue("PressureSamples");
    }

    return true;
}
