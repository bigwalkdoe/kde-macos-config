import org.kde.breeze.components

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.plasma.extras 2.0 as PlasmaExtras
import org.kde.kirigami 2.20 as Kirigami
import org.kde.plasma.plasma5support 2.0 as PlasmaCore

SessionManagementScreen {
    id: root
    property Item mainPasswordBox: passwordBox
    property bool showUsernamePrompt: !showUserList
    property int usernameFontSize
    property int fontSize: parseInt(config.fontSize)
    property string usernameFontColor
    property string lastUserName
    property bool loginScreenUiVisible: false
    property bool passwordFieldOutlined: config.PasswordFieldOutlined == "true"
    property bool hidePasswordRevealIcon: config.HidePasswordRevealIcon == "false"
    property int visibleBoundary: mapFromItem(loginButton, 0, 0).y
    onHeightChanged: visibleBoundary = mapFromItem(loginButton, 0, 0).y + loginButton.height + Kirigami.Units.smallSpacing

    signal loginRequest(string username, string password)

    onShowUsernamePromptChanged: {
        if (!showUsernamePrompt) {
            lastUserName = ""
        }
    }

    onUserSelected: {
        focusFirstVisibleFormControl();
    }

    QQC2.StackView.onActivating: {
        Qt.callLater(focusFirstVisibleFormControl);
    }

    function focusFirstVisibleFormControl() {
        const nextControl = (userNameInput.visible
            ? userNameInput
            : (passwordBox.visible
                ? passwordBox
                : loginButton));
        nextControl.forceActiveFocus(Qt.TabFocusReason);
    }

    function startLogin() {
        const username = showUsernamePrompt ? userNameInput.text : userList.selectedUser
        const password = passwordBox.text

        footer.enabled = false
        mainStack.enabled = false
        userListComponent.userList.opacity = 0.5

        loginButton.forceActiveFocus();
        loginRequest(username, password);
    }

    Rectangle {
        id: inputContainer
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.largeSpacing
        Layout.preferredHeight: 60
        visible: false // We use individual inputs below
    }

    Input {
        id: userNameInput
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.largeSpacing
        Layout.preferredHeight: 44
        font.pointSize: fontSize + 2
        opacity: 1
        text: lastUserName
        visible: showUsernamePrompt
        focus: showUsernamePrompt && !lastUserName
        placeholderText: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Username")
        placeholderTextColor: "#8A9BB0"
        color: "#FFFFFF"
        selectionColor: "#1A73E8"
        selectedTextColor: "#FFFFFF"
        leftPadding: 16
        rightPadding: 16
        background: Rectangle {
            radius: 10
            border.width: 1.5
            border.color: userNameInput.activeFocus ? "#1A73E8" : (root.loginScreenUiVisible ? "#4A90D9" : "#3A5A7A")
            color: userNameInput.activeFocus ? "#253545" : (root.loginScreenUiVisible ? "#1E2A3A" : "#151E2A")
            Behavior on border.color {
                ColorAnimation { duration: 150 }
            }
            Behavior on color {
                ColorAnimation { duration: 150 }
            }
        }
        onAccepted: passwordBox.forceActiveFocus()
    }

    Input {
        id: passwordBox
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.largeSpacing
        Layout.preferredHeight: 44
        font.pointSize: fontSize + 2
        font.family: config.Font || "Noto Sans"
        placeholderText: config.PasswordFieldPlaceholderText == "Password" ? i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Password") : config.PasswordFieldPlaceholderText
        focus: !showUsernamePrompt || lastUserName
        echoMode: TextInput.Password
        onAccepted: startLogin()
        placeholderTextColor: "#8A9BB0"
        passwordCharacter: config.PasswordFieldCharacter == "" ? "●" : config.PasswordFieldCharacter
        color: "#FFFFFF"
        selectionColor: "#1A73E8"
        selectedTextColor: "#FFFFFF"
        leftPadding: 16
        rightPadding: 16
        background: Rectangle {
            radius: 10
            border.width: 1.5
            border.color: passwordBox.activeFocus ? "#1A73E8" : (root.loginScreenUiVisible ? "#4A90D9" : "#3A5A7A")
            color: passwordBox.activeFocus ? "#253545" : (root.loginScreenUiVisible ? "#1E2A3A" : "#151E2A")
            Behavior on border.color {
                ColorAnimation { duration: 150 }
            }
            Behavior on color {
                ColorAnimation { duration: 150 }
            }
        }

        Keys.onEscapePressed: {
            mainStack.currentItem.forceActiveFocus();
        }

        Keys.onPressed: {
            if (event.key == Qt.Key_Left && !text) {
                userList.decrementCurrentIndex();
                event.accepted = true
            }
            if (event.key == Qt.Key_Right && !text) {
                userList.incrementCurrentIndex();
                event.accepted = true
            }
        }

        Keys.onReleased: {
            if (loginButton.opacity == 0 && length > 0) {
                showLoginButton.start()
            }
            if (loginButton.opacity > 0 && length == 0) {
                hideLoginButton.start()
            }
        }

        Connections {
            target: sddm
            onLoginFailed: {
                passwordBox.selectAll()
                passwordBox.forceActiveFocus()
            }
        }
    }

    // macOS-style login button with hover/tap feedback
    Item {
        id: loginButton
        Layout.margins: Kirigami.Units.largeSpacing
        Layout.preferredWidth: 44
        Layout.preferredHeight: 44
        opacity: 0
        visible: opacity > 0

        property bool pressed: false

        Rectangle {
            id: buttonBg
            anchors.fill: parent
            radius: 22
            color: "#1A73E8"
            border.width: 0
            Behavior on color {
                ColorAnimation { duration: 100 }
            }
        }

        Image {
            anchors.centerIn: parent
            source: "assets/login.svgz"
            sourceSize: Qt.size(24, 24)
            smooth: true
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: buttonBg.color = "#2A83F8"
            onExited: buttonBg.color = "#1A73E8"
            onPressed: {
                buttonBg.color = "#0A5FC8"
                buttonBg.scale = 0.95
            }
            onReleased: {
                buttonBg.color = "#1A73E8"
                buttonBg.scale = 1.0
                startLogin();
            }
        }

        PropertyAnimation {
            id: showLoginButton
            target: loginButton
            properties: "opacity"
            to: 0.9
            duration: 150
            easing.type: Easing.OutCubic
        }
        PropertyAnimation {
            id: hideLoginButton
            target: loginButton
            properties: "opacity"
            to: 0
            duration: 120
            easing.type: Easing.InCubic
        }
    }

    // User avatar with subtle glow
    Item {
        id: userAvatar
        Layout.margins: Kirigami.Units.largeSpacing
        Layout.preferredWidth: 80
        Layout.preferredHeight: 80
        visible: !showUsernamePrompt

        Rectangle {
            id: avatarContainer
            anchors.centerIn: parent
            width: 80
            height: 80
            radius: 40
            clip: true
            border.width: 2
            border.color: root.loginScreenUiVisible ? "#1A73E8" : "#3A5A7A"
            Behavior on border.color {
                ColorAnimation { duration: 300 }
            }

            Image {
                id: avatarImage
                anchors.fill: parent
                source: userList.currentUserImage
                fillMode: Image.PreserveAspectCrop
                smooth: true
            }
        }
    }
}