Dim fso, shell, dir
Set fso   = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
shell.Run "cmd.exe /k """ & dir & "\setup.bat""", 1, False
