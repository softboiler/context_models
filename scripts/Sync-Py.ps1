<#.SYNOPSIS
Sync Python dependencies.#>
Param(
    # Python version.
    [string]$Version,
    # Sync to highest dependencies.
    [switch]$High,
    # Perform minimal sync for release workflow.
    [switch]$Release
)

. scripts/Common.ps1
. scripts/Initialize-Shell.ps1

'****** SYNCING' | Write-Progress

'CHECKING ENVIRONMENT TYPE' | Write-Progress
$High = $High ? $High : [bool]$Env:SYNC_PY_HIGH
$CI = $Env:SYNC_PY_DISABLE_CI ? $null : $Env:CI
$Devcontainer = $Env:SYNC_PY_DISABLE_DEVCONTAINER ? $null : $Env:DEVCONTAINER
$Env:UV_SYSTEM_PYTHON = $CI ? 'true' : $null
if (!$Release -and $CI) { $msg = 'CI' }
elseif ($Devcontainer) { $msg = 'devcontainer' }
elseif ($Release) {$msg = 'release'}
"Will run $msg steps" | Write-Progress -Info

if ($Release) {
    "Finished $msg steps" | Write-Progress -Info
    '****** DONE ******' | Write-Progress -Done
    return
}

if (!$CI -and !$Devcontainer -and
    (Get-Command -Name 'code' -ErrorAction 'Ignore') -and
    ($Env:PYRIGHT_PYTHON_PYLANCE_VERSION)
) {
    'INSTALLING PYLANCE LOCALLY' | Write-Progress
    $LocalExtensions = '.vscode/extensions'
    $Pylance = 'ms-python.vscode-pylance'
    $Install = @(
        "--extensions-dir=$LocalExtensions",
        "--install-extension=$Pylance@$Env:PYRIGHT_PYTHON_PYLANCE_VERSION"
    )
    code @Install
    if (!(Test-Path $LocalExtensions)) {
        'COULD NOT INSTALL PYLANCE LOCALLY' | Write-Progress -Info
        'PROCEEDING WITHOUT LOCAL PYLANCE INSTALL' | Write-Progress -Done
    }
    else {
        $PylanceExtension = Get-ChildItem -Path $LocalExtensions -Filter "$Pylance-*"
        # Remove other files
        Get-ChildItem -Path $LocalExtensions |
            Where-Object { Compare-Object $_ $PylanceExtension } |
            Remove-Item -Recurse
        # Remove local Pylance bundled stubs
        $PylanceExtension |
            ForEach-Object { Get-ChildItem "$_/dist/bundled" -Filter '*stubs' } |
            Remove-Item -Recurse
        'INSTALLED PYLANCE LOCALLY' | Write-Progress -Done
    }
}
'*** RUNNING PRE-SYNC TASKS' | Write-Progress
if ($CI) {
    'SYNCING PROJECT WITH TEMPLATE' | Write-Progress
    context_models_tools elevate-pyright-warnings
    try { scripts/Sync-Template.ps1 -Stay } catch [System.Management.Automation.NativeCommandExitException] {
        git stash save --include-untracked
        scripts/Sync-Template.ps1 -Stay
        git stash pop
        git add .
    }
    'PROJECT SYNCED WITH TEMPLATE' | Write-Progress
}
if ($Devcontainer) {
    $repo = Get-ChildItem '/workspaces'
    $submodules = Get-ChildItem "$repo/submodules"
    $safeDirs = @($repo) + $submodules
    foreach ($dir in $safeDirs) {
        if (!($safeDirs -contains $dir)) { git config --global --add safe.directory $dir }
    }
}
if (!$CI) {
    'SYNCING SUBMODULES' | Write-Progress
    Get-ChildItem '.git/modules' -Filter 'config.lock' -Recurse -Depth 1 | Remove-Item
    git submodule update --init --merge
    'SUBMODULES SYNCED' | Write-Progress -Done
    '' | Write-Host
}
'*** PRE-SYNC DONE ***' | Write-Progress -Done

'SYNCING DEPENDENCIES' | Write-Progress
context_models_tools compile $($High ? '--high' : '--no-high') | uv pip sync -
'DEPENDENCIES SYNCED' | Write-Progress -Done

'*** RUNNING POST-SYNC TASKS' | Write-Progress
if (!$CI) {
    'INSTALLING PRE-COMMIT HOOKS' | Write-Progress
    pre-commit install
    'PRE-COMMIT HOOKS INSTALLED' | Write-Progress -Done
    '' | Write-Host
}
'*** POST-SYNC DONE ***' | Write-Progress -Done
'' | Write-Host

'****** DONE ******' | Write-Progress -Done

# ? Stop PSScriptAnalyzer from complaining about these "unused" variables
$PSNativeCommandUseErrorActionPreference, $NoModifyPath | Out-Null
