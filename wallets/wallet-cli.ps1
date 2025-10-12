#!/usr/bin/env pwsh
<#
    EAGLCOIN wallet-cli.ps1
    Minimal interactive wallet CLI for local testnet node.
    - Place in C:\rocke\EAGLCOIN\cli\wallet-cli.ps1
    - Data stored in ./wallets/wallets.json (created automatically)
#>

# --- Configuration ---
$Root = Split-Path -Parent $PSScriptRoot      # script folder's parent (cli/)
$WalletsDir = Join-Path $Root "wallets"
$WalletsFile = Join-Path $WalletsDir "wallets.json"

# Node config (adjust if your node uses a different port)
$NodeHost = "http://127.0.0.1:21801"

# Ensure directory exists
if (-not (Test-Path $WalletsDir)) {
    New-Item -Path $WalletsDir -ItemType Directory | Out-Null
}

# --- Helper functions for JSON (wallets stored as an array) ---
function Load-Wallets {
    if (-not (Test-Path $WalletsFile)) { return @() }
    try {
        $text = Get-Content -Path $WalletsFile -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($text)) { return @() }
        $objs = $text | ConvertFrom-Json -ErrorAction Stop
        # Convert single object to array if needed
        if ($null -eq $objs) { return @() }
        if ($objs -is [System.Array]) { return $objs } else { return ,$objs }
    } catch {
        Write-Host "⚠️ Error reading $WalletsFile: $($_.Exception.Message)"
        return @()
    }
}

function Save-Wallets([object[]]$wallets) {
    try {
        $json = $wallets | ConvertTo-Json -Depth 5
        $json | Out-File -FilePath $WalletsFile -Encoding UTF8
        return $true
    } catch {
        Write-Host "❌ Error writing $WalletsFile: $($_.Exception.Message)"
        return $false
    }
}

# --- Wallet utilities ---
function Find-WalletByName($name, [object[]]$wallets) {
    return $wallets | Where-Object { $_.name -ieq $name } | Select-Object -First 1
}

function Create-Wallet($name, [decimal]$initial = 100) {
    $wallets = Load-Wallets
    if (Find-WalletByName -name $name -wallets $wallets) {
        Write-Host "❌ Wallet '$name' already exists."
        return
    }

    # simple address generator (not crypto-secure; for testnet only)
    $addr = (Get-Random -Minimum 100000000 -Maximum 999999999).ToString()

    $new = [PSCustomObject]@{
        name    = $name
        address = $addr
        balance = [decimal]$initial
    }

    $wallets += $new
    if (Save-Wallets -wallets $wallets) {
        Write-Host "✅ Wallet '$name' created!"
        Write-Host "   Address: $($new.address)"
        Write-Host "   Balance: $($new.balance) EAGL"
    } else {
        Write-Host "❌ Failed to save wallet."
    }
}

function List-Wallets {
    $wallets = Load-Wallets
    if ($wallets.Count -eq 0) {
        Write-Host "Wallets: (none)"
        return
    }
    Write-Host "Wallets:"
    foreach ($w in $wallets) {
        Write-Host ("  {0,-12} {1,-12} {2,8} EAGL" -f $w.name, $w.address, $w.balance)
    }
}

function Show-Balance($name) {
    $wallets = Load-Wallets
    $w = Find-WalletByName -name $name -wallets $wallets
    if (-not $w) { Write-Host "❌ Wallet '$name' not found."; return }
    Write-Host "Balance of $($w.name): $($w.balance) EAGL"
}

function Transfer($from, $to, [decimal]$amount) {
    if ($amount -le 0) { Write-Host "❌ Amount must be positive."; return }

    $wallets = Load-Wallets
    $wf = Find-WalletByName -name $from -wallets $wallets
    $wt = Find-WalletByName -name $to -wallets $wallets

    if (-not $wf) { Write-Host "❌ Sender '$from' not found."; return }
    if (-not $wt) { Write-Host "❌ Receiver '$to' not found."; return }

    if ($wf.balance -lt $amount) { Write-Host "❌ Insufficient funds."; return }

    # Subtract/add and persist
    $wf.balance = [decimal]($wf.balance - $amount)
    $wt.balance = [decimal]($wt.balance + $amount)

    # Save
    if (Save-Wallets -wallets $wallets) {
        Write-Host "✅ Transferred $amount EAGL from '$from' to '$to'."
        # Optionally submit to node so it's "on-chain"
        try {
            $payload = @{ from = $wf.address; to = $wt.address; amount = $amount } | ConvertTo-Json
            $resp = Invoke-RestMethod -Method Post -Uri ($NodeHost.TrimEnd('/') + "/submit") -Body $payload -ContentType "application/json" -ErrorAction Stop
            if ($resp.result -eq "accepted") {
                Write-Host "📤 Transaction submitted to node. New block height: $($resp.height)"
            } else {
                Write-Host "⚠️ Node response: $($resp | Out-String)"
            }
        } catch {
            Write-Host "⚠️ Node submit failed: $($_.Exception.Message) — transaction kept locally."
        }
    } else {
        Write-Host "❌ Failed to update wallets file."
    }
}

# --- Node integration helpers ---
function Node-Status {
    try {
        $resp = Invoke-RestMethod -Uri ($NodeHost.TrimEnd('/') + "/status") -Method Get -ErrorAction Stop
        Write-Host "✅ Node status: $($resp.status) — blocks: $($resp.blocks) — port: $($resp.port)"
    } catch {
        Write-Host "❌ Node offline or unreachable at $NodeHost. ($($_.Exception.Message))"
    }
}

function Node-Chain {
    try {
        $resp = Invoke-RestMethod -Uri ($NodeHost.TrimEnd('/') + "/chain") -Method Get -ErrorAction Stop
        # Pretty-print JSON output
        $resp | ConvertTo-Json -Depth 5 | Out-Host
    } catch {
        Write-Host "❌ Failed to fetch chain: $($_.Exception.Message)"
    }
}

function Node-SubmitTx($fromName, $toName, [decimal]$amount) {
    $wallets = Load-Wallets
    $wf = Find-WalletByName -name $fromName -wallets $wallets
    $wt = Find-WalletByName -name $toName -wallets $wallets
    if (-not $wf -or -not $wt) { Write-Host "❌ Sender or receiver not found."; return }
    $payload = @{ from = $wf.address; to = $wt.address; amount = $amount } | ConvertTo-Json
    try {
        $resp = Invoke-RestMethod -Method Post -Uri ($NodeHost.TrimEnd('/') + "/submit") -Body $payload -ContentType "application/json" -ErrorAction Stop
        Write-Host "📤 Node response: $($resp | ConvertTo-Json -Depth 2)"
    } catch {
        Write-Host "❌ Submit failed: $($_.Exception.Message)"
    }
}

# --- Interactive loop ---
Write-Host "EAGLCOIN CLI - Type 'help' for commands (hidden by default)."

while ($true) {
    $raw = Read-Host -Prompt "EAGL>"
    if ($null -eq $raw) { continue }
    $line = $raw.Trim()
    if ($line -eq "") { continue }

    # Normalize spaces, split into tokens
    $parts = -split $line
    if ($parts.Length -eq 0) { continue }
    $cmd = $parts[0].ToLower()

    switch ($cmd) {
        "help" {
            Write-Host ""
            Write-Host "Commands:"
            Write-Host "  create <name>                  - Create new wallet (initial balance 100)"
            Write-Host "  list                           - List wallets"
            Write-Host "  balance <name>                 - Show wallet balance"
            Write-Host "  transfer <from> <to> <amount>  - Transfer EAGL (local + try submit to node)"
            Write-Host "  node status                    - Check node status"
            Write-Host "  node chain                     - Show chain from node"
            Write-Host "  node submit <from> <to> <amt>  - Submit tx to node (by wallet name)"
            Write-Host "  exit                           - Quit"
            Write-Host ""
        }

        "create" {
            if ($parts.Length -lt 2) { Write-Host "Usage: create <name>"; continue }
            $name = $parts[1]
            Create-Wallet -name $name
        }

        "list" {
            List-Wallets
        }

        "balance" {
            if ($parts.Length -lt 2) { Write-Host "Usage: balance <name>"; continue }
            Show-Balance -name $parts[1]
        }

        "transfer" {
            if ($parts.Length -lt 4) { Write-Host "Usage: transfer <from> <to> <amount>"; continue }
            $from = $parts[1]; $to = $parts[2]
            try {
                $amt = [decimal]::Parse($parts[3])
            } catch {
                Write-Host "❌ Invalid amount."
                continue
            }
            Transfer -from $from -to $to -amount $amt
        }

        "node" {
            if ($parts.Length -lt 2) { Write-Host "Usage: node <status|chain|submit>"; continue }
            $sub = $parts[1].ToLower()
            switch ($sub) {
                "status" { Node-Status }
                "chain"  { Node-Chain }
                "submit" {
                    if ($parts.Length -lt 5) { Write-Host "Usage: node submit <from> <to> <amount>"; continue }
                    $from = $parts[2]; $to = $parts[3]
                    try { $amt = [decimal]::Parse($parts[4]) } catch { Write-Host "Invalid amount."; continue }
                    Node-SubmitTx -fromName $from -toName $to -amount $amt
                }
                default { Write-Host "Unknown node command. Use: status | chain | submit" }
            }
        }

        "exit" { break }
        "quit" { break }

        default {
            Write-Host "[!] Unknown command. Type 'help'."
        }
    }
}

Write-Host "Goodbye."
