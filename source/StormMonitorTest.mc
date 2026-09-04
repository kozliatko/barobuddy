using Toybox.Lang;
using Toybox.Test;

//! Unit tests for StormMonitor. Excluded from non --unit-test builds.
//!
//! Everything is local to a test: only (:test) functions are stripped from a
//! shipping build, so a shared helper or a file-scope const here would be dead
//! weight in the 124 kB watch face budget.
//!
//! The thresholds mirror the ones BaroBuddyView passes in (1.5 / 1.0 hPa,
//! 3 hour re-arm), but the monitor takes them as parameters, so these tests
//! pin the behaviour and not the tuning.

(:test)
function testStormStartsIdle(logger as Test.Logger) as Lang.Boolean {
    var m = new StormMonitor(1.5, 1.0, 10800);
    Test.assertMessage(!m.isActive(), "monitor started active");
    Test.assertMessage(m.getLastAlertTime() == null, "monitor started with an alert time");
    return true;
}

//! A calm or rising barometer must never fire.
(:test)
function testStormIgnoresSmallDrops(logger as Test.Logger) as Lang.Boolean {
    var m = new StormMonitor(1.5, 1.0, 10800);
    var t0 = 1700000000;

    Test.assertMessage(!m.update(0.0, t0), "flat pressure alerted");
    Test.assertMessage(!m.update(-2.0, t0 + 900), "rising pressure alerted");
    Test.assertMessage(!m.update(1.49, t0 + 1800), "just below trigger alerted");
    Test.assertMessage(!m.isActive(), "monitor latched below the trigger");

    return true;
}

//! The trigger is inclusive and fires exactly once per storm.
(:test)
function testStormTriggersOnce(logger as Test.Logger) as Lang.Boolean {
    var m = new StormMonitor(1.5, 1.0, 10800);
    var t0 = 1700000000;

    Test.assertMessage(m.update(1.5, t0), "trigger value did not alert");
    Test.assertMessage(m.isActive(), "monitor did not latch");
    Test.assertEqual(m.getLastAlertTime() as Lang.Number, t0);

    // Still falling, but the user has already been told.
    Test.assertMessage(!m.update(3.0, t0 + 900), "alerted twice for one storm");
    Test.assertMessage(!m.update(5.0, t0 + 1800), "alerted twice for one storm");
    Test.assertMessage(m.isActive(), "monitor unlatched while still falling");

    return true;
}

//! The warning must not flicker: it clears at a lower drop than it triggers.
(:test)
function testStormHysteresis(logger as Test.Logger) as Lang.Boolean {
    var m = new StormMonitor(1.5, 1.0, 10800);
    var t0 = 1700000000;

    m.update(2.0, t0);
    Test.assertMessage(m.isActive(), "monitor did not latch");

    // Between clear and trigger — recovering, but not yet recovered.
    Test.assertMessage(!m.update(1.2, t0 + 900), "unexpected alert");
    Test.assertMessage(m.isActive(), "monitor cleared inside the hysteresis band");

    Test.assertMessage(!m.update(1.0, t0 + 1800), "unexpected alert");
    Test.assertMessage(m.isActive(), "monitor cleared at the clear threshold, not below it");

    Test.assertMessage(!m.update(0.9, t0 + 2700), "unexpected alert");
    Test.assertMessage(!m.isActive(), "monitor did not clear below the clear threshold");

    return true;
}

//! A second storm inside the re-arm window latches the warning again but must
//! not buzz the wrist a second time.
(:test)
function testStormRearmWindow(logger as Test.Logger) as Lang.Boolean {
    var rearm = 10800;
    var m = new StormMonitor(1.5, 1.0, rearm);
    var t0 = 1700000000;

    Test.assertMessage(m.update(2.0, t0), "first storm did not alert");
    Test.assertMessage(!m.update(0.0, t0 + 900), "unexpected alert");
    Test.assertMessage(!m.isActive(), "monitor did not clear");

    // One second short of the re-arm window.
    var early = t0 + rearm - 1;
    Test.assertMessage(!m.update(2.0, early), "alerted inside the re-arm window");
    Test.assertMessage(m.isActive(), "warning should still show without a vibration");
    Test.assertEqual(m.getLastAlertTime() as Lang.Number, t0);

    // Clear, then try again once the window has elapsed.
    m.update(0.0, early + 60);
    var late = t0 + rearm + 60;
    Test.assertMessage(m.update(2.0, late), "did not alert after the re-arm window");
    Test.assertEqual(m.getLastAlertTime() as Lang.Number, late);

    return true;
}

//! A clock corrected backwards must not mute the alert until it catches up.
(:test)
function testStormSurvivesClockGoingBackwards(logger as Test.Logger) as Lang.Boolean {
    var m = new StormMonitor(1.5, 1.0, 10800);
    var t0 = 1700000000;

    Test.assertMessage(m.update(2.0, t0), "first storm did not alert");
    m.update(0.0, t0 + 60);

    // Time zone change: two hours earlier, well inside the re-arm window.
    var earlier = t0 - 7200;
    Test.assertMessage(m.update(2.0, earlier), "backwards clock suppressed the alert");
    Test.assertEqual(m.getLastAlertTime() as Lang.Number, earlier);

    return true;
}

//! A gap in the data must not cancel a warning that is already showing.
(:test)
function testStormNullDropKeepsState(logger as Test.Logger) as Lang.Boolean {
    var m = new StormMonitor(1.5, 1.0, 10800);
    var t0 = 1700000000;

    Test.assertMessage(!m.update(null, t0), "null drop alerted");
    Test.assertMessage(!m.isActive(), "null drop latched the monitor");

    m.update(2.0, t0 + 900);
    Test.assertMessage(m.isActive(), "monitor did not latch");

    Test.assertMessage(!m.update(null, t0 + 1800), "null drop alerted");
    Test.assertMessage(m.isActive(), "null drop cleared an active warning");

    return true;
}

(:test)
function testStormReset(logger as Test.Logger) as Lang.Boolean {
    var m = new StormMonitor(1.5, 1.0, 10800);
    var t0 = 1700000000;

    m.update(2.0, t0);
    Test.assertMessage(m.isActive(), "monitor did not latch");

    m.reset();
    Test.assertMessage(!m.isActive(), "reset left the monitor active");
    Test.assertMessage(m.getLastAlertTime() == null, "reset left the re-arm timer set");

    // Re-arm timer is gone, so the next storm alerts immediately.
    Test.assertMessage(m.update(2.0, t0 + 60), "did not alert after a reset");

    return true;
}

//! End to end against a real buffer. getDropHpa() reports
//! (mean over the window) - (current), which for a steady fall is about half
//! the real drop — so a 3 hPa fall over 3 h lands near 1.5 and must trip the
//! monitor, while a gentle decline over the same window must not.
(:test)
function testStormFromPressureBuffer(logger as Test.Logger) as Lang.Boolean {
    var windowS = 10800;
    var minSamples = 5;
    var t0 = 1700000000;

    var storm = new PressureBuffer(24, 900);
    var calm = new PressureBuffer(24, 900);
    for (var i = 0; i < 13; i++) {
        var t = t0 + i * 900;
        storm.addSample(t, 101300.0 - (300.0 * i / 12.0)); // -3 hPa over 3 h
        calm.addSample(t, 101300.0 - (60.0 * i / 12.0));   // -0.6 hPa over 3 h
    }

    var last = t0 + 12 * 900;

    var stormMonitor = new StormMonitor(1.5, 1.0, 10800);
    Test.assertMessage(stormMonitor.update(storm.getDropHpa(windowS, minSamples), last),
        "a 3 hPa fall over 3 h did not raise a storm warning");

    var calmMonitor = new StormMonitor(1.5, 1.0, 10800);
    Test.assertMessage(!calmMonitor.update(calm.getDropHpa(windowS, minSamples), last),
        "a 0.6 hPa fall over 3 h raised a storm warning");

    return true;
}
