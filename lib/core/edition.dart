/// The public build: Job, Lab and Internships stay hidden.
// Not const so tests can switch it.
var personalEdition = false;

/// Mini-apps and Home widgets only the owner's build shows.
const personalOnlyApps = {'job', 'lab', 'internships'};
const personalOnlyWidgets = {'deadlines', 'work'};
