Instructions for Installing the MakerAi Package in Delphi
Prerequisites
Have Delphi installed on your system.
An internet connection to clone the repository.
Optional: Have Git installed to clone the repository.
Installation Steps
1. Download the MakerAi Package
Option 1: Clone the Repository with Git
Open a terminal or command line.
Execute the following command to clone the repository to your computer:
git clone https://github.com/gustavoeenriquez/MakerAi.git
This will create a folder called MakerAi with all necessary files.
Option 2: Download the Package as a ZIP File
Go to the repository page on GitHub: https://github.com/gustavoeenriquez/MakerAi.
Click the green Code button and select Download ZIP.
Extract the ZIP file contents to a folder on your computer.

2. Open the Project in Delphi
Open Delphi.
Go to the File menu and select Open Project....
Navigate to the MakerAi\fuentes folder and select the MakerAi.dproj file. This file is the main component package.

3. Compile the Package
In the Delphi IDE, make sure the MakerAi.dproj file is open.
Select Build from the top menu or press Ctrl+F9. This will compile the package.
If no errors appear, the package will compile correctly and be ready for installation.

4. Install the Package in Delphi
After compiling, go to the Component menu and select Install Packages....
In the window that opens, click the Add... button.
Navigate to the folder where the .bpl file was generated (usually inside the \Win32\Release or \Win64\Release folder, depending on your configuration).
Select the MakerAi.bpl file and click Open.
Delphi will add the package to the list of installed components.

5. Test the Components
Go to the File menu and select Open Project....
Navigate to the MakerAi\demos folder and open one of the example projects.
Run the project to make sure the components are working correctly.
1. Install the Package on All Platforms
When you install a package in Delphi, it only registers for the design environment (IDE). To make it available on all platforms at compile and run time, make sure to correctly configure the project options:
a) Enable all platforms in the package project
Open the MakerAi.dproj file in Delphi.
Go to the Project > Build Configurations menu.
Make sure all necessary platforms (Win32, Win64, macOS, iOS, Android, Linux) are enabled.
If they are not enabled, select Add Platform and add them manually.
b) Compile the package for each platform
Switch to each platform in the Target Platforms list of the IDE.
Compile the package for each selected platform (Build option or Ctrl+F9).
This ensures the necessary .bpl or .so file versions are generated for the corresponding platforms.

2. Verify Library Paths in the IDE
Library paths must include the package source folder so applications using the component can find the necessary units at compile time:
Go to the Tools > Options menu.
In the Language > Delphi Options > Library section, select each platform in the Selected Platform dropdown.
Make sure the .\fuentes folder is included in the Library Path and Browsing Path for each platform.

3. Configure Design-Time Resource Files
If your package uses specific resource or image files, like component icons (TAIGraph.bmp, etc.), verify they are accessible from the IDE:
.bmp files for component icons must be in the same folder as the .dpk file or defined in project paths.
Make sure resources are correctly compiled and registered:
The .rc file must be compiled into a .res to automatically include it in the package.
Example in package code:
{$R MakerAI.res}

4. Register Components Correctly
Components must be registered in the IDE to be available in the component palette. This should already be implemented in the uMakerAi.Register.pas unit, but make sure the Register call includes all components:
procedure Register;
begin
  RegisterComponents('MakerAI', [TTAiGraph, TTAiGraphNode, TTAiGraphLink]);
end;

5. Test the Installation
Once the package is installed, verify the components are available in the Component Palette under the corresponding category (e.g., "MakerAI").
Create a new project for each platform and test that you can add and use the components at design time and runtime.

Conclusion
In summary, the only thing you need to do additionally to the normal installation process is:
Make sure to enable all platforms in the package project.
Compile the package for each platform.
Verify that library paths are configured for all platforms.
Test that components register correctly in the IDE and work at design time.

Instructions for Uninstalling the MakerAi Package from Delphi
Uninstallation Steps
1. Close Active Projects
Close all projects that are using MakerAi components.
Save all pending changes to your projects.
Close all MakerAi-related files open in the IDE.
2. Uninstall the Package from the IDE
Go to the Component menu and select Install Packages....
In the Project Options window, find the MakerAi package in the list of installed packages.
Select the MakerAi package.
Click the Remove button to remove the package from the list of installed components.
Click OK to confirm the changes.
3. Delete Compiled Files
Navigate to the folder where you installed the MakerAi package.
Delete the following files (if they exist):
All generated .bpl files
All .dcp files
.lib files
.dcu files
Any other compiled files in the Win32, Win64 and other platform folders
4. Clean Library Paths
Go to the Tools > Options menu.
In the Language > Delphi Options > Library section.
For each platform in the Selected Platform dropdown:
Review the Library Path
Remove any references to MakerAi folders
Also review the Browsing Path and remove corresponding references
5. Clean System Registry (optional)
Close Delphi completely.
Open the Registry Editor (regedit).
Search for the following paths and delete MakerAi-related entries:
HKEY_CURRENT_USER\Software\Embarcadero\BDS[version]\Known Packages
HKEY_CURRENT_USER\Software\Embarcadero\BDS[version]\Known IDE Packages
6. Delete Source Files
Once you have verified the uninstallation was successful, you can delete:
The complete MakerAi folder
Any backups you created during installation
7. Verify Uninstallation
Restart Delphi.
Verify that:
MakerAi components no longer appear in the component palette
There are no error messages related to MakerAi when starting the IDE
Previous example projects using MakerAi no longer compile (this is expected)
Important Notes
Before uninstalling, make sure you have backups of your projects that use MakerAi components.
If you plan to reinstall a different version, it is recommended to restart the system after uninstallation.
If some files cannot be deleted, verify they are not being used by any application.
If you encounter problems during uninstallation, you can try performing the process with Delphi in safe mode (starting it with the -SafeMode parameter).
Common Problem Resolution
If after uninstallation:
Error messages appear when opening Delphi: Verify all library paths related to MakerAi were removed.
Components still appear in the palette: Clean the IDE cache by deleting related .dcu and .dcp files.
There are errors compiling other projects: Verify no references to MakerAi remain in project options.