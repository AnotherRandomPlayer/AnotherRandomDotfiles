import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * Diccionario japones (API publica de Jisho) con teclado romaji -> kana propio.
 * Boton de la caja: A (texto normal) -> あ (hiragana) -> ア (katakana)
 */
Item {
    id: root

    property real padding: 12

    // Lo pasa SidebarLeftContent; es quien tiene la propiedad "extend" (ancho de la barra)
    property var scopeRoot: null   // lo pasa SidebarLeftContent (ya no se usa para ampliar)

    // Ventana de la barra lateral: ahi vive la propiedad "extend" (ancho 460 <-> 750)
    property var hostWindow: QsWindow.window
    readonly property bool canExtend: hostWindow !== null && hostWindow !== undefined
                                      && hostWindow.extend !== undefined
    readonly property bool extended: canExtend && hostWindow.extend === true
    readonly property bool isDictionary: true   // SidebarLeftContent lo usa para ocultar las pestanas
    property bool loading: false
    property string errorText: ""

    // 0 = texto normal, 1 = hiragana, 2 = katakana
    property int kanaMode: 1
    property bool _converting: false
    property var kanaTable: buildTable()

    ListModel { id: results }

    // Lee el portapapeles (necesita wl-clipboard) y busca lo que haya
    Process {
        id: pasteProc
        command: ["wl-paste", "-n"]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = text.split("\n")[0].trim().slice(0, 60)
                if (t === "") return
                root._converting = true
                input.text = t
                root._converting = false
                root.search(t)
            }
        }
    }

    onActiveFocusChanged: if (activeFocus) input.forceActiveFocus()

    // ---------- Romaji -> kana ----------
    function buildTable() {
        var t = {}
        var vowels = ["a", "i", "u", "e", "o"]
        var rows = {
            "":  ["あ", "い", "う", "え", "お"],
            "k": ["か", "き", "く", "け", "こ"],
            "g": ["が", "ぎ", "ぐ", "げ", "ご"],
            "s": ["さ", "し", "す", "せ", "そ"],
            "z": ["ざ", "じ", "ず", "ぜ", "ぞ"],
            "t": ["た", "ち", "つ", "て", "と"],
            "d": ["だ", "ぢ", "づ", "で", "ど"],
            "n": ["な", "に", "ぬ", "ね", "の"],
            "h": ["は", "ひ", "ふ", "へ", "ほ"],
            "b": ["ば", "び", "ぶ", "べ", "ぼ"],
            "p": ["ぱ", "ぴ", "ぷ", "ぺ", "ぽ"],
            "m": ["ま", "み", "む", "め", "も"],
            "r": ["ら", "り", "る", "れ", "ろ"],
            "y": ["や", "", "ゆ", "", "よ"],
            "w": ["わ", "うぃ", "う", "うぇ", "を"]
        }
        for (var c in rows)
            for (var i = 0; i < 5; i++)
                if (rows[c][i] !== "") t[c + vowels[i]] = rows[c][i]

        var ybase = { k: "き", g: "ぎ", n: "に", h: "ひ", b: "び", p: "ぴ", m: "み", r: "り" }
        for (var b in ybase) {
            t[b + "ya"] = ybase[b] + "ゃ"
            t[b + "yu"] = ybase[b] + "ゅ"
            t[b + "yo"] = ybase[b] + "ょ"
        }

        var extra = {
            "shi": "し", "sha": "しゃ", "shu": "しゅ", "sho": "しょ", "she": "しぇ",
            "chi": "ち", "cha": "ちゃ", "chu": "ちゅ", "cho": "ちょ", "che": "ちぇ",
            "tsu": "つ", "ji": "じ", "ja": "じゃ", "ju": "じゅ", "jo": "じょ", "je": "じぇ",
            "fu": "ふ", "fa": "ふぁ", "fi": "ふぃ", "fe": "ふぇ", "fo": "ふぉ",
            "si": "し", "ti": "ち", "tu": "つ", "hu": "ふ", "zi": "じ",
            "sya": "しゃ", "syu": "しゅ", "syo": "しょ",
            "tya": "ちゃ", "tyu": "ちゅ", "tyo": "ちょ",
            "zya": "じゃ", "zyu": "じゅ", "zyo": "じょ",
            "jya": "じゃ", "jyu": "じゅ", "jyo": "じょ",
            "dya": "ぢゃ", "dyu": "ぢゅ", "dyo": "ぢょ",
            "thi": "てぃ", "dhi": "でぃ",
            "vu": "ゔ", "va": "ゔぁ", "vi": "ゔぃ", "ve": "ゔぇ", "vo": "ゔぉ",
            "xa": "ぁ", "xi": "ぃ", "xu": "ぅ", "xe": "ぇ", "xo": "ぉ",
            "xya": "ゃ", "xyu": "ゅ", "xyo": "ょ", "xtu": "っ", "xtsu": "っ",
            "n'": "ん", "-": "ー"
        }
        for (var k in extra) t[k] = extra[k]
        return t
    }

    function romajiToKana(input, katakana) {
        var s = input.toLowerCase()
        var out = ""
        var i = 0
        while (i < s.length) {
            var c = s.charAt(i)
            var nx = s.charAt(i + 1)

            // consonante doble -> っ  (kk, tt, ss...)
            if (c === nx && /[bcdfghjkmpqrstvwxyz]/.test(c)) { out += "っ"; i++; continue }
            if (c === "t" && s.substr(i + 1, 2) === "ch") { out += "っ"; i++; continue }

            var matched = false
            for (var len = 4; len >= 1; len--) {
                var key = s.substr(i, len)
                if (key.length === len && kanaTable[key] !== undefined) {
                    out += kanaTable[key]
                    i += len
                    matched = true
                    break
                }
            }
            if (matched) continue

            // n seguida de consonante -> ん
            if (c === "n" && nx !== "" && !/[aiueoy']/.test(nx)) { out += "ん"; i++; continue }

            out += c
            i++
        }

        if (katakana) {
            var k = ""
            for (var j = 0; j < out.length; j++) {
                var code = out.charCodeAt(j)
                k += (code >= 0x3041 && code <= 0x3096) ? String.fromCharCode(code + 0x60) : out.charAt(j)
            }
            out = k
        }
        return out
    }

    // Al buscar, una "n" suelta al final se convierte en ん
    function finalizeKana(s) {
        if (kanaMode === 0) return s
        var out = romajiToKana(s, kanaMode === 2)
        if (out.charAt(out.length - 1) === "n")
            out = out.slice(0, -1) + (kanaMode === 2 ? "ン" : "ん")
        return out
    }

    // ---------- Busqueda en Jisho ----------
    function search(q) {
        q = q.trim()
        if (q === "") return
        loading = true
        errorText = ""
        results.clear()

        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            root.loading = false
            if (xhr.status !== 200) {
                root.errorText = "No se pudo consultar Jisho (código " + xhr.status + ")"
                return
            }
            try {
                var data = JSON.parse(xhr.responseText).data
                if (!data || data.length === 0) {
                    root.errorText = "Sin resultados"
                    return
                }
                for (var i = 0; i < data.length; i++) {
                    var e = data[i]
                    var jp = (e.japanese && e.japanese.length > 0) ? e.japanese[0] : {}
                    var senses = []
                    var n = Math.min(e.senses.length, 4)
                    for (var j = 0; j < n; j++) {
                        var s = e.senses[j]
                        var line = (j + 1) + ". " + s.english_definitions.join("; ")
                        if (s.parts_of_speech && s.parts_of_speech.length > 0)
                            line += "  (" + s.parts_of_speech.join(", ") + ")"
                        senses.push(line)
                    }
                    results.append({
                        word: jp.word || jp.reading || "",
                        reading: jp.word ? (jp.reading || "") : "",
                        common: e.is_common === true,
                        jlpt: (e.jlpt && e.jlpt.length > 0)
                              ? e.jlpt[0].replace("jlpt-", "").toUpperCase() : "",
                        meanings: senses.join("\n")
                    })
                }
            } catch (err) {
                root.errorText = "Respuesta no válida de Jisho"
            }
        }
        xhr.open("GET", "https://jisho.org/api/v1/search/words?keyword=" + encodeURIComponent(q))
        xhr.send()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: 10

        // Caja de busqueda
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            radius: height / 2
            color: Appearance.colors.colLayer2

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 6
                spacing: 6

                TextField {
                    id: input
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    placeholderText: root.kanaMode === 0 ? "Inglés o japonés…" : "Escribe en romaji: taberu → たべる"
                    placeholderTextColor: Appearance.colors.colSubtext
                    color: Appearance.colors.colOnLayer1
                    selectionColor: Appearance.colors.colPrimary
                    font.pixelSize: 15
                    background: null

                    onTextChanged: {
                        if (root.kanaMode === 0 || root._converting) return
                        var c = root.romajiToKana(text, root.kanaMode === 2)
                        if (c !== text) {
                            root._converting = true
                            text = c
                            cursorPosition = c.length
                            root._converting = false
                        }
                    }
                    onAccepted: {
                        var q = root.finalizeKana(text)
                        if (q !== text) text = q
                        root.search(q)
                    }
                }

                // Pegar del portapapeles y buscar
                Rectangle {
                    Layout.preferredWidth: 54
                    Layout.preferredHeight: 34
                    radius: 17
                    color: pasteArea.containsMouse ? Appearance.colors.colLayer1 : "transparent"

                    StyledText {
                        anchors.centerIn: parent
                        text: "Pegar"
                        color: Appearance.colors.colPrimary
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: pasteArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pasteProc.running = true
                    }
                }

                // Ampliar / reducir la barra lateral
                Rectangle {
                    visible: root.canExtend
                    Layout.preferredWidth: 62
                    Layout.preferredHeight: 34
                    radius: 17
                    color: extendArea.containsMouse ? Appearance.colors.colLayer1 : "transparent"

                    StyledText {
                        anchors.centerIn: parent
                        text: root.extended ? "Reducir" : "Ampliar"
                        color: Appearance.colors.colPrimary
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: extendArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.hostWindow.extend = !root.hostWindow.extend
                    }
                }

                // Selector de modo: A / あ / ア
                Rectangle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    radius: 17
                    color: modeArea.containsMouse ? Appearance.colors.colLayer1 : "transparent"

                    StyledText {
                        anchors.centerIn: parent
                        text: root.kanaMode === 0 ? "A" : (root.kanaMode === 1 ? "あ" : "ア")
                        color: Appearance.colors.colPrimary
                        font.pixelSize: 16
                        font.bold: true
                    }
                    MouseArea {
                        id: modeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.kanaMode = (root.kanaMode + 1) % 3
                            if (root.kanaMode !== 0)
                                input.text = root.romajiToKana(input.text, root.kanaMode === 2)
                            input.forceActiveFocus()
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.loading || root.errorText !== ""
            text: root.loading ? "Buscando…" : root.errorText
            color: Appearance.colors.colSubtext
            font.pixelSize: 13
            wrapMode: Text.Wrap
        }

        // Resultados
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8
            model: results

            delegate: Rectangle {
                width: ListView.view.width
                height: col.implicitHeight + 24
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2

                ColumnLayout {
                    id: col
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        StyledText {
                            text: model.word
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: 26
                            font.bold: true
                        }
                        StyledText {
                            visible: model.reading !== ""
                            text: model.reading
                            color: Appearance.colors.colPrimary
                            font.pixelSize: 15
                            Layout.alignment: Qt.AlignBottom
                        }
                        Item { Layout.fillWidth: true }
                        StyledText {
                            visible: model.common
                            text: "común"
                            color: Appearance.colors.colSubtext
                            font.pixelSize: 11
                        }
                        StyledText {
                            visible: model.jlpt !== ""
                            text: model.jlpt
                            color: Appearance.colors.colPrimary
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: model.meanings
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: 13
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
