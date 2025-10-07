# wallet-cli.ps1
# EAGLCOIN CLI - PowerShell

$WalletFile = ".\wallets\wallets.json"
$BlockchainFile = ".\wallets\blocks.json"
$PendingTransactions = @()
$NodeRunning = $false

# Ensure files exist
if (-not (Test-Path $WalletFile)) { "{}" | Out-File $WalletFile -Encoding UTF8 }
if (-not (Test-Path $BlockchainFile)) { 
    @(@{
        Index = 0
        Timestamp = (Get-Date).ToString("o")
        PreviousHash = "0"
        Transactions = @()
        Miner = "Genesis"
        Nonce = 0
        Hash = "0"
    }) | ConvertTo-Json -Depth 5 | Out-File $BlockchainFile -Encoding UTF8
}

# Load wallets
function Load-Wallets { 
    return Get-Content $WalletFile | ConvertFrom-Json 
}
function Save-Wallets ($wallets) { 
    $wallets | ConvertTo-Json -Depth 5 | Out-File $WalletFile -Encoding UTF8
}

# Load blockchain
function Load-Blockchain { 
    return Get-Content $BlockchainFile | ConvertFrom-Json 
}
function Save-Blockchain ($chain) { 
    $chain | ConvertTo-Json -Depth 5 | Out-File $BlockchainFile -Encoding UTF8
}

# Hash function
function Get-Hash ($input) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($input)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash($bytes)
    return ($hash | ForEach-Object { $_.ToString("x2") }) -join ''
}

# Create new block
function New-Block {
    param(
        [string]$Miner,
        [array]$Transactions
    )
    $chain = Load-Blockchain
    $prevBlock = $chain[-1]

    $index = $prevBlock.Index + 1
    $timestamp = (Get-Date).ToString("o")
    $nonce = 0
    $blockContent = "$index$timestamp$($Transactions|ConvertTo-Json)$Miner$nonce$($prevBlock.Hash)"
    $hash = Get-Hash $blockContent

    return @{
        Index = $index
        Timestamp = $timestamp
        PreviousHash = $prevBlock.Hash
        Transactions = $Transactions
        Miner = $Miner
        Nonce = $nonce
        Hash = $hash
    }
}

# Add block to chain
function Add-BlockToChain ($block) {
    $chain = Load-Blockchain
    $chain += $block
    Save-Blockchain $chain
}

# Apply transactions to wallets
function Update-Wallets ($block) {
    $wallets = Load-Wallets
    foreach ($tx in $block.Transactions) {
        $from = $tx.From
        $to = $tx.To
        $amt = [double]$tx.Amount

        if (-not $wallets.ContainsKey($from)) { continue }
        if (-not $wallets.ContainsKey($to)) { continue }

        $wallets[$from].Balance -= $amt
        $wallets[$to].Balance += $amt
    }

    # Mining reward: 10 $EAGL per block
    if (-not $wallets.ContainsKey($block.Miner)) { $wallets[$block.Miner] = @{ Balance = 0; EncryptedKey = "" } }
    $wallets[$block.Miner].Balance += 10

    Save-Wallets $wallets
}

# CLI Commands
function Create-Wallet {
    param($Name, $Password)
    $wallets = Load-Wallets
    if ($wallets.ContainsKey($Name)) { Write-Host "Wallet already exists"; return }
    $wallets[$Name] = @{ Balance = 0; EncryptedKey = $Password } # simple password storage for testnet
    Save-Wallets $wallets
    Write-Host "Wallet '$Name' created"
}

function List-Wallets {
    $wallets = Load-Wallets
    foreach ($w in $wallets.PSObject.Properties.Name) {
        Write-Host "$w : Balance = $($wallets[$w].Balance)"
    }
}

function Show-Balance {
    param($Name)
    $wallets = Load-Wallets
    if (-not $wallets.ContainsKey($Name)) { Write-Host "Wallet not found"; return }
    Write-Host "Balance of $Name: $($wallets[$Name].Balance)"
}

function Queue-Transfer {
    param($From, $Pass, $To, $Amount)
    $wallets = Load-Wallets
    if (-not $wallets.ContainsKey($From)) { Write-Host "Sender wallet not found"; return }
    if ($wallets[$From].EncryptedKey -ne $Pass) { Write-Host "Incorrect password"; return }
    if (-not $wallets.ContainsKey($To)) { Write-Host "Receiver wallet not found"; return }
    if ([double]$wallets[$From].Balance -lt [double]$Amount) { Write-Host "Insufficient funds"; return }

    $PendingTransactions += @{
        From = $From
        To = $To
        Amount = [double]$Amount
    }
    Write-Host "Transaction queued"
}

# Node commands
function Node-Start { $global:NodeRunning = $true; Write-Host "Node started" }
function Node-Stop { $global:NodeRunning = $false; Write-Host "Node stopped" }
function Node-Status { 
    Write-Host "Node running: $NodeRunning"
    $chain = Load-Blockchain
    Write-Host "Blockchain length: $($chain.Count) blocks"
}

function Start-AutoMine {
    param([string]$MinerWallet)
    if (-not $NodeRunning) { Write-Host "Start node first"; return }
    Write-Host "[Auto-Mining] Press Ctrl+C to stop"
    while ($true) {
        if ($PendingTransactions.Count -gt 0) {
            $block = New-Block -Miner $MinerWallet -Transactions $PendingTransactions
            Add-BlockToChain $block
            Update-Wallets $block
            $PendingTransactions.Clear()
            Write-Host "[Auto-Mining] Block #$($block.Index) mined!"
        } else { Start-Sleep -Seconds 2 }
    }
}

# Interactive CLI
Write-Host "EAGLCOIN CLI - Interactive Mode"
Write-Host "Type 'help' for commands, 'exit' to quit.`n"

while ($true) {
    $input = Read-Host "EAGL>"

    switch -Wildcard ($input.ToLower()) {
        "help" { 
            Write-Host "Commands:"
            Write-Host " create <WalletName> <Password>       - Create wallet"
            Write-Host " list                                 - List wallets"
            Write-Host " balance <WalletName>                  - Show balance"
            Write-Host " transfer <From> <Pass> <To> <Amount> - Queue transaction"
            Write-Host " node start|stop|status|mine <Wallet> - Node commands"
            Write-Host " exit                                 - Quit CLI"
        }
        "exit" { break }
        "create "* { 
            $parts = $input.Split(" ")
            Create-Wallet $parts[1] $parts[2]
        }
        "list" { List-Wallets }
        "balance "* { 
            $parts = $input.Split(" ")
            Show-Balance $parts[1]
        }
        "transfer "* { 
            $parts = $input.Split(" ")
            Queue-Transfer $parts[1] $parts[2] $parts[3] $parts[4]
        }
        "node "* {
            $parts = $input.Split(" ")
            switch ($parts[1]) {
                "start" { Node-Start }
                "stop" { Node-Stop }
                "status" { Node-Status }
                "mine" { Start-AutoMine $parts[2] }
                default { Write-Host "Unknown node command" }
            }
        }
        default { Write-Host "Unknown command. Type 'help' for list" }
    }
}
