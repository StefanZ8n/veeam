# Search in logfiles for a list of patterns and return the resulting counts
# Return as JSON list of entries listing the matched files, patterns and counts
# Stefan Zimmermann, stefan.zimmermann@veeam.com, 06.07.2023

## LogPath
# Can contain * to match everything

$logPath = "C:\ProgramData\Veeam\Backup\Plugin\Backup\*\Session.log"

### Patterns

## "PleaseWait;"
# This is the response for a task-slot request when no task-slots are available on the repository. 
# The request will be repeated every 10s per waiting channel/session, as will this pattern until a task-slot is available (and the returning msg will be "Ready;")

## "Error"
# Matching general message level, can match multiple times per error for multi-line errors

$searchPatterns = @("PleaseWait;", "Error")

### Processing

$logfiles = Get-ChildItem -Path $logPath -Recurse

$results = @()

$logfiles.ForEach({ 
    $logfile = $_;

    $result = @{
        "logfile" = $logfile.FullName;
    }

    $groups = (select-string -Pattern $searchPatterns $logfile).Pattern | Group-Object
    $groups | % { $result += @{ $_.Name = $_.Count } }    
    
    $results += $result
    
})

$results | ConvertTo-Json