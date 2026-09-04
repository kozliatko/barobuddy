using Toybox.Application.Properties;
using Toybox.Lang;
using Toybox.Test;

//! Unit tests for AppSettings. Excluded from non --unit-test builds.
//!
//! These run against the real property store, seeded from
//! resources/settings/properties.xml. Tests that write to it restore the value
//! before returning, so they can run in any order.

//! Defaults out of properties.xml must match the ones AppSettings falls back
//! to, otherwise the face looks different before and after the first sync.
(:test)
function testSettingsDefaults(logger as Test.Logger) as Lang.Boolean {
    var s = new AppSettings();

    Test.assertMessage(s.getShowSeconds(), "ShowSeconds should default to true");
    Test.assertMessage(s.getShowGraph(), "ShowPressureGraph should default to true");
    Test.assertMessage(s.getShowHeartRate(), "ShowHeartRate should default to true");
    Test.assertMessage(s.getStormAlert(), "StormAlert should default to true");
    Test.assertEqual(s.getPressureUnit(), PressureFormatter.UNIT_HPA);

    return true;
}

(:test)
function testSettingsTypes(logger as Test.Logger) as Lang.Boolean {
    var s = new AppSettings();

    Test.assertMessage(s.getShowSeconds() instanceof Lang.Boolean, "ShowSeconds is not a Boolean");
    Test.assertMessage(s.getShowGraph() instanceof Lang.Boolean, "ShowGraph is not a Boolean");
    Test.assertMessage(s.getShowHeartRate() instanceof Lang.Boolean, "ShowHeartRate is not a Boolean");
    Test.assertMessage(s.getStormAlert() instanceof Lang.Boolean, "StormAlert is not a Boolean");
    Test.assertMessage(s.getPressureUnit() instanceof Lang.Number, "PressureUnit is not a Number");

    return true;
}

//! load() is what onSettingsChanged() calls, so a changed property has to be
//! picked up without rebuilding the object.
(:test)
function testSettingsReload(logger as Test.Logger) as Lang.Boolean {
    var s = new AppSettings();
    var original = Properties.getValue("ShowSeconds");

    try {
        Properties.setValue("ShowSeconds", false);
        Test.assertMessage(s.getShowSeconds(), "settings changed without a reload");

        s.load();
        Test.assertMessage(!s.getShowSeconds(), "reload did not pick up the new value");

        Properties.setValue("ShowSeconds", true);
        s.load();
        Test.assertMessage(s.getShowSeconds(), "reload did not pick up the new value");
    } finally {
        Properties.setValue("ShowSeconds", original);
    }

    return true;
}

//! A unit id the app does not know — from a newer settings page on the phone —
//! must be clamped, not passed on to PressureFormatter.
(:test)
function testSettingsRejectsUnknownPressureUnit(logger as Test.Logger) as Lang.Boolean {
    var s = new AppSettings();
    var original = Properties.getValue("PressureUnit");

    try {
        Properties.setValue("PressureUnit", 99);
        s.load();
        Test.assertEqual(s.getPressureUnit(), PressureFormatter.UNIT_HPA);

        Properties.setValue("PressureUnit", -1);
        s.load();
        Test.assertEqual(s.getPressureUnit(), PressureFormatter.UNIT_HPA);

        Properties.setValue("PressureUnit", PressureFormatter.UNIT_MMHG);
        s.load();
        Test.assertEqual(s.getPressureUnit(), PressureFormatter.UNIT_MMHG);
    } finally {
        Properties.setValue("PressureUnit", original);
    }

    return true;
}

//! Whatever is in the store, the unit handed to PressureFormatter must be one
//! it recognises.
(:test)
function testSettingsAlwaysYieldsAValidUnit(logger as Test.Logger) as Lang.Boolean {
    var s = new AppSettings();
    var original = Properties.getValue("PressureUnit");
    var garbage = [0, 1, 2, 3, -7, 1000];

    try {
        for (var i = 0; i < garbage.size(); i++) {
            Properties.setValue("PressureUnit", garbage[i]);
            s.load();
            Test.assertMessage(PressureFormatter.isValidUnit(s.getPressureUnit()),
                "stored unit " + garbage[i] + " leaked through as " + s.getPressureUnit());
        }
    } finally {
        Properties.setValue("PressureUnit", original);
    }

    return true;
}
