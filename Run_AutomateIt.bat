@echo off
title AutomateIt Server & Tunnel
echo Starting AutomateIt API...
start "AutomateIt API" dotnet run --project "AutomateIt.API"

echo.
echo Starting Ngrok Static Tunnel (https://untaxed-curtly-raisin.ngrok-free.dev)...
start "Ngrok Tunnel" ngrok http --url untaxed-curtly-raisin.ngrok-free.dev 5161

echo.
echo ==================================================
echo BOTH PROCESSES STARTED!
echo Keep this window open if you want to monitor.
echo.
echo API: Running on port 5161
echo Domain: https://untaxed-curtly-raisin.ngrok-free.dev
echo ==================================================
pause
