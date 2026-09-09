using Toybox.Lang;

//! Ids for what each cell of the bottom status row shows.
//!
//! A module rather than a class: it is a set of ids and one range check, so
//! there is nothing to allocate and nothing to keep alive on the view.
module StatusField {

    //! Field ids. These are the raw values stored in the StatusField*
    //! properties, so they must stay in sync with
    //! resources/settings/settings.xml.
    //!
    //! Values are contiguous from zero so a stored id can be range checked
    //! without a lookup. They must never be renumbered: the number is what
    //! sits in the property store on a watch that has already been set up.
    enum Field {
        FIELD_NONE          = 0,
        FIELD_HEART_RATE    = 1,
        FIELD_STEPS         = 2,
        FIELD_BATTERY       = 3,
        FIELD_CALORIES      = 4,
        FIELD_DISTANCE      = 5,
        FIELD_FLOORS        = 6,
        FIELD_NOTIFICATIONS = 7
    }

    //! Number of selectable fields, FIELD_NONE included.
    const FIELD_COUNT = 8;

    //! How many cells the row has. Three is what fits the chord of a round
    //! screen at that height; see BaroBuddyView.onLayout().
    const SLOT_COUNT = 3;

    //! True when `field` is one of the FIELD_* ids. Settings arriving from a
    //! newer version of the app on the phone can carry a value we do not know.
    function isValid(field as Lang.Number) as Lang.Boolean {
        return field >= 0 && field < FIELD_COUNT;
    }
}
