# Load blockchain file
$chainPath = Join-Path $PSScriptRoot "blockchain.json"
if (Test-Path $chainPath) {
    try {
        $chain = Get-Content $chainPath -Raw | ConvertFrom-Json
        # Ensure $chain is an array
        if ($null -eq $chain) { $chain = @() }
        elseif ($chain -isnot [System.Collections.IEnumerable]) { $chain = @($chain) }
    } catch {
        Write-Host "⚠️ Error reading blockchain.json: $_"
        $chain = @()
    }
} else {
    $chain = @()
}

# Function to add new block
function Add-Block($tx) {
    $block = [PSCustomObject]@{
        height    = ($chain.Count + 1)
        timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ssZ")
        from      = $tx.from
        to        = $tx.to
        amount    = [double]$tx.amount
        hash      = (Get-Random -Maximum 100000000).ToString("X")
    }

    # Force $chain to array form, then append block safely
    if ($chain -isnot [System.Collections.ArrayList]) {
        $chain = [System.Collections.ArrayList]@($chain)
    }
    [void]$chain.Add($block)

    # Save to file
    $chain | ConvertTo-Json -Depth 5 | Set-Content $chainPath
    Write-Host "💸 TX: $($tx.from) → $($tx.to) : $($tx.amount) EAGL (Block $($block.height))"
}

# Main loop (for receiving tx)
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:21801/")
$listener.Start()
Write-Host "🚀 EAGL Node started on port 21801"
Write-Host "Press Ctrl+C to stop."
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

while ($true) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $res = $ctx.Response
    if ($req.HttpMethod -eq "POST" -and $req.Url.AbsolutePath -eq "/tx") {
        $body = New-Object IO.StreamReader($req.InputStream)
        $json = $body.ReadToEnd() | ConvertFrom-Json
        Add-Block $json
        $response = @{ status = "ok" } | ConvertTo-Json
    }
    elseif ($req.Url.AbsolutePath -eq "/chain") {
        $response = $chain | ConvertTo-Json -Depth 5
    }
    else {
        $response = @{ error = "Unknown route" } | ConvertTo-Json
    }
    $buffer = [Text.Encoding]::UTF8.GetBytes($response)
    $res.ContentLength64 = $buffer.Length
    $res.OutputStream.Write($buffer, 0, $buffer.Length)
    $res.OutputStream.Close()
}
