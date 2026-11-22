polkit.addRule(function(action, subject) {
    var power = [
        "org.freedesktop.login1.reboot",
        "org.freedesktop.login1.reboot-multiple-sessions",
        "org.freedesktop.login1.power-off",
        "org.freedesktop.login1.power-off-multiple-sessions"
    ];
    if (subject.user == "m" && power.indexOf(action.id) >= 0) {
        return polkit.Result.YES;
    }
});
