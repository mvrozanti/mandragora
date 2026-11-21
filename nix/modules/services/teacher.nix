{ pkgs, ... }:

let
  port = 6691;
  teacherPython = import ../../pkgs/teacher-python.nix { inherit pkgs; };
  teacherRoot = "/home/m/Projects/teacher";
  teacherState = "/home/m/.local/share/teacher";
in
{
  mandragora.hub.services.teacher-teach = {
    inherit port;
    userService = true;
    memoryMax = "1G";
    systemd = {
      description = "teacher — Socratic tutor (claude CLI + FSRS) served to the phone app's teach screen over the tailnet";
      wantedBy = [ "default.target" ];
      path = [
        pkgs.claude-code
        "/etc/profiles/per-user/m"
        "/nix/var/nix/profiles/default"
        "/run/current-system/sw"
      ];
      environment = {
        PYTHONPATH = teacherRoot;
        TEACHER_HOST = "0.0.0.0";
        TEACHER_PORT = toString port;
        TEACHER_INBOX_URL = "http://127.0.0.1:6688/api/inbox";
        TEACHER_DB_PATH = "${teacherState}/data/teacher.db";
        TEACHER_BOOKS_DIR = "/home/m/Documents/library/books";
        TEACHER_AGENTS_MD = "${teacherRoot}/AGENTS.md";
        TEACHER_READ_ROOTS = "/home/m/Documents,/home/m/Projects,/etc/nixos/mandragora";
      };
      serviceConfig = {
        Type = "simple";
        WorkingDirectory = teacherRoot;
        ExecStart = "${teacherPython}/bin/python -m teacher.server";
        Restart = "on-failure";
        RestartSec = "10s";
        TimeoutStartSec = "2min";
      };
      unitConfig.ConditionPathExists = [
        "${teacherRoot}/teacher/server.py"
        "${teacherRoot}/AGENTS.md"
      ];
    };
  };
}
