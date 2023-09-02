# Table of Contents
- [Summary](#summary)
- [Requirements](#requirements)
- [Usage](#usage)
- [Examples](#examples)
- [Parameters](#parameters)
- [Notes](#notes)


# Summary
The purpose of this script is to help identify SCCM applications which have invalid supersedence chains.  
This happens when older version of applications are deleted, but are still being referenced by other applications which supersede them.  
This is known to cause issues, particularly when an application with an invalid supersedence chain is referenced by a task sequence (TS).  
When such a TS is deployed to Software Center, the TS can fail to run, throwing a very cryptic and difficult to troubleshoot error: `The software could not be found on any servers at this time.`. For whatever reason, the is not a problem when running such a TS from WinPE.  
This error may also be generic, caused by other issues such as problems with a referenced app's revision history being too large, or invalid.  

Takes a list of application names and outputs all supersence chains of those apps. Can take the following:
- An MECM device name. Application names are pulled from the list of deployments to collections which contain the given device.  
- An array of strings, representing the names of the applications.  
- A string representing the name of a TS. Application names are pulled from the application references used by the given TS.  
- A string representing the name of a collection. Application names are pulled from the application deployments to the given collection.  

Handles apps with multiple references and complex/nested supersedences (recursively).  
Also outputs some useful info about the referenced apps.  

# Requirements
- Must be run on a system that has the SCCM Console app installed. The ConfigurationManager Powershell modules rely on this Windows-only application.
- Must be run in Powershell 5.1. The ConfigurationManager Powershell module requires it.
  - PowerShell 7 compatibility is untested. It may work, except when using the `-Computer` parameter, which definitely won't work in v7.
- Must be run AS a user with permissions to the campus SCCM service.

# Usage
1. Download `Get-AppSupersedence.psm1` to the appropriate subdirectory of your PowerShell [modules directory](https://github.com/engrit-illinois/how-to-install-a-custom-powershell-module).
2. Run it, e.g.:
    - `Get-AppSupersedence -Computer "comp-name-01"`
    - `Get-AppSupersedence -AppNames "Name of app"`
    - `Get-AppSupersedence -AppNames "Name of app 1","Name of app 2","Name of app 3"`
    - `Get-AppSupersedence -TS "Name of TS"`
    - `Get-AppSupersedence -Collection "Name of collection"`

## Example output
_Note: if run in Powershell console, lines which reference invalid apps are colored red, for easier skimming._  
_Note: As of this writing, `UIUC-ENGR-mseng3 Supersedence Test 2` is the name of a small TS which intentionally references both apps with valid supersedence chains, and apps which eventually supersede a deleted app, to demonstrate the problem that this script is intended to help identify._  

```
mseng3@ENGRIT-MSENG3 cd C:\git\get-appsupersedence\> Import-Module .\Get-AppSupersedence.psm1
mseng3@ENGRIT-MSENG3 cd C:\git\get-appsupersedence\> Get-AppSupersedence -TS "UIUC-ENGR-mseng3 Supersedence Test 2"

[2019-12-11 16:49:53] Crawling supersedence chains for TS "UIUC-ENGR-mseng3 Supersedence Test 2"...

[2019-12-11 16:49:54] Found 4 references in TS "UIUC-ENGR-mseng3 Supersedence Test 2":
[2019-12-11 16:49:58]     1) App: Acrobat DC SDL - Latest (ScopeId_209059C8-4AC8-44C6-803C-9B729BCFE00B/Application_19192bda-f6a0-4d62-b1a1-b44b5fe6b130/34)
[2019-12-11 16:50:02]     2) App: UIUC-ENGR-mseng3 Supersedence Test D (ScopeId_209059C8-4AC8-44C6-803C-9B729BCFE00B/Application_82e39f6c-8786-49d9-913f-8826842c0070/5)
[2019-12-11 16:50:06]     3) App: UIUC-ENGR-mseng3 Supersedence Test B (ScopeId_209059C8-4AC8-44C6-803C-9B729BCFE00B/Application_9afabacc-da34-475e-a60e-d69b34a6e85f/7)
[2019-12-11 16:50:10]     4) App: Acrobat Reader DC - Latest (ScopeId_209059C8-4AC8-44C6-803C-9B729BCFE00B/Application_d1af8db4-6d92-4f87-a9db-a03b375faa76/55)

[2019-12-11 16:50:10] Crawling supersedence chain of "Acrobat DC SDL - Latest"...

[2019-12-11 16:50:24] Crawling supersedence chain of "UIUC-ENGR-mseng3 Supersedence Test D"...

[2019-12-11 16:50:27] Crawling supersedence chain of "UIUC-ENGR-mseng3 Supersedence Test B"...

[2019-12-11 16:50:37] Crawling supersedence chain of "Acrobat Reader DC - Latest"...

[2019-12-11 16:51:05] Checking for invalid supersedence references...
[2019-12-11 16:51:05] Done.

[2019-12-11 16:51:05] Supersedence chains:
[2019-12-11 16:51:05] ======================================================================================================

[2019-12-11 16:51:05]     "Acrobat DC SDL - Latest" (ScopeId_209059C8-4AC8-44C6-803C-9B729BCFE00B/Application_19192bda-f6a0-4d62-b1a1-b44b5fe6b130/34):
[2019-12-11 16:51:05]     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

[2019-12-11 16:51:05]         Supersedence chain:
[2019-12-11 16:51:05]         ----------------------------------
[2019-12-11 16:51:05]         Acrobat DC SDL 19.021.20049
[2019-12-11 16:51:06]             Acrobat DC SDL 19.021.20048
[2019-12-11 16:51:06]                 Acrobat DC SDL 19.021.20047
[2019-12-11 16:51:06]                     Acrobat DC SDL 19.012.20036
[2019-12-11 16:51:06]                         No superseded apps

[2019-12-11 16:51:06]         Other infos:
[2019-12-11 16:51:06]         ----------------------------------
[2019-12-11 16:51:06]         CIVersion (Revision): "34"
[2019-12-11 16:51:06]         SDMPackageVersion (?): "34"
[2019-12-11 16:51:06]         SourceCIVersion (?): "0"
[2019-12-11 16:51:06]         AutoInstall (From TS w/o being deployed): "true"
[2019-12-11 16:51:06]         Has an invalid supersedence ref: "False"

[2019-12-11 16:51:06]     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

[2019-12-11 16:51:06]     "UIUC-ENGR-mseng3 Supersedence Test D" (ScopeId_209059C8-4AC8-44C6-803C-9B729BCFE00B/Application_82e39f6c-8786-49d9-913f-8826842c0070/5):
[2019-12-11 16:51:06]     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

[2019-12-11 16:51:06]         Supersedence chain:
[2019-12-11 16:51:06]         ----------------------------------
[2019-12-11 16:51:06]         {INVALID}

[2019-12-11 16:51:06]         Other infos:
[2019-12-11 16:51:06]         ----------------------------------
[2019-12-11 16:51:06]         CIVersion (Revision): "5"
[2019-12-11 16:51:06]         SDMPackageVersion (?): "5"
[2019-12-11 16:51:06]         SourceCIVersion (?): "0"
[2019-12-11 16:51:06]         AutoInstall (From TS w/o being deployed): "false"
[2019-12-11 16:51:06]         Has an invalid supersedence ref: "True"

[2019-12-11 16:51:06]     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

[2019-12-11 16:51:06]     "UIUC-ENGR-mseng3 Supersedence Test B" (ScopeId_209059C8-4AC8-44C6-803C-9B729BCFE00B/Application_9afabacc-da34-475e-a60e-d69b34a6e85f/7):
[2019-12-11 16:51:06]     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

[2019-12-11 16:51:06]         Supersedence chain:
[2019-12-11 16:51:06]         ----------------------------------
[2019-12-11 16:51:06]         UIUC-ENGR-mseng3 Supersedence Test D
[2019-12-11 16:51:06]             {INVALID}
[2019-12-11 16:51:06]         UIUC-ENGR-mseng3 Supersedence Test C
[2019-12-11 16:51:06]             No superseded apps

[2019-12-11 16:51:06]         Other infos:
[2019-12-11 16:51:06]         ----------------------------------
[2019-12-11 16:51:06]         CIVersion (Revision): "7"
[2019-12-11 16:51:06]         SDMPackageVersion (?): "7"
[2019-12-11 16:51:06]         SourceCIVersion (?): "0"
[2019-12-11 16:51:06]         AutoInstall (From TS w/o being deployed): "true"
[2019-12-11 16:51:06]         Has an invalid supersedence ref: "True"

[2019-12-11 16:51:06]     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

[2019-12-11 16:51:06]     "Acrobat Reader DC - Latest" (ScopeId_209059C8-4AC8-44C6-803C-9B729BCFE00B/Application_d1af8db4-6d92-4f87-a9db-a03b375faa76/55):
[2019-12-11 16:51:06]     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

[2019-12-11 16:51:06]         Supersedence chain:
[2019-12-11 16:51:06]         ----------------------------------
[2019-12-11 16:51:06]         Acrobat Reader DC 19.021.20049
[2019-12-11 16:51:06]             Acrobat Reader DC 19.021.20047
[2019-12-11 16:51:06]                 Acrobat Reader DC 19.012.20036
[2019-12-11 16:51:06]                     Acrobat Reader DC 19.012.20034
[2019-12-11 16:51:06]                         Acrobat Reader DC 19.010.20099
[2019-12-11 16:51:06]                             Acrobat Reader DC 19.010.20064
[2019-12-11 16:51:06]                                 Acrobat Reader DC 18.011.20063
[2019-12-11 16:51:06]                                     Acrobat Reader DC 18.011.20040
[2019-12-11 16:51:06]                                         No superseded apps

[2019-12-11 16:51:06]         Other infos:
[2019-12-11 16:51:06]         ----------------------------------
[2019-12-11 16:51:06]         CIVersion (Revision): "55"
[2019-12-11 16:51:06]         SDMPackageVersion (?): "55"
[2019-12-11 16:51:06]         SourceCIVersion (?): "0"
[2019-12-11 16:51:06]         AutoInstall (From TS w/o being deployed): "true"
[2019-12-11 16:51:06]         Has an invalid supersedence ref: "False"

[2019-12-11 16:51:06]     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

[2019-12-11 16:51:06] ======================================================================================================

[2019-12-11 16:51:06] EOF
mseng3@ENGRIT-MSENG3 cd C:\git\get-appsupersedence\>
```

# Parameters

### -Computer
Required if not using `-AppNames`, `-TS`, or `-Collection`.  
A string representing the name of a device object. Supersedence will be polled from the application of each application deployment to the given device.  
Aliases: `-Device`, `-Resource`  

### -Collection
Required if not using `-Computer`, `-AppNames` or `-TS`.  
A string representing the name of a collection. Supersedence will be polled from the application of seach application deployment to the given collection.  

### -AppNames
Required if not using `-Computer`, `-TS` or `-Collection`.  
An array of strings representing the name of one or more applications. Supersedence will be polled from each given application.  
The app name needs to be the name of the application package in MECM, and not the LocalizedDisplayName shown in Software Center.  
Aliases: `-Apps`, `-Applications`  

### -TS
Required if not using `-Computer`, `-AppNames` or `-Collection`.  
A string representing the name of a task sequence. Supersedence will be polled from the application of app reference in the given TS.  
Aliases: `-TaskSequence`  

### -Log
Optional.  
The full path to a log file that will have a copy of all the console output.  

### -DebugLevel
Optional. Recommend leaving default. Only useful for debugging the script.  
0 (default): Just the intended output  
1: Output from intermediate steps  
2: Output from various minor operations and variable value checks  
Aliases: `-Verbosity`

### -SiteCode
Optional. Recommend leaving default.  
The site code of the SCCM site to query.  
Default is `MP0`.  

### -Provider
Optional. Recommend leaving default.  
The SMS provider machine name.  
Default is `sccmcas.ad.uillinois.edu`.  

### -CMPSModulePath
Optional string, representing the local path where the ConfigurationManager Powershell module exists.  
Default value is `$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1`, because there's where it is for us.  
You may need to change this, depending on your SCCM (Console) version. The path has changed across various versions of SCCM, but the environment variable used by default should account for those changes in most cases.  

### -DisableCaching
Optional switch.  
By default, the app caches information about apps retrieved from MECM, so that if it's required more than once (e.g. multiple apps supersede the same app), it only has to be retrieved from MECM once.  
For example, most of our app supersedence chains are configured linearly (e.g. v4 supersedes v3, which supersedes v2, which supersedes v1). However some are configured cumulatively, such that each version supersedes EVERY older version (e.g. v4 supersedes v3, v2 and v1, and v3 supersedes v2 and v1, and v2 supersedes v1).  
In these cases, caching significantly improves the script's performance, as it greatly minimizes redundant communications with MECM, since the script recursively evaluates each supersedence chain. For example, in an instance where an app has a dozen or so such cumulative supersedences, caching reduces the script runtime from several hours down to several minutes.  
Ostensibly, this cumulative supersedence is done to optimize MECM client/Software Center performance, so that it doesn't choke (which is known to happen) when trying to enumerate long supersedence chains all the way back to the oldest version.  
Disabling caching is not recommended and is only left in because it was the default behavior before the caching feature was added.  

# Notes
- Expect it to take something on the order of 10 minutes to process a large OSD TS.  Depends on how numerous and complicated the supersedence chains are.  
- If necessary, re-import the module using `Import-Module "c:\path\to\script\Get-AppSupersedence.psm1" -Force`.  Useful after you've made changes to the script source.  
- You may need to escape TS and application names with special characters, e.g. `Get-AppSupersedence "Notepad\+\+ - Latest"`.  
- Ignore `Get-AppSupersedenceByTS_old.psm1`. This was the previous iteration of the script, which doesn't support the `-AppNames` or `-Collection` parameters. It's kept for the author's reference.
- By mseng3. See my other projects here: https://github.com/mmseng/code-compendium.
