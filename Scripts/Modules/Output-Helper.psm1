
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
$script:annotationColors = @{
    Notice = 'White'
    Warning = 'Yellow'
    Error = 'Red'
    Debug = 'Blue'
}
$script:annotationGitHubCommands = @{
    Notice = '::notice::'
    Warning = '::warning::'
    Error = '::error::'
    Debug = '::debug::'
}
$script:annotationGitHubLineBreak = '%0A'

# Groups
$script:groupIndentation = "  "
$script:groupLevel = 0

function Format-AlpacaMessage {
    Param(
        [string] $Message = "",
        [ValidateSet( 'None', 'Red', 'Green', 'Yellow', 'Blue', 'Magenta', 'Cyan', 'White' )]
        [string] $Color = 'None',
        [string] $LinePrefix = "",
        [string] $LineBreak = "`n"
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $Message
    }

    $messageLines = $Message -split '\r?\n'
    $formattedMessageLines = $messageLines |
        ForEach-Object { "`e[$($script:colorCodes[$Color])m$($LinePrefix)$($_)`e[0m" }
    $formattedMessage = $formattedMessageLines -join $LineBreak

    return $formattedMessage
}
Export-ModuleMember -Function Format-AlpacaMessage

function Write-AlpacaOutput {
    Param(
        [string] $Message = "",
        [ValidateSet( 'None', 'Red', 'Green', 'Yellow', 'Blue', 'Magenta', 'Cyan', 'White' )]
        [string] $Color = 'None'
    )

    $linePrefix = $script:groupIndentation * $script:groupLevel;

    $formattedMessage = Format-AlpacaMessage -Message $Message -Color $Color -LinePrefix $linePrefix

    Write-Host $formattedMessage
}
Export-ModuleMember -Function Write-AlpacaOutput

function Write-AlpacaAnnotation {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Message,
        [ValidateSet('Notice', 'Warning', 'Error', 'Debug')]
        [string] $Annotation = 'Notice',
        [switch] $WithoutGitHubAnnotation
    )
    $color = $script:annotationColors[$Annotation]

    if ($WithoutGitHubAnnotation) {
        $formattedMessage = Format-AlpacaMessage -Message "$($Annotation): $($Message)" -Color $color
    } else {
        $formattedMessage = Format-AlpacaMessage -Message $Message -Color $color -LineBreak $script:annotationGitHubLineBreak
        $formattedMessage = "$($script:annotationGitHubCommands[$Annotation])$formattedMessage"
    }

    Write-Host $formattedMessage
}
Export-ModuleMember -Function Write-AlpacaAnnotation

function Write-AlpacaNotice {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Message,
        [switch] $WithoutGitHubAnnotation
    )

    Write-AlpacaAnnotation -Message $Message -Annotation "Notice" -WithoutGitHubAnnotation:$WithoutGitHubAnnotation
}
Export-ModuleMember -Function Write-AlpacaNotice

function Write-AlpacaWarning {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Message,
        [switch] $WithoutGitHubAnnotation
    )

    Write-AlpacaAnnotation -Message $Message -Annotation "Warning" -WithoutGitHubAnnotation:$WithoutGitHubAnnotation
}
Export-ModuleMember -Function Write-AlpacaWarning

function Write-AlpacaError {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Message,
        [switch] $WithoutGitHubAnnotation
    )

    Write-AlpacaAnnotation -Message $Message -Annotation "Error" -WithoutGitHubAnnotation:$WithoutGitHubAnnotation
}
Export-ModuleMember -Function Write-AlpacaError

function Write-AlpacaDebug {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Message,
        [switch] $WithoutGitHubAnnotation
    )

    Write-AlpacaAnnotation -Message $Message -Annotation "Debug" -WithoutGitHubAnnotation:$WithoutGitHubAnnotation
}
Export-ModuleMember -Function Write-AlpacaDebug

function Write-AlpacaGroupStart {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Message,
        [switch] $UseGitHubCommand
    )

    if ($UseGitHubCommand) {
        Write-Host "::group::$($Message)"
    } else {
        Write-AlpacaOutput -Message "> $Message"
        $script:groupLevel += 1
    }
}
Export-ModuleMember -Function Write-AlpacaGroupStart

function Write-AlpacaGroupEnd {
    Param(
        [string] $Message,
        [switch] $UseGitHubCommand
    )
    if ($UseGitHubCommand) {
        Write-Host "::endgroup::"
    } else {
        $script:groupLevel = [Math]::Max($script:groupLevel - 1, 0)
    }
    if ($Message) {
        Write-AlpacaOutput -Message $Message
    }
}
Export-ModuleMember -Function Write-AlpacaGroupEnd
