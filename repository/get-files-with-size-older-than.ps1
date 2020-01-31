<#
.SYNOPSIS
    Recursive list all files in a given folder whichs creation time is older than given days
.DESCRIPTION
    List the file paths and sizes for all files in a given folder (and it's subfolders)
    which are older than the given amount of days and match the filter (defaults to *)
.EXAMPLE
    PS C:\>get-files-with-size-older-than.ps1 -Age 15
    Get all files from the current folder (".") which are older than 15 days
    PS C:\>get-files-with-size-older-than.ps1 -Folder %TEMP% -Age 3 -Filter *.log
    Get all *.log files from %TEMP% folder which are older than 3 days
.INPUTS
    -Folder = The folder name to check recursively (default: ".")
    -Age = The minimum age the files have to have to be listed in days (default: 30)
    -Filter = A file name filter which must match (default: "*")
.OUTPUTS
    Prints list of file paths, creation time and file length (in bytes), ordered by file length
.NOTES
    Written by Stefan Zimmermann <stefan.zimmermann@veeam.com>
#>

[CmdletBinding()]
param (
    # Folder to get files from
    [string]
    $Folder = ".",
    # Files older than this age will be listed
    [Int64]
    $Age = 30,
    # Filter only for files matching this regex
    [string]
    $Filter = "*"
)

Write-Output "Listing all files matching $Filter in $Path older than $Age days"

$allFiles = Get-ChildItem -Path $Folder -Filter $Filter -Recurse -File
$oldDate = (Get-Date).AddDays(-$Age)
$olderFiles = $allFiles | Where-Object { $_.CreationTime -lt $oldDate }

$olderFiles | Select-Object -Property CreationTime, Length, FullName | Sort-Object -Property Length -Descending | Format-Table -AutoSize