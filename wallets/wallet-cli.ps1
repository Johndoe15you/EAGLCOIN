# ========================================
# EAGLCOIN Wallet CLI
# ========================================
# Version: 2.0 - Stable + Node Support + Create Wallet
# ========================================

$ErrorActionPreference = "SilentlyContinue"
Clear-Host

# === FILES & CONFIG ===
$walletDir  = "$PSScriptRoot"
$walletFile = Join-Path $walletDir "wallets.json"
if (-not (Test-Path $walletFile)) { '{}' | Out-File $walletFile }

# === FUNCTIONS ===

function Load-Wallets {
    try {
        $json = Get-Content $walletFile -Raw
        if ($json.Trim() -eq "") { return @{} }
        $wallets = $json | ConvertFrom-Json
        if ($wallets -isnot [hashtable]) {
            $wallets = @{} + $wallets.PSObject.Properties.Name.ForEach({
                @{ $_ = $wallets.$_ }
            })
        }
        return $wallets
    } catch {
        Write-Host "⚠️ Error reading wallets.json: $($_.Exception.Message)"
        return @{}
    }
}

function Save-Wallets ($wallets) {
    try {
        ($wallets | ConvertTo-Json -Depth 5) | Out-File $walletFile
        Write-Host "💾 Wallets saved."
    } catch {
        Write-Host "❌ Failed to save wallets: $($_.Exception.Message)"
    }
}

function Create-Wallet {
    param([string]$name)
    if (-not $name) {
        Write-Host "Usage: create <walletName>"
        return
    }
    $wallets = Load-Wallets
    if ($wallets.ContainsKey($name)) {
        Write-Host "❌ Wallet '$name' already exists."
        return
    }

    # Simulated keypair generation
    $address = ("4" + (Get-Random -Minimum 10000000 -Maximum 99999999))
    $viewKey = [guid]::NewGuid().ToString().Replace("-", "")
    $spendKey = [guid]::NewGuid().ToString().Replace("-", "")

    $wallets[$name] = [ordered]@{
        Address   = $address
        ViewKey   = $viewKey
        SpendKey  = $spendKey
        Balance   = 0
    }

    Save-Wallets $wallets
    Write-Host "✅ Wallet '$name' created!"
    Write-Host "   Address: $address"
}

function List-Wallets {
    $wallets = Load-Wallets
    if ($wallets.Count -eq 0) {
        Write-Host "No wallets yet. Create one with 'create <name>'"
        return
    }

    Write-Host "Wallets:"
    foreach ($name in $wallets.Keys) {
        $w = $wallets[$name]
        Write-Host "  🪙 $name - $($w.Address)"
    }
}

function Delete-Wallet {
    param([string]$name)
    $wallets = Load-Wallets
    if (-not $wallets.ContainsKey($name)) {
        Write-Host "❌ Wallet '$name' not found."
        return
    }
    $wallets.Remove($name)
    Save-Wallets $wallets
    Write-Host "🗑️ Wallet '$name' deleted."
}

function Send-Coins {
    param([string]$from, [string]$to, [double]$amount)
    if (-not $from -or -not $to -or -not $amount) {
        Write-Host "Usage: send <from> <to> <amount>"
        return
    }

    $wallets = Load-Wallets
    if (-not $wallets.ContainsKey($from)) {
        Write-Host "❌ Wallet '$from' not found."
        return
    }
    $wallet = $wallets[$from]

    if ($wallet.Balance -lt $amount) {
        Write-Host "❌ Not enough balance."
        return
    }

    $wallet.Balance -= $amount
    $wallets[$from] = $wallet
    Save-Wallets $wallets

    Write-Host "📤 Sent $amount EAGL from $from → $to"

    # Send to node (if running)
    try {
        $body = @{from=$from;to=$to;amount=$amount} | ConvertTo-Json
        Invoke-RestMethod -Uri "http://localhost:8080/submit" -Method Post -Body $body -ContentType "application/json" | Out-Null
        Write-Host "✅ Transaction submitted to node."
    } catch {
        Write-Host "⚠️ Node offline or not reachable."
    }
}

function Node-Status {
    try {
        $r = Invoke-RestMethod -Uri "http://localhost:8080/status"
        Write-Host "🌐 Node: $($r.status) - Blocks: $($r.blocks)"
    } catch {
        Write-Host "⚠️ Node not reachable."
    }
}

function Show-Help {
    @"
Available commands:
  create <name>          - Create a new wallet
  list                   - List all wallets
  delete <name>          - Delete a wallet
  send <from> <to> <amt> - Send EAGL
  node status            - Check node connection
  help                   - Show this help
  exit                   - Exit CLI
"@
}

# === MAIN CLI LOOP ===
Write-Host "EAGLCOIN CLI - Type 'help' for commands."
while ($true) {
    Write-Host -NoNewline "EAGL>: "
    $input = Read-Host
    if (-not $input) { continue }

    $parts = $input.Split(' ')
    $cmd = $parts[0].ToLower()

    switch ($cmd) {
        "help"          { Show-Help }
        "list"          { List-Wallets }
        "create"        { Create-Wallet $parts[1] }
        "delete"        { Delete-Wallet $parts[1] }
        "send"          { Send-Coins $parts[1] $parts[2] $parts[3] }
        "node" {
            if ($parts.Length -ge 2 -and $parts[1] -eq "status") { Node-Status }
            else { Write-Host "Usage: node status" }
        }
        "exit"          { break }
        default         { Write-Host "[!] Unknown command. Type 'help'." }
    }
}
