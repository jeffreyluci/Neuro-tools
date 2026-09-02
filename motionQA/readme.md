# motionQA

**MotionQA** - A tool that provides multiple motion quality metrics for a
typical functional MR imaging series.

# Usage
`motionQA`
`motionQA(<locataion of image file>)`
`motionQA(options)`

# Options
**dvarsThresh**  - A 1x2 matrix specifying the quality boundaries for
                        the DVARS metric.
**regQualThresh** - A 1x2 matrix specifying the quality bodaries and
                        the flagging threshold for the quality of image
                        registration. Note that this metric is reversed
                        compared to the others, where low values indicate
                        low quality, so the order of the low and high
                        values in this option are "backwards."<br>
**fixedImage**    - Can be an integer, specifying the timepoint of the
                        volume to be used as the coregistration reference.
                        Or, optionally, can be one of the words, "first",
                        "middle", or "last" supplied as a char or string
                        vector. The default is the middle volume.<br>
**silent**        - A boolean that will suppress all graphical output
                        so that this tool can be used in a non-interactive
                        workflow. Supression happens when true. Default is
                        false.<br>
**jsonOutput**    - A boolean that will demand or suppress generation 
                        of the json sidecar. Default is false.<br>
**pdfOutput**    - A boolean that will demand or suppress generation
                        of the PDF report. Default is true.<br>
**timing**        - A boolean that selects the command line output of
                        various timing metrics. Note that if the silent
                        option is set true, the timing metrics will not
                        be printed, regardless of how this is set.<br>

Options syntax: All options should be set as arguments. For example ...<br>
                motionQA(fixedImage = 'first', pdfOutput = false)<br>

# Discussion
This tool will read a series of DICOMs or a single 4D NIfTI file, use a
rigid-body, monomodal coregistration method to track motion through the
timecourse and provide multiple metrics that can be used to quantify the
degree of motion observed in that series. By default, motionQA generates a
json sidecar (in the same directory as the source image file(s)) populated
with useful metadata as well as the metrics. By request, a PDF can also or
instead be generated with much of the same information.

Written by J. Luci: jeffrey.luci@rutgers.edu<br>
https://github.com/jeffreyluci/Neuro-tools/tree/main/motionQA<br>
Version History:<br>
20260824: Initial Release<br>

20260828: Fixed first image coregistration bug. Switched to tiled layout
          instead of subplot to gain more granular control over figure
          layout properties. Added coregistration quality metric. Moved
          timing feature to an option. Fixed figure display bug that was
          inconsistent with silent option.<br>
		  
20260830: Added IMA support. Eliminated case sensitivity of file
          extensions. Added autoscaling of plots to screen size.
          Streamlined DICOM file read error handling. Fixed handling of
          truncated run issues.<br>
		  
20260831: Fixed figure window sizing error.
