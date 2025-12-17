
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
    Error   = 'Red'
}
$script:annotationGitHubCommands = @{
    Notice  = '::notice::'
    Warning = '::warning::'
    Error   = '::error::'
}
$script:annotationGitHubLineBreak = '%0A'

# Groups
$script:groupIndentation = "  "
$script:groupLevel = 0

function Format-AlpacaMessage {
    param(
        [Parameter(ValueFromPipeline  = $true)]
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
    param(
        [Parameter(ValueFromPipeline = $true)]
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
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string] $Message,
        [ValidateSet('Notice', 'Warning', 'Error')]
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
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string] $Message,
        [switch] $WithoutGitHubAnnotation
    )

    Write-AlpacaAnnotation -Message $Message -Annotation "Notice" -WithoutGitHubAnnotation:$WithoutGitHubAnnotation
}
Export-ModuleMember -Function Write-AlpacaNotice

function Write-AlpacaWarning {
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string] $Message,
        [switch] $WithoutGitHubAnnotation
    )

    Write-AlpacaAnnotation -Message $Message -Annotation "Warning" -WithoutGitHubAnnotation:$WithoutGitHubAnnotation
}
Export-ModuleMember -Function Write-AlpacaWarning

function Write-AlpacaError {
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string] $Message,
        [switch] $WithoutGitHubAnnotation
    )

    Write-AlpacaAnnotation -Message $Message -Annotation "Error" -WithoutGitHubAnnotation:$WithoutGitHubAnnotation
}
Export-ModuleMember -Function Write-AlpacaError

function Write-AlpacaDebug {
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string] $Message
    )
    if (-not (Get-AlpacaIsDebugMode)) {
        return
    }
    "Debug: {0}" -f $Message | Write-AlpacaOutput -Color 'Blue'
}
Export-ModuleMember -Function Write-AlpacaDebug

function Write-AlpacaGroupStart {
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
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
    param(
        [Parameter(ValueFromPipeline = $true)]
        [string] $Message,
        [switch] $UseGitHubCommand
    )
    if ($UseGitHubCommand) {
        Write-Host "::endgroup::"
    }
    else {
        $script:groupLevel = [Math]::Max($script:groupLevel - 1, 0)
    }
    if ($Message) {
        Write-AlpacaOutput -Message $Message
    }
}
Export-ModuleMember -Function Write-AlpacaGroupEnd

function Get-AlpacaIsDebugMode {
    return $env:RUNNER_DEBUG -eq '1' -or $env:GITHUB_RUN_ATTEMPT -gt 1
}
Export-ModuleMember -Function Get-AlpacaIsDebugMode