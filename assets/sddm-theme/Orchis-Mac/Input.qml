import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

TextField {
    placeholderTextColor: "#8A9BB0"
    palette.text: "#FFFFFF"
    font.pointSize: config.fontSize
    font.family: config.Font || "Noto Sans"
    width: parent.width
    background: Rectangle {
        radius: 22
        border.color: parent.activeFocus ? "#1A73E8" : "#3A5A7A"
        border.width: 1.5
        color: parent.activeFocus ? "#253545" : "#151E2A"
        Behavior on border.color {
            ColorAnimation { duration: 150 }
        }
        Behavior on color {
            ColorAnimation { duration: 150 }
        }
    }
    leftPadding: 16
    rightPadding: 16
}
