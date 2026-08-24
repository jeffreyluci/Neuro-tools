# motionQA

MotionQA - A tool that provides multiple motion quality metrics for a
typical functional MR imaging series.<br>
<br>
Usage: motionQA<br>
       motionQA(<locataion of image file>)<br>
       motionQA(options)<br>
<br>
This tool will read a series of DICOMs or a single 4D NIfTI file, use a
rigid-body, monomodal coregistration method to track motion through the
timecourse and provide multiple metrics that can be used to quantify the
degree of motion observed in that series. By default, motionQA generates a
json sidecar (in the same directory as the source image file(s)) populated
with useful metadata as well as the metrics. By request, a PDF can also or
instead be generated with much of the same information.<br>
<br>
Options: dvarsThresh - A 1x2 matrix specifying the quality boundaries for
                       the DVARS metric.<br>
         fixedImage  - Can be an integer, specifying the timepoint of the
                       volume to be used as the coregistration reference.
                       Or, optionally, can be one of the words, "first",
                       "middle", or "last" supplied as a char or string
                       vector. The default is the middle volume.<br>
         silent      - A boolean that will suppress all graphical output
                       so that this tool can be used in a non-interactive
                       workflow. Supression happens when true. Default is
                       false.<br>
         jsonOutput  - A boolean that will demand or suppress generation 
                       of the json sidecar. Default is false.<br>
         pdfOutput   - A boolean that will demand or suppress generation
                       of the PDF report. Default is true.<br>

Options syntax: All options should be set as arguments. For example ...<br>
                motionQA(fixedImage = 'first', pdfOutput = false)<br>

Written by J. Luci: jeffrey.luci@rutgers.edu<br>
https://github.com/jeffreyluci/Neuro-tools/tree/main/motionQA<br>
Version History:<br>
20260824: Initial Release<br>
