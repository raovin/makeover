Option Explicit

Dim shell, fso, scriptDir, ps1, powershell, command, index, arg

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = fso.BuildPath(scriptDir, "Show-MacAppleMenu.ps1")
powershell = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"

command = """" & powershell & """ -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & ps1 & """"

For index = 0 To WScript.Arguments.Count - 1
  arg = Replace(WScript.Arguments(index), """", """""")
  command = command & " """ & arg & """"
Next

shell.Run command, 0, False
