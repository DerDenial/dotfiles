#!/usr/bin/env python3
"""Install this export without privileges, network access, or session commands.

Only the destinations in destination_paths() are writable. All filesystem access
walks directory descriptors with O_NOFOLLOW; embedded hashes are integrity checks,
not a signature or a substitute for reviewing downloaded code.
"""
from __future__ import annotations

import argparse
import datetime as dt
import errno
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import secrets
import shutil
import stat
import sys
from dataclasses import dataclass

CONFIG_TREES = frozenset({
    "quickshell", "hypr", "kitty", "fish", "fastfetch", "gtk-3.0", "gtk-4.0",
    "xsettingsd", "swaync",
})
EDITOR = ".config/VSCodium/User/settings.json"
WALLPAPER = "assets/wallpapers/notch-default.png"
THEME_FOLDERS = (
    "Gruvbox", "Tokyo-Night", "Catppuccin", "Kanagawa", "Everforest", "Nord",
    "Rose-Pine", "Dracula", "Solarized-Dark", "Material",
)
REQUIRED_FILES = frozenset({
    ".config/quickshell/shell.qml", ".config/quickshell/Theme/Theme.qml",
    ".config/hypr/hyprland.lua", WALLPAPER,
})
# Integrity checks cover only files copied into the destination home.
# Regenerate these hashes when changing the exported configuration payload.
PAYLOAD_SHA256 = {
    '.config/VSCodium/User/settings.json': '3ab5edbd7d7b97ef0cf1c169661e98363b0b07bfac7ed599a0231706a50cfda1',
    '.config/fastfetch/config.jsonc': 'c4c8a36f18826879c46a18eb2954c33f2f266862a38d70d5677cb9f09e2937d7',
    '.config/fish/config.fish': 'd72ee0a99d9c65c30ae3a019d7915931532bdf06b059c718e69a21cc23f4c49b',
    '.config/gtk-3.0/gtk.css': '4e34498bf80c56119d27750d52ecf787173446737250ec3b897cef0740d165af',
    '.config/gtk-3.0/settings.ini': '7751b3adb56064a2ddefe6786c99da678a034a6a50a422ec9a2d39b02a3b717e',
    '.config/gtk-4.0/gtk.css': 'ee9c9570603be233c78c4a89d7d19d6c5a1fc2fa2ba2e81cd7ed208763920374',
    '.config/gtk-4.0/settings.ini': 'ead8e57f1ed70e3ad0ee50c43b05ec975139c67ad17bb4313d83f0265ff6995e',
    '.config/hypr/hypridle.conf': '116ead139459fb357a32ffdbfe8924f7fedc621a45ce57f6500823d1796a5cd9',
    '.config/hypr/hyprland.lua': '5188bcf03fd27dbcb84fcb9541942ffde6a72b85c1dea128d01f7ba7cab57432',
    '.config/hypr/hyprlock.conf': 'd1151d2741a485bdaed1441f125a3bcfd5a517f773d86a5237ff4fc8dca5b7a5',
    '.config/hypr/hyprtoolkit.conf': '2a14ea70537e7d66e15de8d1b7bc0228610a69166fc498009a51f33bea53c48c',
    '.config/hypr/modules/autostart.lua': '47ed2332790e6e3030381b8be1e436d1698d69522c5b8fdd1bbb398c22dc1f97',
    '.config/hypr/modules/binds.lua': 'd17eb62e590ab25ab273d8929b48b0e9054767aadfd08db698fe1f93a7739073',
    '.config/hypr/modules/decorations.lua': '6927715082f952de324f331413f3adec4e6b27d054a37ba10babc75328be24ad',
    '.config/hypr/modules/edge-mode.lua': 'b085b5d548233f33cce3e06e10d0aa451296999581da70388cebb8202d108774',
    '.config/hypr/modules/env.lua': '00998fda3d3b2f15c0d9749f5a25f6c724031bb33b37e529f062e6e805097548',
    '.config/hypr/modules/hotkey-guide.lua': '497794a80bc82510417734309aa44426fc4fa28452f687bcd08c72cefb56aa20',
    '.config/hypr/modules/input.lua': 'f30e0dafbb8ce993deed6b28e5f929564c362f65dd8fff55f75531bc93873c45',
    '.config/hypr/modules/layout.lua': 'a3bb53e73af8fea0a65d003aba655c9becd16c52292267e7b7d9d9d84e55cf15',
    '.config/hypr/modules/misc.lua': 'd2cad7068442496e0a0cabb5a3233454ef8e9f5357a27434b8ed5e8d72e286cc',
    '.config/hypr/modules/monitors.lua': '3681417b673997d14494d77ff73258b0bc34cb95f7799d3f5d7f3d2f0d61c8ef',
    '.config/hypr/modules/pin-window.lua': '4f03ad00e9cba2cdabfc1830401a38740ab435131ed7dd8846ef1932386c1744',
    '.config/hypr/modules/show-desktop.lua': '5fe5e75b45f7943ef2bbd69a394114a847e6f4f491defbba10ba534e35973db1',
    '.config/hypr/modules/theme-colors.lua': 'f56a6b7a01a67ac17c87e451508acc95122efbf94eccc9b6f7d32edf2548ee8f',
    '.config/hypr/modules/windowrules.lua': 'bc5b591fad032976cb6e13c20a54c8f25a8a7fde175cc8b78c20d5687eacfe41',
    '.config/kitty/colors/colors.conf': '4e1bbef64dc841fdf828cd5ef59665836f2aaa510edbf0b276b3452d97a214c5',
    '.config/kitty/kitty.conf': '942ac98cb17a8be972ed584a18d5814f99c7a90236817ac251f29c4b7041a610',
    '.config/quickshell/AppLauncher.qml': '45ce16ca25227390625686bcdcb9af9e2fc6c6316005642403347b9e870ad57c',
    '.config/quickshell/AudioPopup.qml': '93e2b7ad928d32f3607ff3a4bdbefdffeb12f0160fa7899316dbfafdf5234d7f',
    '.config/quickshell/BatteryIndicator.qml': '3679a398a471d8eee570dedc27a518cd1367dea20ed043026ceab4bc1be3daf5',
    '.config/quickshell/BatteryPopup.qml': '04527e36d19354ccd1f3c9358df1982afbb8e4234a9b72bc2d78f10631add714',
    '.config/quickshell/BluetoothPopup.qml': 'e1e227223308357356f630c7424d093e81f10736d9b85fe23e6383bf25b8fd50',
    '.config/quickshell/Calculator.js': '7a8d3550855ccf6d2c4bbac8086c85e2939643b6a9fb15cb356af63d3db7e94a',
    '.config/quickshell/CalendarPopup.qml': '69ae57a2399d192a75bdff7921125b74ff7e40ca3bb073069ba80728f29b4559',
    '.config/quickshell/Clipboard/README.md': '093ab3421f3b8b53014a65f2dfce6fb5286fa309169ae626069cf530bac36d6f',
    '.config/quickshell/Clipboard/store.py': 'fb57bf119a56ba94eff3307aba4f3ee1f8ab46ec7b8678b8da883174be3b980e',
    '.config/quickshell/ClipboardHistory.qml': '24f6d3d11088a513f5d269e0494169349f13ca54b36b09354fe65693180df323',
    '.config/quickshell/ClipboardState.qml': '5dd5017360bdec958a6147a025684ae2520b95be896a835e1428bba0db6822c8',
    '.config/quickshell/CompactNotch.qml': 'b100fdc152ee44c22e3d25645b53701d49e84ae07ef78c22df1e1b7c54a3af3a',
    '.config/quickshell/ConnectionCheckBody.qml': '99a6991b3d3025e221971f39744365e9913fc590c1cc05e4ed04d2a3beb98f89',
    '.config/quickshell/ConnectionCheckState.qml': '2e6ae5a5f9a91d92f8854da82c2584bba68829c9ab96cd366500d7376b2155e6',
    '.config/quickshell/EdgeBarState.qml': '234039a43cb3f4faa9d208ec0aee0f390b5005a1dc1c5abb754fec4ab1423140',
    '.config/quickshell/EdgeTaskbarContent.qml': 'bb633757d7e4b8fb3a6cafbb2d067707f31d1cd51e698e2d125debbd434c6e28',
    '.config/quickshell/Emoji/CATALOG.md': '85d202dce22ae4cd23c5a3468335fa0e900a49ead5ab53d9879e5ddde88f835c',
    '.config/quickshell/Emoji/LICENSE-UNICODE.txt': 'e7a93b009565cfce55919a381437ac4db883e9da2126fa28b91d12732bc53d96',
    '.config/quickshell/Emoji/README-backend.md': '0e3fc16adcc89b23ed9faa977c9bf7aa2f10070f1b9700d26830c70403413dd8',
    '.config/quickshell/Emoji/backend.py': '2952b807e3acef6c32480d74e893e2d1ef9aefeacb82f067ed30e6dc7bdeda56',
    '.config/quickshell/Emoji/catalog-info.json': '02746359fd4561331e57222fc0d51c357350340af7fd0fe4f717686acc7f18d5',
    '.config/quickshell/Emoji/catalog-sources.json': '7f4abeb4a6572bd897ee6e5d06f26d4f2f09c927b54b7704a7fb7f40e0ec8d93',
    '.config/quickshell/Emoji/emojis.json': 'd0fb3c87128a552112ecf10c2489ad3a90fb93d230a60db3ce3fdb83ebf5801f',
    '.config/quickshell/EmojiPicker.qml': '113a1872c33b46f462149217a4598b293a34c27570de5ebbc9fa69501147e83d',
    '.config/quickshell/EmojiState.qml': 'cdf0bcfa794ea2d26c681c15638f77472198f6cff192e99f6600504bb0b25872',
    '.config/quickshell/FileSearchState.qml': 'a0766b7e87d61f8a0e772b4daaecb4a64e8ce4d1351bbf688e4162c182d6c02c',
    '.config/quickshell/FileShelf.qml': '9db25be0dd79ae4c76f19960388072fdced5591fc5dbb8a5ea819fdcfd4eb896',
    '.config/quickshell/FileShelfPanel.qml': 'd60483b234b5ab2bc35b2eec799e7b07a4e2066c3226992da3f0db88374006f8',
    '.config/quickshell/FileShelfState.qml': '30329bf9c33dd0a5c55525800652ee31cd22619f3652af9255750acb5c591888',
    '.config/quickshell/Files/files.py': '07d3b64b74c8940a3d6e9fe13a170e35a4261319672d399d5284f49295e357a3',
    '.config/quickshell/FlipClock.qml': 'dd088682b4ac00de4ec4ad563f683bac39eae4afe34b11b25200d88180ed8040',
    '.config/quickshell/FlipDigit.qml': '7eba91f7098b043d1c6d1dc698c6ce06007de626a12ef329f641d1cde6a08514',
    '.config/quickshell/Hardware/telemetry.py': '5e589f392f5356f387bc19ceeab89a5c33101c68f51b2aac9e305b71c47605a8',
    '.config/quickshell/HardwarePanel.qml': '5e028ff80b944bb85b658a1f165794db614a4e21833eb2802fa66d37a5aea7a4',
    '.config/quickshell/HardwarePanelBody.qml': 'ce5a6485a597444bd460062f53c9a591d96f1e972dd7377d1d05101b966167aa',
    '.config/quickshell/HardwareTelemetry.qml': '873d91f1e0c97e8571ddf40114dbead0fed0d92bab514d5a9d4e71868a0b52ba',
    '.config/quickshell/HotkeyGuideState.qml': '9a67ea453bf55ea2f5c2501a8cdacddc8172bc2c40e8421eb9b24cdf02f1f67b',
    '.config/quickshell/HotkeyOverview.qml': 'b86abf4d8de78c4fb24b9653a4e64fb02e8aa6ce0fb4918ecb50490e86889ba7',
    '.config/quickshell/Hotkeys/README-backend.md': 'ce0a8ef4a13140e09a8204f160b5ac81bb42dbeb3c27edc1a34e999133cb2206',
    '.config/quickshell/Hotkeys/catalog.py': 'f84abf2fc4d855c1a2e2a11ca212c12bea6342088a167fb2844f1a827ad16f6d',
    '.config/quickshell/HoverNotchContent.qml': 'd3d5bca6a636bb369c53928fe1f60dc8e7f79911993a7666c7c80ea42ee9e7e6',
    '.config/quickshell/LockScreen/design.conf.in': 'd84b04f4785fb5b95f88140169e0ea99446827e04525b3dde242b46106b37246',
    '.config/quickshell/LockScreen/lock.py': 'e4d2a146a83df97260d6c4949c0f58b1eb66628ace9c221f4018f0e5d9018778',
    '.config/quickshell/LockScreen/runtime.py': 'e92c9202d6b1fa94c6b7ade5598d0ab99038cff6c432b084f050d8ae9c89470b',
    '.config/quickshell/LockScreen/start-idle.py': '65e222cbef6061461fdcf845374eed71c029bd88e7ca3ab5221f8055856f4683',
    '.config/quickshell/LockScreen/sync.py': 'cecbb66725620b0f883339bc4539f27a48926a43d0d144348b9e9e55e8f07b29',
    '.config/quickshell/Logout/launch.py': '3a5cdbaea0b73ee1ace317432df3e79254f557422876dff62543c5239160f5e1',
    '.config/quickshell/MenuBodyLoader.qml': 'a6b77262d0deee66228a57bc1131dcea3f28906b312eda63765277f8fd026bf4',
    '.config/quickshell/Network/README-check.md': 'b45644b748034e0391e9981387a270752231560fb1e27bf1c4cb141df4b83ec2',
    '.config/quickshell/Network/check.py': 'f637058b150e5a556c2b058c4a10d0320e5e6a5016d19345e8f290a9cb9bed45',
    '.config/quickshell/Network/telemetry.py': '3f94d53d80fdabd519d50beb456c96d5dd103c621b77d3b65b718727e9b07f3a',
    '.config/quickshell/NetworkPanel.qml': '15d0770e1b4de8180c0a06e5d9401a0e383ff09cb264f0523f5859a690be1e9c',
    '.config/quickshell/NetworkPanelBody.qml': '058ef992f5ab6aedf8884b806ac72e3c95f83723cd6ed54d5da165f69702b923',
    '.config/quickshell/NetworkPopup.qml': '2e6901f74aaa252c09c09c38733a34cd76268443faca2d09103c4c1dd3ec4e9e',
    '.config/quickshell/NetworkTelemetry.qml': '62db52f2af25759dd04635ccc3b2ed8730aa72fa20e1f4ea54fe175f0bd3214f',
    '.config/quickshell/NotchContentStretch.qml': '69caf39b08a407935ed05738f0ea2450c1da2f562a001394c007073b766ab576',
    '.config/quickshell/NotchMenuSurface.qml': '26e8bb09ced70e54f0cc28a3db3bd1e3b8b9eb82388306c1c4f3d324982e2ac0',
    '.config/quickshell/NotchMotion.qml': 'c93127d95a2816e02141ba716cac9a2b44bde460a9683e9aa3641e083b199345',
    '.config/quickshell/NotchOsdContent.qml': '6bce29a958053853918794a72497507052cda81091e654385ea8b6e9f210fdaf',
    '.config/quickshell/NotchOsdState.qml': '3511f7b8d1e4b926513e9d0a7a66e96fadc1f3f971aa6aa5f257eb184b8b4df7',
    '.config/quickshell/NotchTransition.qml': 'e3b861ef8c7cc40eed2527b6f914f57d081477a8f47f7050b4852ab1a2464e36',
    '.config/quickshell/Notes/README.md': '91653197b89904880aad6f52c7c1e64cf0c7d674166359fa7d8ccecff4c35d76',
    '.config/quickshell/Notes/store.py': '7090f45b282f210a8a2fa41f3c893b1429d0220788f2cacbbc6788330f3b906b',
    '.config/quickshell/NotesState.qml': '6e964b20db7c950a48ea40f60b3f97d9f07d2a7ba03b2bf1fc44fc1a5a13fcbc',
    '.config/quickshell/NotificationCard.qml': '2e249402c9a8823803ed950eaefdd14932a7db316690c490be5c4201dc5ccf49',
    '.config/quickshell/NotificationCenter.qml': 'a69919618c15c8e81f8c45c1ba31e90ac80d643a36eb9372f01fcf900e55551f',
    '.config/quickshell/NotificationCenterBody.qml': '2669cf5ad113103b20e234b09287f1c571cb4e86422ea3600e3bcfadce9ba65b',
    '.config/quickshell/NotificationToastContent.qml': 'bf18a2538b4d43f611f2371ed1c4780a2abf71a136642aca9ce76e98e5f6fc3e',
    '.config/quickshell/Notifications/README-backend.md': 'bfa4cd9d0dddbc98e6db1f8910175d2527d7785fb1823f123ebf560cb6d905e4',
    '.config/quickshell/Notifications/Service.qml': 'b293d45e367a52688de6cb3f73801616e588830e700e1daf5ccc952bd590f1c8',
    '.config/quickshell/Notifications/qmldir': 'c94b57a6ae5de9eab21ac6ede25821d0bf108a9c7f9b59e7765ec92fcabdf9ca',
    '.config/quickshell/Osd/backlight.py': '011672a32e6b91331151d275801354a4ea2a6269938ad11efb3b2b6e8a882e56',
    '.config/quickshell/PerformancePopup.qml': 'd029202643e34ebebb18066b4f7a7ed750f958fa09f94103f25e4930cb4867bc',
    '.config/quickshell/PickerButton.qml': 'e4a933beca09ce9431f2ceb96429c6a9687f65717589d803607161969957e86a',
    '.config/quickshell/PickerRail.qml': '2055d2b9ef3a0c4e1846529f850bc037329b52f7356db71a350a9244d8ef2078',
    '.config/quickshell/PickerThemeCard.qml': '508dc0f78b1c65493e888cbb68de77ac36c46ada0ce0955a6892952c9210b98c',
    '.config/quickshell/PickerWallpaperCard.qml': 'ead945171ac31d0ff19d7f00d60aa236e26fbf3fe0ef7c0d0eea5d288271e3ea',
    '.config/quickshell/Pill.qml': '8f2a2b01e995b4c7df7145d73f33cc07b1b171c85586d3cf9e07b08a06a6fe59',
    '.config/quickshell/Poller.qml': '484ba008d9d14daab702299a794ec1c0ff85bea05846cf9004a48b37f42658f3',
    '.config/quickshell/PowerMenu.qml': '8dad39ddf4d12eb3d0d44c275a8d694446c2e6e5a2f350c690d2714038b834be',
    '.config/quickshell/PowerPopup.qml': '0e1c1e7ab07df2ebc3c798cfd40d5df55d2c0c7f236564cbfd1d18c61f5aa69d',
    '.config/quickshell/QuickNotes.qml': '4f2717a24145526a317f74f061dfd712feddcd74db8760c658f95750a7e2fd14',
    '.config/quickshell/QuickSettings.qml': 'dabc3ffefb7df912bed375db369a45a07f4b640f94b5bd122ed22acc3cf8951f',
    '.config/quickshell/QuickSlider.qml': '6af88b4d23db3c96d8602ebf5a14e466d6f05106adc7d0448ae38e87e701184f',
    '.config/quickshell/QuickToggle.qml': 'edce442d347abcacf65891a8a32385d4aebe3b9a3696c247ffec1c19fd3e958a',
    '.config/quickshell/ScreenshotEditor.qml': '34d134e0d2e1ea27b9c9f3860adfae9688470cad6eddaba14c7036df0cb79676',
    '.config/quickshell/ScreenshotEditorBody.qml': 'cc4d3eeb44d2e3f76760c3b173b73e7de94d64fd587eac8c56d9ae6ce8d5a930',
    '.config/quickshell/Screenshots/backend.py': '83db97bf20a9a26072e0e66e0b18a4bdab029aedf9bc23e03af71b6cee484c23',
    '.config/quickshell/SelectionTrail.qml': 'f0af352caf45bebeb200a365e66aff8866cc0ce58c8fa2026f1f95f53c51a683',
    '.config/quickshell/Settings/AppImagePreferences.qml': 'be3622f80be6a98f41f9de0b641ea45e8a4629131cbc11733aa0ff53a71428cc',
    '.config/quickshell/Settings/AppImagesPage.qml': '8529dc096eb62c15679b8b191ef898e902730a4359af89d96b25f78e890a5328',
    '.config/quickshell/Settings/AppearancePage.qml': 'fc96cc8e72f4315e0235b2616fa0d10cf4967d46c2619c0b51512806dabe5bac',
    '.config/quickshell/Settings/AudioPage.qml': 'be3947cd20d9d2e45d38641fe1b42b804a4ee5cf6a621e1c1856ca08de72b6e4',
    '.config/quickshell/Settings/BluetoothPage.qml': 'a2a72164230b0a5b9bab9d1c00bf97ab23a9fff3e0de8a41cb7ba8e7d1b8bc32',
    '.config/quickshell/Settings/CursorPreferences.qml': '29fc6aec0f3a1df94d1da31c2f1661094f74c0b2a1eeadf86a87ca1de74964ca',
    '.config/quickshell/Settings/CursorSettings.qml': 'bde673ee9c19faf95732693eb30d09723c32b29fe1f71206d4352c1d54235a9a',
    '.config/quickshell/Settings/DisplayPage.qml': '71cbfb3b2477c576996d38448fe4e9a6fa7df10de009dac93f9465b466c3298a',
    '.config/quickshell/Settings/InputPage.qml': 'c55ebf0921f9c8060fd3fa49ffbd611f2f125eabc64f66ee2a14dd6ca21f9664',
    '.config/quickshell/Settings/NetworkPage.qml': '95e6ae335b5d21cdb6f48d50d52de5994a91d5f66b849a817952ab3d1b2f6196',
    '.config/quickshell/Settings/NotificationsPage.qml': '12dd387645580635078add0dd50ece51b57ae2bb11e21a83160a1096bb5de46f',
    '.config/quickshell/Settings/OverviewPage.qml': '283ce7976f30e93c727441e16e03e0e29659167eda75e315b71b10458e9b3f7a',
    '.config/quickshell/Settings/PowerPage.qml': '4dd1a9d9322a22f6bc1c3543bd3c54b4c2f430c76ac3712561eda889305c7ebd',
    '.config/quickshell/Settings/ProfilePreferences.qml': '2f20fe69db45543478cbdc6cbf2613cdee4c98b92cdc5ba343b56a283babe0ed',
    '.config/quickshell/Settings/ProfileSettings.qml': 'ea0892a1fb946d89229559dfac9883aaa7cdf85a3832d6073b67fd2b04c69494',
    '.config/quickshell/Settings/SButton.qml': 'f4ed0e4a321be06e36320232f08e7bfedb3956e2dd74817d5bf32366723360cf',
    '.config/quickshell/Settings/SCard.qml': 'a821cacf16f1c39056eb9aae0093034a2d93d4e8b48aef4a7f6a53550b3f31fc',
    '.config/quickshell/Settings/SLabel.qml': '31d49a4ad38daf59f52e61133deaddf6f1ef75cbb7f458ab5e679a480911b00d',
    '.config/quickshell/Settings/SMomentumFlickable.qml': '614cdcbd9712afa8ed5c77ab31922083f39aaead1deeaf26ca3e0f37aa2eec32',
    '.config/quickshell/Settings/SNotice.qml': '5a06f74987d32b99725fff9f957cad6a7099738c88abc78759488839b25758f7',
    '.config/quickshell/Settings/SPage.qml': 'e2b816498311768c81786383da830965aa587355888bd45a5459eb72d977ad71',
    '.config/quickshell/Settings/SRow.qml': '5a46ededadb74fde13a98877f92ae0900631fb32d63adbe2856bf1c61f9137a0',
    '.config/quickshell/Settings/SSlider.qml': '2caf6db15af806b723aa2dc82fac4d281e2d02700d8dc4dfb1c32978324f3b6d',
    '.config/quickshell/Settings/SToggle.qml': 'f66143830c777b4156368f610c0c440ce38a303a2cb8ff8d6544ddeb627ce2e1',
    '.config/quickshell/Settings/SystemPage.qml': '48fe7a8432da67f3f3576d3258621596d0eef1ff836e38aa9ec40cd4c8535e10',
    '.config/quickshell/Settings/WallpaperMotionSettings.qml': '25442a4ba4a235d247dc3e668ac97da0b7d4d27a301ff5234381935aba7bf82e',
    '.config/quickshell/Settings/WindowsPage.qml': 'bf7585f02a67b5da98ea47372448a302536360518158c7a410980293b818dcd4',
    '.config/quickshell/Settings/appimage_manager.py': '76069cc39f30e800abb8ee63ca4615bb8e50b78d36f2d07219917b9e1e0c80c1',
    '.config/quickshell/Settings/cursor_preferences.py': 'e6fc7bd18b3b0da98f14c67c6330f6d2faba9459c7959a1cf406ab848a2b0988',
    '.config/quickshell/Settings/input-preferences.py': '1c3430d83e600a1e4e2fb82595d41e51fa1b29826e239835553cde7cf2740242',
    '.config/quickshell/Settings/system-info.py': '8febd76b7c7c2bed271c851d076b6b769552634d72d44f5112824df5d8805352',
    '.config/quickshell/Settings/window-preferences.py': '625f58b76cf4681ee392940331433605c8fc728b7cf5552027119985923823c8',
    '.config/quickshell/SettingsApp.qml': '1ae6d9e7886789c2170bb93662e5ee655c5fcaa5d107f37706c50f4d907c447b',
    '.config/quickshell/SettingsPageHeader.qml': '9d1bde3886dcce2589847dfccf94d835b0dc5c49afc72b0726c9eb232dc550e9',
    '.config/quickshell/Shelf/store.py': '1560f16d9ed365f32a5f83a3e9988323949794b5840e24a220a690a510c22f68',
    '.config/quickshell/SpeedTest/README-backend.md': '0195534919ecf8e25a6f1a11684a3d8f8616e02449af78475d3924905642cbd8',
    '.config/quickshell/SpeedTest/run.py': 'dc7ba86a90ca20a5b6e427ad73ba9e3fe3d561c2af39596574acedec9c6796cb',
    '.config/quickshell/SpeedTestBody.qml': '0b119a663917395b402cf09740cf22779726b4cb702d6aa80acf36b4f6d9296d',
    '.config/quickshell/SpeedTestPanel.qml': '24d0318c31fca11efcb0c37f89f30cb46b07e9bc4c761096d5fec83668344bf3',
    '.config/quickshell/SpeedTestState.qml': '5b180234770162be3db9bbd8b83092f2c839754165c8a33813ef3f833a867689',
    '.config/quickshell/Speedometer.qml': '2cd212e52e7c25d8b37c0d10861058e11b7a9933e7677378937179be2556e489',
    '.config/quickshell/SystemState/BluetoothPower.qml': 'a9ac77d7b3aa6026306e5321c8f34ded6d52e1bdf32543e3dbd7b0aabe91ff8b',
    '.config/quickshell/SystemState/qmldir': '8175d405da7ed4b39f18b6066e853aa6cea99751b471e04cee33dba2a07a164e',
    '.config/quickshell/TailscaleState.qml': '01c6f3b18054dcfc7e65bc2ab2628e0a9abaff0b6a1d091eec5e80e00568d0d1',
    '.config/quickshell/TaskManager.qml': 'e77c3861ee1f51d859c10be54af57d41417e8c558fca7b8791136b453af2fcc8',
    '.config/quickshell/TaskManager/processes.py': '44d30ea6a53ed8e5f814d9a7a8e5166f792126a32f9354d3a906e3cfe29ba8a8',
    '.config/quickshell/TaskManagerPanel.qml': '16c72cca8cacbfdb7aa3870b2dae8dc58e82887a960ca87d934cc29af71bd48e',
    '.config/quickshell/TaskManagerState.qml': '6895354a7ca522c23dd82560361d2b261226e067e13df06508cf7904f2897189',
    '.config/quickshell/Theme/Theme.qml': '685faa40a70aa841de0273a32be851e593d8debf74133c5082f5e9f2f8635956',
    '.config/quickshell/Theme/qmldir': '595ada8d7ad58ab44c3434858a86e218f734631a69ffb6170e7d4f48bc1d6245',
    '.config/quickshell/ThemeSwitcher.qml': '56c3427b4dbfe3dfbcf284ceb17a959b5ca18e5e8ba9f85cfbc95175b138ceaa',
    '.config/quickshell/TrayIcons.qml': '564f439117a395141667cd5a5238998bfc122ead55a7458c26579b70b73b8dc8',
    '.config/quickshell/Wallpapers/Cache.qml': 'b02db7a1f336334cbba13bedf6ecea58d364c08ec3ad66b8a668c47783a9055b',
    '.config/quickshell/Wallpapers/Preview.qml': 'dc80ad5229895c152cde3def86dad1261d318150ad9b1422a7231a33336bd3c9',
    '.config/quickshell/Wallpapers/qmldir': '6b3f257dfcac357f6dc047ce1182d650edde31499b18d58f1fa01742e5223b4b',
    '.config/quickshell/Wallpapers/thumbnail-cache.README.md': 'b40c2da9d74817e3fa786a5afb42066f8542138d0b97c03994316ea8d669f295',
    '.config/quickshell/Wallpapers/thumbnail-cache.py': 'ab9080de7d1365d8bbb45c1741f62a93d9ff26c57bf740d6080e2cf375345546',
    '.config/quickshell/WifiSignalIndicator.qml': '24d93be6efc9b83f1eb13fd1c8dbe147df6fec017ff3405224eae67e4015eb50',
    '.config/quickshell/WindowActions.qml': 'a4096396019da7e6afbdd5206cd7f95703136f04d6a760631ba70d1b293bd681',
    '.config/quickshell/WindowBar.qml': '79f3c73081d7669dbb8ea67d55fae8a52358281a706f08937b9a74830c578e85',
    '.config/quickshell/WindowBarState.qml': '1ace1b108b88d06265d55331595057c7a57e5390119263bc11d6b385905ecf4a',
    '.config/quickshell/WindowPreview.qml': 'd9b120e2f8dd9613cd0ed42e4772f43da8531bb9960e47ef1a0c44af4e126686',
    '.config/quickshell/WorkspaceIndicators.qml': 'fe4d0410c6fefa1bcd482a55d17c1c6a59af72084eb610cfa0b999e03342024b',
    '.config/quickshell/Workspaces.qml': '3ce09338393e4cac67120610150977f35894c161c4b54259b3972bd1669f728d',
    '.config/quickshell/appearance_targets.py': '6d14ed9e1e82ff3e455c3396796b8bf75d448f930c5983d49e5be0c3e90281d1',
    '.config/quickshell/apply-theme.py': '89bdf81215d678dc84a94c2fb2d8f722430793a6ffe7e7a758460db43dd63d82',
    '.config/quickshell/desktop_theme.py': '169e6bdd03e9a6039d6d63d99472521752542eec332e25ece809f28fc55a24bf',
    '.config/quickshell/hypr_appearance.py': '9492eb46cdd71207aaf4acbfe563687ebd9fb80e7991a98ccef72e76f7fec795',
    '.config/quickshell/icon_palette.py': '68e5a9d446f766a21e1c988b582d1d03cfa4028cf4e29214f0e54e003c2c49e9',
    '.config/quickshell/material-palette.py': '9d15ef3e955c3c7e7845d08a1e0f8330eede65f66bfe367545d140768f2ba59e',
    '.config/quickshell/notification_theme.py': '43c53f5cda3d1500ef630e8fdf7488d38023c0f0cafee903d7b33fcd2c8e169c',
    '.config/quickshell/profile-avatar.py': '4423679fe4fc71bdd78bf3d68616442dec4265bebb2130dde56a622d31b95b7d',
    '.config/quickshell/session-power.py': '23cf2e45c2ba7db181c69fce07f9971e87bf7b9d2b41b6552e910f63f8b807c4',
    '.config/quickshell/shell.qml': '440444adb46194a0671019d486ebe510e2d2d2e01df1622f215e17abff644691',
    '.config/quickshell/sync-chatgpt-theme.py': 'd76049d1c48448bafe5522e231a3e9012662e1dafc9b28266a11457ff0fa4899',
    '.config/quickshell/sync-sddm.py': '9887def4a398c080f845f26c7683d86a3aaaf165fa02c2faa40bd9bcc574ad14',
    '.config/quickshell/templates/fastfetch.jsonc.template': '51a1a8bb0f7f4d6c08e563a5880e56e5d206ee8da842e2772c75eab503cc220f',
    '.config/quickshell/templates/starship.toml.template': '4cdeef095e78798949a59107d73d60e22c0363dbce1384655f1ad3c1aaecb362',
    '.config/starship.toml': '32109d947df1b65554164df6cce31707591e7db5d5e7d76dff45ddf49fe42487',
    '.config/xsettingsd/xsettingsd.conf': '7f552eedcc9123799151d499bc06adb45ccb6d78e5bc8e1e3d8aae2a4ac7fce3',
    '.local/share/applications/org.gnome.Settings.desktop': '6e90a8576361e83f6d13166ad7b6976e21866345b7fb9643e0ee4e1ab1e5e35c',
    '.local/share/applications/org.quickshell.TaskManager.desktop': '184c576c609823ffdd78406314f26adfd8bec3663e37b0df69b052d4a6cef9cf',
    '.local/share/applications/quickshell-notes.desktop': '378bd9edb89700d42907d08e8eebc2f3bc5b2182990da7337390d87a658a4db8',
    '.local/share/dbus-1/services/org.erikreider.swaync.service': '52c54382f17efff565a58781a17a9a03e34a1c1ced662f0b407b130e98037edd',
    'assets/wallpapers/notch-default.png': '8380b02d262c2fadd761295a296f50d183c48da9b428a4d0a73d9a7e0ae194ee',
}

EDITOR_KEYS = frozenset({
    "workbench.colorTheme", "editor.fontFamily", "editor.fontSize",
    "editor.fontLigatures", "window.commandCenter", "window.titleBarStyle",
    "workbench.layoutControl.enabled", "workbench.browser.showInTitleBar",
    "workbench.activityBar.location", "workbench.iconTheme",
    "workbench.colorCustomizations", "editor.tokenColorCustomizations",
    "editor.semanticTokenColorCustomizations",
})
BACKUPS = ".local/state/notch-dotfiles/backups"
HEX = re.compile(r"[0-9a-f]{64}\Z")
DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
FILE_FLAGS = os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK


class InstallError(Exception):
    """An actionable, user-facing validation or transaction error."""


def canonical_path(value: str) -> str:
    if not isinstance(value, str) or not value or "\\" in value:
        raise InstallError(f"Invalid relative path: {value!r}")
    parts = value.split("/")
    if any(part in ("", ".", "..") for part in parts) or any(ord(c) < 32 for c in value):
        raise InstallError(f"Unsafe relative path: {value!r}")
    if PurePosixPath(value).is_absolute():
        raise InstallError(f"Absolute path is not allowed: {value!r}")
    return value


def destination_paths(source: str) -> tuple[str, ...]:
    """The complete install allowlist; the embedded payload cannot expand it."""
    canonical_path(source)
    parts = source.split("/")
    if source == EDITOR or source == ".config/starship.toml":
        return (source,)
    if len(parts) >= 3 and parts[0] == ".config" and parts[1] in CONFIG_TREES:
        return (source,)
    if (len(parts) == 4 and parts[:3] == [".local", "share", "applications"]
            and parts[3].endswith(".desktop")):
        return (source,)
    if (len(parts) == 5 and parts[:4] == [".local", "share", "dbus-1", "services"]
            and parts[4].endswith(".service")):
        return (source,)
    if source == WALLPAPER:
        return tuple(f"Pictures/Wallpapers/{folder}/notch-default.png" for folder in THEME_FOLDERS)
    if parts[0] in (".config", ".local"):
        raise InstallError(f"Path is outside the install allowlist: {source}")
    if parts[0].startswith(".") and source != ".gitignore":
        raise InstallError(f"Unapproved dotfile in payload: {source}")
    return ()  # Documentation, scripts, and optional extras are not installed.


def allowed_destination(path: str) -> bool:
    if path in destination_paths(WALLPAPER):
        return True
    return destination_paths(path) == (path,)


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def no_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise InstallError(f"Duplicate JSON key: {key!r}")
        result[key] = value
    return result


def read_json(data: bytes, label: str):
    try:
        return json.loads(data.decode("utf-8-sig"), object_pairs_hook=no_duplicates,
                          parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))
    except (ValueError, UnicodeError) as exc:
        raise InstallError(f"Cannot read {label}: {exc}") from exc


@dataclass(frozen=True)
class Snapshot:
    data: bytes
    mode: int
    atime_ns: int
    mtime_ns: int

    @classmethod
    def fresh(cls, data: bytes, mode: int = 0o644):
        now = __import__("time").time_ns()
        return cls(data, mode & 0o777, now, now)

    def metadata(self):
        return {"mode": self.mode, "atime_ns": self.atime_ns, "mtime_ns": self.mtime_ns,
                "sha256": sha(self.data)}


class Tree:
    """Read/write only regular files through directories that are never symlinks."""

    def __init__(self, root: Path):
        self.root = Path(os.path.abspath(root))
        fd = self.open_root()
        os.close(fd)

    def open_root(self):
        fd = os.open("/", DIR_FLAGS)
        try:
            for part in self.root.parts[1:]:
                next_fd = os.open(part, DIR_FLAGS, dir_fd=fd)
                os.close(fd)
                fd = next_fd
            return fd
        except OSError as exc:
            os.close(fd)
            raise InstallError(f"Directory is missing, unsafe, or a symlink: {self.root} ({exc.strerror})") from exc

    def parent(self, rel: str, create=False, created=None):
        canonical_path(rel)
        fd = self.open_root()
        prefix = []
        try:
            for part in rel.split("/")[:-1]:
                prefix.append(part)
                try:
                    next_fd = os.open(part, DIR_FLAGS, dir_fd=fd)
                except FileNotFoundError:
                    if not create:
                        raise
                    os.mkdir(part, mode=0o700, dir_fd=fd)
                    if created is not None:
                        created.append("/".join(prefix))
                    next_fd = os.open(part, DIR_FLAGS, dir_fd=fd)
                os.close(fd)
                fd = next_fd
            return fd, rel.split("/")[-1]
        except BaseException:
            os.close(fd)
            raise

    def read(self, rel: str) -> Snapshot | None:
        try:
            fd, name = self.parent(rel)
        except FileNotFoundError:
            return None
        except OSError as exc:
            raise InstallError(f"Unsafe parent directory for {self.root / rel}: {exc.strerror}") from exc
        try:
            try:
                file_fd = os.open(name, FILE_FLAGS, dir_fd=fd)
            except FileNotFoundError:
                return None
            except OSError as exc:
                raise InstallError(f"Cannot read regular file {self.root / rel}: {exc.strerror}") from exc
            try:
                info = os.fstat(file_fd)
                if not stat.S_ISREG(info.st_mode):
                    raise InstallError(f"Only regular files are allowed: {self.root / rel}")
                with os.fdopen(file_fd, "rb", closefd=False) as stream:
                    data = stream.read()
                return Snapshot(data, stat.S_IMODE(info.st_mode) & 0o777,
                                info.st_atime_ns, info.st_mtime_ns)
            finally:
                os.close(file_fd)
        finally:
            os.close(fd)

    def missing_parents(self, rel: str) -> list[str]:
        fd = self.open_root()
        parts = rel.split("/")[:-1]
        missing = []
        try:
            for i, part in enumerate(parts):
                if missing:
                    missing.append("/".join(parts[:i + 1]))
                    continue
                try:
                    next_fd = os.open(part, DIR_FLAGS, dir_fd=fd)
                except FileNotFoundError:
                    missing.append("/".join(parts[:i + 1]))
                    continue
                except OSError as exc:
                    raise InstallError(f"Unsafe parent directory for {self.root / rel}: {exc.strerror}") from exc
                os.close(fd)
                fd = next_fd
            return missing
        finally:
            os.close(fd)

    def write(self, rel: str, snapshot: Snapshot, created=None):
        fd, name = self.parent(rel, create=True, created=created)
        temp = f".notch-dotfiles-{secrets.token_hex(12)}.tmp"
        try:
            try:
                info = os.stat(name, dir_fd=fd, follow_symlinks=False)
                if not stat.S_ISREG(info.st_mode):
                    raise InstallError(f"Refusing to replace a symlink or special file: {self.root / rel}")
            except FileNotFoundError:
                pass
            out = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                          0o600, dir_fd=fd)
            try:
                with os.fdopen(out, "wb", closefd=False) as stream:
                    stream.write(snapshot.data)
                    stream.flush()
                os.fchmod(out, snapshot.mode & 0o777)
                os.utime(out, ns=(snapshot.atime_ns, snapshot.mtime_ns))
                os.fsync(out)
            finally:
                os.close(out)
            os.replace(temp, name, src_dir_fd=fd, dst_dir_fd=fd)
            os.fsync(fd)
        finally:
            try:
                os.unlink(temp, dir_fd=fd)
            except FileNotFoundError:
                pass
            os.close(fd)

    def remove(self, rel: str):
        try:
            fd, name = self.parent(rel)
        except FileNotFoundError:
            return
        try:
            try:
                info = os.stat(name, dir_fd=fd, follow_symlinks=False)
            except FileNotFoundError:
                return
            if not stat.S_ISREG(info.st_mode):
                raise InstallError(f"Refusing to remove a symlink or special file: {self.root / rel}")
            os.unlink(name, dir_fd=fd)
        finally:
            os.close(fd)

    def remove_empty_dirs(self, directories):
        for rel in sorted(set(directories), key=lambda value: (-value.count("/"), value)):
            try:
                fd, name = self.parent(rel)
                try:
                    os.rmdir(name, dir_fd=fd)
                finally:
                    os.close(fd)
            except OSError as exc:
                if exc.errno not in (errno.ENOENT, errno.ENOTEMPTY, errno.EEXIST):
                    raise


def load_export(source: Path) -> tuple[Tree, dict[str, Snapshot]]:
    """Validate and read the install payload using this installer's embedded hashes."""
    tree = Tree(source)
    entries = PAYLOAD_SHA256
    if not isinstance(entries, dict) or not entries or len(entries) > 10000:
        raise InstallError("Embedded payload must be a nonempty path-to-SHA256 object")
    for path, expected in entries.items():
        canonical_path(path)
        if not destination_paths(path):
            raise InstallError(f"Path is not an installable payload file: {path}")
        if not isinstance(expected, str) or not HEX.fullmatch(expected):
            raise InstallError(f"Invalid SHA256 for {path}")
    missing = REQUIRED_FILES - entries.keys()
    if missing:
        raise InstallError("Required export files are missing: " + ", ".join(sorted(missing)))
    files = {}
    for path, expected in sorted(entries.items()):
        snapshot = tree.read(path)
        if snapshot is None:
            raise InstallError(f"Payload file is missing: {path}")
        if sha(snapshot.data) != expected:
            raise InstallError(f"Checksum mismatch: {path}; no files were installed")
        files[path] = snapshot
    return tree, files


def jsonc(data: bytes, label: str):
    """Strip comments and trailing commas without changing JSON string contents."""
    try:
        text = data.decode("utf-8-sig")
        out = []
        i = 0
        in_string = False
        while i < len(text):
            c = text[i]
            if in_string:
                out.append(c)
                if c == "\\":
                    i += 1
                    if i < len(text):
                        out.append(text[i])
                elif c == '"':
                    in_string = False
            elif c == '"':
                in_string = True
                out.append(c)
            elif text[i:i + 2] == "//":
                i += 2
                while i < len(text) and text[i] not in "\r\n":
                    i += 1
                out.append("\n")
                continue
            elif text[i:i + 2] == "/*":
                end = text.find("*/", i + 2)
                if end < 0:
                    raise ValueError("unclosed block comment")
                out.append(" ")
                i = end + 2
                continue
            else:
                out.append(c)
            i += 1
        clean = "".join(out)
        out = []
        in_string = False
        i = 0
        while i < len(clean):
            c = clean[i]
            if in_string:
                out.append(c)
                if c == "\\":
                    i += 1
                    if i < len(clean):
                        out.append(clean[i])
                elif c == '"':
                    in_string = False
            elif c == '"':
                in_string = True
                out.append(c)
            elif c == ",":
                after = i + 1
                while after < len(clean) and clean[after].isspace():
                    after += 1
                if after >= len(clean) or clean[after] not in "}]":
                    out.append(c)
            else:
                out.append(c)
            i += 1
        obj = read_json("".join(out).encode(), label)
    except (ValueError, UnicodeError) as exc:
        raise InstallError(f"Cannot merge {label}: {exc}; correct its JSON/JSONC first") from exc
    if not isinstance(obj, dict):
        raise InstallError(f"Cannot merge {label}: settings must be a JSON object")
    return obj


def deep_merge(existing, exported):
    if isinstance(existing, dict) and isinstance(exported, dict):
        result = dict(existing)
        for key, value in exported.items():
            result[key] = deep_merge(result[key], value) if key in result else value
        return result
    if isinstance(existing, list) and isinstance(exported, list):
        return existing + [item for item in exported if item not in existing]
    return exported


def editor_snapshot(source: Snapshot, original: Snapshot | None) -> Snapshot:
    exported = jsonc(source.data, "exported VSCodium settings")
    unexpected = exported.keys() - EDITOR_KEYS
    if unexpected:
        raise InstallError("Non-appearance VSCodium settings in export: " + ", ".join(sorted(unexpected)))
    existing = jsonc(original.data, "existing VSCodium settings") if original else {}
    merged = deep_merge(existing, exported)
    content = (json.dumps(merged, indent=4, ensure_ascii=False) + "\n").encode()
    return Snapshot(content, original.mode if original else source.mode,
                    source.atime_ns, source.mtime_ns)


@dataclass
class Action:
    source: str
    target: str
    desired: Snapshot | None
    original: Snapshot | None


def same(left: Snapshot | None, right: Snapshot | None) -> bool:
    if left is None or right is None:
        return left is right
    return left.data == right.data and left.mode == right.mode


def validate_target(source: Path, home: Path):
    if os.geteuid() == 0:
        raise InstallError("Run the installer as your normal desktop user, without sudo or root")
    source = Path(os.path.abspath(source))
    home = Path(os.path.abspath(home))
    if home == Path("/") or home == source or source in home.parents:
        raise InstallError("The destination home must be outside the export checkout")
    return Tree(home)


def plan_install(source: Path, home: Path) -> tuple[Tree, list[Action]]:
    target = validate_target(source, home)
    _, files = load_export(source)
    actions = []
    destinations = set()
    for path, snapshot in files.items():
        for dest in destination_paths(path):
            if dest in destinations:
                raise InstallError(f"Duplicate installation destination: {dest}")
            destinations.add(dest)
            if Path(os.path.abspath(source)) == target.root / dest or Path(os.path.abspath(source)) in (target.root / dest).parents:
                raise InstallError(f"Installation would overwrite its source checkout: {dest}")
            original = target.read(dest)
            desired = editor_snapshot(snapshot, original) if dest == EDITOR else snapshot
            actions.append(Action(path, dest, desired, original))
    # Existing Quickshell watchers see helpers/components before the shell entry point.
    actions.sort(key=lambda item: (item.target == ".config/quickshell/shell.qml", item.target))
    target.missing_parents(BACKUPS + "/validation/backup.json")
    return target, actions


def display_plan(actions: list[Action], home: Path, dry_run: bool):
    changed = [action for action in actions if not same(action.original, action.desired)]
    print(f"{'Dry run' if dry_run else 'Plan'}: {len(changed)} file(s) to change under {home}; "
          f"{len(actions) - len(changed)} unchanged.")
    for action in changed:
        operation = "remove" if action.desired is None else ("replace" if action.original else "create")
        if action.source == EDITOR:
            operation = "merge appearance"
        print(f"  {operation:16} {action.target}")
    return changed


def write_json(tree: Tree, path: str, obj):
    tree.write(path, Snapshot.fresh((json.dumps(obj, indent=2, sort_keys=True) + "\n").encode(), 0o600))


def apply_actions(target: Tree, actions: list[Action], on_complete=None):
    attempted = []
    created = []
    try:
        for action in actions:
            if not same(target.read(action.target), action.original):
                raise InstallError(f"File changed after planning: {action.target}; retry after reviewing it")
            attempted.append(action)
            if action.desired is None:
                target.remove(action.target)
            else:
                target.write(action.target, action.desired, created)
        if on_complete is not None:
            on_complete()
    except BaseException as exc:
        failures = []
        for action in reversed(attempted):
            try:
                if action.original is None:
                    target.remove(action.target)
                else:
                    target.write(action.target, action.original)
            except BaseException as rollback_exc:
                failures.append(f"{action.target}: {rollback_exc}")
        try:
            target.remove_empty_dirs(created)
        except BaseException as rollback_exc:
            failures.append(str(rollback_exc))
        if failures:
            raise InstallError(f"Transaction failed ({exc}); rollback needs attention: {'; '.join(failures)}") from exc
        raise InstallError(f"Transaction failed; previous files were restored: {exc}") from exc


def install(source: Path, home: Path, *, dry_run=False):
    target, actions = plan_install(source, home)
    changed = display_plan(actions, target.root, dry_run)
    if dry_run:
        print("No files were written. No packages or session commands were run.")
        return None
    if not changed:
        print("Already installed; no files were changed.")
        return None
    backup_rel = BACKUPS + "/" + dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ-") + secrets.token_hex(4)
    created_dirs = sorted({path for action in changed for path in target.missing_parents(action.target)},
                          key=lambda path: (path.count("/"), path))
    journal = {"schema_version": 1, "status": "prepared", "target_home": str(target.root),
               "created_dirs": created_dirs, "entries": []}
    # Back up every original before the first destination is changed.
    for action in changed:
        entry = {"path": action.target, "existed": action.original is not None,
                 "installed_sha256": sha(action.desired.data), "installed_mode": action.desired.mode}
        if action.original:
            target.write(backup_rel + "/files/" + action.target, action.original)
            entry["original"] = action.original.metadata()
        journal["entries"].append(entry)
    write_json(target, backup_rel + "/backup.json", journal)
    def finish():
        journal["status"] = "installed"
        write_json(target, backup_rel + "/backup.json", journal)

    try:
        apply_actions(target, changed, finish)
    except BaseException:
        print(f"Recovery backup: {target.root / backup_rel}", file=sys.stderr)
        journal["status"] = "failed"  # Recovery data remains available even after a successful rollback.
        try:
            write_json(target, backup_rel + "/backup.json", journal)
        except BaseException:
            pass  # The prepared record already contains the originals and full recovery plan.
        raise
    print(f"Installed {len(changed)} file(s). Backup: {target.root / backup_rel}")
    print(f'Restore: ./install.sh --restore "{target.root / backup_rel}"')
    print("No packages were installed and no session commands were run. See INSTALL.md for dependencies and first login.")
    return target.root / backup_rel


def metadata_snapshot(data: bytes, obj) -> Snapshot:
    if not isinstance(obj, dict) or not isinstance(obj.get("sha256"), str) or not HEX.fullmatch(obj["sha256"]):
        raise InstallError("Invalid original-file metadata in backup")
    for name in ("mode", "atime_ns", "mtime_ns"):
        if type(obj.get(name)) is not int or obj[name] < 0:
            raise InstallError(f"Invalid {name} in backup metadata")
    if obj["mode"] > 0o777 or sha(data) != obj["sha256"]:
        raise InstallError("Original backup file checksum or permissions do not match")
    return Snapshot(data, obj["mode"], obj["atime_ns"], obj["mtime_ns"])


def restore(source: Path, home: Path, backup: Path, *, dry_run=False):
    target = validate_target(source, home)
    backup = Path(os.path.abspath(backup))
    parent = target.root / BACKUPS
    if backup.parent != parent:
        raise InstallError(f"Choose a backup directory directly inside {parent}")
    canonical_path(backup.name)
    backup_rel = BACKUPS + "/" + backup.name
    raw = target.read(backup_rel + "/backup.json")
    if raw is None:
        raise InstallError("This directory has no backup.json recovery record")
    journal = read_json(raw.data, "backup.json")
    if (not isinstance(journal, dict) or type(journal.get("schema_version")) is not int
            or journal["schema_version"] != 1 or journal.get("target_home") != str(target.root)
            or journal.get("status") not in ("prepared", "installed", "failed", "restored")):
        raise InstallError("Backup schema, status, or target home does not match")
    entries = journal.get("entries")
    directories = journal.get("created_dirs")
    if not isinstance(entries, list) or not entries or not isinstance(directories, list):
        raise InstallError("Invalid backup entries or created_dirs")
    actions = []
    seen = set()
    for entry in entries:
        if not isinstance(entry, dict):
            raise InstallError("Invalid backup entry")
        path = canonical_path(entry.get("path"))
        if not allowed_destination(path) or path in seen:
            raise InstallError(f"Invalid or duplicate backup destination: {path}")
        seen.add(path)
        if type(entry.get("existed")) is not bool:
            raise InstallError("Invalid existed flag in backup")
        installed_sha = entry.get("installed_sha256")
        installed_mode = entry.get("installed_mode")
        if (not isinstance(installed_sha, str) or not HEX.fullmatch(installed_sha)
                or type(installed_mode) is not int or not 0 <= installed_mode <= 0o777):
            raise InstallError("Invalid installed-file checksum or permissions in backup")
        desired = None
        if entry["existed"]:
            original = target.read(backup_rel + "/files/" + path)
            if original is None:
                raise InstallError(f"Original backup file is missing: {path}")
            desired = metadata_snapshot(original.data, entry.get("original"))
        current = target.read(path)
        if same(current, desired):
            continue  # Already restored, or an interrupted install never wrote it.
        if current is None or sha(current.data) != installed_sha or current.mode != installed_mode:
            raise InstallError(f"File changed since installation: {path}; preserve/review it before restoring")
        actions.append(Action("backup", path, desired, current))
    allowed_dirs = {"/".join(path.split("/")[:i]) for path in seen for i in range(1, len(path.split("/")))}
    if any(not isinstance(path, str) or canonical_path(path) not in allowed_dirs for path in directories):
        raise InstallError("Backup contains an unrelated directory-removal path")
    changed = display_plan(actions, target.root, dry_run)
    if dry_run:
        print("No files were written.")
        return
    def finish():
        target.remove_empty_dirs(directories)  # Only directories created by this install, and only while empty.
        journal["status"] = "restored"
        write_json(target, backup_rel + "/backup.json", journal)

    apply_actions(target, changed, finish)
    print(f"Restored {len(changed)} file(s). Unlisted files and nonempty directories were preserved.")


DEPENDENCIES = (
    ("Hyprland",), ("qs", "quickshell"), ("kitty",), ("fish",), ("starship",),
    ("fastfetch",), ("awww",), ("awww-daemon",), ("hyprlock",), ("hypridle",),
    ("wpctl",), ("brightnessctl",), ("nmcli",), ("bluetoothctl",), ("swaync",),
    ("python3",), ("wl-copy",), ("wl-paste",), ("hyprshot",), ("playerctl",),
    ("upower",), ("xdg-open",),
)


def check(source: Path):
    _, files = load_export(source)
    print(f"Export integrity: {len(files)} file(s) verified.")
    missing = []
    for alternatives in DEPENDENCIES:
        found = next((shutil.which(name) for name in alternatives if shutil.which(name)), None)
        print(f"  {'found  ' if found else 'missing'} {' / '.join(alternatives)}" + (f" ({found})" if found else ""))
        if not found:
            missing.append(alternatives[0])
    print("This read-only check finds executables on PATH; it cannot verify Hyprland Lua support, Qt modules, fonts, or service setup.")
    print("See INSTALL.md for dependency setup. No packages or commands were run.")
    return 1 if missing else 0


def main(argv=None):
    parser = argparse.ArgumentParser(description="Copy the checked Notch dotfiles into your home, with automatic backups. No sudo, network, or session reloads.")
    parser.add_argument("--dry-run", action="store_true", help="show the complete plan without writing files")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="verify export integrity and list dependency executables (read only)")
    mode.add_argument("--restore", metavar="BACKUP", type=Path, help="restore an installer backup; stop if installed files were edited")
    parser.add_argument("--target-home", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--test-mode", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    if bool(args.target_home) != args.test_mode:
        parser.error("--target-home is reserved for isolated tests and requires --test-mode")
    actual_home = Path.home()
    if args.test_mode and Path(os.path.abspath(args.target_home)) == Path(os.path.abspath(actual_home)):
        parser.error("--test-mode cannot target the real home directory")
    home = args.target_home if args.test_mode else actual_home
    source = Path(os.path.abspath(__file__)).parent.parent
    try:
        if args.check:
            return check(source)
        if args.restore:
            restore(source, home, args.restore, dry_run=args.dry_run)
        else:
            install(source, home, dry_run=args.dry_run)
    except (InstallError, OSError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
