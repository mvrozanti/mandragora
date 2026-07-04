polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.systemd1.manage-units" &&
        subject.user == "m" &&
        subject.local &&
        subject.active) {
        if (action.lookup("unit") == "ollama.service") {
            return polkit.Result.YES;
        }
    }
});
