using Toybox.Application;
using Toybox.Lang;
using Toybox.WatchUi;

//! Entry point for the BaroBuddy watch face.
class BaroBuddyApp extends Application.AppBase {

    //! Kept so shutdown can flush the pressure buffer and a settings change can
    //! be pushed into the running view.
    private var _view as BaroBuddyView?;

    public function initialize() {
        AppBase.initialize();
        _view = null;
    }

    //! Called on application start up.
    public function onStart(state as Lang.Dictionary?) as Void {
    }

    //! Called when the application is exiting. Last opportunity to persist the
    //! pressure history; without this the samples collected since the last
    //! periodic save would be lost.
    public function onStop(state as Lang.Dictionary?) as Void {
        if (_view != null) {
            _view.saveBuffer();
        }
    }

    //! Returns the initial view and its delegate.
    public function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var view = new BaroBuddyView();
        _view = view;
        return [view, new BaroBuddyDelegate(view)];
    }

    //! Called when settings change in Garmin Connect Mobile.
    public function onSettingsChanged() as Void {
        if (_view != null) {
            _view.onSettingsChanged();
        }
        WatchUi.requestUpdate();
    }
}
