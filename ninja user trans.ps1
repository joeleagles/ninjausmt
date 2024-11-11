####Set Variables Based on Selected User####
$user_name = $env:user_name
$DownLevelUserName = (Get-WmiObject win32_useraccount | Where-Object -property caption -like *$user_name).Caption
$FullUserName = (Get-WmiObject win32_useraccount | Where-Object -property caption -like *$user_name).Name
$UserSID = (Get-WmiObject win32_useraccount | Where-Object -property caption -like *$user_name).SID
$UserPath = (Get-CimInstance Win32_UserProfile | Where-Object -property SID -eq $UserSID).LocalPath


####Set Arguments List With Options####
$Arguments = "C:\UserTrans\Profile /i:MigApp.xml /i:MigDocs.xml /v:13 /l:C:\UserTrans\Profile\Scan.log /ue:*\* /ui:$DownLevelUserName /localonly"
$SizeCheckArguments = "C:\UserTrans\Profile /p:C:\UserTrans\requiredspace.xml /i:MigApp.xml /i:MigDocs.xml /v:13 /l:C:\UserTrans\Profile\Scan.log /ue:*\* /ui:$DownLevelUserName /localonly"
if ([System.Boolean]::Parse($env:doNotCompress)){"";Write-Host "Do Not Compress Enabled";""; $Arguments += " /nocompress"; $SizeCheckArguments += " /nocompress"}
if ([System.Boolean]::Parse($env:fileListLog)){"";Write-Host "File List Log Enabled";""; $Arguments += " /listfiles:C:\UserTrans\Profile\Files.log"; $SizeCheckArguments += " /listfiles:C:\UserTrans\Profile\Files.log"}
if ([System.Boolean]::Parse($env:overwriteExistingTransitionStore)){"";Write-Host "Overwite Enabled";""; $Arguments += " /o"; $SizeCheckArguments += " /o"}
if ([System.Boolean]::Parse($env:shadowCopy)){"";Write-Host "Shadow Copy Enabled";""; $Arguments += " /vsc"}
if ([System.Boolean]::Parse($env:checkRequiredFreeSpace)){"";Write-Host "Check Required Free Space Disabled";""}


####Set ADK USMT Program Location Based on Machine Architecture####
$usmtPath
if ($env:PROCESSOR_ARCHITECTURE -eq "AMD64"){
	$usmtPath = "C:\UserTrans\Tools\Assessment and Deployment Kit\User State Migration Tool\amd64\"
}elseif($env:PROCESSOR_ARCHITECTURE -eq "x86"){
	$usmtPath = "C:\UserTrans\Tools\Assessment and Deployment Kit\User State Migration Tool\x86\"
}else{
  Write-Host "Unknown Processor Architechture. exiting"
  Exit 1
}


####Check If Needed Paths Exist And Create Them If They Don't####
if (-Not(Test-Path -Path "C:\Usertrans")){
  New-Item -path "c:\" -name "UserTrans" -ItemType "directory"
}
if (-Not(Test-Path -Path "c:\UserTrans\Tools")){
  New-Item -path "c:\UserTrans" -name "Tools" -ItemType "directory"
}
if (-Not(Test-Path -Path "c:\UserTrans\Profile")){
  New-Item -path "c:\UserTrans" -name "Profile" -ItemType "directory"
}


####Check If ADK USMT Is Already Installed####
if (-Not(Test-Path -Path "C:\UserTrans\Tools\Assessment and Deployment Kit\User State Migration Tool")){
  ####Check If ADK Installer Is Present, If Not, Download It####
  if (-Not(Test-Path -Path "C:\Usertrans\Tools\adksetup.exe")){
   try{
     invoke-webrequest -uri "https://download.microsoft.com/download/5/8/6/5866fc30-973c-40c6-ab3f-2edb2fc3f727/ADK/adksetup.exe" -OutFile "c:\UserTrans\Tools\adksetup.exe"
   }Catch{
     Write-Host "An error occured when downloading the Windows Assessment and Deployment Kit. Threatlocker may be ringfencing this script."
     ""
     Write-Host "Exiting Script"
     Exit 1
    }
  }else{
    Write-Host "ADK Installer already downloaded"
    ""
    Write-Host "Continuing"
  }
  ####Install ADK USMT####
  try{
    C:\UserTrans\Tools\adksetup.exe /q /features "Optionid.UserStateMigrationTool" /installpath "C:\UserTrans\Tools\"
  }Catch{
    Write-Host "Error Occured When Installing ADK USMT. Exiting Script"
    Exit 1
  }
  Start-Sleep -Seconds 120
}else{
  Write-Host "ADK USMT Already Installed"
  ""
  Write-Host "Continuing"
}


####Check If There Is Enough Space On The Drive For Local Backup####
if ([System.Boolean]::Parse($env:checkRequiredFreeSpace)){
  cd $usmtpath
  $FreeBytes = ((gwmi win32_logicaldisk) | Where-Object -property DeviceID -eq 'C:').FreeSpace
  start-Process -NoNewWindow '.\scanstate.exe' $SizeCheckArguments -wait -RedirectStandardOutput 'C:\UserTrans\requiredspace.log'
  [xml]$xmlData = Get-Content "C:\UserTrans\requiredspace.xml"
  $RequiredSpace = ($xmlData.PreMigration.storesize.size).'#text'
  if ($RequiredSpace –gt $FreeBytes){
    ""
    Write-Host "Not Enough Free Space On Drive."
    ""
    $NeededSpace = [Math]::Round(($RequiredSpace - $FreeBytes) / 1GB, 2)
    Write-Host "Need Another" $NeededSpace "GB"
    ""
    Write-Host "Exiting"
    Exit 1
  }
}


####Run Migration ScanState####
cd $usmtpath
start-Process -NoNewWindow '.\scanstate.exe' $Arguments -wait