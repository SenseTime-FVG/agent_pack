; Agent Pack Installer — Inno Setup Script
; Requires Inno Setup 6.x

#define MyAppName "Agent Pack"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Agent Pack"
#define MyAppURL "https://github.com/YOUR_ORG/agent-pack"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={autopf}\AgentPack
DefaultGroupName={#MyAppName}
OutputDir=..\dist
OutputBaseFilename=AgentPack-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Files]
; Bundle scripts and shared files
Source: "scripts\*"; DestDir: "{app}\scripts"; Flags: recursesubdirs
Source: "..\shared\*"; DestDir: "{app}\shared"; Flags: recursesubdirs
Source: "..\config\*"; DestDir: "{app}\config"; Flags: recursesubdirs

[Icons]
; Created conditionally in code section based on product selection
Name: "{group}\Uninstall Agent Pack"; Filename: "{uninstallexe}"

[UninstallDelete]
Type: dirifempty; Name: "{app}"

[Code]
var
  ProductPage: TWizardPage;
  HermesCheckbox: TCheckBox;
  OpenClawCheckbox: TCheckBox;
  ProviderPage: TWizardPage;
  ProviderRadios: array of TRadioButton;
  ApiKeyEdit: TEdit;
  BaseUrlEdit: TEdit;
  ModelEdit: TEdit;
  CustomPanel: TPanel;
  VerifyButton: TButton;
  VerifyLabel: TLabel;

// ---- Product Selection Page ----
procedure CreateProductPage;
var
  lbl: TLabel;
begin
  ProductPage := CreateCustomPage(wpSelectDir,
    'Select Products', 'Choose which AI agents to install.');

  lbl := TLabel.Create(ProductPage);
  lbl.Parent := ProductPage.Surface;
  lbl.Caption := 'Select one or more products to install:';
  lbl.Top := 10;
  lbl.Left := 0;
  lbl.Width := ProductPage.SurfaceWidth;

  HermesCheckbox := TCheckBox.Create(ProductPage);
  HermesCheckbox.Parent := ProductPage.Surface;
  HermesCheckbox.Caption := 'Hermes Agent — Self-improving AI agent by Nous Research';
  HermesCheckbox.Top := 50;
  HermesCheckbox.Left := 20;
  HermesCheckbox.Width := ProductPage.SurfaceWidth - 40;
  HermesCheckbox.Checked := True;

  OpenClawCheckbox := TCheckBox.Create(ProductPage);
  OpenClawCheckbox.Parent := ProductPage.Surface;
  OpenClawCheckbox.Caption := 'OpenClaw — Multi-channel AI gateway';
  OpenClawCheckbox.Top := 80;
  OpenClawCheckbox.Left := 20;
  OpenClawCheckbox.Width := ProductPage.SurfaceWidth - 40;
  OpenClawCheckbox.Checked := False;
end;

// ---- Provider Selection Page ----
procedure OnProviderChange(Sender: TObject);
begin
  // Show custom URL fields only when "Custom" is selected
  CustomPanel.Visible := ProviderRadios[3].Checked;
end;

procedure OnVerifyClick(Sender: TObject);
var
  ResultCode: Integer;
  Provider, Cmd: String;
begin
  if ProviderRadios[0].Checked then Provider := 'openrouter'
  else if ProviderRadios[1].Checked then Provider := 'openai'
  else if ProviderRadios[2].Checked then Provider := 'anthropic'
  else Provider := 'custom';

  Cmd := 'python "' + ExpandConstant('{app}') + '\shared\verify-llm.py"'
    + ' --provider ' + Provider
    + ' --api-key "' + ApiKeyEdit.Text + '"';

  if Provider = 'custom' then begin
    Cmd := Cmd + ' --base-url "' + BaseUrlEdit.Text + '"';
    Cmd := Cmd + ' --model "' + ModelEdit.Text + '"';
  end;

  VerifyLabel.Caption := 'Verifying...';
  VerifyLabel.Font.Color := clBlue;

  if Exec('cmd.exe', '/c ' + Cmd, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then begin
    if ResultCode = 0 then begin
      VerifyLabel.Caption := 'Connection verified!';
      VerifyLabel.Font.Color := clGreen;
    end else begin
      VerifyLabel.Caption := 'Verification failed. You can configure later.';
      VerifyLabel.Font.Color := clRed;
    end;
  end else begin
    VerifyLabel.Caption := 'Could not run verification.';
    VerifyLabel.Font.Color := clRed;
  end;
end;

procedure CreateProviderPage;
var
  lbl: TLabel;
  providerNames: array of String;
  i, yPos: Integer;
begin
  ProviderPage := CreateCustomPage(ProductPage.ID,
    'LLM Provider', 'Configure your AI model provider.');

  lbl := TLabel.Create(ProviderPage);
  lbl.Parent := ProviderPage.Surface;
  lbl.Caption := 'Select your LLM provider:';
  lbl.Top := 5;
  lbl.Left := 0;

  SetArrayLength(providerNames, 4);
  providerNames[0] := 'OpenRouter (recommended - 200+ models, free tier)';
  providerNames[1] := 'OpenAI';
  providerNames[2] := 'Anthropic';
  providerNames[3] := 'Custom endpoint';

  SetArrayLength(ProviderRadios, 4);
  yPos := 30;
  for i := 0 to 3 do begin
    ProviderRadios[i] := TRadioButton.Create(ProviderPage);
    ProviderRadios[i].Parent := ProviderPage.Surface;
    ProviderRadios[i].Caption := providerNames[i];
    ProviderRadios[i].Top := yPos;
    ProviderRadios[i].Left := 20;
    ProviderRadios[i].Width := ProviderPage.SurfaceWidth - 40;
    ProviderRadios[i].OnClick := @OnProviderChange;
    yPos := yPos + 24;
  end;
  ProviderRadios[0].Checked := True;

  // API Key
  lbl := TLabel.Create(ProviderPage);
  lbl.Parent := ProviderPage.Surface;
  lbl.Caption := 'API Key:';
  lbl.Top := yPos + 15;
  lbl.Left := 0;

  ApiKeyEdit := TEdit.Create(ProviderPage);
  ApiKeyEdit.Parent := ProviderPage.Surface;
  ApiKeyEdit.Top := yPos + 35;
  ApiKeyEdit.Left := 0;
  ApiKeyEdit.Width := ProviderPage.SurfaceWidth - 120;
  ApiKeyEdit.PasswordChar := '*';

  // Verify button
  VerifyButton := TButton.Create(ProviderPage);
  VerifyButton.Parent := ProviderPage.Surface;
  VerifyButton.Caption := 'Verify';
  VerifyButton.Top := yPos + 33;
  VerifyButton.Left := ProviderPage.SurfaceWidth - 110;
  VerifyButton.Width := 100;
  VerifyButton.OnClick := @OnVerifyClick;

  VerifyLabel := TLabel.Create(ProviderPage);
  VerifyLabel.Parent := ProviderPage.Surface;
  VerifyLabel.Top := yPos + 60;
  VerifyLabel.Left := 0;
  VerifyLabel.Width := ProviderPage.SurfaceWidth;
  VerifyLabel.Caption := '';

  // Custom endpoint fields (hidden by default)
  CustomPanel := TPanel.Create(ProviderPage);
  CustomPanel.Parent := ProviderPage.Surface;
  CustomPanel.Top := yPos + 85;
  CustomPanel.Left := 0;
  CustomPanel.Width := ProviderPage.SurfaceWidth;
  CustomPanel.Height := 70;
  CustomPanel.BevelOuter := bvNone;
  CustomPanel.Visible := False;

  lbl := TLabel.Create(ProviderPage);
  lbl.Parent := CustomPanel;
  lbl.Caption := 'Base URL:';
  lbl.Top := 0;
  lbl.Left := 0;

  BaseUrlEdit := TEdit.Create(ProviderPage);
  BaseUrlEdit.Parent := CustomPanel;
  BaseUrlEdit.Top := 18;
  BaseUrlEdit.Left := 0;
  BaseUrlEdit.Width := ProviderPage.SurfaceWidth;

  lbl := TLabel.Create(ProviderPage);
  lbl.Parent := CustomPanel;
  lbl.Caption := 'Model name:';
  lbl.Top := 42;
  lbl.Left := 0;

  ModelEdit := TEdit.Create(ProviderPage);
  ModelEdit.Parent := CustomPanel;
  ModelEdit.Top := 58;
  ModelEdit.Left := 0;
  ModelEdit.Width := ProviderPage.SurfaceWidth;
end;

// ---- Validation ----
function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = ProductPage.ID then begin
    if (not HermesCheckbox.Checked) and (not OpenClawCheckbox.Checked) then begin
      MsgBox('Please select at least one product.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

// ---- Post-Install: Run Scripts ----
procedure RunInstallScripts;
var
  ResultCode: Integer;
  ScriptsDir, SharedDir, Params: String;
begin
  ScriptsDir := ExpandConstant('{app}') + '\scripts';
  SharedDir := ExpandConstant('{app}') + '\shared';

  // Install dependencies
  Params := '-ExecutionPolicy Bypass -File "' + ScriptsDir + '\install-deps.ps1"';
  if HermesCheckbox.Checked then Params := Params + ' -NeedPython';
  if OpenClawCheckbox.Checked then Params := Params + ' -NeedNode';
  Exec('powershell.exe', Params, '', SW_SHOW, ewWaitUntilTerminated, ResultCode);

  // Install Hermes
  if HermesCheckbox.Checked then begin
    Params := '-ExecutionPolicy Bypass -File "' + ScriptsDir + '\install-hermes.ps1"';
    Exec('powershell.exe', Params, '', SW_SHOW, ewWaitUntilTerminated, ResultCode);
  end;

  // Install OpenClaw
  if OpenClawCheckbox.Checked then begin
    Params := '-ExecutionPolicy Bypass -File "' + ScriptsDir + '\install-openclaw.ps1"';
    Exec('powershell.exe', Params, '', SW_SHOW, ewWaitUntilTerminated, ResultCode);
  end;

  // Configure LLM
  if ApiKeyEdit.Text <> '' then begin
    Params := '-ExecutionPolicy Bypass -File "' + ScriptsDir + '\configure-llm.ps1"';
    if ProviderRadios[0].Checked then Params := Params + ' -Provider openrouter'
    else if ProviderRadios[1].Checked then Params := Params + ' -Provider openai'
    else if ProviderRadios[2].Checked then Params := Params + ' -Provider anthropic'
    else Params := Params + ' -Provider custom';
    Params := Params + ' -ApiKey "' + ApiKeyEdit.Text + '"';
    if CustomPanel.Visible then begin
      Params := Params + ' -BaseUrl "' + BaseUrlEdit.Text + '"';
      Params := Params + ' -Model "' + ModelEdit.Text + '"';
    end;
    if HermesCheckbox.Checked then Params := Params + ' -Hermes';
    if OpenClawCheckbox.Checked then Params := Params + ' -OpenClaw';
    Params := Params + ' -SharedDir "' + SharedDir + '"';
    Exec('powershell.exe', Params, '', SW_SHOW, ewWaitUntilTerminated, ResultCode);
  end;

  // Install skills
  Params := '-ExecutionPolicy Bypass -File "' + ScriptsDir + '\install-skills.ps1"';
  Params := Params + ' -SharedDir "' + SharedDir + '"';
  Params := Params + ' -Products';
  if HermesCheckbox.Checked then Params := Params + ' hermes';
  if OpenClawCheckbox.Checked then Params := Params + ' openclaw';
  Exec('powershell.exe', Params, '', SW_SHOW, ewWaitUntilTerminated, ResultCode);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    RunInstallScripts;

    // Create desktop shortcuts based on selection
    if HermesCheckbox.Checked then begin
      CreateShellLink(
        ExpandConstant('{userdesktop}\Hermes Agent.lnk'),
        '', 'cmd.exe', '/k hermes',
        ExpandConstant('{userprofile}'), 'Hermes Agent', 0, SW_SHOWNORMAL);
      CreateShellLink(
        ExpandConstant('{group}\Hermes Agent.lnk'),
        '', 'cmd.exe', '/k hermes',
        ExpandConstant('{userprofile}'), 'Hermes Agent', 0, SW_SHOWNORMAL);
    end;
    if OpenClawCheckbox.Checked then begin
      CreateShellLink(
        ExpandConstant('{userdesktop}\OpenClaw.lnk'),
        '', 'cmd.exe', '/k openclaw gateway --verbose',
        ExpandConstant('{userprofile}'), 'OpenClaw Gateway', 0, SW_SHOWNORMAL);
      CreateShellLink(
        ExpandConstant('{group}\OpenClaw.lnk'),
        '', 'cmd.exe', '/k openclaw gateway --verbose',
        ExpandConstant('{userprofile}'), 'OpenClaw Gateway', 0, SW_SHOWNORMAL);
    end;
  end;
end;

// ---- Init ----
procedure InitializeWizard;
begin
  CreateProductPage;
  CreateProviderPage;
end;
