// AlmanacOS setup wizard — pick apps to install, and which of them to connect
// to the local model server chosen on the previous page.
//
// Nothing is installed from here. The wizard runs as the unprivileged
// plasma-setup user, often before there is a network, so this page only
// records the choice in choices.ini. /usr/libexec/almanac-setup acts on it once
// the wizard has finished. See that script for the file format.

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
    * IDs ticked for install. Required apps are never in here.
    */
    property var selected: []

    /**
    * IDs whose "connect" switch is on, whether or not they are installed.
    */
    property var hooked: []

    /**
    * Written by the Local AI page, which comes first.
    */
    property string backendName: "Lemonade"

    Settings {
        id: choices
        location: "file:///var/lib/almanac-setup/choices/choices.ini"
    }

    function has(list: var, id: string): bool {
        return list.indexOf(id) >= 0;
    }

    function toggled(list: var, id: string, on: bool): var {
        const rest = list.filter(other => other !== id);
        return on ? rest.concat([id]) : rest;
    }

    function installed(app: var): bool {
        return app.required === true || root.has(root.selected, app.id);
    }

    function idsOf(kind: string): string {
        return Catalog.apps
            .filter(app => app.kind === kind && !app.required && root.has(root.selected, app.id))
            .map(app => app.id)
            .join(" ");
    }

    // Space-separated lists, so the shell side can read them without a parser.
    // aiIds is what gets hooked up: AI-capable, switched on, and installed.
    function save(): void {
        const ai = Catalog.apps.filter(app => app.ai && root.has(root.hooked, app.id) && root.installed(app));
        choices.setValue("apps/selected", root.selected.join(" "));
        choices.setValue("apps/hooked", root.hooked.join(" "));
        choices.setValue("apps/flatpaks", idsOf("flatpak"));
        choices.setValue("apps/brews", idsOf("brew"));
        choices.setValue("apps/aiIds", ai.map(app => app.id).join(" "));
        choices.setValue("meta/revision", String(Date.now()));
        choices.sync();
    }

    // Keep only IDs still in the catalog, so a re-run after an app is dropped
    // from it does not try to install or hook up something no longer offered.
    function load(key: string, fallback: var): var {
        const previous = choices.value(key, null);
        if (previous === null || previous === undefined) {
            return fallback;
        }
        const known = Catalog.apps.map(app => app.id);
        return String(previous).split(" ").filter(id => known.indexOf(id) >= 0);
    }

    function onPageActivated(): void {
        choices.sync();
        root.backendName = String(choices.value("ai/backend", "lemonade")) === "ramalama" ? "ramalama" : "Lemonade";
    }

    // A re-run (after an upgrade that bumps the flow version) starts from what
    // was picked last time; a first run starts from the catalog's defaults.
    Component.onCompleted: {
        root.selected = load("apps/selected",
            Catalog.apps.filter(app => app.recommended && !app.required).map(app => app.id));
        root.hooked = load("apps/hooked",
            Catalog.apps.filter(app => app.ai).map(app => app.id));
        onPageActivated();
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
                text: i18nc("@info %1 is Lemonade or ramalama", "Choose apps to install, and which should use %1 for their AI features. Apps download in the background once setup is finished and this device is online.", root.backendName)
            }

            FormCard.FormCard {
                maximumWidth: root.cardWidth
                Layout.alignment: Qt.AlignHCenter

                Repeater {
                    model: Catalog.apps

                    delegate: ColumnLayout {
                        id: row

                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        spacing: 0

                        FormCard.FormDelegateSeparator {
                            visible: row.index > 0
                        }

                        FormCard.FormTextDelegate {
                            visible: row.modelData.required === true
                            text: row.modelData.name
                            description: i18nc("@info", "Included with AlmanacOS. %1", row.modelData.description)
                        }

                        FormCard.FormCheckDelegate {
                            visible: row.modelData.required !== true
                            text: row.modelData.name
                            description: row.modelData.description
                            checked: root.has(root.selected, row.modelData.id)
                            onToggled: {
                                root.selected = root.toggled(root.selected, row.modelData.id, checked);
                                root.save();
                            }
                        }

                        FormCard.FormSwitchDelegate {
                            visible: row.modelData.ai === true
                            enabled: root.installed(row.modelData)
                            leftPadding: Kirigami.Units.gridUnit * 2
                            text: i18nc("@option:check %1 is Lemonade or ramalama", "Use %1 for AI features", root.backendName)
                            checked: root.has(root.hooked, row.modelData.id)
                            onToggled: {
                                root.hooked = root.toggled(root.hooked, row.modelData.id, checked);
                                root.save();
                            }
                        }
                    }
                }
            }
        }
    }
}
