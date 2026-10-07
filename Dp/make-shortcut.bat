@echo off
rem Creates a "Dp" shortcut with the Dp icon on the Desktop
powershell -NoProfile -Command "$d='%~dp0'; $s=(New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Desktop')+'\Dp.lnk'); $s.TargetPath=$d+'Dp.bat'; $s.WorkingDirectory=$d; $s.IconLocation=$d+'Dp.ico'; $s.WindowStyle=7; $s.Save()"
echo Done: Dp shortcut created on Desktop.
pause
