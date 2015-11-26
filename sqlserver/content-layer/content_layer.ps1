﻿[CmdletBinding()]
param
(
	[Parameter(Mandatory=$True,ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,HelpMessage="Name of the output image")]
	[string] $OutputImage,
	[Parameter(Mandatory=$True,ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,HelpMessage="Path to the SQL script")]
	[string] $SqlFile,
    [Parameter(Mandatory=$True,ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,HelpMessage="Path to the database directory")]
    [string] $DatabaseDir
)

$TurboCmd = 'turbo.exe'

function PrintFatal($errorMsg)
{
    Write-Host $errorMsg -ForegroundColor Red
}

function Question($caption, $question, $defaultChoice)
{
    $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes"
    $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No"
    $choices = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

    $result = $host.ui.PromptForChoice($caption, $question, $choices, $defaultChoice) 

    switch ($result)
    {
        0 { return $True }
        1 { return $False }
    }
}

function CheckRuntimeRequirements()
{
    Try
    {
        & $TurboCmd version | Out-Null
    }
    Catch
    {
        throw "Error: Turbo is not installed on host machine. "
    }

    # TODO: check .Net and PowerShell version
}

function Build($config)
{
    $initialLocation = $pwd.Path
    Try
    {
        $tempDirName = [System.Guid]::NewGuid().ToString()
        Set-Location $env:temp
        $tempDir = New-Item -Type Directory -Name $tempDirName
        
        Try
        {
            Set-Location $tempDir
            Copy-Item -Path $config.SqlFile -Destination ([System.IO.Path]::Combine($tempDir.FullName, 'script.sql'))
            
            $tempDatabaseDir = New-Item -ItemType Directory -Name 'DATA'
            ForEach ($extension in '*.mdf', '*.ldf')
            {
                Get-ChildItem -Path $config.DatabaseDir -Filter $extension | Copy-Item -Destination $tempDatabaseDir
            }

            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile('https://raw.githubusercontent.com/turboapps/turbome/master/sqlserver/content-layer/build.me', "$tempDir\build.me")

            & $TurboCmd build --overwrite --name $config.OutputImage build.me script.sql DATA
            if($LASTEXITCODE -ne 0)
            {
                throw "Error: Build returned exit code $LASTEXITCODE"
            }
        }
        Finally
        {
            Set-Location $env:temp
            Remove-Item -Recurse $tempDirName
        }
    }
    Finally
    {
        Set-Location $initialLocation
    }
}

function Run($config)
{
    $result = Question 'Run Image' 'Would you like to run the image now?' 0
    if(-not $result)
    {
        return
    }

    & $TurboCmd try ('{0},mssql2014-labsuite' -f $config.OutputImage)
}

function Push($config)
{
    $result = Question 'Push Image' 'Would you like to push the image to the Turbo hub?' 0
    if(-not $result)
    {
        return
    }

    $remoteImageName = Read-Host -Prompt 'Provide the name of the remote image or press [Enter] if defaults are ok'
    $pushParams = $config.OutputImage
    if($remoteImageName)
    {
        $pushParams = -join $pushParams, ' ', $remoteImageName
    }
    & $TurboCmd push $pushParams
    if($LASTEXITCODE -ne 0)
    {
        throw "Error: Push returned exit code $LASTEXITCODE"
    }
}

$sqlFileExists = Test-Path $SqlFile
if(-not $sqlFileExists)
{
    PrintFatal "Error: Script file '$SqlFile' was not found"
    Exit -1
}

$databaseDirExists = Test-Path $DatabaseDir
if(-not $databaseDirExists)
{
    PrintFatal "Error: Database directory '$DatabaseDir' was not found"
    Exit -1
}

$config = New-Object -TypeName PsObject -Property (@{
    'OutputImage' = $OutputImage;
    'SqlFile' = (Get-Item $SqlFile | % { $_.FullName });
    'DatabaseDir'= (Get-Item $DatabaseDir | % { $_.FullName });
})  

Try
{
    CheckRuntimeRequirements
    
    Build $config
    Run $config
    Push $config
}
Catch
{
    PrintFatal $_.Exception.Message
    PrintFatal $_.Exception.StackTrace
    Exit -1
}