# ---------------------------------------
# EAGLCOIN CLI - Interactive PowerShell
# ---------------------------------------

$walletFile = ".\wallets.json"

# Load wallets or initialize
if (Test-Path $walletFile) {
    $wallets = Get-Content $walletFile | ConvertFrom-Json
} else {
    $wallets = @{}
}

function Save-Wallets {
    $wallets | ConvertTo-Json -Depth 3 | Set-Content $walletFile
}

# ----------------------------
# Wallet Functions
# ----------------------------
function Create-Wallet($Name, $Password) {
    if ($wallets.$Name) {
        Write-Host "Wallet '$Name' already exists."
        return
    }
    $wallets.$Name = @{
        Password = $Password
        Balance  = 0
    }
    Save-Wallets
    Write-Host "Wallet '$Name' created."
}

function Show-Balance($Name) {
    if (-not $wallets.$Name) {
        Write-Host "Wallet '$Name' does not exist."
        return
    }
    $bal = $wallets.$Name.Balance
    Write-Host "Balance of ${Name}: ${bal} EAGL"
}

function Transfer-EAGL($From, $Password, $To, $Amount) {
    if (-not $wallets.$From) { Write-Host "Sender wallet '$From' not found."; return }
    if (-not $wallets.$To) { Write-Host "Recipient wallet '$To' not found."; return }
    if ($wallets.$From.Password -ne $Password) { Write-Host "Incorrect password."; return }
    if ($wallets.$From.Balance -lt $Amount) { Write-Host "Insufficient balance."; return }

    $wallets.$From.Balance -= $Amount
    $wallets.$To.Balance   += $Amount
    Save-Wallets
    Write-Host "$Amount EAGL transferred from ${From} to ${To}."
}

function List-Wallets {
    foreach ($w in $wallets.PSObject.Properties.Name) {
        $bal = $wallets.$w.Balance
        Write-Host "$w : $bal EAGL"
    }
}

# ----------------------------
# Node Functions
# ----------------------------
function Start-Node { Write-Host "Node started (simulated)." }
function Stop-Node  { Write-Host "Node stopped (simulated)." }
function Node-Status { Write-Host "Node status: running (simulated)." }

function Mine-Block($Miner) {
    if (-not $wallets.$Miner) { Write-Host "Miner wallet '$Miner' not found."; return }
    $wallets.$Miner.Balance += 10
    Save-Wallets
    Write-Host "Mined 1 block. $Miner received 10 EAGL."
}

function Auto-Mine($Miner) {
    if (-not $wallets.$Miner) { Write-Host "Miner wallet '$Miner' not found."; return }
    Write-Host "Auto-mining every 5s. Press Ctrl+C to stop."
    while ($true) {
        Mine-Block $Miner
        Start-Sleep -Seconds 5
    }
}

function Node-Command($Args) {
    if ($Args.Count -eq 0) {
        Write-Host "Node management options: start | stop | status | mine <miner> | mine auto <miner>"
        return
    }

    switch ($Args[0].ToLower()) {
        "start"  { Start-Node }
        "stop"   { Stop-Node }
        "status" { Node-Status }
        "mine" {
            if ($Args.Count -eq 2) { Mine-Block $Args[1] }
            elseif ($Args.Count -eq 3 -and $Args[1].ToLower() -eq "auto") { Auto-Mine $Args[2] }
            else { Write-Host "Invalid mine command. Usage: mine <miner> | mine auto <miner>" }
        }
        default { Write-Host "Unknown node command." }
    }
}

# ----------------------------
# Interactive Loop
# ----------------------------
Write-Host "EAGLCOIN CLI - Interactive Mode"
Write-Host "Type 'help' for commands, 'exit' to quit."
while ($true) {
    $command = Read-Host "EAGL>"

    switch -Regex ($command) {
        "^help$" {
            Write-Host @"
Commands:
  create [name]                    - Create new wallet
  balance [name]                   - Show wallet balance
  transfer [from] [to] [amount]    - Send EAGL
  node [start|stop|status|mine]    - Node management
  list                             - Show all wallets
  exit                             - Quit
"@
        }

        "^create\s+(\w+)\s+(\S+)$" { Create-Wallet $matches[1] $matches[2] }
        "^balance\s+(\w+)$"        { Show-Balance $matches[1] }
        "^transfer\s+(\w+)\s+(\w+)\s+(\d+)$" { Transfer-EAGL $matches[1] $matches[2] $matches[3] $matches[4] }
        "^list$"                    { List-Wallets }
        "^node\s*(.*)$" {
            $args = @()
            if ($matches[1]) { $args = $matches[1].Trim() -split '\s+' }
            Node-Command $args
        }
        "^(exit|quit|q|bye)$" { break }
        default { Write-Host "Unknown command. Type 'help'." }
    }
}
