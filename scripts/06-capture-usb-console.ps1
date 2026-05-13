param(
    [string]$Port = "COM3",
    [int]$BaudRate = 115200,
    [string]$LogPath = "",
    [switch]$ListOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ResolvedLogPath {
    param([string]$RequestedPath)

    if ([string]::IsNullOrWhiteSpace($RequestedPath)) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        return Join-Path (Get-Location) "output/usb-console-$timestamp.log"
    }

    if ([System.IO.Path]::IsPathRooted($RequestedPath)) {
        return $RequestedPath
    }

    return Join-Path (Get-Location) $RequestedPath
}

$ports = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object

if ($ListOnly) {
    if (-not $ports) {
        Write-Host "No serial ports detected."
        exit 0
    }

    Write-Host "Detected serial ports:"
    $ports | ForEach-Object { Write-Host "  $_" }
    exit 0
}

if (-not ($ports -contains $Port)) {
    Write-Error "Requested port $Port is not present. Run with -ListOnly first."
}

$resolvedLogPath = Get-ResolvedLogPath -RequestedPath $LogPath
$logDir = Split-Path -Parent $resolvedLogPath

if (-not [string]::IsNullOrWhiteSpace($logDir)) {
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
}

$encoding = [System.Text.Encoding]::ASCII
$writer = [System.IO.StreamWriter]::new($resolvedLogPath, $true, $encoding)
$writer.AutoFlush = $true

$serial = [System.IO.Ports.SerialPort]::new($Port, $BaudRate, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$serial.Handshake = [System.IO.Ports.Handshake]::None
$serial.DtrEnable = $true
$serial.RtsEnable = $true
$serial.ReadTimeout = 250
$serial.WriteTimeout = 1000
$serial.Encoding = $encoding

Write-Host "Opening $Port at $BaudRate baud..."
try {
    $serial.Open()
}
catch {
    Write-Error "Failed to open ${Port}: $_"
    exit 1
}
Write-Host "Connected. Logging to $resolvedLogPath"
Write-Host "[Interactive: type commands directly. Press Ctrl+] to exit.]" -ForegroundColor Cyan
Write-Host "[Tip: if device already booted, press Enter to get login prompt]" -ForegroundColor Yellow
Write-Host ""

# Send Enter immediately in case device is already at login/shell prompt
Start-Sleep -Milliseconds 300
$serial.Write("`r`n")

try {
    while ($true) {
        # Read from serial → stdout + log
        try {
            $chunk = $serial.ReadExisting()
        }
        catch {
            Write-Host "`n[Serial read error: $_]" -ForegroundColor Red
            break
        }
        if (-not [string]::IsNullOrEmpty($chunk)) {
            [Console]::Write($chunk)
            $writer.Write($chunk)
        }

        # Forward keyboard input → serial (non-blocking)
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            # Ctrl+] (ASCII 29) to exit
            if ($key.Key -eq [ConsoleKey]::Oem6 -and
                ($key.Modifiers -band [ConsoleModifiers]::Control)) {
                Write-Host "`n[Disconnected]"
                break
            }
            elseif ($key.Key -eq [ConsoleKey]::Enter) {
                $serial.Write("`r`n")
            }
            elseif ($key.Key -eq [ConsoleKey]::Backspace) {
                $serial.Write([char]8)
            }
            else {
                if ($key.KeyChar -ne [char]0) {
                    $serial.Write([string]$key.KeyChar)
                }
            }
        }
        else {
            Start-Sleep -Milliseconds 10
        }
    }
}
finally {
    if ($serial.IsOpen) {
        $serial.Close()
    }

    $writer.Dispose()
    Write-Host ""
    Write-Host "Log saved to $resolvedLogPath"
}