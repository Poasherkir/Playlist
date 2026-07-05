Dim fso, shell, dir
Set fso   = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
shell.Run "powershell.exe -ExecutionPolicy Bypass -File """ & dir & "\start.ps1""", 1, False
