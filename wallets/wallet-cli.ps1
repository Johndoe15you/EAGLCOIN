# ========================================
# EAGL Wallet CLI - v2.3
# ========================================

$WalletFile = "C:\Users\rocke\EAGLCOIN\wallets.json"
$NodeUrl    = "http://127.0.0.1:21801"

if (-not (Test-Path $WalletFile)) { '[]' | Out-File $WalletFile }

function Load-Wallets {
    try {
        $json = Get-Content $WalletFile -Raw
        if ($json.Trim() -eq "") { return @() }
        return $json | ConvertFrom-Json
    } catch {
        Write-Host "⚠️ Error reading wallets.json: $($_.Exception.Message)"
        return @()
    }
}

function Save-Wallets($wallets) {
    ($wallets | ConvertTo-Json -Depth 5) | Out-File $WalletFile
}

function Create-Wallet($name) {
    $wallets = @() + (Load-Wallets)
    if ($wallets | Where-Object { $_.name -eq $name }) {
        Write-Host "⚠️ Wallet '$name' already exists."
        return
    }
    $wallet = [PSCustomObject]@{
        name    = $name
        address = [string](Get-Random -Maximum [int64]::MaxValue)
        balance = 100
    }
    $wallets += $wallet
    Save-Wallets $wallets
    Write-Host "✅ Wallet '$($wallet.name)' created!"
    Write-Host "   Address: $($wallet.address)"
    Write-Host "   Balance: $($wallet.balance) EAGL"
}

function Transfer($fromName, $toName, $amount) {
    $wallets = @() + (Load-Wallets)
    $from = $wallets | Where-Object { $_.name -eq $fromName }
    $to   = $wallets | Where-Object { $_.name -eq $toName }

    if (-not $from) { Write-Host "⚠️ Wallet '$fromName' not found"; return }
    if (-not $to)   { Write-Host "⚠️ Wallet '$toName' not found"; return }
    if ($from.balance -lt $amount) { Write-Host "⚠️ Insufficient balance"; return }

    $from.balance -= $amount
    $to.balance   += $amount
    Save-Wallets $wallets

    Write-Host "✅ Transferred $amount EAGL from '$fromName' to '$toName'."

    $payload = @{ from = $from.address; to = $to.address; amount = $amount } | ConvertTo-Json
    try {
        $res = Invoke-RestMethod -Uri "$NodeUrl/submit" -Method POST -Body $payload -ContentType "application/json"
        if ($res.result -eq "accepted") {
            Write-Host "📤 Transaction submitted. New block height: $($res.height)"
        } else {
            Write-Host "⚠️ Node rejected transaction:"
            $res | ConvertTo-Json -Depth 5
        }
    } catch {
        Write-Host "❌ Failed to submit to node: $_"
    }
}

function List-Wallets {
    $wallets = Load-Wallets
    if ($wallets.Count -eq 0) { Write-Host "Wallets: (none)"; return }
    foreach ($w in $wallets) {
        Write-Host " - $($w.name): $($w.balance) EAGL (Address: $($w.address))"
    }
}

function Node-Status {
    try {
        $res = Invoke-RestMethod -Uri "$NodeUrl/status" -Method GET
        Write-Host "✅ Node: $($res.status) — Blocks: $($res.blocks)"
    } catch {
        Write-Host "❌ Node offline."
    }
}

function Node-Chain {
    try {
        $res = Invoke-RestMethod -Uri "$NodeUrl/chain" -Method GET
        $res | ConvertTo-Json -Depth 5
    } catch {
        Write-Host "❌ Node offline."
    }
}

# === CLI ===
while ($true) {
    Write-Host -NoNewline "EAGL>: "
    $input = Read-Host
    if (-not $input) { continue }
    $args = $input -split "\s+"

    switch ($args[0].ToLower()) {
        "create" { if ($args.Count -gt 1) { Create-Wallet $args[1] } else { Write-Host "Usage: create <name>" } }
        "list" { List-Wallets }
        "transfer" {
            if ($args.Count -lt 4) { Write-Host "Usage: transfer <from> <to> <amount>"; continue }
            [double]$amt = $args[3]
            Transfer $args[1] $args[2] $amt
        }
        "node" {
            if ($args.Count -lt 2) { Write-Host "Usage: node <status|chain>"; continue }
            if ($args[1] -eq "status") { Node-Status }
            elseif ($args[1] -eq "chain") { Node-Chain }
        }
        "exit" { break }
        default { Write-Host "Unknown command." }
    }
}
