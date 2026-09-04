using Toybox.Lang;
using Toybox.WatchUi;

//! Translates a barometric pressure trend into a five-state forecast.
//!
//! This is a module rather than a class: it holds no state, so there is no
//! object to allocate and no instance to keep alive on the view.
module WeatherPredictor {

    //! Forecast states, ordered from improving to deteriorating.
    //! Values are contiguous from zero so callers can use them to index flat
    //! lookup arrays without a Dictionary.
    enum Forecast {
        FORECAST_RISING_FAST  = 0,
        FORECAST_RISING       = 1,
        FORECAST_STEADY       = 2,
        FORECAST_FALLING      = 3,
        FORECAST_FALLING_FAST = 4
    }

    //! Number of distinct forecast states.
    const FORECAST_COUNT = 5;

    //! Classification thresholds, in hPa per 6 hours.
    //! Boundary values fall into the calmer of the two neighbouring states.
    const TREND_RISING_FAST_HPA6H  =  3.0;
    const TREND_RISING_HPA6H       =  0.5;
    const TREND_FALLING_HPA6H      = -0.5;
    const TREND_FALLING_FAST_HPA6H = -3.0;

    //! Arrow directions returned by getArrowDirection().
    const ARROW_UP_FAST   =  2;
    const ARROW_UP        =  1;
    const ARROW_FLAT      =  0;
    const ARROW_DOWN      = -1;
    const ARROW_DOWN_FAST = -2;

    //! Classifies a pressure trend into a forecast state.
    //! @param trendHpa6h Pressure trend in hPa per 6 hours, from
    //!        PressureBuffer.getTrendHpa6h().
    //! @return One of the FORECAST_* values.
    function classify(trendHpa6h as Lang.Float) as Forecast {
        if (trendHpa6h > TREND_RISING_FAST_HPA6H) {
            return FORECAST_RISING_FAST;
        } else if (trendHpa6h > TREND_RISING_HPA6H) {
            return FORECAST_RISING;
        } else if (trendHpa6h >= TREND_FALLING_HPA6H) {
            return FORECAST_STEADY;
        } else if (trendHpa6h >= TREND_FALLING_FAST_HPA6H) {
            return FORECAST_FALLING;
        }
        return FORECAST_FALLING_FAST;
    }

    //! Resource id of the human readable label for a forecast state.
    //! Kept separate from getLabel() so a caller can compare ids and skip
    //! reloading the string when the forecast has not changed.
    function getLabelResource(forecast as Forecast) as Lang.ResourceId {
        switch (forecast) {
            case FORECAST_RISING_FAST:
                return Rez.Strings.ForecastRisingFast;
            case FORECAST_RISING:
                return Rez.Strings.ForecastRising;
            case FORECAST_STEADY:
                return Rez.Strings.ForecastSteady;
            case FORECAST_FALLING:
                return Rez.Strings.ForecastFalling;
            default:
                return Rez.Strings.ForecastFallingFast;
        }
    }

    //! Human readable label for a forecast state.
    //! Allocates a String, so callers should cache the result and only reload
    //! it when the forecast state actually changes.
    function getLabel(forecast as Forecast) as Lang.String {
        return WatchUi.loadResource(getLabelResource(forecast)) as Lang.String;
    }

    //! Direction of the trend arrow for a forecast state, from +2 (rising
    //! fast) to -2 (falling fast).
    //!
    //! Deliberately not a glyph: Unicode arrows such as U+2191 are not
    //! guaranteed to exist in the device fonts and would render as a blank or
    //! a tofu box. The view draws the arrow itself from this direction.
    function getArrowDirection(forecast as Forecast) as Lang.Number {
        switch (forecast) {
            case FORECAST_RISING_FAST:
                return ARROW_UP_FAST;
            case FORECAST_RISING:
                return ARROW_UP;
            case FORECAST_STEADY:
                return ARROW_FLAT;
            case FORECAST_FALLING:
                return ARROW_DOWN;
            default:
                return ARROW_DOWN_FAST;
        }
    }

    //! True when the forecast warrants highlighting the display, i.e. pressure
    //! is dropping fast enough to expect a storm.
    function isSevere(forecast as Forecast) as Lang.Boolean {
        return forecast == FORECAST_FALLING_FAST;
    }
}
