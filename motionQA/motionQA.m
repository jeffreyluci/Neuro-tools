function motionQA(pathToFile, options)
%MotionQA - A tool that provides multiple motion quality metrics for a
%typical functional MR imaging series.
%
%Usage: motionQA
%       motionQA(<locataion of image file>)
%       motionQA(options)
%
%This tool will read a series of DICOMs or a single 4D NIfTI file, use a
%rigid-body, monomodal coregistration method to track motion through the
%timecourse and provide multiple metrics that can be used to quantify the
%degree of motion observed in that series. By default, motionQA generates a
%json sidecar (in the same directory as the source image file(s)) populated
%with useful metadata as well as the metrics. By request, a PDF can also or
%instead be generated with much of the same information.
%
%Options: dvarsThresh - A 1x2 matrix specifying the quality boundaries for
%                       the DVARS metric.
%         fixedImage  - Can be an integer, specifying the timepoint of the
%                       volume to be used as the coregistration reference.
%                       Or, optionally, can be one of the words, "first",
%                       "middle", or "last" supplied as a char or string
%                       vector. The default is the middle volume.
%         silent      - A boolean that will suppress all graphical output
%                       so that this tool can be used in a non-interactive
%                       workflow. Supression happens when true. Default is
%                       false.
%         jsonOutput  - A boolean that will demand or suppress generation 
%                       of the json sidecar. Default is false.
%         pdfOutput   - A boolean that will demand or suppress generation
%                       of the PDF report. Default is true.
%
%Options syntax: All options should be set as arguments. For example ...
%                motionQA(fixedImage = 'first', pdfOutput = false)

%Written by J. Luci: jeffrey.luci@rutgers.edu
%https://github.com/jeffreyluci/Neuro-tools/tree/main/motionQA
%Version History:
%20260824: Initial Release

arguments
    pathToFile char = []
    options.dvarsThresh = [7, 10];
    options.fixedImage
    options.silent     (1,1) logical = false
    options.jsonOutput (1,1) logical = true
    options.pdfOutput  (1,1) logical = true
end

if ~isempty(pathToFile)
    if ~exist(pathToFile, 'file')
        error(['File: ', pathToFile, ' is not found.']);
    end
end

stats.software.name = 'motionQA';
stats.software.author = 'Jeffrey Luci <jeffrey.luci@rutgers.edu>';
stats.software.URL = 'TBD GitHub';
stats.software.version = '20260824';

if options.pdfOutput
    import mlreportgen.dom.* %#ok<*SIMPT>
    import mlreportgen.report.*
end

% Prepare preferences
% Threshold element 1 is the upper bound for the "green" zone
% Threshold element 2 is the upper bound for the "yellow zone
% All points in the yellow zone will be in the yellow scrub list
% All points in the red zone will be in the red scrub list
transThresh = [1   2   ];
rotThresh   = [0.5 1.49];
fdThresh    = [0.2 0.5 ];
rmsThresh   = [0.2 0.5 ];

% Background colors [R G B] for data quality zones on plots
colorRed    = [0.9 0   0];
colorYellow = [1.0 1.0 0];
colorGreen  = [0   0.9 0];


if isempty(pathToFile)
    % Get image file - if DICOM, only first file is needed.
    [imageFile, imageDir] = uigetfile({'*.dcm;*.dicom;*.nii;*.nii.gz', 'Image files'; ...
                                       '*.dcm;*.dicom',                'DICOM files'; ...
                                       '*.nii;*.nii.gz',               'NIfTI files'; ...
                                       '*.*',                          'All files'} , ...
                                       'Browse to first image file ...', ...
                                      ['.', filesep], ...
                                      'MultiSelect', 'off');
    if isempty(imageFile) || strcmp(num2str(imageFile), '0')
        return;
    end
else 
    [imageDir, imageFile] = fileparts(pathToFile);
end
[~,~,ext] = fileparts(imageFile);

% Log for stats if needed later
stats.filename = [imageDir, imageFile];
% d=dir(imageDir);
% d=d(3:end);

% Read in image data and header
startTime = tic;
if strcmp(ext, '.dcm') || strcmp(ext, '.dicom') % DICOM Block
    d=dir(imageDir);
    d=d(3:end);
    hdr = dicominfo([imageDir, d(1).name]);
    dx = hdr.PerFrameFunctionalGroupsSequence.Item_1.PixelMeasuresSequence.Item_1.PixelSpacing(2);
    dy = hdr.PerFrameFunctionalGroupsSequence.Item_1.PixelMeasuresSequence.Item_1.PixelSpacing(1);
    dz = hdr.PerFrameFunctionalGroupsSequence.Item_1.PixelMeasuresSequence.Item_1.SliceThickness;

    IM = uint16(zeros(hdr.Columns,        ...
                      hdr.Rows,           ...
                      hdr.NumberOfFrames, ...
                      hdr.NumberOfTemporalPositions));
    currentOrder = zeros(hdr.NumberOfTemporalPositions,1);
    readList  = true(hdr.NumberOfTemporalPositions,1);

    for ii = 1:numel(d)
        try
            IM(:,:,:,ii) = squeeze(dicomread([imageDir, d(ii).name]));
            currentOrder(ii) = str2double(getDicomTags([imageDir, d(ii).name]));
        catch
            readList(ii) = false;
            if ~options.silent
                disp(['Skipping: ', d(ii).name]);
            end
        end
    end

    %Remove skipped data reads
    IM = IM(:,:,:,readList);
    currentOrder = currentOrder(readList);

    %Guarantee DICOM images are in temporal order
    [~,temporalOrder] = sort(currentOrder);
    IM = IM(:,:,:,temporalOrder);

    outFileBaseName = [hdr.PatientID, '_', hdr.SeriesDescription];

else % NIfTI Block
    IM = niftiread([imageDir, imageFile]); 
    niftiHdr = niftiinfo([imageDir, imageFile]);
    dx = niftiHdr.PixelDimensions(1);
    dy = niftiHdr.PixelDimensions(2);
    dz = niftiHdr.PixelDimensions(3);
    [~, outFileBaseName, ~] = fileparts(imageFile);
end

%Check to make sure the number of volumes is greater than 1
if size(IM,4)<2
    error('Only one temporal position found.');
end


%Determine fixed image reference number
if ~isfield(options, 'fixedImage')
    options.fixedImage = round(size(IM,4)/2);
elseif isnumeric(options.fixedImage)
    if round(options.fixedImage) ~= options.fixedImage
        error('Image reference number must be an integer.');
    end
elseif all(isletter(options.fixedImage))
    switch options.fixedImage
        case "first"
            options.fixedImage = 1;
        case 'first'
            options.fixedImage = 1;
        case "last"
            options.fixedImage = size(IM,4);
        case 'last'
            options.fixedImage = size(IM,4);
        case "middle"
            options.fixedImage = round(size(IM,4)/2);
        case 'middle'
            options.fixedImage = round(size(IM,4)/2);
        otherwise
            error(['Image reference: ' options.fixedImage ' not recognized.']);
    end
else
    error(['Image reference: ' num2str(options.fixedImage) ' not recognized.']);
end

%Check to make sure the requested reference image is actually a number in
%the series read in.
if options.fixedImage>size(IM,4) || options.fixedImage<1
    error('Fixed reference image is not within the number of volumes.');
end

imageReadTime = toc(startTime);
fprintf('Time to read in images: %0.1f seconds.\n', imageReadTime);
coregStart = tic;

numVolumes = size(IM, 4);

% Preallocate motion parameters
translations = zeros(numVolumes, 3); % [Tx Ty Tz] in mm
rotations    = zeros(numVolumes, 3); % [Yaw Pitch Roll] in degrees
rot_rad      = zeros(numVolumes, 3); % in radians
FD           = zeros(numVolumes,1);
rmsFD        = zeros(numVolumes,1);  % used in FSL
tform        = cell(numVolumes,1);
tform{1}     = affine3d(eye(4));
dT = [0,0,0]; 
dR = [0,0,0];

% Reference volume (default = first one)
fixed = IM(:,:,:,options.fixedImage);

% Define volxel size
voxelSize = [dx dy dz];

% Standard brain radius in mm used by ASLPrep and FSL
r = 50;

% Optimizer and metric for monomodal registration
[optimizer, metric] = imregconfig('monomodal');
optimizer.MaximumIterations = 100;
optimizer.MaximumStepLength = 1.0e-02;

% Perform framewise calcs
diagOnes = eye(3);

% Set up parallel processing environment
if isempty(gcp('nocreate'))
    clusterObject = parcluster('local');
    numWorkers = clusterObject.NumWorkers-1;
    parpool(numWorkers);
end
pctRunOnAll warning('off', 'all');

parfor ii = 2:numVolumes

    moving = IM(:,:,:,ii);

    % Compute rigid transform
    tform{ii} = imregtform(moving, fixed, 'rigid', optimizer, metric);
end

% Compute DVARS
% Simple brain mask from the mean image, to exclude background/air voxels
% that would otherwise dilute the metric.
meanIM = mean(single(IM), 4);
normIM = meanIM / max(meanIM(:));
brainMask = normIM > graythresh(normIM(:));

% Reshape to voxels x time, restricted to the mask
voxelData = reshape(single(IM), [], numVolumes);
voxelData = voxelData(brainMask(:), :);

% Frame-to-frame intensity differences
diffData = diff(voxelData, 1, 2);   % (voxels) x (numVolumes-1)

dvars = zeros(numVolumes, 1);
dvars(2:end) = sqrt(mean(diffData.^2, 1))';

% Express as %-of-mean-signal so the metric is comparable across scans/
% scanners instead of sitting in raw (arbitrary) intensity units.
globalMeanSignal = mean(voxelData(:));
dvarsPct = 100 * dvars / globalMeanSignal;

%Compute FD and rmsFD
for ii = 2:numVolumes
    % Extract transformation matrix
    T2 = tform{ii}.T;
    T1 = tform{ii-1}.T;

    % Compute relative transform
    T_rel = T2 / T1;   % equivalent to T2 * inv(T1)
    
    % Extract rotation and translation
    R = T_rel(1:3,1:3);
    t = T_rel(4,1:3);   % in voxels, converts below
    
    % Convert translation to mm
    t_mm = t .* voxelSize;
    
    % Compute A = R - I
    A = R - diagOnes;
    
    % Jenkinson RMS used in FSL
    rmsFD(ii) = sqrt( (r^2/5) * trace(A' * A) + sum(t_mm.^2) );

    % Translation (in voxels, convert to mm)
    translations(ii, :) = T2(4,1:3) .* voxelSize;

    % Extract rotation matrix
    R = T2(1:3,1:3);

    % Convert rotation matrix to Euler angles (ZYX convention)
    % yaw (Z), pitch (X), roll (Y)
    yaw   = atan2( R(2,1),      R(1,1)              );
    pitch = atan2(-R(3,1), sqrt(R(3,2)^2 + R(3,3)^2));
    roll  = atan2( R(3,2),      R(3,3)              );

    rotations(ii,:) = rad2deg([yaw pitch roll]);

    % Compute FD
    rot_rad(ii,:) = deg2rad(rotations(ii,:));
    dT = translations(ii,:) - translations(ii-1,:);
    dR = rot_rad(ii,:) - rot_rad(ii-1,:);
    FD(ii) = sum(abs(dT)) + r * sum(abs(dR));

end

coregTime = toc(coregStart);
fprintf('Time to perform coregistrations: %0.1f seconds, or %0.1f sec/volume.\n', coregTime, coregTime/numVolumes);
dataPrepStartTime = tic;

% Update stats struct with new info
stats.meanTranslation = mean(translations,1);
stats.meanRotataion   = mean(rotations,1);
stats.meanDvarsPct    = mean(dvarsPct,1);
stats.meanFD          = mean(FD,1);
stats.meanRmsFD       = mean(rmsFD,1);

% Preallocate red scrub lists to avoid report problems later.
if options.pdfOutput
    stats.translationRedScrubList = [];
    stats.rotationRedScrubList    = [];
    stats.dvarsRedScrubList       = [];
    stats.fdRedScrubList          = [];
    stats.rmsFDRedScrubList       = [];
end

% Compile scrub lists
% Translation scrub
redOutliers = abs(translations) > transThresh(2);
idx = any(redOutliers, 2);
stats.translationRedScrubList = find(idx);
yellowOutliers = abs(translations) > transThresh(1);
idx = any(yellowOutliers, 2);
presegmentedScrubList = find(idx);
stats.translationYellowScrubList = setdiff(presegmentedScrubList, stats.translationRedScrubList);
stats.translationScrubPercentage = 100*[numel(stats.translationYellowScrubList)/numVolumes, ...
                                        numel(stats.translationRedScrubList)/numVolumes];

% Rotations scrub
redOutliers = abs(rotations) > rotThresh(2);
idx = any(redOutliers, 2);
stats.rotationRedScrubList = find(idx);
yellowOutliers = abs(rotations) > rotThresh(1);
idx = any(yellowOutliers, 2);
presegmentedScrubList = find(idx);
stats.rotationYellowScrubList = setdiff(presegmentedScrubList, stats.rotationRedScrubList);
stats.rotationScrubPercentage = 100*[numel(stats.rotationYellowScrubList)/numVolumes, ...
                                     numel(stats.rotationRedScrubList)/numVolumes];

% DVARS scrub
redOutliers = abs(dvarsPct) > options.dvarsThresh(2);
stats.dvarsRedScrubList = find(redOutliers);
yellowOutliers = abs(dvarsPct) > options.dvarsThresh(1);
presegmentedScrubList = find(yellowOutliers);
stats.dvarsYellowScrubList = setdiff(presegmentedScrubList, stats.dvarsRedScrubList);
stats.dvarsScrubPercentage = 100*[numel(stats.dvarsYellowScrubList)/numVolumes, ...
                                   numel(stats.dvarsRedScrubList)/numVolumes];

% Absolute FD scrub
redOutliers = abs(FD) > fdThresh(2);
idx = any(redOutliers, 2);
stats.fdRedScrubList = find(idx);
yellowOutliers = abs(FD) > fdThresh(1);
idx = any(yellowOutliers, 2);
presegmentedScrubList = find(idx);
stats.fdYellowScrubList = setdiff(presegmentedScrubList, stats.fdRedScrubList);
stats.fdScrubPercentage = 100*[numel(stats.fdYellowScrubList)/numVolumes, ...
                               numel(stats.fdRedScrubList)/numVolumes];

% RMS FD scrub
redOutliers = abs(rmsFD) > rmsThresh(2);
idx = any(redOutliers, 2);
stats.rmsFDRedScrubList = find(idx);
yellowOutliers = abs(rmsFD) > rmsThresh(1);
idx = any(yellowOutliers, 2);
presegmentedScrubList = find(idx);
stats.rmsFDYellowScrubList = setdiff(presegmentedScrubList, stats.rmsFDRedScrubList);
stats.rmsFDScrubPercentage = 100*[numel(stats.rmsFDYellowScrubList)/numVolumes, ...
                                  numel(stats.rmsFDRedScrubList)/numVolumes];

if ~options.silent || options.pdfOutput

    %Prepare plot styles
    lineTypes = {'-', ':', '--'};

    X = [0 numVolumes*2, numVolumes*2, 0];

    yTransMax = max(abs(translations(:)));
    if yTransMax < transThresh(2)
        yTransMax = transThresh(2)*1.5;
    end
    transYRed    = [-yTransMax*50   -yTransMax*50   yTransMax*50   yTransMax*50  ];
    transYYellow = [-transThresh(2) -transThresh(2) transThresh(2) transThresh(2)];
    transYGreen  = [-transThresh(1) -transThresh(1) transThresh(1) transThresh(1)];

    yRotMax = max(abs(rotations(:)));
    if yRotMax < rotThresh(2)
        yRotMax = rotThresh(2)*1.5;
    end
    rotYRed    = [-yRotMax*50   -yRotMax*50   yRotMax*50   yRotMax*50  ];
    rotYYellow = [-rotThresh(2) -rotThresh(2) rotThresh(2) rotThresh(2)];
    rotYGreen  = [-rotThresh(1) -rotThresh(1) rotThresh(1) rotThresh(1)];

    yDvarsMax = max(abs(dvarsPct(:)));
    if yDvarsMax < options.dvarsThresh(2)
        yDvarsMax = options.dvarsThresh(2)*1.5;
    end
    dvarsYRed    = [-yDvarsMax*50   -yDvarsMax*50   yDvarsMax*50   yDvarsMax*50  ];
    dvarsYYellow = [-options.dvarsThresh(2) -options.dvarsThresh(2) options.dvarsThresh(2) options.dvarsThresh(2)];
    dvarsYGreen  = [-options.dvarsThresh(1) -options.dvarsThresh(1) options.dvarsThresh(1) options.dvarsThresh(1)];

    yFDMax = max(abs(FD(:)));
    if yFDMax < fdThresh(2)
        yFDMax = fdThresh(2)*1.5;
    end
    fdYRed    = [-yFDMax*50   -yFDMax*50   yFDMax*50   yFDMax*50  ];
    fdYYellow = [-fdThresh(2) -fdThresh(2) fdThresh(2) fdThresh(2)];
    fdYGreen  = [-fdThresh(1) -fdThresh(1) fdThresh(1) fdThresh(1)];

    yRmsMax = max(abs(rmsFD(:)));
    if yRmsMax < rmsThresh(2)
        yRmsMax = rmsThresh(2)*1.5;
    end
    rmsYRed    = [-yRmsMax*50   -yRmsMax*50   yRmsMax*50   yRmsMax*50  ];
    rmsYYellow = [-rmsThresh(2) -rmsThresh(2) rmsThresh(2) rmsThresh(2)];
    rmsYGreen  = [-rmsThresh(1) -rmsThresh(1) rmsThresh(1) rmsThresh(1)];

    % Plot translations
    % Prepare Figure
    if options.silent
        fig = figure('Visible', 'off');
    else
        fig = figure;
    end
    fig.ToolBar      = 'none';
    fig.MenuBar      = 'none';
    fig.NumberTitle  = 'off';
    fig.DockControls = 'off';
    fig.Name         = 'Motion Analysis Results';
    if ~options.silent
        fig.Position     = [100 100 950, 1250];
        movegui(fig, 'center');
    end

    % Plot translations
    subplot(5,1,1);
    ytickformat('%.1f')
    patch(X, transYRed,    colorRed,    'EdgeColor', 'none', 'FaceAlpha', 0.3);
    hold('on');
    patch(X, transYYellow, colorYellow, 'EdgeColor', 'none', 'FaceAlpha', 1);
    patch(X, transYGreen,  colorGreen,  'EdgeColor', 'none', 'FaceAlpha', 1);
    transHandle = zeros(1,3);
    for ii = 1:3
    transHandle(ii) = plot(translations(:,ii), 'LineWidth', 1.5, ...
                                               'Color', 'k', ...
                                               'LineStyle', lineTypes{ii});
    end
    if yTransMax > 7.5*transThresh(2)
        set(gca, 'YTick', [-yTransMax*1.2 0 yTransMax*1.2]);
    else
        set(gca, 'YTick', [-yTransMax*1.2 -transThresh(2), -transThresh(1) 0 transThresh(1) transThresh(2) yTransMax*1.2]);
    end
    set(gca, 'XLim', [0, numVolumes], 'YLim', [-yTransMax*1.2 yTransMax*1.2]);


    ylabel('Translation (mm)','FontSize', 12);
    legend(transHandle, {'X','Y','Z'});
    title(['Rigid Body Translation: ' num2str(100-stats.translationScrubPercentage(2),3) '% Good'],'FontSize', 13);
    set(gca, 'Layer', 'top');


    % Plot rotations
    subplot(5,1,2);
    ytickformat('%.1f')
    patch(X, rotYRed,    colorRed,    'EdgeColor', 'none', 'FaceAlpha', 0.3);
    hold('on');
    patch(X, rotYYellow, colorYellow, 'EdgeColor', 'none', 'FaceAlpha', 1);
    patch(X, rotYGreen,  colorGreen,  'EdgeColor', 'none', 'FaceAlpha', 1);
    rotHandle = zeros(1,3);
    for ii = 1:3
    rotHandle(ii) = plot(rotations(:,ii), 'LineWidth', 1.5, ...
                                          'Color', 'k', ...
                                          'LineStyle', lineTypes{ii});
    end
    %rotHandle = plot(rotations, 'LineWidth', 1.5);
    if yRotMax > 7.5*rotThresh(2)
        set(gca, 'YTick', [-yRotMax*1.2 0 yRotMax*1.2]);
    else
        set(gca, 'YTick', [-yRotMax*1.2 -rotThresh(2), -rotThresh(1) 0 rotThresh(1) rotThresh(2) yRotMax*1.2]);
    end
    set(gca, 'XLim', [0, numVolumes], 'YLim', [-yRotMax*1.2 yRotMax*1.2]);
    ylabel('Rotation (°)','FontSize', 12);
    legend(rotHandle, {'Yaw (Z)','Pitch (X)','Roll (Y)'});
    title(['Rigid Body Rotation: ' num2str(100-stats.rotationScrubPercentage(2),3) '% Good'],'FontSize', 13);
    set(gca, 'Layer', 'top');

    %Plot DVARS
    subplot(5,1,3);
    ytickformat('%.1f')
    patch(X, dvarsYRed,    colorRed,    'EdgeColor', 'none', 'FaceAlpha', 0.3);
    hold('on');
    patch(X, dvarsYYellow, colorYellow, 'EdgeColor', 'none', 'FaceAlpha', 1);
    patch(X, dvarsYGreen,  colorGreen,  'EdgeColor', 'none', 'FaceAlpha', 1);
    plot(dvarsPct, 'LineWidth', 1.5, 'Color', 'k');
    if yDvarsMax > 7.5*options.dvarsThresh(2)
        set(gca, 'YTick', [-yDvarsMax*1.2 0 yDvarsMax*1.2]);
    else
        set(gca, 'YTick', [-yDvarsMax*1.2, -options.dvarsThresh(2), ...
                           -options.dvarsThresh(1), 0, options.dvarsThresh(1), ...
                            options.dvarsThresh(2), yDvarsMax*1.2]);
    end
    set(gca, 'XLim', [0, numVolumes], 'YLim', [-0.025 yDvarsMax*1.2]);
    ylabel('DVARS (%)','FontSize', 12);
    title(['DVARS: ' num2str(100-stats.dvarsScrubPercentage(2),3) '% Good'],'FontSize', 13);
    set(gca, 'Layer', 'top');

    % Plot FD
    subplot(5,1,4);
    ytickformat('%.1f')
    patch(X, fdYRed,    colorRed,    'EdgeColor', 'none', 'FaceAlpha', 0.3);
    hold('on');
    patch(X, fdYYellow, colorYellow, 'EdgeColor', 'none', 'FaceAlpha', 1);
    patch(X, fdYGreen,  colorGreen,  'EdgeColor', 'none', 'FaceAlpha', 1);
    plot(FD, 'LineWidth', 1.5, 'Color', 'k');
    if yFDMax > 7.5*fdThresh(2)
        set(gca, 'YTick', [-yFDMax*1.2 0 yFDMax*1.2]);
    else
        set(gca, 'YTick', [-yFDMax*1.2 -fdThresh(2), -fdThresh(1) 0 fdThresh(1) fdThresh(2) yFDMax*1.2]);
    end
    set(gca, 'XLim', [0, numVolumes], 'YLim', [-0.025 yFDMax*1.2]);
    ylabel('FD (mm)','FontSize', 12);
    title(['Absolute Framewise Displacement: ' num2str(100-stats.fdScrubPercentage(2),3) '% Good'],'FontSize', 13);
    set(gca, 'Layer', 'top');


    % Plot rmsFD
    subplot(5,1,5);
    ytickformat('%.1f')
    patch(X, rmsYRed,    colorRed,    'EdgeColor', 'none', 'FaceAlpha', 0.3);
    hold('on');
    patch(X, rmsYYellow, colorYellow, 'EdgeColor', 'none', 'FaceAlpha', 1);
    patch(X, rmsYGreen,  colorGreen,  'EdgeColor', 'none', 'FaceAlpha', 1);
    plot(rmsFD, 'LineWidth', 1.5, 'Color', 'k');
    if yRmsMax > 7.5*rmsThresh(2)
        set(gca, 'YTick', [-yRmsMax*1.2 0 yRmsMax*1.2]);
    else
        set(gca, 'YTick', [-yRmsMax*1.2 -rmsThresh(2), -rmsThresh(1) 0 rmsThresh(1) rmsThresh(2) yRmsMax*1.2]);
    end
    set(gca, 'XLim', [0, numVolumes], 'YLim', [-0.025 yRmsMax*1.2]);
    xlabel('Volume Index','FontSize', 12);
    ylabel('rms FD (mm)','FontSize', 12);
    title(['RMS Framewise Displacement: ' num2str(100-stats.rmsFDScrubPercentage(2),3) '% Good'], 'FontSize', 13);
    set(gca, 'Layer', 'top');

    if options.pdfOutput
        transScrubTable    = Table(buildScrubTable(stats.translationRedScrubList));
        rotationScrubTable = Table(buildScrubTable(stats.rotationRedScrubList));
        dvarsScrubTable    = Table(buildScrubTable(stats.dvarsRedScrubList));
        fdScrubTable       = Table(buildScrubTable(stats.fdRedScrubList));
        rmsFDScrubTable    = Table(buildScrubTable(stats.rmsFDRedScrubList));

        reportHandle = Report([imageDir, outFileBaseName], 'pdf');
        tempFile = [tempname, '.png'];
        exportgraphics(fig, tempFile, 'Resolution', 300);
        figImage = Image(tempFile);
        figImage.Width = '6in';
        figImage.Height = '7.89in';
        add(reportHandle, TitlePage('Title', ['Motion Analysis Results for ',  outFileBaseName], ...
            'Subtitle', ['Processed Using motionQA version: ' stats.software.version], ...
            'Author', '©Jeffrey Luci, 2026', ...
            'PubDate', string(datetime)));

        CH1 = Chapter('Plotted Coregistration Results');
        add(CH1, figImage);
        add(reportHandle, CH1);

        CH2 = Chapter('Translation Scrub Data');
        add(CH2, transScrubTable);
        add(reportHandle, CH2);

        CH3 = Chapter('Rotation Scrub Data');
        add(CH3, rotationScrubTable);
        add(reportHandle, CH3);

        CH4 = Chapter('DVARS Scrub Data');
        add(CH4, dvarsScrubTable);
        add(reportHandle, CH4);

        CH5 = Chapter('Absolute Framewise Displacement Scrub Data');
        add(CH5, fdScrubTable);
        add(reportHandle, CH5);

        CH6 = Chapter('RMS Framewise Displacement Scrub Data');
        add(CH6, rmsFDScrubTable);
        add(reportHandle, CH6);
        
        close(reportHandle);
        delete(tempFile);
    end    
end

dataPrepTime = toc(dataPrepStartTime);
totalTime = toc(startTime);
fprintf('Time to output results: %0.1f sec.\n', dataPrepTime);
fprintf('Total time elapsed: %0.1f sec.\n', totalTime);

stats.times.dataRead = imageReadTime;
stats.times.coreg    = coregTime;
stats.times.output   = dataPrepTime;
stats.times.total    = totalTime;

% Write json file if silent or if requested
if options.silent || options.jsonOutput
    stats = orderfields(stats, {'filename', 'software', 'times', 'meanTranslation', 'meanRotataion', ...
                                'meanDvarsPct', 'meanFD', 'meanRmsFD', ...
                                'translationScrubPercentage', 'rotationScrubPercentage', ...
                                'fdScrubPercentage', 'rmsFDScrubPercentage', 'dvarsScrubPercentage'...
                                'translationRedScrubList', 'translationYellowScrubList', ...
                                'rotationRedScrubList', 'rotationYellowScrubList', ...
                                'dvarsRedScrubList', 'dvarsYellowScrubList', ...
                                'fdRedScrubList', 'fdYellowScrubList', ...
                                'rmsFDRedScrubList', 'rmsFDYellowScrubList'});
    stats.translations = translations;
    stats.rotations = rotations;
    stats.FD = FD;
    stats.rmsFD = rmsFD;

    jsonText = jsonencode(stats, 'PrettyPrint', true);
    fid = fopen([imageDir, outFileBaseName, '.json'], 'wt');
    if fid == -1
        error('Could not open json file for writing.');
    end
    fwrite(fid, jsonText, 'char');
    fclose(fid);
end

if options.silent && exist('fig', 'var')
    close(fig);
end

end


function instanceNumber = getDicomTags(dicomFile)
    fid = fopen(dicomFile, 'r');
    data = fread(fid, 16000, 'uint8=>uint8')';
    fclose(fid);

    isImplicit = usesImplicitVR(data);

    % Find Acquisition Number (0020,0012) - VR is IS (Integer String)
    % Hex: 20 00 12 00
    idx = strfind(data, uint8([32 0 19 0]));
    instanceNumber = str2double(parseValue(data, idx, isImplicit));
end


function tf = usesImplicitVR(data)
    % File Meta group (0002,xxxx) is ALWAYS Explicit VR LE, regardless of
    % the main dataset's transfer syntax - so this lookup itself never
    % needs to branch.
    tf = false; % default: assume explicit if we can't find it (safer - see note below)
    idx = strfind(data, uint8([2 0 16 0])); % (0002,0010) Transfer Syntax UID
    if isempty(idx)
        return
    end
    idx = idx(1);
    len = double(typecast(data(idx+6:idx+7), 'uint16')); % UI is short-form
    uid = strtrim(char(data(idx+8 : idx+8+len-1)));
    tf = strcmp(uid, '1.2.840.10008.1.2'); % Implicit VR Little Endian
    % Anything else - Explicit VR LE, or any of the compressed (JPEG/RLE/etc)
    % transfer syntaxes - is Explicit VR for header purposes, since
    % compression only changes how PixelData itself is stored, and
    % PixelData comes after Acquisition Number in the dataset.
end


function val = parseValue(data, idx, isImplicit)
    if isempty(idx)
        val = '';
        return
    end
    idx = idx(1); % take first occurrence

    if isImplicit
        % Implicit VR: Tag(4) + Length(4, uint32) - no VR field at all.
        len = double(typecast(data(idx+4:idx+7), 'uint32'));
        valStart = idx + 8;
    else
        % Explicit VR: Tag(4) + VR(2) + ...
        vr = char(data(idx+4:idx+5));
        longFormVRs = {'OB','OW','OF','OL','OD','SQ','UT','UN','UC','UR'};
        if any(strcmp(vr, longFormVRs))
            % long form: VR(2) + reserved(2) + Length(4, uint32)
            len = double(typecast(data(idx+8:idx+11), 'uint32'));
            valStart = idx + 12;
        else
            % short form (IS falls here): VR(2) + Length(2, uint16)
            len = double(typecast(data(idx+6:idx+7), 'uint16'));
            valStart = idx + 8;
        end
    end
    if valStart + len - 1 > numel(data)
        val = ''; % value ran past the 16000-byte read window
        return
    end
    val = strtrim(char(data(valStart : valStart+len-1)));
end


function tableData = buildScrubTable(list)
    header = {'Flagged Volume Index Numbers:'};
    if isempty(list)
        body = {'None'};
    else
        body = num2cell(list);
    end
    tableData = [header; body];
end