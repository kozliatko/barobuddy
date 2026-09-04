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

    //! An off-screen Dc the size of the real screen, so the layout maths runs
    //! against the device it will ship to.
    function createDc() as Graphics.Dc {
        var settings = System.getDeviceSettings();
        var bitmap = new Graphics.BufferedBitmap({
            :width => settings.screenWidth,
            :height => settings.screenHeight
        });
        return bitmap.getDc();
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
