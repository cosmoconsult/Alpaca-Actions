
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
$script:annotationGitHubByteLimit = 4096 # 4KB

# Groups
$script:groupIndentation = "  "
$script:groupLevel = 0

$script:xmasEmojis = @("🎄", "❄️", "⛄", "🎅", "🤶", "🦌", "🛷", "🎁", "🍪", "☃️")
$script:xmasEmojiLastUsed = $null

function Format-AlpacaMessage {
    Param(
        [string] $Message = "",
        [ValidateSet( 'None', 'Red', 'Green', 'Yellow', 'Blue', 'Magenta', 'Cyan', 'White' )]
        [string] $Color = 'None',
        [string] $LinePrefix = "",
        [string] $LineSuffix = "",
        [string] $LineBreak = "`n"
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $Message
    }

    if ($Color -ne 'None') {
        $LinePrefix = "`e[$($script:colorCodes[$Color])m$($LinePrefix)"
        $LineSuffix = "$($LineSuffix)`e[0m"
    }

    $messageLines = Split-AlpacaMessage -Message $Message
    $formattedMessageLines = $messageLines |
        ForEach-Object { "$($LinePrefix)$($_)$($LineSuffix)" }
    $formattedMessage = $formattedMessageLines -join $LineBreak

    return $formattedMessage
}
Export-ModuleMember -Function Format-AlpacaMessage

function Split-AlpacaMessage {
    Param(
        [string] $Message = "",
        [ValidateRange(0, [int]::MaxValue)]
        [int]    $LineByteLimit = 0
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $Message
    }

    $lines = $Message -split '\r?\n'

    if ($LineByteLimit -eq 0) {
        return $lines
    }

    $truncatedLines = @()
    foreach ($line in $lines) {
        $lineBytes = [System.Text.Encoding]::UTF8.GetBytes($line)

        while ($lineBytes.Length -gt $LineByteLimit) {
            $truncatedLineByteCount = $LineByteLimit

            # Ensure we do not cut off in the middle of a UTF-8 character
            # Check if we're cutting inside a multi-byte UTF-8 sequence (continuation byte: 10xxxxxx)
            # Start by checking the last byte after the limit and move backwards until non-continuation byte is found
            while ($truncatedLineByteCount -gt 0 -and ($lineBytes[$truncatedLineByteCount] -band 0xC0) -eq 0x80) {
                $truncatedLineByteCount -= 1
            }

            if ($truncatedLineByteCount -eq 0) {
                throw "Alpaca Message split failed: Unable to find valid UTF-8 character boundary within byte limit"
            }

            $truncatedLineBytes = $lineBytes[0..($truncatedLineByteCount - 1)]
            $truncatedLines += [System.Text.Encoding]::UTF8.GetString($truncatedLineBytes)

            $lineBytes = $lineBytes[$truncatedLineBytes.Length..($lineBytes.Length - 1)]
        }

        $truncatedLines += [System.Text.Encoding]::UTF8.GetString($lineBytes)
    }

    return $truncatedLines
}
Export-ModuleMember -Function Split-AlpacaMessage

function Write-AlpacaOutput {
    Param(
        [string] $Message = "",
        [ValidateSet( 'None', 'Red', 'Green', 'Yellow', 'Blue', 'Magenta', 'Cyan', 'White' )]
        [string] $Color = 'None'
    )

    $linePrefix = $script:groupIndentation * $script:groupLevel;
    $lineSuffix = ""

    $date = Get-Date
    if ($date.Month -eq 12 -and $date.Day -le 26) {
        $emoji = $null
        while ($emoji -in $null, $script:xmasEmojiLastUsed) {
            $emoji = $script:xmasEmojis | Get-Random
        }
        $script:xmasEmojiLastUsed = $emoji
        $lineSuffix = " $emoji"
    }

    $formattedMessage = Format-AlpacaMessage -Message $Message -Color $Color -LinePrefix $linePrefix -LineSuffix $lineSuffix

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
    if ($WithoutGitHubAnnotation) {
        $color = $script:annotationColors[$Annotation]
        $formattedMessage = Format-AlpacaMessage -Message "$($Annotation): $($Message)" -Color $color
        Write-Host $formattedMessage
    } else {
        Write-AlpacaGitHubAnnotation -Message $Message -Annotation $Annotation
    }
}
Export-ModuleMember -Function Write-AlpacaAnnotation

function Write-AlpacaGitHubAnnotation {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Message,
        [ValidateSet('Notice', 'Warning', 'Error', 'Debug')]
        [string] $Annotation = 'Notice'
    )
    $color = $script:annotationColors[$Annotation]

    $gitHubAnnotationCommand = $script:annotationGitHubCommands[$Annotation]
    $gitHubAnnotationLineBreak = $script:annotationGitHubLineBreak
    $gitHubAnnotationByteLimit = $script:annotationGitHubByteLimit

    # First, check if the entire message fits within the byte limit
    $formattedMessage = Format-AlpacaMessage -Message $Message -Color $color -LineBreak $gitHubAnnotationLineBreak
    $annotationMessage = "$($gitHubAnnotationCommand)$($formattedMessage)"
    if ([System.Text.Encoding]::UTF8.GetByteCount($annotationMessage) -le $gitHubAnnotationByteLimit) {
        # Fits within byte limit, write directly
        Write-Host $annotationMessage
        return
    }

    $gitHubAnnotationCommandByteCount = [System.Text.Encoding]::UTF8.GetByteCount($gitHubAnnotationCommand)
    $gitHubAnnotationLineBreakByteCount = [System.Text.Encoding]::UTF8.GetByteCount($gitHubAnnotationLineBreak)

    $truncatedInfo = Format-AlpacaMessage -Message "--- Truncated (see logs for full message) ---" -Color $color
    $truncatedInfoByteCount = [System.Text.Encoding]::UTF8.GetByteCount($truncatedInfo)

    $annotationLines = @()
    $annotationByteCount = 0
    $overflowLines = @()

    # Calculate reserved byte count for command and truncated info (<command>[message]<info>)
    $annotationByteCount = $gitHubAnnotationCommandByteCount + $gitHubAnnotationLineBreakByteCount + $truncatedInfoByteCount

    # Split message into lines
    $line, $lines = Split-AlpacaMessage -Message $Message

    # Process first line separately to handle if it exceeds byte limit
    $formattedLine = Format-AlpacaMessage -Message $line -Color $color
    $formattedLineByteCount = [System.Text.Encoding]::UTF8.GetByteCount("$formattedLine")
    if ($annotationByteCount + $formattedLineByteCount -ge $gitHubAnnotationByteLimit) {
        # First line exceeds byte limit, split further
        $formatByteCount = $formattedLineByteCount - [System.Text.Encoding]::UTF8.GetByteCount("$line")
        $splitByteCount = $gitHubAnnotationByteLimit - $annotationByteCount - $formatByteCount
        if ($splitByteCount -ge 1) {
            # Split the line and add first part to annotation
            $splitLine, $null = Split-AlpacaMessage -Message $line -LineByteLimit $splitByteCount
            $annotationLines += Format-AlpacaMessage -Color $color -Message $splitLine
            $annotationByteCount += [System.Text.Encoding]::UTF8.GetByteCount($splitLine)
        }
        # Add full line to overflow
        $overflowLines += $formattedLine
    } else {
        # First line fits, add to annotation
        $annotationLines += $formattedLine
        $annotationByteCount += $formattedLineByteCount
    }

    # Process remaining lines
    foreach ($line in $lines) {
        $formattedLine = Format-AlpacaMessage -Message $line -Color $color
        $formattedLineByteCount = [System.Text.Encoding]::UTF8.GetByteCount($formattedLine)
        if ($overflowLines.Count -gt 0) {
            # Already in overflow, add line to overflow
            $overflowLines += $formattedLine
        } elseif ($annotationByteCount + $gitHubAnnotationLineBreakByteCount + $formattedLineByteCount -le $gitHubAnnotationByteLimit) {
            # Line fits, add to annotation
            $annotationLines += $formattedLine
            $annotationByteCount += $gitHubAnnotationLineBreakByteCount + $formattedLineByteCount
        } else {
            # Line exceeds byte limit, add to overflow
            $overflowLines += $formattedLine
        }
    }

    if ($annotationLines) {
        $annotationLines += $truncatedInfo
        $annotationMessage = "$($gitHubAnnotationCommand)$($annotationLines -join $gitHubAnnotationLineBreak)"
        Write-Host $annotationMessage
    }
    if ($overflowLines) {
        $overflowMessage = $overflowLines -join "`n"
        Write-Host $overflowMessage
    }
}
Export-ModuleMember -Function Write-AlpacaGitHubAnnotation
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
