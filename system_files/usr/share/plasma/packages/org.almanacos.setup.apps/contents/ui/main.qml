// AlmanacOS setup wizard — pick recommended apps to install.
//
// Nothing is installed from here. The wizard runs as the unprivileged
// plasma-setup user, often before there is a network, so this page only
// records the choice in choices.ini. /usr/libexec/almanac-setup installs it
// once the wizard has finished: Flatpaks system-wide as root, Homebrew
// formulae per user at their next login. See that script for the file format.

pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

import org.kde.plasmasetup.components as PlasmaSetupComponents

import "catalog.js" as Catalog

PlasmaSetupComponents.SetupModule {
    id: root

    available: Catalog.apps.length > 0
    nextEnabled: true

    /**
    * IDs of the apps currently ticked.
    */
    property var selected: []

    Settings {
        id: choices
        location: "file:///var/lib/almanac-setup/choices/choices.ini"
    }

    function isSelected(id: string): bool {
        return root.selected.indexOf(id) >= 0;
    }

    function setSelected(id: string, on: bool): void {
        const rest = root.selected.filter(other => other !== id);
        root.selected = on ? rest.concat([id]) : rest;
        save();
    }

    function idsOf(kind: string): string {
        return Catalog.apps
            .filter(app => app.kind === kind && root.isSelected(app.id))
            .map(app => app.id)
            .join(" ");
    }

    // Space-separated lists, so the shell side can read them without a parser.
    // aiNames is only for the Local AI page to show back to the user.
    function save(): void {
        const ai = Catalog.apps.filter(app => app.ai && root.isSelected(app.id));
        choices.setValue("apps/selected", root.selected.join(" "));
        choices.setValue("apps/flatpaks", idsOf("flatpak"));
        choices.setValue("apps/brews", idsOf("brew"));
        choices.setValue("apps/aiIds", ai.map(app => app.id).join(" "));
        choices.setValue("apps/aiNames", ai.map(app => app.name).join(", "));
        choices.setValue("meta/revision", String(Date.now()));
        choices.sync();
    }

    // A re-run (after an upgrade that bumps the flow version) starts from what
    // was picked last time; a first run starts from the recommended set.
    Component.onCompleted: {
        const previous = choices.value("apps/selected", null);
        if (previous === null || previous === undefined) {
            root.selected = Catalog.apps.filter(app => app.recommended).map(app => app.id);
        } else {
            const known = Catalog.apps.map(app => app.id);
            root.selected = String(previous).split(" ").filter(id => known.indexOf(id) >= 0);
        }
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
                text: i18nc("@info", "Choose apps to install. They download in the background once setup is finished and this device is online.")
            }

            FormCard.FormCard {
                maximumWidth: root.cardWidth
                Layout.alignment: Qt.AlignHCenter

                Repeater {
                    model: Catalog.apps

                    delegate: FormCard.FormCheckDelegate {
                        required property var modelData

                        text: modelData.name
                        description: modelData.description
                        checked: root.isSelected(modelData.id)
                        onToggled: root.setSelected(modelData.id, checked)
                    }
                }
            }
        }
    }
}
