# powershell-skype
PowerShell script to automate Skype For Business Deployment
- Enterprise topology with 1 FE, Office Web Apps
- Backend is SQL Server 2012 with Always-On (some manual operations are required after deployment)
- All roles except of Enterprise Voice (mediation and etc) are on FE
- Updates Skype For Business after installation
## Prerequisites
 - skype share on DFS, 
 - SQL Instance (AlwaysON must be configured later)
 - Office Web Apps

## Post-installation steps 
- check simple URLs (shoulde be configured during script execution), 
- add additional FE/Edge, change SQL AlwaysOn Listener if it is necessary