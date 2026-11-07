; Compiled by .github/workflows/build-windows.yml:
;   ISCC /DAppVersion=<version> /DSourceDir=<Release directory> /DOutputName=<name> /O<output> setup.iss
#define AppName "我的世界开发者管理"
#define AppExe "minecraft_developer_manager.exe"

[Setup]
AppId={{E5544E08-4C3E-4E9E-ADA4-93954820E234}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=MCDFsteve
AppPublisherURL=https://github.com/MCDFsteve/mcdev_income
DefaultDirName={autopf}\MCDevIncome
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputBaseFilename={#OutputName}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Installs for the current user unless the dialog asks for all users.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "chinesesimplified"; MessagesFile: "ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; Assets removed by a newer version must not stay behind after an upgrade.
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
