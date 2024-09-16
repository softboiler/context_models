<#
.SYNOPSIS
Initialization commands for PowerShell shells in pre-commit and tasks.#>

. scripts/Common.ps1

# ? Error-handling
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$ErrorView = 'NormalView'

# ? Fix leaky UTF-8 encoding settings on Windows
if ($IsWindows) {
    # Now PowerShell pipes will be UTF-8. Note that fixing it from Control Panel and
    # system-wide has buggy downsides.
    # See: https://github.com/PowerShell/PowerShell/issues/7233#issuecomment-640243647
    [console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
}

# ? Environment setup
function Set-Env {
    <#.SYNOPSIS
    Activate virtual environment and set environment variables.#>

    Param([string]$Version = $(Get-Content '.copier-answers.yml' |
                Find-Pattern '^python_version:\s?["'']([^"'']+)["'']$' |
                Find-Pattern '^([^.]+\.[^.]+).*$')
    )

    # ? Sync the virtual environment
    Sync-Uv
    if (!$CI) {
        if (!(Test-Path '.venv')) { uv venv --python $Version }
        if ($IsWindows) { .venv/scripts/activate.ps1 } else { .venv/bin/activate.ps1 }
        if (!(python --version | Select-String -Pattern $([Regex]::Escape($Version)))) {
            'Virtual environment is the wrong Python version.' | Write-Progress -Info
            'Creating virtual environment with correct Python version' | Write-Progress
            Remove-Item -Recurse -Force $Env:VIRTUAL_ENV
            uv venv --python $Version
            if ($IsWindows) { .venv/scripts/activate.ps1 } else { .venv/bin/activate.ps1 }
        }
    }
    if (!(Get-Command 'context_models_tools' -ErrorAction 'Ignore')) {
        'Installing tools' | Write-Progress
        $Env:UV_TOOL_BIN_DIR = Get-Item 'bin'
        uv tool install --force --python $Version --resolution 'lowest-direct' 'scripts/.'
        'Tools installed' | Write-Progress -Done
    }

    # ? Set environment variables
    $EnvVars = @{}
    context_models_tools init-shell |
        Select-String -Pattern '^(.+)=(.+)$' |
        ForEach-Object {
            $EnvVars.Add($_.Matches.Groups[1].Value, $_.Matches.Groups[2].Value)
        }
    $Keys = @()
    $EnvFile = $Env:GITHUB_ENV ? $Env:GITHUB_ENV : '.env'
    if (!(Test-Path $EnvFile)) { New-Item $EnvFile }
    $Lines = Get-Content $EnvFile | ForEach-Object {
        $_ -replace '^(?<Key>.+)=(?<Value>.+)$', {
            $Key = $_.Groups['Key'].Value
            if ($EnvVars.ContainsKey($Key)) {
                $Keys += $Key
                return "$Key=$($EnvVars[$Key])"
            }
            return $_
        }
    }
    $NewLines = $EnvVars.GetEnumerator() | ForEach-Object {
        $Key, $Value = $_.Key, $_.Value
        Set-Item "Env:$Key" $Value
        if (($Key.ToLower() -ne 'path') -and ($Keys -notcontains $Key)) {
            return "$Key=$Value"
        }
    }
    @($Lines, $NewLines) | Set-Content $EnvFile
}

Set-Env
