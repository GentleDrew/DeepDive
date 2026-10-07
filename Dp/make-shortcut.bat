@echo off
set "DPDIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { $d=$env:DPDIR; $html=Join-Path $d 'Dp.html'; $uri=([System.Uri]$html).AbsoluteUri; $pf=$env:ProgramFiles; $pf86=${env:ProgramFiles(x86)}; $b=@(($pf+'\Microsoft\Edge\Application\msedge.exe'),($pf86+'\Microsoft\Edge\Application\msedge.exe'),($pf+'\Google\Chrome\Application\chrome.exe'),($pf86+'\Google\Chrome\Application\chrome.exe'),($env:LOCALAPPDATA+'\Google\Chrome\Application\chrome.exe')) | Where-Object { Test-Path $_ } | Select-Object -First 1; $lnk=Join-Path ([Environment]::GetFolderPath('Desktop')) 'Dp.lnk'; $s=(New-Object -ComObject WScript.Shell).CreateShortcut($lnk); if($b){ $s.TargetPath=$b; $s.Arguments='--app='+$uri } else { $s.TargetPath=$html }; $s.WorkingDirectory=$d; $s.IconLocation=(Join-Path $d 'Dp.ico'); $s.Save(); Write-Host ('Created: '+$lnk) }"
echo.
echo Done. Check the Dp icon on your Desktop.
pause
