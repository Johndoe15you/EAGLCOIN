# ==============================
#  EAGLCOIN WALLET CLI v1.2
#  PowerShell-only Edition
# ==============================

# --- Wallet Storage ---
$walletFile = "$PSScriptRoot\wallets.json"
if (-Not (Test-Path $walletFile)) {
    @{} | ConvertTo-Json | Out-File $walletFile
}
$wallets = Get-Content $walletFile | ConvertFrom-Json

# --- Blockchain Storage ---
$chainFile = "$PSScriptRoot\blockchain.json"
if (-Not (Test-Path $chainFile)) {
    @(@{}) | ConvertTo-Json | Out-File $chainFile
}
$blockchain = Get-Content $chainFile | ConvertFrom-Json

# --- Save helpers ---
function Save-Wallets { $wallets | ConvertTo-Json | Out-File $walletFile }
function Save-Blockchain { $blockchain | ConvertTo-Json | Out-File $chainFile }

# --- Wallet Creation ---
function New-Wallet($Name) {
    if ($wallets.$Name) {
        Write-Host "Wallet '$Name' already exists."
        return
    }

    $addr = -join ((65..90 + 97..122 + 48..57) | Get-Random -Count 32 | ForEach-Object {[char]$_})
    $wallets | Add-Member -NotePropertyName $Name -NotePropertyValue ([ordered]@{
        Address = $addr
        Balance = 100
    })

    Save-Wallets
    Write-Host "Wallet '$Name' created with address $addr and 100 EAGL."
}

# --- Balance Check ---
function Get-Balance($Name) {
    if (-Not $wallets.$Name) {
        Write-Host "Wallet '$Name' not found."
        return
    }
    $bal = $wallets.$Name.Balance
    Write-Host "Balance of $Name: $bal EAGL"
}

# --- Token Transfer ---
function Send-Tokens($From, $To, [int]$Amount) {
    if (-Not $wallets.$From) { Write-Host "Sender not found."; return }
    if (-Not $wallets.$To) { Write-Host "Recipient not found."; return }
    if ($wallets.$From.Balance -lt $Amount) { Write-Host "Insufficient balance."; return }

    $wallets.$From.Balance -= $Amount
    $wallets.$To.Balance += $Amount
    Save-Wallets
    Write-Host "$Amount EAGL sent from $From to $To."
}

# --- Node / Mining Simulation ---
function Start-Mining($Miner) {
    if (-Not $wallets.$Miner) { Write-Host "Wallet '$Miner' not found."; return }
    $block = [ordered]@{
        Miner = $Miner
        Reward = 50
        Timestamp = (Get-Date)
        Height = $blockchain.Count
    }
    $blockchain += $block
    $wallets.$Miner.Balance += 50
    Save-Blockchain
    Save-Wallets
    Write-Host "Mined block #$($block.Height) — +50 EAGL to $Miner"
}

function Auto-Mine($Miner) {
    if (-Not $wallets.$Miner) { Write-Host "Wallet '$Miner' not found."; return }
    Write-Host "Auto-mining started for wallet '$Miner'. Press Ctrl+C to stop."
    while ($true) {
        Start-Mining $Miner
        Start-Sleep -Seconds 5
    }
}

# --- CLI Loop ---
while ($true) {
    $command = Read-Host "EAGLCLI>"

    switch -Regex ($command) {
        "^(exit|quit|q|bye)$" {
            Write-Host "Goodbye!"
            break
        }

        "^help$" {
            Write-Host @"
Commands:
  create <name>                    - Create new wallet
  balance <name>                   - Show wallet balance
  transfer <from> <to> <amount>    - Send EAGL
  node mine <miner>                - Mine one block
  node mine auto <miner>           - Auto-mine every 5s
  list                             - Show all wallets
  exit                             - Quit
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
            foreach ($w in $wallets.PSObject.Properties.Name) {
                $addr = $wallets.$w.Address
                $bal = $wallets.$w.Balance
                Write-Host "$w -> Address: $addr | Balance: $bal EAGL"
            }
        }

        default {
            Write-Host "Unknown command. Type 'help'."
        }
    } # end switch
} # end while
