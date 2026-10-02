// AlmanacOS setup wizard — the apps offered on the "Apps" page.
//
// This is the only place the list lives. The page writes what was ticked to
// /var/lib/almanac-setup/choices/choices.ini, and /usr/libexec/almanac-setup
// installs from there after the wizard finishes, so nothing else needs editing
// when an entry is added or removed.
//
// While the list is empty the page hides itself (see `available` in main.qml).
//
// Fields:
//   id           Flathub app ID for kind "flatpak"; formula name for "brew";
//                any stable name for "rpm".
//   kind         "flatpak" (system-wide, from Flathub), "brew" (Homebrew,
//                installed per user at their next login), or "rpm" (already in
//                the image; must also be `required`).
//   name         Shown as the row label.
//   description  One line under the label.
//   required     Ships with AlmanacOS. No install checkbox, only the AI switch.
//   recommended  Install checkbox ticked by default.
//   ai           Has a built-in setting for an OpenAI-compatible server that
//                /usr/libexec/almanac-setup-hooks/<id> knows how to fill in.
//                The row gets a "connect to <server>" switch, on by default.
//                Only set this when the hook exists, and never for apps that
//                need a third-party plugin to talk to a model.

.pragma library

var apps = [
    {
        id: "firefox",
        kind: "rpm",
        name: "Firefox",
        description: "Web browser. Its AI chatbot sidebar can use a local model.",
        required: true,
        ai: true,
    },
    {
        id: "com.calibre_ebook.calibre",
        kind: "flatpak",
        name: "Calibre",
        description: "E-book library and reader, with \"Discuss with AI\"",
        recommended: false,
        ai: true,
    },
    {
        id: "io.dbeaver.DBeaverCommunity",
        kind: "flatpak",
        name: "DBeaver Community",
        description: "Database client, with an AI SQL assistant",
        recommended: false,
        ai: true,
    },
    {
        // AI is a separate plugin, and its settings live in the app's own
        // browser storage — nothing to pre-fill.
        id: "org.onlyoffice.desktopeditors",
        kind: "flatpak",
        name: "ONLYOFFICE",
        description: "Documents, spreadsheets and presentations",
        recommended: false,
        ai: false,
    },
    {
        // AI only through third-party plugins.
        id: "net.cozic.joplin_desktop",
        kind: "flatpak",
        name: "Joplin",
        description: "Notes and to-do lists, with sync",
        recommended: false,
        ai: false,
    },
    {
        // Has built-in AI, but its settings live inside the notes database,
        // which does not exist until Trilium's own first-run setup. Set it up
        // under Options → AI / LLM, using http://localhost:13305/v1 (Lemonade)
        // or http://localhost:8080/v1 (ramalama).
        id: "org.triliumnotes.Trilium",
        kind: "flatpak",
        name: "Trilium Notes",
        description: "Hierarchical notes and personal knowledge base",
        recommended: false,
        ai: false,
    },
    {
        // Uses translation services, not language models.
        id: "org.kde.CrowTranslate",
        kind: "flatpak",
        name: "Crow Translate",
        description: "Translate text, speak it and read it aloud",
        recommended: false,
        ai: false,
    },
    {
        // Runs its own local speech models; no OpenAI-compatible setting.
        id: "net.mkiol.SpeechNote",
        kind: "flatpak",
        name: "Speech Note",
        description: "Offline speech-to-text, text-to-speech and translation",
        recommended: false,
        ai: false,
    },
];
