# Return the size of backups per VM for the given repositories. Optionally ouptut as CSV.
# v1.0.0, 18.07.2019
# Stefan Zimmermann <stefan.zimmermann@veeam.com>
[CmdletBinding()]
Param(    
    [switch]$csv
)
DynamicParam {
    Add-PSSnapin -Name VeeamPSSnapIn
    $ParameterName = 'Repository'    
    $RuntimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary 
    $AttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
    $ParameterAttribute = New-Object System.Management.Automation.ParameterAttribute
    $ParameterAttribute.Mandatory = $true    
    $AttributeCollection.Add($ParameterAttribute)    
    $arrSet = Get-VBRBackupRepository | select -ExpandProperty Name
    $arrSet += Get-VBRBackupRepository -ScaleOut | select -ExpandProperty Name
    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute($arrSet)
    $AttributeCollection.Add($ValidateSetAttribute)
    $RuntimeParameter = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterName, [string[]], $AttributeCollection)
    $RuntimeParameterDictionary.Add($ParameterName, $RuntimeParameter)
    return $RuntimeParameterDictionary
}
begin {
    $Repository = $PsBoundParameters[$ParameterName]
    Add-PSSnapin -Name VeeamPSSnapIn
}
process {
    $repos = @()
    foreach ($repoName in $Repository) {
        $repos += (Get-VBRBackupRepository -Name $repoName)
    }
    
    $allRepoRestorePoints = Get-VBRRestorePoint | ? { $_.FindRepository() -in $repos }

    foreach ($repo in $repos) {
        
        $result = @{}
        $vmRestorePoints = $allRepoRestorePoints | ? { $_.GetRepository() -eq $repo } | Group-Object -Property VmName | % { $result.add($_.Name, ($_.Group.GetStorage().Stats | Measure-Object -Sum BackupSize).Sum)}
        $table = $result.GetEnumerator() | Sort-Object -Property Value -Descending | format-table -Property Name,@{l="Size";e={[Math]::Round($_.Value/1024/1024/1024, 2)}}

        if ($csv -eq $false) {
            Write-Output $repo.Name
            Write-Output $table
        } else {
            $result.GetEnumerator() | Export-Csv -Path ".\$($repo.Name).csv"
        }
    }
        
}
