function outEOGv = prepro(datapath, starttime, trialpar)
%This function is used to do some prepocessing for all the EEG data stored
%in .bdf (Biosemi) files using FieldTrip. EOG data is extracted and stored
%in the generated file EOG.mat as variable EOGv, which is a structure
%stored 4 pieces of information in its 4 fields:
%   1. Subject ID;
%   2. Sampling rate; (When prepocessing, resampling is done, so this is
%   not the original sampling rate.)
%   3. Epochs of EEG data (EOG only);
%   4. Time information of each epoch.
%TRIALPAR has 3 fields at most: trigger (numeric), continuous ('yes' or
%'no') and trialprepost (a row vector with two elements).

%By Zhang, Liang, 2015/11/4. E-mail:psychelzh@gmail.com.

%Check input parameters.
if ~isfield(trialpar, 'trigger') ...
        || isempty(trialpar.trigger)
    error('UDF:PREPRO:NO_TRIGGER_SPECIFIED', ...
        'Input trial definition must have at least one specific trigger value.');
end
%Check whether read continuous data or not.
if ~isfield(trialpar, 'continuous')
    if isfield(trialpar, 'trialprepost') ...
            && ~isempty(trialpar.trialprepost) ...
            && ~any(isnan(trialpar.trialprepost))
        trialpar.continuous = 'no';
    else
        trialpar.continuous = 'yes';
    end
end

%Check configuration.
if strcmpi(trialpar.continuous, 'yes')
    if length(trialpar.trigger) ~= 2
        error('Continuous data will be read, and the number of triggers of the trial begin and end are not right.');
    end
else
    if ~isfield(trialpar, 'trialprepost') ...
            || isempty(trialpar.trialprepost) ...
            || any(isnan(trialpar.trialprepost))
        pre  = input('You used epoch analysis, how long is the trial before the stimulus (Unit:sec)? Please input a number:\n');
        post = input('And how long is the trial after the stimulus (Unit:sec)? Please input a number:\n');
        trialpar.trialprepost = [pre, post]; %User input its trial parameters.
    end
end

%Access to filenames.
filesInfo = dir([datapath, '\*.bdf']);
filesName = {filesInfo.name};
subid = str2double(regexp(filesName, '\d{4}', 'match', 'once'));
totalfilenum = length(filesName);
fprintf('found %d files.\n', totalfilenum);
for ifile = 1:totalfilenum
    fprintf('now preprocessing %dth file...\n', ifile);
    try
        %Configuration for trial definition.
        cfg                     = [];
        cfg.dataset             = [datapath, '\', filesName{ifile}];
        cfg.channel             = {'EXG3' 'EXG4'};
        cfg.trialdef.eventtype  = 'STATUS';
        cfg.trialdef.eventvalue = trialpar.trigger;
        if strcmpi(trialpar.continuous, 'yes')
            cfg.trialfun             = 'btcontinuous'; %Use a user defined trial function, see help BTCONTINUOUS.
        else
            cfg.trialdef.prestim     = trialpar.trialprepost(1);
            cfg.trialdef.poststim    = trialpar.trialprepost(2);
        end
        cfg                     = ft_definetrial(cfg);
        %Configuration for filtering.
        cfg.bpfilter            = 'yes';
        cfg.bpfreq              = [0.5 20];
        cfg.bpfilttype          = 'fir';
        dataPrepro = ft_preprocessing(cfg);
        %Configuration for resampling.
        cfg                     = [];
        cfg.resamplefs          = 256;
        cfg.detrend             = 'no';
        dataPrepro              = ft_resampledata(cfg, dataPrepro);
        %From the start time to the start point.
        startpoint = floor(dataPrepro.fsample * starttime) + 1;
        %Calculate the vertical EOG data.
        EOGv(ifile).pid     = subid(ifile); %#ok<*AGROW>
        EOGv(ifile).fsample = dataPrepro.fsample;
        EOGv(ifile).trial   = cell(size(dataPrepro.trial)); 
        EOGv(ifile).time    = cell(size(dataPrepro.trial));
        for triali = 1:length(dataPrepro.trial)    
            EOGv(ifile).trial{triali} = [dataPrepro.trial{triali}(1, startpoint:end); ...
                dataPrepro.trial{triali}(2, startpoint:end); ...
                dataPrepro.trial{triali}(1, startpoint:end) - dataPrepro.trial{triali}(2, startpoint:end)];
            EOGv(ifile).time{triali}  = dataPrepro.time{triali}(startpoint:end);            
        end        
    catch exception
        fid = fopen('errlog.log', 'a');
        fprintf(fid, 'Error found while reading file %s.\n', [datapath, '\', filesName{ifile}]);
        if exist('dataPrepro', 'var')
            EOGv(ifile).pid     = subid(ifile);
            EOGv(ifile).fsample = dataPrepro.fsample;
            EOGv(ifile).trial   = {};
            EOGv(ifile).time    = {};
        else
            fclose(fid);
            rethrow(exception);
        end
        fclose(fid);
    end
end
%Save EOGv only.
save(sprintf('EOG_%s_%s', datapath, datestr(now, 'HH-MM')), 'EOGv');
if nargout == 1, outEOGv = EOGv; end