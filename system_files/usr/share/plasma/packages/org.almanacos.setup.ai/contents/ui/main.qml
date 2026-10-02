// AlmanacOS setup wizard — pick the local model server.
//
// Comes before the apps page, which names the server on each app's "use for AI
// features" switch. Like that page, this only records the choice in
// choices.ini; /usr/libexec/almanac-setup acts on it after the wizard
// finishes. The server is system-wide (Lemonade's service is left on or turned
// off). The command-line switch is applied per user at their next login, as
// `almanac-ai backend <server>`.

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
    property bool cli: true

    readonly property string backendName: backend === "ramalama" ? "ramalama" : "Lemonade"

    Settings {
        id: choices
        location: "file:///var/lib/almanac-setup/choices/choices.ini"
    }

    function save(): void {
        choices.setValue("ai/backend", root.backend);
        choices.setValue("ai/cli", root.cli);
        choices.setValue("meta/revision", String(Date.now()));
        choices.sync();
    }

    Component.onCompleted: {
        const backend = String(choices.value("ai/backend", "lemonade"));
        root.backend = backend === "ramalama" ? "ramalama" : "lemonade";
        // QSettings hands an INI boolean back as the string "true"/"false".
        root.cli = String(choices.value("ai/cli", true)) === "true";
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
                text: i18nc("@info", "AlmanacOS runs language models on this device. Choose which server provides them. On the next page you can connect apps to it.")
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
                    text: i18nc("@option:check %1 is Lemonade or ramalama", "Point command-line tools at %1", root.backendName)
                    description: i18nc("@info", "Sets OPENAI_BASE_URL, plus config for aichat and llm.")
                    checked: root.cli
                    onToggled: {
                        root.cli = checked;
                        root.save();
                    }
                }
            }
        }
    }
}
