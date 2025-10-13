# =======================================
# EAGL Wallet CLI
# Version 3.1 - Fixed Node/JSON Sync
# =======================================

$NodeUrl = "http://127.0.0.1:21801"
$WalletFile = Join-Path $PSScriptRoot "wallets.json"

if (-not (Test-Path $WalletFile)) {
    @() | ConvertTo-Json | Out-File $WalletFile
}

function Load-Wallets {
    try {
        $json = Get-Content $WalletFile -Raw
        if ([string]::IsNullOrWhiteSpace($json)) { return @() }
        $wallets = $json | ConvertFrom-Json
        if ($wallets -isnot [System.Collections.IEnumerable]) { $wallets = @($wallets) }
        return $wallets
    } catch {
        Write-Host "⚠️ Error reading wallets.json: $($_.Exception.Message)"
        return @()
    }
}

function Save-Wallets($wallets) {
    try {
        ($wallets | ConvertTo-Json -Depth 5) | Out-File $WalletFile
        Write-Host "💾 Wallets saved."
    } catch {
        Write-Host "❌ Failed to save wallets: $($_.Exception.Message)"
    }
}

function Create-Wallet($name) {
    $wallets = Load-Wallets
    if ($wallets | Where-Object { $_.name -eq $name }) {
        Write-Host "⚠️ Wallet '$name' already exists."
        return
    }

    $address = (Get-Random -Minimum 100000000 -Maximum 999999999).ToString()
    $wallet = [pscustomobject]@{
        name    = $name
        address = $address
        balance = 100
    }

    $wallets = @($wallets + $wallet)
    Save-Wallets $wallets

    Write-Host "✅ Wallet '$name' created!"
    Write-Host "   Address: $address"
    Write-Host "   Balance: 100 EAGL"
}

function List-Wallets {
    $wallets = Load-Wallets
    if (-not $wallets -or $wallets.Count -eq 0) {
        Write-Host "Wallets: (none)"
        return
    }

    Write-Host "Wallets:"
    foreach ($w in $wallets) {
        Write-Host " • $($w.name): $($w.balance) EAGL [$($w.address)]"
    }
}

function Get-Wallet($name) {
    $wallets = Load-Wallets
    return ($wallets | Where-Object { $_.name -eq $name })
}

function Update-Wallet($wallet) {
    $wallets = Load-Wallets | Where-Object { $_.name -ne $wallet.name }
    $wallets = @($wallets + $wallet)
    Save-Wallets $wallets
}

function Node-Status {
    try {
        $r = Invoke-RestMethod "$NodeUrl/status" -TimeoutSec 3
        Write-Host "✅ Node status: $($r.status) — blocks: $($r.blocks) — port: $($r.port)"
    } catch {
        Write-Host "❌ Node offline or unreachable at $NodeUrl. ($($_.Exception.Message))"
    }
}

function Node-Chain {
    try {
        $r = Invoke-RestMethod "$NodeUrl/chain" -TimeoutSec 3
        if ($r -is [array]) {
            $json = $r | ConvertTo-Json -Depth 5
            Write-Host $json
        } else {
            Write-Host (ConvertTo-Json $r -Depth 5)
        }
    } catch {
        Write-Host "❌ Failed to fetch blockchain: $($_.Exception.Message)"
    }
}

function Transfer($fromName, $toName, $amount) {
    $wallets = Load-Wallets
    $from = Get-Wallet $fromName
    $to   = Get-Wallet $toName

    if (-not $from) { Write-Host "❌ Sender '$fromName' not found."; return }
    if (-not $to)   { Write-Host "❌ Recipient '$toName' not found."; return }

    $amt = [double]$amount
    if ($from.balance -lt $amt) {
        Write-Host "❌ Insufficient balance."
        return
    }

    # local update
    $from.balance -= $amt
    $to.balance   += $amt
    Update-Wallet $from
    Update-Wallet $to

    Write-Host "✅ Transferred $amount EAGL from '$fromName' to '$toName'."

    try {
        $body = @{
            from   = $from.address
            to     = $to.address
            amount = $amt
        } | ConvertTo-Json

        $resp = Invoke-RestMethod -Uri "$NodeUrl/add" -Method POST -Body $body -ContentType "application/json" -TimeoutSec 5

        if ($resp.result -eq "accepted") {
            Write-Host "📤 Transaction submitted to node. New block height: $($resp.height)"
        } elseif ($resp.error) {
            Write-Host "⚠️ Node response error: $($resp.error)"
        } else {
            Write-Host "⚠️ Node response:"
            Write-Host ($resp | ConvertTo-Json -Depth 5)
        }
    } catch {
        Write-Host "❌ Node offline or error submitting transaction: $($_.Exception.Message)"
    }
}

function Show-Help {
    Write-Host ""
    Write-Host "🪙  EAGL CLI Commands"
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host " create <name>          → Create new wallet"
    Write-Host " list                   → List wallets"
    Write-Host " transfer <from> <to> <amt> → Send coins"
    Write-Host " node status            → Show node status"
    Write-Host " node chain             → Show blockchain"
    Write-Host " help                   → Show this help"
    Write-Host " exit                   → Exit CLI"
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host ""
}

# === MAIN LOOP ===
Write-Host "EAGLCOIN CLI - Type 'help' for commands."
while ($true) {
    Write-Host -NoNewline "EAGL>: "
    $input = Read-Host
    if ([string]::IsNullOrWhiteSpace($input)) { continue }

    $parts = $input -split ' '
    $cmd = $parts[0].ToLower()
    $args = $parts[1..($parts.Count - 1)]

    switch ($cmd) {
        "help" { Show-Help }
        "create" { if ($args.Count -ge 1) { Create-Wallet $args[0] } else { Write-Host "Usage: create <name>" } }
        "list" { List-Wallets }
        "transfer" { if ($args.Count -ge 3) { Transfer $args[0] $args[1] $args[2] } else { Write-Host "Usage: transfer <from> <to> <amount>" } }
        "node" {
            if ($args.Count -ge 1) {
                switch ($args[0]) {
                    "status" { Node-Status }
                    "chain" { Node-Chain }
                    default { Write-Host "Usage: node [status|chain]" }
                }
            } else {
                Write-Host "Usage: node [status|chain]"
            }
        }
        "exit" { break }
        default { Write-Host "[!] Unknown command. Type 'help'." }
    }
}
