function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [string[]]$ArgumentList = @(),

        [string]$SafeLabel = $Command
    )

    & $Command @ArgumentList
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw "External command '$SafeLabel' failed with exit code ${exitCode}."
    }
}
