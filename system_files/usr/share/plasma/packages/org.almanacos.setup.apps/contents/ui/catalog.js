// AlmanacOS setup wizard — the apps offered on the "Recommended Apps" page.
//
// This is the only place the list lives. The page writes what was ticked to
// /var/lib/almanac-setup/choices/choices.ini, and /usr/libexec/almanac-setup
// installs from there after the wizard finishes, so nothing else needs editing
// when an entry is added or removed.
//
// While the list is empty the page hides itself (see `available` in main.qml),
// so shipping it empty is safe.
//
// Fields:
//   id           Flathub app ID for kind "flatpak"; formula name for "brew".
//   kind         "flatpak" (system-wide, from Flathub) or "brew" (Homebrew,
//                installed per user at their next login).
//   name         Shown as the checkbox label.
//   description  One line under the label.
//   recommended  Ticked by default.
//   ai           The app can talk to a local model server. It is listed on the
//                "Local AI" page, and if the user opts in, the executable
//                /usr/libexec/almanac-setup-hooks/<id> (when present) is run
//                as that user to point the app at Lemonade or ramalama.

.pragma library

var apps = [
    // {
    //     id: "com.jeffser.Alpaca",
    //     kind: "flatpak",
    //     name: "Alpaca",
    //     description: "Chat with local models",
    //     recommended: true,
    //     ai: true,
    // },
];
