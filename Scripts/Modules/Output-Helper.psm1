
# Colors
$script:ColorCodes = @{
    None    = '0'
    Red     = '31'
    Green   = '32'
    Yellow  = '33'
    Blue    = '34'
    Magenta = '35'
    Cyan    = '36'
    White   = '37'
}

# Annotations
$script:AnnotationColors = @{
    Notice  = 'White'
    Warning = 'Yellow'
    Error   = 'Red'
}
$script:AnnotationGitHubCommands = @{
    Notice  = '::notice::'
    Warning = '::warning::'
    Error   = '::error::'
}
$script:AnnotationGitHubLineBreak = '%0A'
$script:AnnotationGitHubByteLimit = 4096 # 4KB

# Groups
$script:GroupIndentation = "  "
$script:GroupLevel = 0

$script:XmasEmojis = @("🎄", "❄️", "⛄", "🎅", "🤶", "🦌", "🛷", "🎁", "🍪", "☃️")
$script:XmasEmojiLastUsed = $null

function Format-AlpacaMessage {
    param(
        [Parameter(ValueFromPipeline = $true)]
        [string] $Message = "",
        [ValidateSet( 'None', 'Red', 'Green', 'Yellow', 'Blue', 'Magenta', 'Cyan', 'White' )]
        [string] $Color = 'None',
        [string] $LinePrefix = "",
        [string] $LineSuffix = "",
        [string] $LineBreak = "`n"
    )
    begin {
        if ($Color -ne 'None') {
            $LinePrefix = "`e[$($script:ColorCodes[$Color])m$($LinePrefix)"
            $LineSuffix = "$($LineSuffix)`e[0m"
        }
    }

    process {
        if ([string]::IsNullOrWhiteSpace($Message)) {
            return $Message
        }

        $messageLines = Split-AlpacaMessage -Message $Message
        $formattedMessageLines = $messageLines |
        ForEach-Object { "$($LinePrefix)$($_)$($LineSuffix)" }
        $formattedMessage = $formattedMessageLines -join $LineBreak

        return $formattedMessage
    }
}
Export-ModuleMember -Function Format-AlpacaMessage

function Split-AlpacaMessage {
    param(
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
    param(
        [Parameter(ValueFromPipeline = $true)]
        [string] $Message = "",
        [ValidateSet( 'None', 'Red', 'Green', 'Yellow', 'Blue', 'Magenta', 'Cyan', 'White' )]
        [string] $Color = 'None'
    )

    begin {
        $linePrefix = $script:GroupIndentation * $script:GroupLevel;
        $lineSuffix = ""

        $date = Get-Date
        if ($date.Month -eq 12 -and $date.Day -in 24, 25, 26) {
            $emoji = $null
            while ($emoji -in $null, $script:XmasEmojiLastUsed) {
                $emoji = $script:XmasEmojis | Get-Random
            }
            $script:XmasEmojiLastUsed = $emoji
            $lineSuffix = " $emoji"
        }
    }

    process {
        $formattedMessage = Format-AlpacaMessage -Message $Message -Color $Color -LinePrefix $linePrefix -LineSuffix $lineSuffix

        Write-Host $formattedMessage
    }
}
Export-ModuleMember -Function Write-AlpacaOutput

function Write-AlpacaAnnotation {
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string] $Message,
        [ValidateSet('Notice', 'Warning', 'Error')]
        [string] $Annotation = 'Notice',
        [string] $GitHubAnnotationParams = $null,
        [switch] $WithoutGitHubAnnotation
    )

    process {
        if ($WithoutGitHubAnnotation) {
            $color = $script:AnnotationColors[$Annotation]
            $formattedMessage = Format-AlpacaMessage -Message "$($Annotation): $($Message)" -Color $color
            Write-Host $formattedMessage
        }
        else {
            Write-AlpacaGitHubAnnotation -Message $Message -Annotation $Annotation -AnnotationParams $GitHubAnnotationParams
        }
    }
}
Export-ModuleMember -Function Write-AlpacaAnnotation

function Write-AlpacaGitHubAnnotation {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message,
        [ValidateSet('Notice', 'Warning', 'Error')]
        [string] $Annotation = 'Notice',
        [string] $AnnotationParams = $null
    )
    $color = $script:AnnotationColors[$Annotation]

    $gitHubAnnotationCommand = $script:AnnotationGitHubCommands[$Annotation]
    $gitHubAnnotationLineBreak = $script:AnnotationGitHubLineBreak
    $gitHubAnnotationByteLimit = $script:AnnotationGitHubByteLimit

    if (!([String]::IsNullOrWhiteSpace($AnnotationParams))) {
        $gitHubAnnotationCommand = $gitHubAnnotationCommand -replace '::$', " $AnnotationParams::"
    }

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
    }
    else {
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
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string] $Message,
        [string] $GitHubAnnotationParams = $null,
        [switch] $WithoutGitHubAnnotation
    )

    process {
        Write-AlpacaAnnotation -Message $Message -Annotation "Notice" -GitHubAnnotationParams $GitHubAnnotationParams -WithoutGitHubAnnotation:$WithoutGitHubAnnotation
    }
}
Export-ModuleMember -Function Write-AlpacaNotice

function Write-AlpacaWarning {
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string] $Message,
        [string] $GitHubAnnotationParams = $null,
        [switch] $WithoutGitHubAnnotation
    )

    process {
        Write-AlpacaAnnotation -Message $Message -Annotation "Warning" -GitHubAnnotationParams $GitHubAnnotationParams -WithoutGitHubAnnotation:$WithoutGitHubAnnotation
    }
}
Export-ModuleMember -Function Write-AlpacaWarning

function Write-AlpacaError {
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string] $Message,
        [string] $GitHubAnnotationParams = $null,
        [switch] $WithoutGitHubAnnotation
    )

    process {
        Write-AlpacaAnnotation -Message $Message -Annotation "Error" -GitHubAnnotationParams $GitHubAnnotationParams -WithoutGitHubAnnotation:$WithoutGitHubAnnotation
    }
}
Export-ModuleMember -Function Write-AlpacaError

function Write-AlpacaDebug {
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string] $Message
    )

    process {
        if (-not (Get-AlpacaIsDebugMode)) {
            return
        }

        "Debug: {0}" -f $Message | Write-AlpacaOutput -Color 'Blue'
    }
}
Export-ModuleMember -Function Write-AlpacaDebug

function Write-AlpacaGroupStart {
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string] $Message,
        [switch] $UseGitHubCommand
    )

    process {
        if ($UseGitHubCommand) {
            Write-Host "::group::$($Message)"
        }
        else {
            Write-AlpacaOutput -Message "> $Message"
            $script:GroupLevel += 1
        }
    }
}
Export-ModuleMember -Function Write-AlpacaGroupStart

function Write-AlpacaGroupEnd {
    param(
        [Parameter(ValueFromPipeline = $true)]
        [string] $Message,
        [switch] $UseGitHubCommand
    )

    process {
        if ($UseGitHubCommand) {
            Write-Host "::endgroup::"
        }
        else {
            $script:GroupLevel = [Math]::Max($script:GroupLevel - 1, 0)
        }
        if ($Message) {
            Write-AlpacaOutput -Message $Message
        }
    }
}
Export-ModuleMember -Function Write-AlpacaGroupEnd

function Get-AlpacaIsDebugMode {
    return $env:RUNNER_DEBUG -eq '1' -or $env:GITHUB_RUN_ATTEMPT -gt 1
}
Export-ModuleMember -Function Get-AlpacaIsDebugMode

function Invoke-AlpacaOutputHandler {
    param(
        [Parameter(ValueFromPipeline = $true)]
        [object] $Value
    )

    process {
        switch ($Value.GetType()) {
            ( [System.Management.Automation.ErrorRecord] ) { Write-AlpacaError $Value; throw $Value }
            ( [System.Management.Automation.WarningRecord] ) { Write-AlpacaWarning $Value }
            ( [System.Management.Automation.VerboseRecord] ) { Write-AlpacaDebug $Value }
            ( [System.Management.Automation.DebugRecord] ) { Write-AlpacaDebug $Value }
            ( [System.Management.Automation.InformationRecord] ) {
                $message = $Value.ToString()

                if ($message -match '(?s)^\s*::\s*(?<cmd>.+?)\s*::(?<msg>.*)') {
                    # Map GH commands to Alpaca annotations and groups
                    $command = $matches['cmd'].Trim()
                    $commandMessage = $matches['msg'].Trim()
                    switch ($command) {
                        'group' { Write-AlpacaGroupStart $commandMessage }
                        'endgroup' { Write-AlpacaGroupEnd $commandMessage }
                        'debug' { Write-AlpacaDebug $commandMessage }
                        { $_ -like 'error*' } { Write-AlpacaError $commandMessage -GitHubAnnotationParams ($command -replace '^error\s*', '') }
                        { $_ -like 'warning*' } { Write-AlpacaWarning $commandMessage -GitHubAnnotationParams ($command -replace '^warning\s*', '') }
                        { $_ -like 'notice*' } { Write-AlpacaNotice $commandMessage -GitHubAnnotationParams ($command -replace '^notice\s*', '') }
                        default { Write-Host $message }
                    }
                }
                elseif ($message -match '(?s)^\s*##\[\s*(?<cmd>.+?)\s*\](?<msg>.*)') {
                    # Map ADO formatting commands to Alpaca annotations and groups
                    $command = $matches['cmd'].Trim()
                    $commandMessage = $matches['msg'].Trim()
                    switch ($command) {
                        'group' { Write-AlpacaGroupStart $commandMessage }
                        'endgroup' { Write-AlpacaGroupEnd $commandMessage }
                        'debug' { Write-AlpacaDebug $commandMessage }
                        { 'error', 'warning', 'notice' -contains $_ } { Write-AlpacaAnnotation $commandMessage -Annotation $command -WithoutGitHubAnnotation }
                        default { Write-AlpacaOutput $message }
                    }
                }
                elseif ($message -match '(?s)^\s*##vso\[task\.logissue\s+.*?;?\s*type\s*=\s*(?<type>error|warning)\s*;?.*?\](?<msg>.*)') {
                    # Map ADO issue commands to Alpaca annotations
                    $issueType = $matches['type'].Trim()
                    $issueMessage = $matches['msg'].Trim()
                    switch ($issueType) {
                        'error' { Write-AlpacaError $issueMessage }
                        'warning' { Write-AlpacaWarning $issueMessage }
                    }
                }
                else {
                    # Map all other information records to Alpaca output
                    Write-AlpacaOutput $message
                }
            }
            default { return $Value }
        }
    }
}
Export-ModuleMember -Function Invoke-AlpacaOutputHandler

function ConvertTo-AlpacaOutputString {
    [CmdletBinding()]
    param(
        [object]$Value,
        [switch]$ReplaceNullAndEmptyString
    )

    if ($null -eq $Value) {
        if ($ReplaceNullAndEmptyString) {
            return '[null]'
        }
        return
    }
    if ($Value -is [String]) {
        if ([String]::IsNullOrEmpty($Value)) {
            if ($ReplaceNullAndEmptyString) {
                return '[empty]'
            }
            return
        }
    }
    if ($Value -is [scriptblock]) {
        return $Value.ToString()
    }
    return ConvertTo-Json -InputObject $Value -Depth 10 -Compress
}
Export-ModuleMember -Function ConvertTo-AlpacaOutputString