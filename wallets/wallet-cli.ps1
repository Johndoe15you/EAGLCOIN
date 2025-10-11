# EAGLCOIN Wallet CLI - Full version with node support
# Saves wallets in JSON and starts a simple node via background job
# PowerShell 7+ recommended

$walletFile = "$PSScriptRoot\wallets.json"
$nodeLog    = "$PSScriptRoot\node.log"
$wallets    = @{}

function Load-Wallets {
    if (Test-Path $walletFile) {
        try { $wallets = Get-Content $walletFile | ConvertFrom-Json -AsHashtable }
        catch { Write-Host "⚠️ Error reading ${walletFile}: $_" }
    } else { $wallets = @{} }
}

function Save-Wallets {
    try { $wallets | ConvertTo-Json | Set-Content $walletFile }
    catch { Write-Host "⚠️ Error saving ${walletFile}: $_" }
}

function Show-Help {
@"
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Commands:
  help                    - Show this help
  create <name>           - Create wallet
  list                    - List wallets
  balance <name>          - Show balance
  transfer <from> <to> <amount> - Transfer EAGL
  node start|stop|status  - Manage local node
  exit                    - Quit CLI
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"@
}

function Create-Wallet($name) {
    if ($wallets.ContainsKey($name)) { Write-Host "Wallet '$name' exists."; return }
    $wallets[$name] = 100
    Save-Wallets
    Write-Host "✅ Wallet '$name' created with 100 EAGL."
}

function List-Wallets {
    if ($wallets.Count -eq 0) { Write-Host "No wallets yet."; return }
    Write-Host "Wallets:"
    foreach ($k in $wallets.Keys) { Write-Host "  $k : $($wallets[$k]) EAGL" }
}

function Show-Balance($name) {
    if (-not $wallets.ContainsKey($name)) { Write-Host "❌ No wallet '$name'"; return }
    Write-Host "$name has $($wallets[$name]) EAGL."
}

function Transfer($from,$to,[decimal]$amount) {
    if (-not $wallets.ContainsKey($from) -or -not $wallets.ContainsKey($to)) {
        Write-Host "❌ Invalid wallet(s)."; return
    }
    if ($wallets[$from] -lt $amount) { Write-Host "❌ Insufficient funds."; return }
    $wallets[$from] -= $amount
    $wallets[$to]   += $amount
    Save-Wallets
    Write-Host "✅ Transferred $amount EAGL from $from → $to."
}

function Node-Start {
    if (Get-Job -Name "EaglNodeJob" -ErrorAction SilentlyContinue) {
        Write-Host "Node already running."; return
    }
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host "🚀 Starting EAGL node on port 21801..."
    Start-Job -Name "EaglNodeJob" -ScriptBlock {
        $listener = [System.Net.HttpListener]::new()
        $listener.Prefixes.Add("http://+:21801/")
        $listener.Start()
        Add-Content $using:nodeLog "Node started on port 21801 $(Get-Date)"
        while ($true) {
            $ctx = $listener.GetContext()
            $res = @{ status="ok"; time=(Get-Date) } | ConvertTo-Json
            $bytes = [Text.Encoding]::UTF8.GetBytes($res)
            $ctx.Response.OutputStream.Write($bytes,0,$bytes.Length)
            $ctx.Response.Close()
        }
    } | Out-Null
    Write-Host "✅ Node online and logging to node.log"
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

function Node-Stop {
    $job = Get-Job -Name "EaglNodeJob" -ErrorAction SilentlyContinue
    if ($null -eq $job) { Write-Host "Node not running."; return }
    Stop-Job $job -Force; Remove-Job $job
    Write-Host "🛑 Node stopped."
}

function Node-Status {
    $job = Get-Job -Name "EaglNodeJob" -ErrorAction SilentlyContinue
    if ($job -and $job.State -eq "Running") {
        Write-Host "✅ Node is running on port 21801."
    } else { Write-Host "❌ Node is not running." }
}

# --- MAIN LOOP ---
Load-Wallets
Write-Host "EAGLCOIN CLI - Type 'help' for commands (hidden by default)."

while ($true) {
    $inputLine = Read-Host "EAGL>"
    if ([string]::IsNullOrWhiteSpace($inputLine)) { continue }
    $parts = -split '\s+', $inputLine.Trim()
    $cmd = ($parts[0] -as [string]).ToLower()
    switch ($cmd) {
        'help'     { Show-Help }
        'create'   { if ($parts.Count -ge 2) { Create-Wallet $parts[1] } else { Write-Host "Usage: create <name>" } }
        'list'     { List-Wallets }
        'balance'  { if ($parts.Count -ge 2) { Show-Balance $parts[1] } else { Write-Host "Usage: balance <name>" } }
        'transfer' { if ($parts.Count -ge 4) { Transfer $parts[1] $parts[2] $parts[3] } else { Write-Host "Usage: transfer <from> <to> <amount>" } }
        'node' {
            if ($parts.Count -lt 2) { Node-Status; break }
            switch ($parts[1].ToLower()) {
                'start'  { Node-Start }
                'stop'   { Node-Stop }
                'status' { Node-Status }
                default  { Write-Host "Usage: node <start|stop|status>" }
            }
        }
        'exit'     { Write-Host "Goodbye!"; break }
        default    { Write-Host "[!] Unknown command. Type 'help'." }
    }
}
