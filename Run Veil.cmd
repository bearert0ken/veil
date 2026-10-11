@echo off
rem Double-click to open Veil. It will request administrator rights.
cd /d "%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0veil.ps1"
