# statusline.ps1 — Render a one-line session context from JSON piped from Claude Code session events
# Usage: someCommand | .\statusline.ps1
# Output: "repo-name branch* model context-usage%"

param(
    [Parameter(ValueFromPipeline=$true)]
    [string]$JsonInput
)

# Collect all piped input lines into a single string
begin {
    $allInput = ""
}

process {
    $allInput += $JsonInput
    if ($allInput) { $allInput += "`n" }
}

end {
    # Try to parse the JSON; handle empty input gracefully
    if (-not $allInput -or $allInput.Trim().Length -eq 0) {
        Write-Host "[no session data]"
        exit 0
    }

    try {
        $session = $allInput | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        # If JSON parse fails, output a minimal diagnostic
        Write-Host "[parse error]"
        exit 0
    }

    # Extract project/repo name: git root basename or fallback to pwd basename
    $projectName = ""
    try {
        # Try to get the git root directory
        $gitRoot = git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $gitRoot) {
            $projectName = Split-Path -Leaf $gitRoot
        }
    }
    catch {}

    # Fallback to current working directory basename if git failed
    if (-not $projectName) {
        $projectName = Split-Path -Leaf (Get-Location).Path
    }

    # Extract git branch and dirty status
    $branchName = ""
    $isDirty = ""
    try {
        $branchName = git rev-parse --abbrev-ref HEAD 2>$null
        if ($LASTEXITCODE -ne 0) { $branchName = "" }

        # Check for uncommitted changes (dirty working tree)
        $status = git status --porcelain 2>$null
        if ($LASTEXITCODE -eq 0 -and $status) {
            $isDirty = "*"
        }
    }
    catch {}

    # Default branch if we couldn't get it
    if (-not $branchName) {
        $branchName = "(detached)"
    }

    # Extract model display name from session JSON (normalize vendor name away)
    $modelName = ""
    if ($session.model) {
        $modelName = $session.model
        # Strip vendor prefixes for display (optional, keeps the model tier if present)
        # e.g., "claude-opus-4-1-20250514" -> keep as-is (generic)
        # or "claude-haiku-4-5-20251001" -> keep as-is
    }
    if (-not $modelName) {
        $modelName = "(unknown)"
    }

    # Extract context window usage percentage
    $contextUsage = ""
    if ($session.usage) {
        if ($session.usage.inputTokens -and $session.usage.cacheCreationInputTokens -and $session.usage.contextWindow) {
            $totalUsed = $session.usage.inputTokens + $session.usage.cacheCreationInputTokens
            $contextWindow = $session.usage.contextWindow
            if ($contextWindow -gt 0) {
                $percentUsed = [math]::Round(($totalUsed / $contextWindow) * 100)
                $contextUsage = "$percentUsed%"
            }
        }
    }
    if (-not $contextUsage) {
        $contextUsage = "?%"
    }

    # Render the one-liner: "project branch* model context%"
    $oneLiner = "$projectName $branchName$isDirty $modelName $contextUsage"
    Write-Host $oneLiner
}
