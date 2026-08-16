@echo off
REM SetupComplete runs after Windows setup completes. This file should be placed at:
REM Sources\$OEM$\$\Setup\Scripts\SetupComplete.cmd on the install USB so it ends up in %WINDIR%\Setup\Scripts\SetupComplete.cmd

powershell -ExecutionPolicy Bypass -File "%WINDIR%\Setup\Scripts\install-from-usb.ps1" >> "%WINDIR%\Temp\setup-usb-install.log" 2>&1
exit /b 0
