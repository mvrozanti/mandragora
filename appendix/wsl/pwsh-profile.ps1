# Mandragora PowerShell profile snippet -- keeps PSReadLine in sync with
# the keybindings we ship for zsh.
#
# Source from your PowerShell $PROFILE:
#
#   if (Test-Path '\\wsl$\NixOS\etc\nixos\mandragora\appendix\wsl\pwsh-profile.ps1') {
#     . '\\wsl$\NixOS\etc\nixos\mandragora\appendix\wsl\pwsh-profile.ps1'
#   }
#
# Re-sourced every PowerShell launch, so future zsh keybind changes
# need no manual mirror -- just re-pull the repo and the next pwsh
# session picks them up.

if (Get-Module -ListAvailable PSReadLine) {
    # Alt+Enter: insert literal newline without executing -- same as our zsh widget.
    Set-PSReadLineKeyHandler -Chord 'Alt+Enter' -Function AddLine
}
