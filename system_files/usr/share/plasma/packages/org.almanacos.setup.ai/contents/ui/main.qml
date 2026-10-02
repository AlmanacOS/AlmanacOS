// AlmanacOS setup wizard — pick the local model server, and whether apps are
// pointed at it.
//
// Like the apps page, this only records the choice in choices.ini;
// /usr/libexec/almanac-setup acts on it after the wizard finishes. The server
// choice is system-wide (Lemonade's service is left on or turned off). The
// hookup is per user: at each user's next login it runs
// `almanac-ai backend <server>` and the hook for every AI-capable app ticked on
// the previous page.

pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

import org.kde.plasmasetup.components as PlasmaSetupComponents

PlasmaSetupComponents.SetupModule {
    id: root

    nextEnabled: true

    property string backend: "lemonade"
    property bool hookup: true

    /**
    * Names of the AI-capable apps ticked on the Recommended Apps page.
    */
    property string aiNames: ""

    readonly property string backendName: backend === "ramalama" ? "ramalama" : "Lemonade"

    Settings {
        id: choices
        location: "file:///var/lib/almanac-setup/choices/choices.ini"
    }

    function save(): void {
        choices.setValue("ai/backend", root.backend);
        choices.setValue("ai/hookup", root.hookup);
        choices.setValue("meta/revision", String(Date.now()));
        choices.sync();
    }

    // The apps page writes the same file from another Settings object, so
    // re-read it each time this page comes into view.
    function onPageActivated(): void {
        choices.sync();
        root.aiNames = String(choices.value("apps/aiNames", ""));
    }

    Component.onCompleted: {
        const backend = String(choices.value("ai/backend", "lemonade"));
        root.backend = backend === "ramalama" ? "ramalama" : "lemonade";
        // QSettings hands an INI boolean back as the string "true"/"false".
        root.hookup = String(choices.value("ai/hookup", true)) === "true";
        root.onPageActivated();
        save();
    }

    contentItem: ScrollView {
        id: scroll
        clip: true

        ColumnLayout {
            width: scroll.availableWidth
            spacing: Kirigami.Units.gridUnit

            Label {
                Layout.fillWidth: true
                Layout.maximumWidth: root.cardWidth
                Layout.alignment: Qt.AlignHCenter
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: i18nc("@info", "AlmanacOS runs language models on this device. Choose which server provides them.")
            }

            FormCard.FormCard {
                maximumWidth: root.cardWidth
                Layout.alignment: Qt.AlignHCenter

                FormCard.FormRadioDelegate {
                    text: i18nc("@option:radio", "Lemonade (recommended)")
                    description: i18nc("@info", "Always running in the background. Serves models on port 13305.")
                    checked: root.backend === "lemonade"
                    onToggled: {
                        if (checked) {
                            root.backend = "lemonade";
                            root.save();
                        }
                    }
                }

                FormCard.FormDelegateSeparator {}

                FormCard.FormRadioDelegate {
                    text: i18nc("@option:radio", "ramalama")
                    description: i18nc("@info", "Runs models in containers, on port 8080, while \"ramalama serve\" is running. Lemonade's background service is turned off.")
                    checked: root.backend === "ramalama"
                    onToggled: {
                        if (checked) {
                            root.backend = "ramalama";
                            root.save();
                        }
                    }
                }
            }

            FormCard.FormCard {
                maximumWidth: root.cardWidth
                Layout.alignment: Qt.AlignHCenter

                FormCard.FormSwitchDelegate {
                    text: i18nc("@option:check %1 is Lemonade or ramalama", "Connect apps to %1 automatically", root.backendName)
                    description: root.aiNames.length > 0
                        ? i18nc("@info %1 is a list of app names", "Applies to %1, and to command-line tools that use the OpenAI API.", root.aiNames)
                        : i18nc("@info", "Applies to command-line tools that use the OpenAI API.")
                    checked: root.hookup
                    onToggled: {
                        root.hookup = checked;
                        root.save();
                    }
                }
            }
        }
    }
}
