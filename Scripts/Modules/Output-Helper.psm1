
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
        [string] $Message = "",
        [string] $Command = "",
        [string] $LineBreak = "`n",
        [ValidateSet( 'None', 'Red', 'Green', 'Yellow', 'Blue', 'Magenta', 'Cyan', 'White' )]
        [string] $Color = 'None'
    )

    $groupPrefix = $script:groupIndentation * $script:groupLevel;

    $formattedMessageLines = $Message -split '\r?\n' | ForEach-Object { "`e[$($script:colorCodes[$Color])m$($_)`e[0m" }
    $formattedMessage = $formattedMessageLines -join $LineBreak

    Write-Host "$($groupPrefix)$($Command)$($formattedMessage)"
}
Export-ModuleMember -Function Write-AlpacaOutput

function Write-AlpacaAnnotation {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Message,
        [ValidateSet('Notice', 'Warning', 'Error', 'Debug')]
        [string] $Annotation = 'Notice',
        [ValidateSet( 'None', 'Red', 'Green', 'Yellow', 'Blue', 'Magenta', 'Cyan', 'White' )]
        [string] $Color = 'None'
    )

    Write-AlpacaOutput -Message $Message `
                       -Command $script:annotationCommands[$Annotation] `
                       -LineBreak $script:annotationLineBreak `
                       -Color $Color
}
Export-ModuleMember -Function Write-AlpacaAnnotation

function Write-AlpacaNotice {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Message,
        [bool] $Annotation = $true
    )

    if ($Annotation) {
        Write-AlpacaAnnotation -Message $Message -Annotation "Notice" -Color "White"
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
        Write-AlpacaAnnotation -Message $Message -Annotation "Warning" -Color "Yellow"
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
        Write-AlpacaAnnotation -Message $Message -Annotation "Error" -Color "Red"
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
        Write-AlpacaAnnotation -Message $Message -Annotation "Debug" -Color "Blue"
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
        Write-AlpacaOutput -Message $Message -Command "::group::" 
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
        Write-AlpacaOutput -Message $Message -Command "::endgroup::"
    } else {
        $script:groupLevel = [Math]::Max($script:groupLevel - 1, 0)
        if ($Message) {
            Write-AlpacaOutput -Message $Message
        }
    }
}
Export-ModuleMember -Function Write-AlpacaGroupEnd
