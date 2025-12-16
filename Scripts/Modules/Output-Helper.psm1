
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
        [string] $LineSuffix = "",
        [string] $LineBreak = "`n",
        [int]    $LineByteLimit = 0
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $Message
    }

    $LinePrefix = "`e[$($script:colorCodes[$Color])m$($LinePrefix)"
    $LineSuffix = "$($LineSuffix)`e[0m"

    $actualLineByteLimit = $LineByteLimit
    if ($LineByteLimit -gt 0) {
        $actualLineByteLimit = $actualLineByteLimit `
            - [System.Text.Encoding]::UTF8.GetByteCount($LinePrefix) `
            - [System.Text.Encoding]::UTF8.GetByteCount($LineSuffix) `
            - [System.Text.Encoding]::UTF8.GetByteCount($LineBreak)

        if ($actualLineByteLimit -le 0) {
            throw "Alpaca Message formation failed: Line byte limit $($LineByteLimit) is too low to accommodate color, prefix, suffix and line break"
        }
    }

    $messageLines = Split-AlpacaMessage -Message $Message -LineByteLimit $actualLineByteLimit
    $formattedMessageLines = $messageLines |
        ForEach-Object { "$($LinePrefix)$($_)$($LineSuffix)" }
    $formattedMessage = $formattedMessageLines -join $LineBreak

    return $formattedMessage
}
Export-ModuleMember -Function Format-AlpacaMessage

function Split-AlpacaMessage {
    Param(
        [string] $Message = "",
        [int]    $LineByteLimit = 0
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $Message
    }

    $lines = $Message -split '\r?\n'

    if ($LineByteLimit -eq 0) {
        return $lines
    }

    if ($LineByteLimit -lt 0) {
        throw "Alpaca Message split failed: Line byte limit must not be negative"
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

    $formattedMessages = @()
    if ($WithoutGitHubAnnotation) {
        $formattedMessages += Format-AlpacaMessage -Message "$($Annotation): $($Message)" -Color $color
    } else {
        $lineBreak = $script:annotationGitHubLineBreak
        $lineBreakByteCount = [System.Text.Encoding]::UTF8.GetByteCount($LineBreak)
        $gitHubCommand = $($script:annotationGitHubCommands[$Annotation])
        $gitHubCommandByteCount = [System.Text.Encoding]::UTF8.GetByteCount($gitHubCommand)

        $annotationByteLimit = 4096 - $gitHubCommandByteCount # 4KB limit minus command length
        $formattedMessage = Format-AlpacaMessage -Message $Message -Color $color -LineBreak $lineBreak -LineByteLimit $annotationByteLimit
        if ([System.Text.Encoding]::UTF8.GetByteCount($formattedMessage) -gt $annotationByteLimit) {
            $lines = $formattedMessage -split $lineBreak
            $splitLines = @()
            $splitByteCount = 0
            foreach ($line in $lines) {
                $lineByteCount = [System.Text.Encoding]::UTF8.GetByteCount("$line")
                while ($true) {
                    if ($splitByteCount -eq 0) {
                        # First line in split
                        $splitLines += $line
                        $splitByteCount += $lineByteCount
                        break
                    } elseif ($splitByteCount + $lineBreakByteCount + $lineByteCount -le $annotationByteLimit) {
                        # Can fit in current split
                        $splitLines += $line
                        $splitByteCount += $lineBreakByteCount + $lineByteCount
                        break
                    } else {
                        # Cannot fit in current split, flush current split and retry
                        $formattedMessages += "$($gitHubCommand)$($splitLines -join $lineBreak)" 
                        $splitLines = @()
                        $splitByteCount = 0
                    }
                }
            }
            # Flush remaining split
            if ($splitLines) {
                $formattedMessages += "$($gitHubCommand)$($splitLines -join $lineBreak)" 
            }
        } else {
            $formattedMessages += "$($gitHubCommand)$($formattedMessage)"
        }
    }

    foreach ($formattedMessage in $formattedMessages) {
        Write-Host $formattedMessage
    }
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
