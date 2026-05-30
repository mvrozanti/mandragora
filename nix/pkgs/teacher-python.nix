{ pkgs }:

pkgs.python3.withPackages (p: [
  p.anthropic
  p.python-telegram-bot
  p.apscheduler
  p.pytz
  p.python-dotenv
])
