@echo off
rem Double-click this file to open GDID Shield. It will ask for admin rights.
cd /d "%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0gdid-shield.ps1"
