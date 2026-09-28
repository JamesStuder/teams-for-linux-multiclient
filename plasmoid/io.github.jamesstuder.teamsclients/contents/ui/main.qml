import QtQuick
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
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
    readonly property int signedOut: clients.filter(c => c.signin).length

    function run(args) { exec.connectSource(tool + " " + args + " #" + Date.now()) }

    Plasmoid.icon: "teams-for-linux"
    Plasmoid.status: unread > 0 || signedOut > 0 ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.ActiveStatus
    toolTipMainText: signedOut > 0 ? `Microsoft Teams: ${signedOut} signed out`
        : unread > 0 ? `Microsoft Teams: ${unread} unread` : "Microsoft Teams"
    toolTipSubText: clients.length === 0 ? "No clients configured (teams-client add NAME)"
        : clients.map(c => `Meta+Shift+${c.n}  ${c.name}: ` +
            (!c.running ? "not running" : c.signin ? "⚠ signed out, sign in again"
                : c.unread > 0 ? `${c.unread} unread` : "no new messages")).join("\n")
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
        // Signed-out warning, top left (the unread badge sits bottom right)
        Kirigami.Icon {
            visible: root.signedOut > 0
            anchors { left: parent.left; top: parent.top }
            width: Math.round(parent.width * 0.55)
            height: width
            source: "dialog-warning"
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

    // PlasmaExtras.Menu is a native QMenu. QQC2 Popup.Window menus crashed plasmashell
    // whenever they were destroyed (freed QQuickWindow still queued for a redraw).
    PlasmaExtras.Menu { id: menu }
    Component { id: menuComp; PlasmaExtras.Menu {} }
    Component {
        id: itemComp
        PlasmaExtras.MenuItem {
            property var cb
            onClicked: if (cb) cb()
        }
    }
    property var built: []

    function addItem(m, text, cb, extra) {
        const it = itemComp.createObject(m, Object.assign({ text: text, cb: cb }, extra || {}))
        m.addMenuItem(it)
        built.push(it)
        return it
    }
    function addSep(m) {
        const it = itemComp.createObject(m, { separator: true })
        m.addMenuItem(it)
        built.push(it)
    }
    function addSub(m, title, extra) {
        const it = addItem(m, title, null, extra)
        const sub = menuComp.createObject(m, { visualParent: it.action })
        built.push(sub)
        return sub
    }

    // Mirror a client's native tray menu (JSON from `teams-client status`).
    function addNative(m, slug, items) {
        for (const it of items) {
            if (it.type === "separator") {
                addSep(m)
            } else if (it.children.length > 0) {
                addNative(addSub(m, it.label, { enabled: it.enabled }), slug, it.children)
            } else {
                const id = it.id
                addItem(m, it.label, () => root.run(`click ${slug} ${id}`),
                        { enabled: it.enabled, checkable: it.checkable, checked: it.checked })
            }
        }
    }

    function openMenu(parentItem, x, y) {
        if (menu.status === PlasmaExtras.Menu.Open) { menu.close(); return }
        // The menu is closed here, so tearing down the previous build is safe.
        menu.clearMenuItems()
        // clearMenuItems() already deletes the MenuItems it held, so some entries are gone;
        // destroying those throws and used to abort the whole menu.
        for (const o of built) {
            try { if (o && typeof o.destroy === "function") o.destroy() } catch (e) {}
        }
        built = []
        for (const c of clients) {
            const slug = c.slug
            const title = `${c.n}  ${c.name}` + (c.signin ? "  ⚠ signed out" : c.unread > 0 ? `  (${c.unread})`
                : c.running ? "" : "  (not running)")
            const sub = addSub(menu, title, c.signin ? { icon: "dialog-warning" } : undefined)
            addItem(sub, c.signin ? "Sign in" : c.running ? "Show" : "Start", () => root.run(`focus ${slug}`),
                    { icon: c.signin ? "dialog-password" : "window" })
            if (c.running && c.menu.length > 0) {
                addSep(sub)
                addNative(sub, slug, c.menu)
            }
        }
        if (clients.length > 0)
            addSep(menu)
        addItem(menu, "Start all clients", () => root.run("start-all"), { icon: "media-playback-start" })
        if (root.anyRunning)
            addItem(menu, "Quit all clients", () => root.run("quit-all"), { icon: "application-exit" })
        addItem(menu, "Add client…", () => root.run("add-gui"), { icon: "list-add" })
        if (clients.length > 0) {
            const rm = addSub(menu, "Remove client")
            for (const c of clients) {
                const slug = c.slug
                addItem(rm, c.name, () => root.run(`remove-gui ${slug}`))
            }
        }
        menu.visualParent = parentItem
        menu.open(x, y)
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
