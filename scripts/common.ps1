function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [string[]]$ArgumentList = @()
    )

    & $Command @ArgumentList
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        $displayCommand = (@($Command) + $ArgumentList) -join " "
        throw "External command failed with exit code ${exitCode}: $displayCommand"
    }
}
