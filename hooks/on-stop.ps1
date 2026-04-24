. "$PSScriptRoot\ConsoleColor.ps1"
Set-TerminalColor $Config.colors.stopped
Play-HookSound -SoundName 'stop'
Start-Sleep -Seconds $Config.stopResetDelaySeconds
Reset-TerminalColor
