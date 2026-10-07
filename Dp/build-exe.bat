@echo off
cd /d "%~dp0"
set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" ( echo csc.exe not found. & pause & exit /b 1 )
if not exist Dp.html ( echo Dp.html not found in this folder. & pause & exit /b 1 )
if not exist Dp.ico ( echo Dp.ico not found in this folder. & pause & exit /b 1 )
for /f "delims=" %%D in ('powershell -NoProfile -Command "[Environment]::GetFolderPath('Desktop')"') do set "DESK=%%D"
"%CSC%" /nologo /target:winexe /out:"%DESK%\Dp.exe" /win32icon:Dp.ico /resource:Dp.html,Dp.html DpLauncher.cs
if errorlevel 1 ( echo Build failed. & pause & exit /b 1 )
echo.
echo Done: %DESK%\Dp.exe
pause
