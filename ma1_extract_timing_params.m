function timing = ma1_extract_timing_params(trial)
% ma1_extract_timing_params - Extract all timing parameters from a trial structure
%
% Usage:
%   timing = ma1_extract_timing_params(trial);
%
% Input:
%   trial - Single trial structure from monkeypsych .mat file
%
% Output:
%   timing - Structure containing all timing parameters
%
% Example:
%   data = load('Y:\Data\Feno\20260715\Fen2026-07-15_01.mat');
%   timing = ma1_extract_timing_params(data.trial(2));

timing = struct();

%% 1. State-based timing
if isfield(trial, 'states') && isfield(trial, 'states_onset')
    timing.states = trial.states;
    timing.states_onset = trial.states_onset;
    timing.n_states = length(trial.states);
    
    % Calculate state durations
    if length(trial.states_onset) > 1
        timing.state_durations = diff(trial.states_onset);
    else
        timing.state_durations = [];
    end
    
    % Trial duration
    if length(trial.states_onset) > 1
        timing.trial_duration = trial.states_onset(end) - trial.states_onset(1);
    else
        timing.trial_duration = 0;
    end
else
    timing.states = [];
    timing.states_onset = [];
    timing.n_states = 0;
    timing.state_durations = [];
    timing.trial_duration = NaN;
end

%% 2. Time series information
if isfield(trial, 'x_hnd')
    timing.n_samples = length(trial.x_hnd);
    
    % Implied sampling rate
    if timing.trial_duration > 0
        timing.sampling_rate = timing.n_samples / timing.trial_duration;
    else
        timing.sampling_rate = NaN;
    end
else
    timing.n_samples = 0;
    timing.sampling_rate = NaN;
end

if isfield(trial, 'tSample_from_time_start')
    timing.tSample_from_time_start = trial.tSample_from_time_start;
    timing.time_range = [min(trial.tSample_from_time_start), max(trial.tSample_from_time_start)];
else
    timing.tSample_from_time_start = [];
    timing.time_range = [NaN NaN];
end

%% 3. Event timing
if isfield(trial, 'timestamp')
    timing.timestamp = trial.timestamp;
    timing.trial_start_datetime = datetime(trial.timestamp);
else
    timing.timestamp = [];
    timing.trial_start_datetime = NaT;
end

if isfield(trial, 'reward_time')
    timing.reward_time = trial.reward_time;
    timing.rewarded = (trial.reward_time > 0);
else
    timing.reward_time = NaN;
    timing.rewarded = false;
end

%% 4. Abort timing
if isfield(trial, 'aborted_state')
    timing.aborted_state = trial.aborted_state;
    timing.aborted = (~isnan(trial.aborted_state) && trial.aborted_state > 0);
else
    timing.aborted_state = NaN;
    timing.aborted = false;
end

if isfield(trial, 'aborted_state_duration')
    timing.aborted_state_duration = trial.aborted_state_duration;
else
    timing.aborted_state_duration = NaN;
end

%% 5. Microstim timing
if isfield(trial, 'microstim')
    timing.microstim = trial.microstim;
else
    timing.microstim = 0;
end

if isfield(trial, 'microstim_start')
    timing.microstim_start = trial.microstim_start;
    timing.microstim_delivered = (~isnan(trial.microstim_start));
else
    timing.microstim_start = NaN;
    timing.microstim_delivered = false;
end

if isfield(trial, 'microstim_end')
    timing.microstim_end = trial.microstim_end;
    if ~isnan(timing.microstim_start) && ~isnan(trial.microstim_end)
        timing.microstim_duration = trial.microstim_end - trial.microstim_start;
    else
        timing.microstim_duration = NaN;
    end
else
    timing.microstim_end = NaN;
    timing.microstim_duration = NaN;
end

if isfield(trial, 'microstim_state')
    timing.microstim_state = trial.microstim_state;
else
    timing.microstim_state = NaN;
end

%% 6. Trial metadata
if isfield(trial, 'trial_number')
    timing.trial_number = trial.trial_number;
else
    timing.trial_number = NaN;
end

if isfield(trial, 'success')
    timing.success = trial.success;
else
    timing.success = NaN;
end

if isfield(trial, 'completed')
    timing.completed = trial.completed;
else
    timing.completed = NaN;
end

%% 7. Calculate common timing metrics

% Reaction time (cue to target acquisition)
if ~isempty(timing.states) && ~isempty(timing.states_onset)
    cue_idx = find(timing.states == 6, 1);  % CUE_ON
    target_idx = find(timing.states == 4, 1);  % TAR_ACQ
    
    if ~isempty(cue_idx) && ~isempty(target_idx) && target_idx > cue_idx
        timing.reaction_time = timing.states_onset(target_idx) - timing.states_onset(cue_idx);
    else
        timing.reaction_time = NaN;
    end
    
    % Movement time (target acquisition to target hold)
    hold_idx = find(timing.states == 5, 1);  % TAR_HOL
    if ~isempty(target_idx) && ~isempty(hold_idx) && hold_idx > target_idx
        timing.movement_time = timing.states_onset(hold_idx) - timing.states_onset(target_idx);
    else
        timing.movement_time = NaN;
    end
    
    % Fixation hold duration
    fix_acq_idx = find(timing.states == 2, 1);  % FIX_ACQ
    fix_hold_idx = find(timing.states == 3, 1);  % FIX_HOL
    if ~isempty(fix_acq_idx) && ~isempty(fix_hold_idx) && fix_hold_idx > fix_acq_idx
        timing.fixation_hold_duration = timing.states_onset(fix_hold_idx) - timing.states_onset(fix_acq_idx);
    else
        timing.fixation_hold_duration = NaN;
    end
    
    % ⭐ Delay period duration (State 8: DEL_PER)
    % This is the time spent waiting between cue presentation and target appearance
    delay_idx = find(timing.states == 8, 1);  % DEL_PER
    if ~isempty(delay_idx) && delay_idx < length(timing.states_onset)
        timing.delay_duration = timing.state_durations(delay_idx);
    else
        timing.delay_duration = NaN;  % No delay period in this trial
    end
else
    timing.reaction_time = NaN;
    timing.movement_time = NaN;
    timing.fixation_hold_duration = NaN;
    timing.delay_duration = NaN;
end

%% 8. State names (for reference)
timing.state_names = containers.Map({1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 19, 20, 21, 50, 99}, ...
    {'INI_TRI', 'FIX_ACQ', 'FIX_HOL', 'TAR_ACQ', 'TAR_HOL', 'CUE_ON', 'MEM_PER', 'DEL_PER', ...
     'TAR_ACQ_INV', 'TAR_HOL_INV', 'MAT_ACQ', 'MAT_HOL', 'MAT_ACQ_MSK', 'MAT_HOL_MSK', ...
     'SEN_RET', 'ABORT', 'SUCCESS', 'REWARD', 'ITI', 'CLOSE'});

end
