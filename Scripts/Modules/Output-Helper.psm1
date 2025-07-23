
# Colors
$colorCodes = @{
    None = '0'
    Red = '31'
    Green = '32'
    Yellow = '33'
    Blue = '34'
    Magenta = '35'
    Cyan = '36'
    White = '37'
}

# Annotations
$annotationCommands = @{
    Notice = '::notice::'
    Warning = '::warning::'
    Error = '::error::'
    Debug = '::debug::'
}
$annotationLineBreak = '%0A'

function Write-AlpacaOutput {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet( 'None', 'Red', 'Green', 'Yellow', 'Blue', 'Magenta', 'Cyan', 'White' )]
        [string] $Color = 'None'
    )

    $Message -split '\r?\n' | 
        ForEach-Object { 
            Write-Host "`e[$($colorCodes[$Color])m$_`e[0m"
        }
}
Export-ModuleMember -Function Write-AlpacaOutput

function Write-AlpacaAnnotation {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet('Notice', 'Warning', 'Error', 'Debug')]
        [string] $Annotation = 'Notice'
    )

    Write-Host "$($annotationCommands[$Annotation])$($Message -replace '\r?\n', $annotationLineBreak)"
}
Export-ModuleMember -Function Write-AlpacaAnnotation

function Write-AlpacaNotice {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Message,
        [bool] $Annotation = $true
    )

    if ($Annotation) {
        Write-AlpacaAnnotation -Message $Message -Annotation "Notice"
    } else {
        Write-AlpacaOutput -Message $Message -Color "White"
    }
}
Export-ModuleMember -Function Write-AlpacaNotice

function Write-AlpacaWarning {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Message,
        [bool] $Annotation = $true
    )

    if ($Annotation) {
        Write-AlpacaAnnotation -Message $Message -Annotation "Warning"
    } else {
        Write-AlpacaOutput -Message $Message -Color "Yellow"
    }
}
Export-ModuleMember -Function Write-AlpacaWarning

function Write-AlpacaError {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Message,
        [bool] $Annotation = $true
    )

    if ($Annotation) {
        Write-AlpacaAnnotation -Message $Message -Annotation "Error"
    } else {
        Write-AlpacaOutput -Message $Message -Color "Red"
    }
}
Export-ModuleMember -Function Write-AlpacaError

function Write-AlpacaDebug {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Message,
        [bool] $Annotation = $true
    )

    if ($Annotation) {
        Write-AlpacaAnnotation -Message $Message -Annotation "Debug"
    } else {
        Write-AlpacaOutput -Message $Message -Color "Blue"
    }
}
Export-ModuleMember -Function Write-AlpacaDebug
