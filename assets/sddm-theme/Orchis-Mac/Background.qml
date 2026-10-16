/*
    SPDX-FileCopyrightText: 2016 Boudhayan Gupta <bgupta@kde.org>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick 2.15

FocusScope {
    id: sceneBackground

    property var sceneBackgroundType
    property alias sceneBackgroundColor: sceneColorBackground.color
    property alias sceneBackgroundImage: sceneImageBackground.source

    Rectangle {
        id: sceneColorBackground
        anchors.fill: parent
    }

    Image {
        id: sceneImageBackground
        anchors.fill: parent
        sourceSize.width: parent.width
        sourceSize.height: parent.height
        fillMode: Image.PreserveAspectCrop
        smooth: true;
    }

    // Subtle vertical scrim so the clock/footer and login card stay legible
    // regardless of how bright the chosen wallpaper is.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.08) }
            GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.00) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.42) }
        }
    }

    states: [
        State {
            name: "imageBackground"
            when: sceneBackgroundType === "image"
            PropertyChanges {
                target: sceneColorBackground
                visible: false
            }
            PropertyChanges {
                target: sceneImageBackground
                visible: true
            }
        },
        State {
            name: "colorBackground"
            when: sceneBackgroundType !== "image"
            PropertyChanges {
                target: sceneColorBackground
                visible: true
            }
            PropertyChanges {
                target: sceneImageBackground
                visible: false
            }
        }
    ]
}
