using Toybox.Lang;
using Toybox.System;
using Toybox.WatchUi;

//! Watch face delegate.
//!
//! The per-second partial update itself lives on the view: onPartialUpdate() is
//! a method of WatchUi.WatchFace, and only the view has the layout and the
//! settings it needs. What belongs here is the power budget callback, which the
//! delegate forwards so the view can stop drawing seconds.
class BaroBuddyDelegate extends WatchUi.WatchFaceDelegate {

    private var _view as BaroBuddyView;

    public function initialize(view as BaroBuddyView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    //! Called when onPartialUpdate() used more than the allowed power budget.
    //! Ignoring this gets the face's partial updates disabled by the system, so
    //! the view drops the seconds instead.
    public function onPowerBudgetExceeded(powerInfo as WatchUi.WatchFacePowerInfo) as Void {
        _logBudget(powerInfo);
        _view.onPowerBudgetExceeded();
    }

    //! Logging only makes sense while debugging; on a release build there is no
    //! console to print to.
    (:debug)
    private function _logBudget(powerInfo as WatchUi.WatchFacePowerInfo) as Void {
        System.println("Power budget exceeded: "
            + powerInfo.executionTimeAverage
            + " / " + powerInfo.executionTimeLimit);
    }

    (:release)
    private function _logBudget(powerInfo as WatchUi.WatchFacePowerInfo) as Void {
    }
}
