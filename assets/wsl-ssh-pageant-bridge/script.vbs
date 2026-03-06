Set WshShell = CreateObject("WScript.Shell")
Set FSO = CreateObject("Scripting.FileSystemObject")
Set Env = WshShell.Environment("Process")

Dim tmpDir
tmpDir = WshShell.ExpandEnvironmentStrings("%TEMP%")

Dim pathDirs
pathDirs = Split(WshShell.ExpandEnvironmentStrings("%PATH%"), ";")

Dim npiperelayWin
npiperelayWin = ResolveFromPath("npiperelay")
If npiperelayWin = "" Then
    WScript.Quit 1
End If
Env("WSPB_NPIPERELAY") = npiperelayWin

Dim wslenvParts
wslenvParts = "WSPB_NPIPERELAY/up:WSPB_PIPE/u:WSPB_SCRIPT/up"

Dim existingWslenv
existingWslenv = WshShell.ExpandEnvironmentStrings("%WSLENV%")
If existingWslenv = "%WSLENV%" Then
    Env("WSLENV") = wslenvParts
Else
    Env("WSLENV") = existingWslenv & ":" & wslenvParts
End If

Do
    Do While Not IsWslRunning()
        WScript.Sleep 5000
    Loop

    Dim pipePath
    pipePath = GetPageantPipe()

    If pipePath = "" Then
        WshShell.Run "pageant", 1, False

        Dim attempts
        For attempts = 1 To 40
            WScript.Sleep 250
            pipePath = GetPageantPipe()
            If pipePath <> "" Then Exit For
        Next
    End If

    If pipePath = "" Then
        WScript.Sleep 5000
    Else
        Env("WSPB_PIPE") = Replace(pipePath, "\", "/")

        Dim tmpScript
        tmpScript = tmpDir & "\" & FSO.GetTempName() & ".sh"
        Dim f
        Set f = FSO.CreateTextFile(tmpScript, True)
        f.Write "#!/bin/bash" & vbLf & _
            "set -eu" & vbLf & _
            "SOCKET=$(eval echo ""${WSL_SSH_PAGEANT_BRIDGE_SOCK:?not set}"")" & vbLf & _
            "case ""$SOCKET"" in /*) ;; *) echo ""invalid socket path: $SOCKET"" >&2; exit 1;; esac" & vbLf & _
            "if ss -xl 2>/dev/null | grep -qF ""$SOCKET""; then exit 42; fi" & vbLf & _
            "mkdir -p ""$(dirname ""$SOCKET"")""" & vbLf & _
            "rm -f ""$SOCKET""" & vbLf & _
            "rm -f ""$0""" & vbLf & _
            "exec socat \" & vbLf & _
            "  UNIX-LISTEN:""$SOCKET"",fork,mode=600 \" & vbLf & _
            "  EXEC:""$WSPB_NPIPERELAY -ei -s $WSPB_PIPE"",nofork" & vbLf
        f.Close

        Env("WSPB_SCRIPT") = tmpScript

        If WshShell.Run("wsl bash ""$WSPB_SCRIPT""", 0, True) = 42 Then
            WScript.Quit 1
        End If
    End If
Loop

Function IsWslRunning()
    IsWslRunning = (WshShell.Run("wsl --list --running", 0, True) = 0)
End Function

Function GetPageantPipe()
    GetPageantPipe = ""
    Dim regex
    Set regex = New RegExp
    regex.Pattern = "^pageant\..+\.[0-9a-f]{64}$"
    regex.IgnoreCase = True

    Dim tmpFile, lines, pipeName, i
    tmpFile = tmpDir & "\" & FSO.GetTempName()
    WshShell.Run "powershell -NoProfile -NonInteractive -WindowStyle Hidden -Command ""[IO.Directory]::GetFiles('\\.\pipe\','pageant.*') | Set-Content '" & tmpFile & "'""", 0, True
    If FSO.FileExists(tmpFile) Then
        Dim rf
        Set rf = FSO.OpenTextFile(tmpFile, 1)
        If Not rf.AtEndOfStream Then
            lines = Split(rf.ReadAll(), vbCrLf)
        End If
        rf.Close
        FSO.DeleteFile tmpFile

        For i = 0 To UBound(lines)
            pipeName = Trim(Replace(lines(i), "\\.\pipe\", ""))
            If Len(pipeName) > 0 And regex.Test(pipeName) Then
                GetPageantPipe = "\\.\pipe\" & pipeName
                Exit Function
            End If
        Next
    End If
End Function

Function ResolveFromPath(exeName)
    ResolveFromPath = ""
    For i = 0 To UBound(pathDirs)
        If Len(pathDirs(i)) > 0 Then
            candidate = pathDirs(i) & "\" & exeName & ".exe"
            If FSO.FileExists(candidate) Then
                ResolveFromPath = candidate
                Exit Function
            End If
        End If
    Next
End Function
