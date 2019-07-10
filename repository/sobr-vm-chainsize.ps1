# Output the backup size for all VMs on SOBR repositories grouped by SOBR and sorted by size (largest first)
# v1.0.0, 09.07.2019
# Stefan Zimmermann <stefan.zimmermann@veeam.com>

Add-PSSnapin -Name VeeamPSSnapIn

$sobrs = Get-VBRBackupRepository -ScaleOut

$allRestorePoints = Get-VBRRestorePoint | ? { $_.FindRepository().Type -eq "ExtendableRepository" }

foreach ($sobr in $sobrs) {

    Write-Output $sobr.Name

    $result = @{}

    $vmRestorePoints = $allRestorePoints | ? { $_.GetRepository() -eq $sobr } | Group-Object -Property VmName | % { $result.add($_.Name, ($_.Group.GetStorage().Stats | Measure-Object -Sum BackupSize).Sum)}

    $result.GetEnumerator() | Sort-Object -Property Value -Descending | format-table -Property Name,@{l="Size";e={[Math]::Round($_.Value/1024/1024/1024, 2)}}
}