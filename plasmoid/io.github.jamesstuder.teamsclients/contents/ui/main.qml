import QtQuick
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

// One tray icon for every Teams client instance (see teams-client).
// Each client's own tray icon is kept hidden; its native menu is mirrored here.
PlasmoidItem {
    id: root

    readonly property string tool: "\"$HOME/.local/bin/teams-client\""
    readonly property string pollCmd: tool + " status"
    property var clients: []
    readonly property int unread: clients.reduce((n, c) => n + c.unread, 0)
    readonly property bool anyRunning: clients.some(c => c.running)
    property var menu: null

    function run(args) { exec.connectSource(tool + " " + args + " #" + Date.now()) }

    Plasmoid.icon: "teams-for-linux"
    Plasmoid.status: unread > 0 ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.ActiveStatus
    toolTipMainText: unread > 0 ? `Microsoft Teams: ${unread} unread` : "Microsoft Teams"
    toolTipSubText: clients.length === 0 ? "No clients configured (teams-client add NAME)"
        : clients.map(c => `Meta+Shift+${c.n}  ${c.name}: ` +
            (!c.running ? "not running" : c.unread > 0 ? `${c.unread} unread` : "no new messages")).join("\n")
        + "\n\nClick: client menus"
    preferredRepresentation: compactRepresentation

    // The tray may try to expand us on click; there is no popup, the menu is opened by the MouseArea.
    onExpandedChanged: if (expanded) expanded = false

    compactRepresentation: Item {
        id: compact
        Kirigami.Icon {
            anchors.fill: parent
            source: Plasmoid.icon
            active: mouse.containsMouse
            opacity: root.anyRunning ? 1.0 : 0.4
        }
        Rectangle {
            visible: root.unread > 0
            anchors { right: parent.right; bottom: parent.bottom }
            height: Math.round(parent.height * 0.55)
            width: Math.max(height, badgeText.implicitWidth + 4)
            radius: height / 2
            color: Kirigami.Theme.negativeTextColor
            QQC2.Label {
                id: badgeText
                anchors.centerIn: parent
                text: root.unread > 99 ? "99+" : root.unread
                color: "white"
                font.pixelSize: parent.height * 0.75
                font.bold: true
            }
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: ev => root.openMenu(compact, ev.x, ev.y)
        }
    }
    fullRepresentation: Item {}

    Component { id: menuComp; QQC2.Menu { popupType: QQC2.Popup.Window } }
    Component { id: sepComp; QQC2.MenuSeparator {} }
    Component {
        id: itemComp
        QQC2.MenuItem {
            property var cb
            onTriggered: cb()
        }
    }

    function addItem(menu, text, cb, extra) {
        const it = itemComp.createObject(menu, Object.assign({ text: text, cb: cb }, extra || {}))
        menu.addItem(it)
    }

    // Mirror a client's native tray menu (JSON from `teams-client status`).
    function addNative(menu, slug, items) {
        for (const it of items) {
            if (it.type === "separator") {
                menu.addItem(sepComp.createObject(menu))
            } else if (it.children.length > 0) {
                const sub = menuComp.createObject(menu, { title: it.label, enabled: it.enabled })
                addNative(sub, slug, it.children)
                menu.addMenu(sub)
            } else {
                const id = it.id
                addItem(menu, it.label, () => root.run(`click ${slug} ${id}`),
                        { enabled: it.enabled, checkable: it.checkable, checked: it.checked })
            }
        }
    }

    function openMenu(parentItem, x, y) {
        // Destroying a Popup.Window menu right away can crash plasmashell (a queued
        // redraw hits the freed window), so old menus are closed and deleted later.
        if (menu) {
            if (menu.visible) { menu.close(); return }
        }
        const m = menuComp.createObject(parentItem)
        m.closed.connect(() => {
            m.destroy(5000)
            if (root.menu === m) root.menu = null
        })
        menu = m
        for (const c of clients) {
            const slug = c.slug
            const title = `${c.n}  ${c.name}` + (c.unread > 0 ? `  (${c.unread})` : c.running ? "" : "  (not running)")
            const sub = menuComp.createObject(menu, { title: title })
            addItem(sub, c.running ? "Show" : "Start", () => root.run(`focus ${slug}`),
                    { icon: { name: "window" } })
            if (c.running && c.menu.length > 0) {
                sub.addItem(sepComp.createObject(sub))
                addNative(sub, slug, c.menu)
            }
            menu.addMenu(sub)
        }
        if (clients.length > 0)
            menu.addItem(sepComp.createObject(menu))
        addItem(menu, "Start all clients", () => root.run("start-all"), { icon: { name: "media-playback-start" } })
        addItem(menu, "Add client…", () => root.run("add-gui"), { icon: { name: "list-add" } })
        if (clients.length > 0) {
            const rm = menuComp.createObject(menu, { title: "Remove client" })
            for (const c of clients) {
                const slug = c.slug
                addItem(rm, c.name, () => root.run(`remove-gui ${slug}`))
            }
            menu.addMenu(rm)
        }
        menu.popup(parentItem, x, y)
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: (source, data) => {
            if (source === root.pollCmd) {
                try { root.clients = JSON.parse(data.stdout) } catch (e) {}
            }
            disconnectSource(source)
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: exec.connectSource(root.pollCmd)
    }
}
