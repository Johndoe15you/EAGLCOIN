#!/usr/bin/env pwsh
Clear-Host
$walletDir = "$PSScriptRoot"
$walletFile = "$walletDir\wallets.json"
$nodeJobName = "EaglNodeJob"
$nodePort = 21801
$nodeExe = "eagld.exe"

function Load-Wallets {
    if (Test-Path $walletFile) {
        try {
            return (Get-Content $walletFile -Raw | ConvertFrom-Json)
        } catch {
            Write-Host "⚠️  Error reading wallets file. Creating new one..."
            return @{}
        }
    } else {
        return @{}
    }
}

function Save-Wallets($wallets) {
    $wallets | ConvertTo-Json -Depth 5 | Set-Content $walletFile
}

function Start-EaglNode {
    $existing = Get-Job | Where-Object { $_.Name -eq $nodeJobName -and $_.State -eq "Running" }
    if ($existing) {
        Write-Host "🟡 Node already running on port $nodePort"
        return
    }

    $args = @("--rpc-bind-port=$nodePort", "--rpc-bind-ip=0.0.0.0", "--confirm-external-bind")
    try {
        Start-Job -Name $nodeJobName -ScriptBlock {
            & "$using:nodeExe" $using:args *> "$using:walletDir\node.log"
        } | Out-Null
        Start-Sleep -Seconds 3
        if (Test-NodeRunning) { Write-Host "✅ Node started successfully." }
        else { Write-Host "❌ Node failed to start. Check node.log" }
    } catch {
        Write-Host "❌ Node job failed: $($_.Exception.Message)"
    }
}

function Stop-EaglNode {
    Get-Job | Where-Object { $_.Name -eq $nodeJobName } | Stop-Job -Force -ErrorAction SilentlyContinue
    Remove-Job -Name $nodeJobName -Force -ErrorAction SilentlyContinue
    Write-Host "🟥 Node stopped."
}

function Test-NodeRunning {
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$nodePort/get_info" -UseBasicParsing -TimeoutSec 3
        return $r.StatusCode -eq 200
    } catch { return $false }
}

function Show-Menu {
    Write-Host ""
    Write-Host "=== 🪙 EAGL CLI ==="
    Write-Host "Commands: list | add | remove | node start | node stop | node status | exit"
    Write-Host ""
}

$wallets = Load-Wallets
Show-Menu

while ($true) {
    $input = Read-Host -Prompt "EAGL>"
    $parts = $input -split '\s+'
    $cmd = $parts[0].ToLower()

    switch ($cmd) {
        'list' {
            if ($wallets.PSObject.Properties.Count -eq 0) {
                Write-Host "No wallets found."
            } else {
                Write-Host "Wallets:"
                foreach ($w in $wallets.PSObject.Properties) {
                    Write-Host " • $($w.Name): $($w.Value.address)"
                }
            }
        }

        'add' {
            $name = Read-Host "Wallet name"
            $addr = Read-Host "Wallet address"
            $wallets | Add-Member -NotePropertyName $name -NotePropertyValue @{ address = $addr } -Force
            Save-Wallets $wallets
            Write-Host "✅ Added wallet '$name'."
        }

        'remove' {
            $name = Read-Host "Wallet name to remove"
            if ($wallets.PSObject.Properties.Name -contains $name) {
                $wallets.PSObject.Properties.Remove($name)
                Save-Wallets $wallets
                Write-Host "🗑️  Removed wallet '$name'."
            } else { Write-Host "Wallet not found." }
        }

        'node' {
            if ($parts.Count -lt 2) { Write-Host "Usage: node <start|stop|status>"; continue }
            switch ($parts[1].ToLower()) {
                'start' { Start-EaglNode }
                'stop'  { Stop-EaglNode }
                'status' {
                    if (Test-NodeRunning) { Write-Host "🟢 Node running on port $nodePort" }
                    else { Write-Host "🔴 Node not running" }
                }
            }
        }

        'exit' { Stop-EaglNode; Write-Host "👋 Exiting..."; break }

        default { Write-Host "Unknown command: $cmd" }
    }
}
