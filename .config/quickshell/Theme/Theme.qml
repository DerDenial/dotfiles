pragma Singleton
import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel

QtObject {
    id: theme

    readonly property string home: Quickshell.env("HOME") || StandardPaths.writableLocation(StandardPaths.HomeLocation)
    readonly property string materialFallback: "{\"bgDim\": \"#141218\", \"bg0\": \"#141218\", \"surface\": \"#1d1b21\", \"surfaceAlt\": \"#232127\", \"surfaceRaised\": \"#2e2b31\", \"border\": \"#5e5a63\", \"mutedStrong\": \"#948f99\", \"muted\": \"#cac4cf\", \"text\": \"#e6e1e9\", \"textBright\": \"#e6e1e9\", \"accent\": \"#cebdfe\", \"accentDark\": \"#61528c\", \"accentSoft\": \"#39363d\", \"notchBg\": \"#0d0c11\", \"aqua\": \"#cbc3dc\", \"purple\": \"#efb8c8\", \"red\": \"#ffb4ab\", \"green\": \"#a1d39a\", \"greenDark\": \"#386637\", \"blue\": \"#adc6ff\", \"blueDark\": \"#415b8e\", \"yellow\": \"#e5c36c\", \"yellowDark\": \"#725808\", \"orange\": \"#fdb975\", \"orangeDark\": \"#825015\", \"redDark\": \"#b61718\", \"purpleDark\": \"#7a4f5e\", \"surfaceDark\": \"#0d0c11\", \"greenSurface\": \"#386637\", \"redBright\": \"#ffb4ab\", \"textLight\": \"#e6e1e9\", \"textWarm\": \"#e6e1e9\", \"blackOverlay\": \"#B3141218\", \"gray0\": \"#948f99\", \"gray1\": \"#cac4cf\", \"gray2\": \"#e6e1e9\"}"
    readonly property var materialColors: {
        try { return JSON.parse(saved.materialPalette || materialFallback); }
        catch (error) { return JSON.parse(materialFallback); }
    }
    readonly property var themes: [
        {
            id: "gruvbox", name: "Gruvbox", flavor: "Material · Orange", folder: "Gruvbox", defaultWallpaper: "notch-default.png",
            colors: {"bgDim":"#141617","bg0":"#1D2021","surface":"#282828","surfaceAlt":"#32302F","surfaceRaised":"#3C3836","border":"#504945","mutedStrong":"#665C54","muted":"#A89984","text":"#D4BE98","textBright":"#DDC7A1","red":"#EA6962","green":"#A9B665","blue":"#7DAEA3","yellow":"#D8A657","purple":"#D3869B","orange":"#E78A4E","aqua":"#89B482","redDark":"#442E2D","greenDark":"#333E34","blueDark":"#2E3B3B","yellowDark":"#473C29","purpleDark":"#3C333B","surfaceDark":"#3A302F","greenSurface":"#343B2D","redBright":"#F07167","textLight":"#EBDBB2","textWarm":"#F5E2C5","blackOverlay":"#B31D2021","gray0":"#7C6F64","gray1":"#928374","gray2":"#A89984","accent":"#E78A4E","accentDark":"#503A2C","accentSoft":"#352D26","notchBg":"#141617"}
        },
        {
            id: "tokyo-night", name: "Tokyo Night", flavor: "Night · Blue", folder: "Tokyo-Night", defaultWallpaper: "notch-default.png",
            colors: {"bgDim":"#16161E","bg0":"#1A1B26","surface":"#24283B","surfaceAlt":"#292E42","surfaceRaised":"#343A52","border":"#414868","mutedStrong":"#565F89","muted":"#A9B1D6","text":"#C0CAF5","textBright":"#D5DDFB","red":"#F7768E","green":"#9ECE6A","blue":"#7AA2F7","yellow":"#E0AF68","purple":"#BB9AF7","orange":"#FF9E64","aqua":"#7DCFFF","redDark":"#3B2637","greenDark":"#2B392E","blueDark":"#26354A","yellowDark":"#3D342C","purpleDark":"#342D49","surfaceDark":"#302C40","greenSurface":"#2D3A3A","redBright":"#FF899D","textLight":"#D5DDFB","textWarm":"#E5E9FF","blackOverlay":"#B31A1B26","gray0":"#565F89","gray1":"#737AA2","gray2":"#A9B1D6","accent":"#7AA2F7","accentDark":"#323D5A","accentSoft":"#262B3F","notchBg":"#16161E"}
        },
        {
            id: "catppuccin", name: "Catppuccin", flavor: "Mocha · Mauve", folder: "Catppuccin", defaultWallpaper: "notch-default.png",
            colors: {"bgDim":"#11111B","bg0":"#1E1E2E","surface":"#313244","surfaceAlt":"#45475A","surfaceRaised":"#585B70","border":"#6C7086","mutedStrong":"#7F849C","muted":"#A6ADC8","text":"#CDD6F4","textBright":"#CDD6F4","red":"#F38BA8","green":"#A6E3A1","blue":"#89B4FA","yellow":"#F9E2AF","purple":"#CBA6F7","orange":"#FAB387","aqua":"#94E2D5","redDark":"#452B3A","greenDark":"#2E403B","blueDark":"#26384B","yellowDark":"#484039","purpleDark":"#3D334C","surfaceDark":"#373044","greenSurface":"#344442","redBright":"#F5A0B7","textLight":"#CDD6F4","textWarm":"#F5E0DC","blackOverlay":"#B31E1E2E","gray0":"#6C7086","gray1":"#7F849C","gray2":"#9399B2","accent":"#CBA6F7","accentDark":"#494060","accentSoft":"#332E46","notchBg":"#11111B"}
        },
        {"id":"kanagawa","name":"Kanagawa","flavor":"Wave · Gold","folder":"Kanagawa","defaultWallpaper":"notch-default.png","colors":{"bgDim":"#17171F","bg0":"#1F1F28","surface":"#2A2A37","surfaceAlt":"#363646","surfaceRaised":"#45455A","border":"#54546D","mutedStrong":"#72728A","muted":"#9B9BAA","text":"#DCD7BA","textBright":"#E8E2C8","red":"#C34043","green":"#76946A","blue":"#7E9CD8","yellow":"#E6C384","purple":"#957FB8","orange":"#FFA066","aqua":"#7FB4CA","redDark":"#582B31","greenDark":"#3D483F","blueDark":"#404B66","yellowDark":"#655848","purpleDark":"#48415A","surfaceDark":"#272733","greenSurface":"#353C38","redBright":"#CA5D5B","textLight":"#E3DDC2","textWarm":"#E8DFC1","blackOverlay":"#B31F1F28","gray0":"#72728A","gray1":"#9B9BAA","gray2":"#DCD7BA","accent":"#E6C384","accentDark":"#51483F","accentSoft":"#373333","notchBg":"#17171F"}},
        {"id":"everforest","name":"Everforest","flavor":"Forest · Moss","folder":"Everforest","defaultWallpaper":"notch-default.png","colors":{"bgDim":"#232A2E","bg0":"#2D353B","surface":"#343F44","surfaceAlt":"#3D484D","surfaceRaised":"#475258","border":"#56635F","mutedStrong":"#7A8478","muted":"#9DA99A","text":"#D3C6AA","textBright":"#E4D9B9","red":"#E67E80","green":"#A7C080","blue":"#7FBBB3","yellow":"#DBBC7F","purple":"#D699B6","orange":"#E69875","aqua":"#83C092","redDark":"#6E4F53","greenDark":"#586653","blueDark":"#4A6465","yellowDark":"#6A6453","purpleDark":"#685866","surfaceDark":"#323C41","greenSurface":"#4C584C","redBright":"#E68E8A","textLight":"#DCD0B2","textWarm":"#E3D6B3","blackOverlay":"#B32D353B","gray0":"#7A8478","gray1":"#9DA99A","gray2":"#D3C6AA","accent":"#A7C080","accentDark":"#4C584C","accentSoft":"#3C4643","notchBg":"#232A2E"}},
        {"id":"nord","name":"Nord","flavor":"Polar · Ice","folder":"Nord","defaultWallpaper":"notch-default.png","colors":{"bgDim":"#242933","bg0":"#2E3440","surface":"#3B4252","surfaceAlt":"#434C5E","surfaceRaised":"#4C566A","border":"#5A6579","mutedStrong":"#6E7A8F","muted":"#9AA6B8","text":"#D8DEE9","textBright":"#ECEFF4","red":"#BF616A","green":"#A3BE8C","blue":"#81A1C1","yellow":"#EBCB8B","purple":"#B48EAD","orange":"#D08770","aqua":"#8FBCBB","redDark":"#61444F","greenDark":"#57645B","blueDark":"#4B5A6D","yellowDark":"#70695A","purpleDark":"#5D5466","surfaceDark":"#373E4D","greenSurface":"#4B5653","redBright":"#C77B83","textLight":"#E3E7EF","textWarm":"#ECEBEA","blackOverlay":"#B32E3440","gray0":"#6E7A8F","gray1":"#9AA6B8","gray2":"#D8DEE9","accent":"#88C0D0","accentDark":"#445764","accentSoft":"#394551","notchBg":"#242933"}},
        {"id":"rose-pine","name":"Rosé Pine","flavor":"Moon · Rose","folder":"Rose-Pine","defaultWallpaper":"notch-default.png","colors":{"bgDim":"#191724","bg0":"#232136","surface":"#2A273F","surfaceAlt":"#393552","surfaceRaised":"#44415A","border":"#56526E","mutedStrong":"#6E6A86","muted":"#908CAA","text":"#E0DEF4","textBright":"#F2F0FF","red":"#EB6F92","green":"#3E8FB0","blue":"#9CCFD8","yellow":"#F6C177","purple":"#C4A7E7","orange":"#EA9A97","aqua":"#9CCFD8","redDark":"#62364A","greenDark":"#213849","blueDark":"#475763","yellowDark":"#665241","purpleDark":"#554968","surfaceDark":"#1D1B2B","greenSurface":"#1F2E3F","redBright":"#EC86A6","textLight":"#EAE8FA","textWarm":"#F2EBF1","blackOverlay":"#B3191724","gray0":"#6E6A86","gray1":"#908CAA","gray2":"#E0DEF4","accent":"#EA9A97","accentDark":"#553F4E","accentSoft":"#3B3042","notchBg":"#191724"}},
        {"id":"dracula","name":"Dracula","flavor":"Dark · Purple","folder":"Dracula","defaultWallpaper":"notch-default.png","colors":{"bgDim":"#21222C","bg0":"#282A36","surface":"#343746","surfaceAlt":"#3B3D50","surfaceRaised":"#44475A","border":"#565970","mutedStrong":"#6272A4","muted":"#A4A8C4","text":"#F8F8F2","textBright":"#FFFFFF","red":"#FF5555","green":"#50FA7B","blue":"#8BE9FD","yellow":"#F1FA8C","purple":"#BD93F9","orange":"#FFB86C","aqua":"#8BE9FD","redDark":"#733941","greenDark":"#36734E","blueDark":"#4B6D7C","yellowDark":"#6E7354","purpleDark":"#5C4F7A","surfaceDark":"#313342","greenSurface":"#325E47","redBright":"#FF7474","textLight":"#FCFCF9","textWarm":"#FEFEF4","blackOverlay":"#B3282A36","gray0":"#6272A4","gray1":"#A4A8C4","gray2":"#F8F8F2","accent":"#BD93F9","accentDark":"#4D4467","accentSoft":"#3A374D","notchBg":"#21222C"}},
        {"id":"solarized-dark","name":"Solarized Dark","flavor":"Ocean · Teal","folder":"Solarized-Dark","defaultWallpaper":"notch-default.png","colors":{"bgDim":"#001F27","bg0":"#002B36","surface":"#073642","surfaceAlt":"#0A414D","surfaceRaised":"#124D59","border":"#586E75","mutedStrong":"#657B83","muted":"#839496","text":"#93A1A1","textBright":"#EEE8D5","red":"#DC322F","green":"#859900","blue":"#268BD2","yellow":"#B58900","purple":"#6C71C4","orange":"#CB4B16","aqua":"#2AA198","redDark":"#4D2D34","greenDark":"#2F5223","blueDark":"#0D4D6D","yellowDark":"#3F4C23","purpleDark":"#264468","surfaceDark":"#05333F","greenSurface":"#214628","redBright":"#DF534D","textLight":"#C5C8BE","textWarm":"#E8DEC0","blackOverlay":"#B3002B36","gray0":"#657B83","gray1":"#839496","gray2":"#93A1A1","accent":"#2AA198","accentDark":"#0A484E","accentSoft":"#053942","notchBg":"#001F27"}}
,
        { id: "material", name: "Material", flavor: "You · Wallpaper colors", folder: "Material", defaultWallpaper: "notch-default.png", colors: materialColors }
    ]
    readonly property string wallpaperRoot: home + "/Pictures/Wallpapers"
    readonly property string wallpaperFolder: wallpaperRoot + "/" + activeTheme.folder
    readonly property string defaultWallpaper: wallpaperFolder + "/" + activeTheme.defaultWallpaper

    // Only these known awww transitions can be restored from the saved preference.
    // The first entry preserves the existing diagonal wipe for older state files.
    readonly property var wallpaperTransitions: [
        { id: "diagonal", name: "Diagonal wipe", description: "Sweep diagonally across the screen", type: "wipe", angle: "45" },
        { id: "fade", name: "Fade", description: "Blend smoothly into the next wallpaper", type: "fade" },
        { id: "horizontal", name: "Horizontal wipe", description: "Sweep from right to left", type: "wipe", angle: "0" },
        { id: "vertical", name: "Vertical wipe", description: "Sweep from top to bottom", type: "wipe", angle: "90" },
        { id: "wave", name: "Wave", description: "Sweep across with a diagonal wave", type: "wave", angle: "45" },
        { id: "grow", name: "Grow", description: "Reveal from the center outward", type: "grow", position: "center" },
        { id: "outer", name: "Outer", description: "Reveal from the edges inward", type: "outer", position: "center" },
        { id: "none", name: "None", description: "Switch immediately without animation", type: "none" }
    ]
    readonly property string wallpaperTransitionId: wallpaperTransitionForId(saved.wallpaperTransition).id

    function wallpaperTransitionForId(transitionId) {
        return wallpaperTransitions.find(item => item.id === transitionId) || wallpaperTransitions[0];
    }

    function setWallpaperTransition(transitionId) {
        if (!wallpaperTransitions.some(item => item.id === transitionId)) return false;
        saved.wallpaperTransition = transitionId;
        return true;
    }

    function wallpaperCommand(startup) {
        var command = ["awww", "img", activeWallpaper, "--transition-type"];
        if (startup === true) return command.concat(["none"]);
        var transition = wallpaperTransitionForId(wallpaperTransitionId);
        command.push(transition.type);
        if (transition.angle !== undefined) command.push("--transition-angle", transition.angle);
        if (transition.position !== undefined) command.push("--transition-pos", transition.position);
        return command.concat(["--transition-duration", "1.5"]);
    }

    property FileView savedState: FileView {
        path: Quickshell.dataDir + "/theme.json"
        blockLoading: true
        blockWrites: true
        printErrors: false
        onAdapterUpdated: writeAdapter()
        onLoaded: {
            theme.savedStateLoaded = true;
            Qt.callLater(function() {
                if (!saved.activeWallpaper.startsWith(theme.wallpaperFolder + "/"))
                    saved.activeWallpaper = theme.defaultWallpaper;
                theme.wallpaperStartup.start();
                theme.applySystemTheme(theme.activeThemeId, theme.activeTheme.colors);
            });
        }
        onLoadFailed: function(error) {
            theme.savedStateLoaded = true;
            Qt.callLater(function() { theme.applySystemTheme(theme.activeThemeId, theme.activeTheme.colors); });
        }

        JsonAdapter {
            id: saved
            property string materialPalette: ""
            property string materialSeed: ""
            property string materialWallpaper: theme.wallpaperRoot + "/Material/notch-default.png"
            property string activeThemeId: "gruvbox"
            property string wallpaperTransition: "diagonal"
            property string activeWallpaper: theme.defaultWallpaper
            property string gruvboxWallpaper: theme.wallpaperRoot + "/Gruvbox/notch-default.png"
            property string tokyoNightWallpaper: theme.wallpaperRoot + "/Tokyo-Night/notch-default.png"
            property string catppuccinWallpaper: theme.wallpaperRoot + "/Catppuccin/notch-default.png"
            property string kanagawaWallpaper: theme.wallpaperRoot + "/Kanagawa/notch-default.png"
            property string everforestWallpaper: theme.wallpaperRoot + "/Everforest/notch-default.png"
            property string nordWallpaper: theme.wallpaperRoot + "/Nord/notch-default.png"
            property string rosepineWallpaper: theme.wallpaperRoot + "/Rose-Pine/notch-default.png"
            property string draculaWallpaper: theme.wallpaperRoot + "/Dracula/notch-default.png"
            property string solarizeddarkWallpaper: theme.wallpaperRoot + "/Solarized-Dark/notch-default.png"
        }
    }

    property string activeThemeId: saved.activeThemeId
    readonly property string activeWallpaper: saved.activeWallpaper.startsWith(wallpaperFolder + "/") ? saved.activeWallpaper : defaultWallpaper
    readonly property var activeTheme: themes.find(item => item.id === activeThemeId) || themes[0]
    readonly property var palette: activeTheme.colors

    readonly property color accent: palette.accent || palette.aqua
    readonly property color onAccent: palette.onAccent || palette.bg0
    readonly property color onAccentContainer: palette.onAccentContainer || palette.text
    readonly property color onError: palette.onError || palette.bg0
    readonly property color onErrorContainer: palette.onErrorContainer || palette.text
    readonly property color accentDark: palette.accentDark || palette.blueDark
    readonly property color accentSoft: palette.accentSoft || palette.surfaceAlt
    readonly property color notchBg: palette.notchBg || palette.bgDim
    readonly property color bgDim: palette.bgDim
    readonly property color bg0: palette.bg0
    readonly property color surface: palette.surface
    readonly property color surfaceAlt: palette.surfaceAlt
    readonly property color surfaceRaised: palette.surfaceRaised
    readonly property color border: palette.border
    readonly property color mutedStrong: palette.mutedStrong
    readonly property color muted: palette.muted
    readonly property color text: palette.text
    readonly property color textBright: palette.textBright
    readonly property color red: palette.red
    readonly property color green: palette.green
    readonly property color blue: palette.blue
    readonly property color yellow: palette.yellow
    readonly property color purple: palette.purple
    readonly property color orange: palette.orange
    readonly property color aqua: palette.aqua
    readonly property color redDark: palette.redDark
    readonly property color greenDark: palette.greenDark
    readonly property color blueDark: palette.blueDark
    readonly property color yellowDark: palette.yellowDark
    readonly property color purpleDark: palette.purpleDark
    readonly property color surfaceDark: palette.surfaceDark
    readonly property color greenSurface: palette.greenSurface
    readonly property color redBright: palette.redBright
    readonly property color textLight: palette.textLight
    readonly property color textWarm: palette.textWarm
    readonly property color blackOverlay: palette.blackOverlay
    readonly property color gray0: palette.gray0
    readonly property color gray1: palette.gray1
    readonly property color gray2: palette.gray2

    function rememberedWallpaper(themeId) {
        switch (themeId) {
        case "material": return saved.materialWallpaper;
        case "gruvbox": return saved.gruvboxWallpaper;
        case "tokyo-night": return saved.tokyoNightWallpaper;
        case "catppuccin": return saved.catppuccinWallpaper;
        case "kanagawa": return saved.kanagawaWallpaper;
        case "everforest": return saved.everforestWallpaper;
        case "nord": return saved.nordWallpaper;
        case "rose-pine": return saved.rosepineWallpaper;
        case "dracula": return saved.draculaWallpaper;
        case "solarized-dark": return saved.solarizeddarkWallpaper;
        default: return "";
        }
    }

    function rememberWallpaper(themeId, path) {
        switch (themeId) {
        case "material": saved.materialWallpaper = path; break;
        case "gruvbox": saved.gruvboxWallpaper = path; break;
        case "tokyo-night": saved.tokyoNightWallpaper = path; break;
        case "catppuccin": saved.catppuccinWallpaper = path; break;
        case "kanagawa": saved.kanagawaWallpaper = path; break;
        case "everforest": saved.everforestWallpaper = path; break;
        case "nord": saved.nordWallpaper = path; break;
        case "rose-pine": saved.rosepineWallpaper = path; break;
        case "dracula": saved.draculaWallpaper = path; break;
        case "solarized-dark": saved.solarizeddarkWallpaper = path; break;
        }
    }

    function selectTheme(themeId, wallpaperOverride) {
        if (!themes.some(item => item.id === themeId))
            return;
        var selectedTheme = themes.find(item => item.id === themeId);
        activeThemeId = themeId;
        saved.activeThemeId = themeId;
        var selectedFolder = wallpaperRoot + "/" + selectedTheme.folder;
        var defaultPath = selectedFolder + "/" + selectedTheme.defaultWallpaper;
        var remembered = rememberedWallpaper(themeId);
        var nextWallpaper = wallpaperOverride || remembered || defaultPath;
        if (!nextWallpaper.startsWith(selectedFolder + "/"))
            nextWallpaper = defaultPath;
        saved.activeWallpaper = nextWallpaper;
        rememberWallpaper(themeId, nextWallpaper);
        applyWallpaper();
        Qt.callLater(function() {
            if (selectedTheme.id !== "material") theme.applySystemTheme(selectedTheme.id, selectedTheme.colors);
        });
    }

    // One serialized writer updates every configured appearance target,
    // including the translucent window frames without an outer glow.
    property var pendingSystemTheme: null
    function applySystemTheme(themeId, colors) {
        pendingSystemTheme = { id: themeId || activeThemeId, colors: colors || palette };
        if (!systemThemeProcess.running) startSystemTheme();
    }
    function startSystemTheme() {
        if (!pendingSystemTheme) return;
        var request = pendingSystemTheme;
        pendingSystemTheme = null;
        systemThemeProcess.command = ["python3", home + "/.config/quickshell/apply-theme.py", request.id, JSON.stringify(request.colors)];
        systemThemeProcess.running = true;
    }
    property Process systemThemeProcess: Process {
        stdout: StdioCollector { onStreamFinished: if (text.trim()) console.log("Theme:", text.trim()) }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("Theme:", text.trim()) }
        onExited: function(code, status) {
            if (code !== 0) console.warn("System theme application failed:", code);
            if (theme.pendingSystemTheme) Qt.callLater(theme.startSystemTheme);
        }
    }


    property bool randomWallpaperPending: false
    function randomWallpaper() {
        randomWallpaperPending = true;
        chooseRandomWallpaper();
    }
    function chooseRandomWallpaper() {
        if (!randomWallpaperPending || randomWallpaperFiles.status !== FolderListModel.Ready) return;
        var paths = [];
        var prefix = wallpaperFolder + "/";
        for (var i = 0; i < randomWallpaperFiles.count; i++) {
            var path = randomWallpaperFiles.get(i, "filePath");
            if (!path.startsWith(prefix)) return;
            paths.push(path);
        }
        randomWallpaperPending = false;
        if (!paths.length) return;
        var alternatives = paths.filter(path => path !== activeWallpaper);
        if (alternatives.length) paths = alternatives;
        selectWallpaper(paths[Math.floor(Math.random() * paths.length)]);
    }
    property FolderListModel randomWallpaperFiles: FolderListModel {
        folder: "file://" + theme.wallpaperFolder
        showDirs: false
        caseSensitive: false
        nameFilters: ["*.[pP][nN][gG]", "*.[jJ][pP][gG]", "*.[jJ][pP][eE][gG]", "*.[wW][eE][bB][pP]", "*.[bB][mM][pP]"]
        onStatusChanged: if (status === FolderListModel.Ready) Qt.callLater(theme.chooseRandomWallpaper)
        onCountChanged: Qt.callLater(theme.chooseRandomWallpaper)
    }

    function selectWallpaper(path) {
        if (!path.startsWith(wallpaperFolder + "/"))
            return;
        saved.activeWallpaper = path;
        rememberWallpaper(activeThemeId, path);
        applyWallpaper();
    }


    property bool materialPending: false
    // The generator derives accents and surface atmosphere independently from the image.
    function generateMaterial() {
        if (materialProcess.running) { materialPending = true; return; }
        materialPending = false;
        materialProcess.command = [home + "/.config/quickshell/material-runtime/bin/python", home + "/.config/quickshell/material-palette.py", activeWallpaper];
        materialProcess.running = true;
    }
    property Process materialProcess: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var result = JSON.parse(text);
                    if (theme.activeThemeId !== "material" || result.wallpaper !== theme.activeWallpaper) return;
                    saved.materialSeed = result.seed || "";
                    saved.materialPalette = JSON.stringify(result.colors);
                    theme.savedState.writeAdapter();
                    theme.applySystemTheme("material", result.colors);
                    Quickshell.execDetached(["python3", theme.home + "/.config/quickshell/sync-sddm.py", "material", JSON.stringify(result.colors), result.wallpaper]);
                } catch (error) { console.warn("Material palette generation failed:", error); }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn(text.trim()) }
        onExited: if (theme.materialPending && theme.activeThemeId === "material") Qt.callLater(theme.generateMaterial)
    }

    function applyWallpaper(startup) {
        if (activeThemeId === "material") generateMaterial();
        else Quickshell.execDetached(["python3", home + "/.config/quickshell/sync-sddm.py", activeThemeId, JSON.stringify(palette), activeWallpaper]);
        Quickshell.execDetached(wallpaperCommand(startup));
    }

    property bool savedStateLoaded: false

    property Timer wallpaperStartup: Timer {
        interval: 1500
        onTriggered: theme.applyWallpaper(true)
    }
}
