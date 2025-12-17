
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
        # No byte limit specified, return original lines
        return $lines
    }

    foreach ($line in $lines) {
        $lineBytes = [System.Text.Encoding]::UTF8.GetBytes("$line")

        # Split line if it exceeds byte limit
        while ($lineBytes.Length -gt $LineByteLimit) {
            $chunkByteCount = $LineByteLimit

            # Ensure we do not cut off in the middle of a UTF-8 character
            # Check if we're cutting inside a multi-byte UTF-8 sequence (continuation byte: 10xxxxxx)
            # Start by checking the last byte after the limit and move backwards until non-continuation byte is found
            while ($chunkByteCount -gt 0 -and ($lineBytes[$chunkByteCount] -band 0xC0) -eq 0x80) {
                $chunkByteCount -= 1
            }

            if ($chunkByteCount -eq 0) {
                throw "Alpaca Message split failed: Unable to find valid UTF-8 character boundary within byte limit"
            }

            $chunkBytes = $lineBytes[0..($chunkByteCount - 1)]
            Write-Output ([System.Text.Encoding]::UTF8.GetString($chunkBytes))

            $lineBytes = $lineBytes[$chunkByteCount..($lineBytes.Length - 1)]
        }

        Write-Output ([System.Text.Encoding]::UTF8.GetString($lineBytes))
    }
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
    if ($date.Month -eq 12 -and $date.Day -in 24,25,26) {
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
    if ([System.Text.Encoding]::UTF8.GetByteCount("$annotationMessage") -le $gitHubAnnotationByteLimit) {
        # Fits within byte limit, write directly
        Write-Host $annotationMessage
        return
    }

    # Message exceeds byte limit, need to truncate

    $truncatedInfo = Format-AlpacaMessage -Message "--- Annotation truncated (see logs for full details) ---" -Color $color

    # Calculate byte counts of fixed parts
    $gitHubAnnotationLineBreakByteCount = [System.Text.Encoding]::UTF8.GetByteCount("$gitHubAnnotationLineBreak")
    $gitHubAnnotationCommandByteCount = [System.Text.Encoding]::UTF8.GetByteCount("$gitHubAnnotationCommand")
    $truncatedInfoByteCount = [System.Text.Encoding]::UTF8.GetByteCount("$truncatedInfo")
    $reservedByteCount = $gitHubAnnotationCommandByteCount + $gitHubAnnotationLineBreakByteCount + $truncatedInfoByteCount

    # Extract the chunk of the formatted message that fits within the byte limit (+ additional line break bytes in case chunk ends with line break)
    $formattedMessageBytes = [System.Text.Encoding]::UTF8.GetBytes("$formattedMessage")
    $chunkByteLimit = $gitHubAnnotationByteLimit - $reservedByteCount
    $chunkBytes = $formattedMessageBytes[0..($chunkByteLimit + $gitHubAnnotationLineBreakByteCount - 1)]
    $chunk = [System.Text.Encoding]::UTF8.GetString($chunkBytes)

    # Find last line break to avoid cutting lines in half
    $annotationMessageLength = $chunk.LastIndexOf($gitHubAnnotationLineBreak)
    if ($annotationMessageLength -gt 0) {
        # Line break found, split there
        $annotationMessage = $formattedMessage.Substring(0, $annotationMessageLength)
        $overflowMessage = $formattedMessage.Substring($annotationMessageLength + $gitHubAnnotationLineBreak.Length)
    } else {
        # No line break found, need to split first line
        # Get first line of original message
        $line = Split-AlpacaMessage -Message $Message | Select-Object -First 1
        # Calculate byte count added by formatting
        $formattedLine = Format-AlpacaMessage -Message $line -Color $color
        $formatByteCount = [System.Text.Encoding]::UTF8.GetByteCount("$formattedLine") - [System.Text.Encoding]::UTF8.GetByteCount("$line")
        # Extract chunk of first line that fits within byte limit
        $chunkByteLimit = $gitHubAnnotationByteLimit - $reservedByteCount - $formatByteCount
        $chunk = Split-AlpacaMessage -Message $line -LineByteLimit $chunkByteLimit | Select-Object -First 1

        # Create annotation message with chunk of first line
        $annotationMessage = Format-AlpacaMessage -Message $chunk -Color $color
        # Create overflow message with original formatted message
        $overflowMessage = $formattedMessage
    }

    $annotationMessage = "$($gitHubAnnotationCommand)$($annotationMessage)$($gitHubAnnotationLineBreak)$($truncatedInfo)"
    Write-Host $annotationMessage

    $overflowMessage = $overflowMessage -replace $gitHubAnnotationLineBreak, "`n"
    Write-Host $overflowMessage
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
