using Toybox.Lang;

//! Decides when a falling barometer warrants a storm warning.
//!
//! Kept out of the view on purpose: this is the only part of the alert that has
//! interesting behaviour (latching, hysteresis, re-arming), and as a plain
//! object it can be unit tested without a Dc, a sensor or a vibration motor.
//!
//! The input is PressureBuffer.getDropHpa(), which reports
//! (mean over the window) - (current reading). For a steadily falling pressure
//! that value is about half the real drop across the window, so a trigger of
//! 1.5 hPa over a three hour window corresponds to the classic "pressure fell
//! 3 hPa in 3 hours" storm criterion.
class StormMonitor {

    private var _triggerHpa as Lang.Float;   // drop that raises the warning
    private var _clearHpa as Lang.Float;     // drop that lowers it again
    private var _rearmSeconds as Lang.Number;// quiet period between vibrations

    private var _active as Lang.Boolean;         // warning currently shown
    private var _lastAlertTime as Lang.Number?;  // epoch seconds of last vibration

    //! triggerHpa   — raise the warning at or above this drop
    //! clearHpa     — lower it again once the drop falls below this. Must be
    //!                smaller than triggerHpa: without the gap the warning
    //!                would flicker on and off around a single threshold.
    //! rearmSeconds — minimum time between two vibrations. The warning itself
    //!                stays visible, only the buzz is rate limited.
    function initialize(triggerHpa as Lang.Float, clearHpa as Lang.Float,
                        rearmSeconds as Lang.Number) {
        _triggerHpa = triggerHpa;
        _clearHpa = clearHpa;
        _rearmSeconds = rearmSeconds;
        _active = false;
        _lastAlertTime = null;
    }

    //! Feeds a fresh drop reading.
    //!
    //! @param dropHpa Pressure drop in hPa, or null when there is not enough
    //!        history to judge. Null leaves the current state untouched rather
    //!        than clearing it, so a momentary gap in the data does not cancel
    //!        an active warning.
    //! @param nowSec Current time in epoch seconds.
    //! @return true exactly once per storm, when the caller should vibrate.
    function update(dropHpa as Lang.Float?, nowSec as Lang.Number) as Lang.Boolean {
        if (dropHpa == null) {
            return false;
        }

        if (_active) {
            if (dropHpa < _clearHpa) {
                _active = false;
            }
            return false;
        }

        if (dropHpa < _triggerHpa) {
            return false;
        }

        _active = true;
        if (!_canAlert(nowSec)) {
            return false;
        }

        _lastAlertTime = nowSec;
        return true;
    }

    //! True while the warning should be drawn.
    function isActive() as Lang.Boolean {
        return _active;
    }

    //! Epoch seconds of the last vibration, or null if there has been none.
    function getLastAlertTime() as Lang.Number? {
        return _lastAlertTime;
    }

    //! Drops the warning and the re-arm timer.
    function reset() as Void {
        _active = false;
        _lastAlertTime = null;
    }

    // --- Private -------------------------------------------------------------

    private function _canAlert(nowSec as Lang.Number) as Lang.Boolean {
        if (_lastAlertTime == null) {
            return true;
        }
        // A clock that jumped backwards (time zone change, manual set) would
        // otherwise keep the alert suppressed until it caught up again.
        if (nowSec < _lastAlertTime) {
            return true;
        }
        return nowSec - _lastAlertTime >= _rearmSeconds;
    }
}
