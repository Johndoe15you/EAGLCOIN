# ===========================
#  EAGLCOIN Wallet CLI (v0.6)
# ===========================

# In-memory blockchain + wallets
$global:blockchain = @()
$global:wallets = @{}

function New-Block {
    param($PrevHash, $Transactions)
    $Block = [PSCustomObject]@{
        Index = $blockchain.Count
        Timestamp = (Get-Date)
        PrevHash = $PrevHash
        Transactions = $Transactions
        Hash = (Get-Random -Minimum 100000 -Maximum 999999).ToString()
    }
    $global:blockchain += $Block
    return $Block
}

function New-Wallet {
    param([string]$Name)
    if ($wallets.ContainsKey($Name)) {
        Write-Host "Wallet '$Name' already exists."
        return
    }
    $wallets[$Name] = [PSCustomObject]@{
        Address = (New-Guid).ToString()
        Balance = 100 # start with 100 EAGL
    }
    Write-Host "✅ Wallet '$Name' created. Address: $($wallets[$Name].Address)"
}

function Get-Balance {
    param([string]$Name)
    if ($wallets.ContainsKey($Name)) {
        Write-Host "💰 Balance of ${Name}: $($wallets[$Name].Balance) EAGL"
    } else {
        Write-Host "Wallet '${Name}' not found."
    }
}

function Send-Tokens {
    param([string]$From, [string]$To, [int]$Amount)
    if (-not $wallets.ContainsKey($From) -or -not $wallets.ContainsKey($To)) {
        Write-Host "❌ Invalid wallet(s)."
        return
    }
    if ($wallets[$From].Balance -lt $Amount) {
        Write-Host "❌ Insufficient funds."
        return
    }

    $wallets[$From].Balance -= $Amount
    $wallets[$To].Balance += $Amount

    $tx = [PSCustomObject]@{
        From = $From
        To = $To
        Amount = $Amount
    }
    New-Block -PrevHash ($blockchain[-1].Hash) -Transactions @($tx) | Out-Null
    Write-Host "✅ Transferred $Amount EAGL from '$From' to '$To'."
}

function Start-Mining {
    param([string]$Miner)
    if (-not $wallets.ContainsKey($Miner)) {
        Write-Host "❌ Miner wallet not found."
        return
    }

    $reward = 10
    $wallets[$Miner].Balance += $reward
    $tx = [PSCustomObject]@{ From = "network"; To = $Miner; Amount = $reward }
    New-Block -PrevHash ($blockchain[-1].Hash) -Transactions @($tx) | Out-Null
    Write-Host "⛏️  Block mined! $reward EAGL added to '$Miner'."
}

function Auto-Mine {
    param([string]$Miner)
    Write-Host "⛏️  Starting auto-mining for '$Miner'... (Ctrl+C to stop)"
    while ($true) {
        Start-Mining -Miner $Miner
        Start-Sleep -Seconds 5
    }
}

# Genesis Block
if ($blockchain.Count -eq 0) {
    $genesis = New-Block -PrevHash "0" -Transactions @("Genesis Block")
    Write-Host "🪶 EAGL Blockchain initialized. Genesis hash: $($genesis.Hash)"
}

Write-Host "`nWelcome to the EAGLCOIN Wallet CLI 🦅"
Write-Host "Type 'help' for commands.`n"

# CLI Loop
while ($true) {
    $command = Read-Host "EAGLCLI>"

    switch -Regex ($command) {
        "^(exit|quit|q|bye)$" {
            Write-Host "👋 Goodbye!"
            break
        }

        "^help$" {
            Write-Host @"
Commands:
  create <name>          - Create new wallet
  balance <name>         - Show wallet balance
  transfer <from> <to> <amount> - Send EAGL
  node mine <miner>      - Mine one block
  node mine auto <miner> - Auto-mine every 5s
  list                   - Show all wallets
  exit                   - Quit
"@
        }

        "^create\s+(\S+)$" {
            New-Wallet $Matches[1]
        }

        "^balance\s+(\S+)$" {
            Get-Balance $Matches[1]
        }

        "^transfer\s+(\S+)\s+(\S+)\s+(\d+)$" {
            Send-Tokens $Matches[1] $Matches[2] [int]$Matches[3]
        }

        "^node\s+mine\s+auto\s+(\S+)$" {
            Auto-Mine $Matches[1]
        }

        "^node\s+mine\s+(\S+)$" {
            Start-Mining $Matches[1]
        }

        "^list$" {
            foreach ($w in $wallets.Keys) {
                Write-Host "$w → Address: $($wallets[$w].Address) | Balance: $($wallets[$w].Balance) EAGL"
            }
        }

        default {
            Write-Host "❓ Unknown command. Type 'help'."
        }
    }
}
