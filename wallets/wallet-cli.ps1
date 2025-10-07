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
    } # end switch
} # end while
