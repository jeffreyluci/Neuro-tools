# v3

   v3 is a simple 3-plane 3D image viewing tool for MATLAB.

   Usage:  <br>
   v3  <br>
   v3(IM)  <br>
   
   IM: a 3D matrix of raw image data without a header
   
   When called without arguments, v3 will prompt the user to select
   an image file. Both DICOMs and NIfTIs are supported. Both standard
   and enhanced DICOMs are supported. 
   
Author: Jeffrey Luci, jeffrey.luci@rutgers.edu
 
# Version History:

v1 (October, 2011): First release.  <br>

Multiple udocumented releases were distributed.  <br>

20260813: This is a complete overhaul of the code to make use of 
MATLAB's newer uifigure and uicontrol features. This is a faster
and more robust version with numerous bug fixes and added features.<br>
20260816: Enabled window rescaling. Added series UID checks to gracefully
fail if non-enhanced DICOMs of multiple different scans are detected in
the directory specified.<br>
20260820: Further transitioning to new MATLAB ui tools. Fixed window
resizing issue. Removed rotation reset functionality. Fixed crosshair
misalignment problems. Unified the windowing sliders into one to solve the
error checking issues.
