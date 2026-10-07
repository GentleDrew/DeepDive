@echo off
rem Dp launcher: opens Dp.html as an app window (works offline)
set "F=%~dp0Dp.html"
set "E1=%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
set "E2=%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
set "C1=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
set "C2=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
if exist "%E1%" ( start "" "%E1%" --app="file:///%F:\=/%" & exit /b )
if exist "%E2%" ( start "" "%E2%" --app="file:///%F:\=/%" & exit /b )
if exist "%C1%" ( start "" "%C1%" --app="file:///%F:\=/%" & exit /b )
if exist "%C2%" ( start "" "%C2%" --app="file:///%F:\=/%" & exit /b )
start "" "%F%"
