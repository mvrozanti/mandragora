{ pkgs }:

pkgs.python3.withPackages (p: [
  p.mcp
  p.python-telegram-bot
  p.apscheduler
  p.pytz
  p.python-dotenv
])
