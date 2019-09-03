# PowerShell - Skype For Business
PowerShell script to automate Skype For Business Deployment
- Enterprise topology with 1 FE, Office Web Apps
- Backend is SQL Server 2012 with Always-On (some manual operations are required after deployment)
- All roles except of Enterprise Voice (mediation and etc) are on FE
- Updates Skype For Business after the installation
## Prerequisites
 - Skype share on DFS 
 - SQL Instance (AlwaysON must be configured later)
 - Office Web Apps

## Post-installation steps 
- Check simple URLs (shoulde be configured during script execution) 
- Add additional FE/Edge, change SQL AlwaysOn Listener if it is necessary

## Notes 
Created, tested and verified in far 2016. However, I'm pretty sure the script works with later SfB versions (some minor change might be required though). Happy deployment and thanks for stars.
