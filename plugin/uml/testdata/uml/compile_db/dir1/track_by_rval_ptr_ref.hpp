// Expecting relation to dir2 and dir3 even though it is return values and
// those are forward declared.

class TrackPtr;
class TrackRef;

class Tracker {
    TrackPtr* ptr();
    TrackRef& ref();
};
