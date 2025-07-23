
# Colors
$script:colorCodes = @{
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
$script:annotationCommands = @{
    Notice = '::notice::'
    Warning = '::warning::'
    Error = '::error::'
    Debug = '::debug::'
}
$script:annotationLineBreak = '%0A'

# Groups
$script:groupIndentation = "  "
$script:groupLevel = 0

function Write-AlpacaOutput {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet( 'None', 'Red', 'Green', 'Yellow', 'Blue', 'Magenta', 'Cyan', 'White' )]
        [string] $Color = 'None'
    )

    $groupPrefix = $script:groupIndentation * $script:groupLevel;

    $Message -split '\r?\n' | 
        ForEach-Object {
            Write-Host "$($groupPrefix)" -NoNewline
            Write-Host "`e[$($script:colorCodes[$Color])m" -NoNewLine
            Write-Host "$_" -NoNewline
            Write-Host "`e[0m"
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

    $groupPrefix = $script:groupIndentation * $script:groupLevel;

    Write-Host "$($groupPrefix)$($script:annotationCommands[$Annotation])$($Message -replace '\r?\n', $script:annotationLineBreak)"
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

function Write-AlpacaGroupStart {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Message,
        [switch] $UseCommand
    )

    if ($UseCommand) {
        Write-AlpacaOutput -Message "::group::$Message"
    } else {
        Write-AlpacaOutput -Message "> $Message"
        $script:groupLevel += 1
    }
}
Export-ModuleMember -Function Write-AlpacaGroupStart

function Write-AlpacaGroupEnd {
    Param(
        [string] $Message,
        [switch] $UseCommand
    )
    if ($UseCommand) {
        Write-AlpacaOutput -Message "::endgroup::$Message"
    } else {
        $script:groupLevel = [Math]::Max($script:groupLevel - 1, 0)
        if ($Message) {
            Write-AlpacaOutput -Message "$Message"
        }
    }
}
Export-ModuleMember -Function Write-AlpacaGroupEnd
