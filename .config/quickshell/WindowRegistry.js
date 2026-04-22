.pragma library

function getScale(mw, userScale) {
    if (mw <= 0) return 1.0;
    let r = mw / 1920.0;
    let baseScale = 1.0;
    
    if (r <= 1.0) {
        baseScale = Math.max(0.35, Math.pow(r, 0.85));
    } else {
        baseScale = Math.pow(r, 0.5);
    }
    
    return baseScale * (userScale !== undefined ? userScale : 1.0);
}

function s(val, scale) {
    return Math.round(val * scale);
}

function getLayout(name, mx, my, mw, mh, userScale) {
    let scale = getScale(mw, userScale);

    let base = {
        "battery":   { w: s(801, scale), h: s(760, scale), rx: mw - s(821, scale), ry: s(70, scale), comp: "battery/BatteryPopup.qml" },
        "volume":    { w: s(480, scale), h: s(760, scale), rx: mw - s(500, scale), ry: s(70, scale), comp: "volume/VolumePopup.qml" },
        "calendar":  { w: s(1450, scale), h: s(750, scale), rx: Math.floor((mw/2)-(s(1450, scale)/2)), ry: s(70, scale), comp: "calendar/CalendarPopup.qml" },
        "music":     { w: s(700, scale), h: s(620, scale), rx: s(12, scale), ry: s(70, scale), comp: "music/MusicPopup.qml" },
        "network":   { w: s(900, scale), h: s(700, scale), rx: mw - s(920, scale), ry: s(70, scale), comp: "network/NetworkPopup.qml" },
        "stewart":   { w: s(800, scale), h: s(600, scale), rx: Math.floor((mw/2)-(s(800, scale)/2)), ry: Math.floor((mh/2)-(s(600, scale)/2)), comp: "stewart/stewart.qml" },
        "monitors":  { w: s(850, scale), h: s(580, scale), rx: Math.floor((mw/2)-(s(850, scale)/2)), ry: Math.floor((mh/2)-(s(580, scale)/2)), comp: "monitors/MonitorPopup.qml" },
        "focustime": { w: s(900, scale), h: s(720, scale), rx: Math.floor((mw/2)-(s(900, scale)/2)), ry: Math.floor((mh/2)-(s(720, scale)/2)), comp: "focustime/FocusTimePopup.qml" },
        "guide":     { w: s(1200, scale), h: s(750, scale), rx: Math.floor((mw/2)-(s(1200, scale)/2)), ry: Math.floor((mh/2)-(s(750, scale)/2)), comp: "guide/GuidePopup.qml" },
        "settings":  { w: s(450, scale), h: mh - s(0, scale), rx: s(0, scale), ry: s(0, scale), comp: "settings/SettingsPopup.qml" },
        "updater":   { w: s(450, scale), h: s(350, scale), rx: Math.floor((mw/2)-(s(450, scale)/2)), ry: Math.floor((mh/2)-(s(350, scale)/2)), comp: "updater/UpdaterPopup.qml" },
        "notifications": { w: s(800, scale), h: s(700, scale), rx: Math.floor((mw/2)-(s(800, scale)/2)), ry: Math.floor((mh/2)-(s(700, scale)/2)), comp: "notifications/NotificationCenter.qml" },
        "sidepanel": { w: s(600, scale), h: mh - s(56, scale), rx: mw - s(604, scale), ry: s(56, scale), comp: "sidepanel/SidePanel.qml" },
        "wallpaper": { w: mw, h: s(650, scale), rx: 0, ry: Math.floor((mh/2)-(s(650, scale)/2)), comp: "wallpaper/WallpaperPicker.qml" },
        "hidden":    { w: 1, h: 1, rx: -5000 - mx, ry: -5000 - my, comp: "" } 
    };

    if (!base[name]) return null;
    
    let t = base[name];
    t.x = mx + t.rx;
    t.y = my + t.ry;
    
    return t;
}

function getPopupLayout(mw, userScale) {
    let scale = getScale(mw, userScale);
    return {
        w: s(350, scale),
        marginTop: s(70, scale),
        marginRight: s(20, scale),
        spacing: s(12, scale),
        radius: s(14, scale),
        padding: s(12, scale)
    };
}
