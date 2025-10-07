# wallet-node-cli.ps1
# Wallet + Node management CLI for testnet

$walletFile = "$PSScriptRoot\wallets.json"
$nodeFile = "$PSScriptRoot\node.conf"
$nodeProcess = $null

# --- Wallet Functions ---

if (Test-Path $walletFile) {
    $wallets = Get-Content $walletFile | ConvertFrom-Json
} else {
    $wallets = @{}
}

function Save-Wallets { $wallets | ConvertTo-Json -Depth 3 | Set-Content $walletFile }

function Create-Wallet {
    param([string]$Name, [string]$Password)
    if ($wallets.ContainsKey($Name)) { Write-Host "Wallet '$Name' already exists."; return }
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($bytes)
    $pwdBytes = [System.Text.Encoding]::UTF8.GetBytes($Password.PadRight(32).Substring(0,32))
    $encBytes = for ($i=0; $i -lt $bytes.Length; $i++) { $bytes[$i] -bxor $pwdBytes[$i] }
    $encKey = [System.Convert]::ToBase64String($encBytes)
    $wallets[$Name] = @{ PrivateKey = $encKey; Balance = 1000 } # starting test balance
    Save-Wallets
    Write-Host "Wallet '$Name' created successfully."
}

function List-Wallets {
    if ($wallets.Count -eq 0) { Write-Host "No wallets found."; return }
    Write-Host "Wallets:"; foreach ($name in $wallets.Keys) { Write-Host "- $name" }
}

function Show-Balance { param([string]$Name)
    if (-not $wallets.ContainsKey($Name)) { Write-Host "Wallet '$Name' does not exist."; return }
    Write-Host "Balance of ${Name}: $($wallets[$Name].Balance)"
}

function Send-Tokens {
    param([string]$From, [string]$To, [int]$Amount)
    if (-not $wallets.ContainsKey($From)) { Write-Host "Sender wallet '$From' not found."; return }
    if (-not $wallets.ContainsKey($To)) { Write-Host "Recipient wallet '$To' not found."; return }
    if ($wallets[$From].Balance -lt $Amount) { Write-Host "Insufficient balance."; return }
    $wallets[$From].Balance -= $Amount
    $wallets[$To].Balance += $Amount
    Save-Wallets
    Write-Host "$Amount tokens sent from $From to $To."
}

# --- Node Functions ---

function Init-Node {
    if (Test-Path $nodeFile) { Write-Host "Node already initialized." }
    else {
        $conf = @{
            nodeName = "TestnetNode1"
            bindAddress = "0.0.0.0:9030"
            restApi = "127.0.0.1:9053"
        }
        $conf | ConvertTo-Json | Set-Content $nodeFile
        Write-Host "Node initialized with default testnet configuration."
    }
}

function Node-Status {
    if (-not (Test-Path $nodeFile)) { Write-Host "Node not initialized."; return }
    $conf = Get-Content $nodeFile | ConvertFrom-Json
    Write-Host "Node Name: $($conf.nodeName)"
    Write-Host "Bind Address: $($conf.bindAddress)"
    Write-Host "REST API: $($conf.restApi)"
    Write-Host "Status: Running? TBD"
}

function Node-Start {
    if (-not (Test-Path $nodeFile)) { Write-Host "Node not initialized. Run 'node init' first."; return }
    # Example placeholder - replace with actual node executable command
    Write-Host "Starting node..."
    $global:nodeProcess = Start-Process "powershell" -ArgumentList "-NoExit", "-Command", "Write-Host 'Node running...'; Start-Sleep -Seconds 99999" -PassThru
    Write-Host "Node started. PID: $($nodeProcess.Id)"
}

function Node-Stop {
    if ($null -ne $nodeProcess) { Stop-Process -Id $nodeProcess.Id; Write-Host "Node stopped." }
    else { Write-Host "Node process not running." }
}

# --- CLI Parsing ---
param(
    [string]$Command,
    [string]$Sub,
    [string]$Arg1,
    [string]$Arg2,
    [string]$Arg3
)

switch ($Command.ToLower()) {
    # Wallet commands
    "create" { Create-Wallet -Name $Arg1 -Password $Arg2 }
    "list" { List-Wallets }
    "balance" { Show-Balance -Name $Arg1 }
    "send" { Send-Tokens -From $Arg1 -To $Arg2 -Amount ([int]$Arg3) }

    # Node commands
    "node" {
        switch ($Sub.ToLower()) {
            "init" { Init-Node }
            "status" { Node-Status }
            "start" { Node-Start }
            "stop" { Node-Stop }
            default { Write-Host "Node commands: init, status, start, stop" }
        }
    }

    default {
        Write-Host "Commands:"
        Write-Host " Wallet: create <name> <pass>, list, balance <name>, send <from> <to> <amount>"
        Write-Host " Node: node init, node status, node start, node stop"
    }
}
